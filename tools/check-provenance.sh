#!/bin/sh
# Source-integrity check for the libcurl SDK.
#
# Six questions, all answerable without a compiler and without a network:
#
#   1. Do the 418 upstream files still hash to the digests UPSTREAM.sha256
#      records, and is that record itself intact?
#   2. Is the native file set exactly that set -- no missing, extra or renamed
#      file under lib/ or include/?  A plain checksum run cannot see an addition.
#   3. Do the records cover upstream's own compile closure, read out of
#      lib/Makefile.inc rather than out of this fork's build script, and
#      nothing beyond it?
#   4. Is curl's licence file still the licence file, and is every SPDX
#      identifier and per-file notice where NOTICE.md says it is?
#   5. Does UPSTREAM.md still name the release this tree actually holds?
#   6. Does every fork-authored file present in the tree carry the SPDX tag its
#      grant requires?
#
# This is a provenance gate, not a build gate. Nothing here compiles, links or
# runs a target binary; it is the check that an edit to the canonical native
# source cannot pass as a routine change.
#
# It reads only files inside this package and writes nothing anywhere, to disk
# or over the network. The release tarball is not in this tree, so the sha256
# of curl-8.22.0.tar.xz recorded in UPSTREAM.md cannot be recomputed here; what
# that digest rests on is stated in UPSTREAM.md, and this script checks every
# part of the record that is here.
#
# Usage: sh tools/check-provenance.sh      (run from anywhere in the repository)
#
# Exit status is 0 only when every check below passed. Otherwise it is 1 and the
# message names what differed.
#
# SPDX-License-Identifier: curl

set -eu

cd "$(dirname "$0")/.."

fail() {
    echo "check-provenance: $1" >&2
    exit 1
}

# The record count is pinned rather than derived: a manifest that lost records
# and a tree that lost the matching files would otherwise agree with each other.
# Bump it in the same change as UPSTREAM.sha256.
RECORDS=418

# ---------------------------------------------------------------- 1. bytes

sha256sum -c --quiet UPSTREAM.sha256 ||
    fail "a recorded file no longer matches its digest in UPSTREAM.sha256"
echo "1. all $RECORDS recorded digests match"

awk '
{
    if ($1 !~ /^[0-9a-f]{64}$/ || NF != 2) { print "malformed record at line " NR ": " $0; bad = 1 }
    if (seen[$2]++) { print "duplicate record for " $2; bad = 1 }
    if ($2 !~ /^(lib|include)\// && $2 != "COPYING" && $2 != "README" &&
        $2 != "RELEASE-NOTES") { print "record outside the vendored tree: " $2; bad = 1 }
}
END { exit (bad || NR == 0) ? 1 : 0 }' UPSTREAM.sha256 ||
    fail "UPSTREAM.sha256 is malformed, records a path twice, or names a file outside the vendored tree"

[ "$(grep -c . UPSTREAM.sha256)" = "$RECORDS" ] ||
    fail "UPSTREAM.sha256 holds $(grep -c . UPSTREAM.sha256) records, not $RECORDS"

# A vendored test suite, a vendored tool directory or a vendored dependency
# would each show up as a recorded path. The record holds none of them.
if awk '{ print $2 }' UPSTREAM.sha256 |
        grep -qE '^(src|tests|docs|scripts|projects|CMake|m4)/|third[_-]?party|vendor'; then
    fail "UPSTREAM.sha256 records a path this fork does not vendor; see NOTICE.md"
fi
echo "1b. no vendored test suite, tool directory or third-party material is recorded"

# ---------------------------------------------------------------- 2. file set

# One awk over both sides: the recorded paths under lib/ and include/ first,
# then what is on disk. There is no allowlist. A file under lib/ or include/
# that the record does not name is a finding, because every byte of those two
# directories is upstream's.
#
# Two details are load-bearing, and both were wrong here before this was
# observed failing:
#
#   * Only the records under lib/ and include/ belong in this comparison.
#     COPYING, README and RELEASE-NOTES are also recorded and are also
#     upstream, but they live at the package root, which `find lib include`
#     does not walk. Comparing all 418 records against those two directories
#     made the checker report every recorded file as absent, on a tree where
#     `sha256sum -c` had just verified all 418 digests. Their presence is the
#     `for f in COPYING README RELEASE-NOTES` loop below.
#
#   * `-` is passed as the second operand. A manifest given as a file operand
#     does not make GNU awk read standard input as well unless `-` is named, so
#     the on-disk side arrived empty and the same 415 findings came back with
#     `present` holding nothing at all.
find lib include -type f | LC_ALL=C sort | awk '
NR == FNR { if ($2 ~ /^(lib|include)\//) recorded[$2] = 1; next }
{ present[$0] = 1 }
END {
    rc = 0
    for (p in recorded)
        if (!(p in present)) { print "recorded but absent from the tree: " p; rc = 1 }
    for (p in present)
        if (!(p in recorded)) { print "in the tree but not recorded: " p; rc = 1 }
    exit rc
}' UPSTREAM.sha256 - ||
    fail "the vendored file set differs from UPSTREAM.sha256; an intentional change to the native source needs an observed failure, a small causal patch, an explicit per-file deviation record in NOTICE.md, updated digests here, and a CHANGELOG.md entry in the same change"

recorded_vendored=$(awk '$2 ~ /^(lib|include)\// { n++ } END { print n + 0 }' UPSTREAM.sha256)
present_vendored=$(find lib include -type f | wc -l)
[ "$recorded_vendored" = "$present_vendored" ] ||
    fail "UPSTREAM.sha256 records $recorded_vendored files under lib/ and include/; the tree holds $present_vendored"

for f in COPYING README RELEASE-NOTES UPSTREAM.sha256; do
    [ -f "$f" ] || fail "$f is missing from the package root"
done

# The three root records are named in build.zig.zon's .paths, because zig fetch
# hashes only the paths a manifest names and this package installs COPYING as
# the licence of the shipped library. They are not duplicated or renamed here,
# so the README / README.upstream.md byte-identity check some forks carry has no
# analogue in this tree and is not forgotten: upstream's README is preserved in
# place under its own name and is one of the 418 records, and the analogue for
# it is the text check on COPYING below -- a digest alone cannot catch a licence
# file silently replaced by a stub whose digest was updated in the same change.
echo "2. lib/ and include/ hold exactly the recorded files, and the three root records are present"

# ---------------------------------------------------------------- 3. closure

# Read the seven C groups and the seven header groups out of upstream's own
# list, so the closure this package claims to compile is upstream's and not
# this fork's transcription of it. The four files upstream ships without
# listing are named explicitly, so an addition cannot hide in the gap between
# "vendored" and "compiled".
awk '
BEGIN {
    unlisted["dllmain.c"] = 1
    unlisted["config-mac.h"] = 1
    unlisted["config-os400.h"] = 1
    unlisted["config-win32.h"] = 1

    # `|` and not a space between the alternatives. In an awk regular
    # expression a space is a literal space, so a space-separated list built a
    # pattern that matched no line of lib/Makefile.inc at all: `listed` stayed
    # empty, every digested .c and .h was reported as being in no upstream
    # list, and the two pinned counts below never got the chance to fire.
    groups = "LIB_CFILES|LIB_VAUTH_CFILES|LIB_VDNS_CFILES|LIB_VTLS_CFILES|" \
             "LIB_VQUIC_CFILES|LIB_VSSH_CFILES|LIB_CURLX_CFILES|" \
             "LIB_HFILES|LIB_VAUTH_HFILES|LIB_VDNS_HFILES|LIB_VTLS_HFILES|" \
             "LIB_VQUIC_HFILES|LIB_VSSH_HFILES|LIB_CURLX_HFILES"
    listre = "^(" groups ")[ \t]*="

    while ((getline line < "lib/Makefile.inc") > 0) {
        if (line ~ listre) {
            name = substr(line, 1, index(line, "=") - 1)
            # The alignment spaces before `=` are part of the matched line, so
            # `name` keeps them; without this trim `/CFILES$/` never matched and
            # every C unit was counted as a header.
            sub(/[ \t]+$/, "", name)
            cfile = (name ~ /CFILES$/)
            state = 1
            add(substr(line, index(line, "=") + 1), cfile)
            continue
        }
        if (state) {
            add(line, cfile)
            if (line !~ /\\$/) state = 0
        }
    }
    close("lib/Makefile.inc")

    while ((getline line < "UPSTREAM.sha256") > 0)
        recorded[substr(line, index(line, "  ") + 2)] = 1
    close("UPSTREAM.sha256")

    rc = 0
    if (nc != 196) { print "upstream lists " nc " C units, not 196"; rc = 1 }
    if (nh != 187) { print "upstream lists " nh " headers, not 187"; rc = 1 }
    for (u in listed)
        if (!("lib/" u in recorded)) { print "closure unit not digested: lib/" u; rc = 1 }
    for (p in recorded) {
        if (p !~ /^lib\//) continue
        s = substr(p, 5)
        if ((s ~ /\.c$/ || s ~ /\.h$/) && !(s in listed) && !(s in unlisted)) {
            print "digested but in no upstream list: " p
            rc = 1
        }
    }
    exit rc
}
function add(text, cfile,   body, parts, i) {
    body = text
    sub(/[ \t]+$/, "", body)
    sub(/\\$/, "", body)
    if (body == "") return
    parts = split(body, pieces, "[ \t]+")
    for (i = 1; i <= parts; i++)
        if (pieces[i] != "") {
            listed[pieces[i]] = 1
            if (cfile) nc++; else nh++
        }
}' UPSTREAM.sha256 ||
    fail "the vendored tree and upstream's own lib/Makefile.inc closure do not agree"
echo "3. upstream's closure is intact: 196 C units, 187 headers, and the four files it does not list"

# ---------------------------------------------------------------- 4. licence

grep -q 'COPYRIGHT AND PERMISSION NOTICE' COPYING ||
    fail "COPYING no longer carries its title line; something has replaced the licence"
grep -q 'Copyright (c) 1996 - 2026, Daniel Stenberg, <daniel@haxx.se>, and many' COPYING ||
    fail "COPYING no longer carries curl's copyright line"
grep -q 'name of a copyright holder shall not' COPYING ||
    fail "COPYING no longer carries the advertising clause of the curl licence"

copying_digest=$(awk '$2 == "COPYING" { print $1; exit }' UPSTREAM.sha256)
for f in UPSTREAM.md NOTICE.md FORK-LICENSE.md; do
    grep -q "$copying_digest" "$f" ||
        fail "$f does not quote the recorded COPYING digest $copying_digest"
done
# The attribution obligation has to travel in the two licence records. The
# check is two short fragments rather than the whole sentence because a
# markdown record wraps the sentence across lines, and a wrapped notice is
# still a notice.
for f in NOTICE.md FORK-LICENSE.md; do
    grep -q '1996 - 2026' "$f" ||
        fail "$f does not carry curl's copyright years"
    grep -q 'Daniel Stenberg' "$f" ||
        fail "$f does not name curl's copyright holder"
done
grep -q 'Permission to use, copy, modify, and distribute this software for any purpose' FORK-LICENSE.md ||
    fail "FORK-LICENSE.md does not reproduce the curl permission text it grants under"
echo "4a. COPYING is still the curl licence, and the records carry its notice"

# The notice census, read out of the files rather than assumed: six files carry
# no SPDX line and three carry an identifier that is not plain curl. A notice
# dropped, added or rewritten changes one of these two sets.
awk '
BEGIN {
    untagged_expected = "COPYING README RELEASE-NOTES lib/curl_config.h.in lib/libcurl.def lib/libcurl.vers.in"
    notcurl_expected = "lib/curlx/inet_ntop.c lib/curlx/inet_pton.c lib/vssh/vssh.c"
    while ((getline line < "UPSTREAM.sha256") > 0) order[++n] = substr(line, index(line, "  ") + 2)
    close("UPSTREAM.sha256")
    rc = 0
    for (i = 1; i <= n; i++) {
        p = order[i]
        tag = 0
        curltag = 0
        while ((getline line < p) > 0) {
            if (line ~ /SPDX-License-Identifier:/) {
                tag = 1
                if (line ~ /SPDX-License-Identifier:[ \t]*curl[ \t]*$/) curltag = 1
            }
        }
        close(p)
        if (!tag) untagged[++u] = p
        else if (!curltag) notcurl[++c] = p
    }
    sortlist(untagged, u); sortlist(notcurl, c)
    got = ""; for (i = 1; i <= u; i++) got = got " " untagged[i]
    if (got != " " untagged_expected) {
        print "files carrying no SPDX identifier are now:" got; rc = 1
    }
    got = ""; for (i = 1; i <= c; i++) got = got " " notcurl[i]
    if (got != " " notcurl_expected) {
        print "files whose SPDX identifier is not plain curl are now:" got; rc = 1
    }
    exit rc
}
function sortlist(a, n,   i, j, t) {
    for (i = 2; i <= n; i++) {
        t = a[i]; j = i - 1
        while (j >= 1 && a[j] > t) { a[j + 1] = a[j]; j-- }
        a[j + 1] = t
    }
}' UPSTREAM.sha256 ||
    fail "the SPDX census of the vendored tree changed; update NOTICE.md in the same change, naming the term and the line"
echo "4b. the per-file notices are where NOTICE.md says: curl, ISC, curl AND ISC, public domain, FSF automake"

# The terms that are not curl, named by the file that carries them.
grep -q 'SPDX-License-Identifier: ISC' lib/curlx/inet_ntop.c ||
    fail "lib/curlx/inet_ntop.c no longer carries its ISC identifier"
grep -q 'SPDX-License-Identifier: ISC' lib/curlx/inet_pton.c ||
    fail "lib/curlx/inet_pton.c no longer carries its ISC identifier"
grep -q 'SPDX-License-Identifier: curl AND ISC' lib/vssh/vssh.c ||
    fail "lib/vssh/vssh.c no longer carries its curl AND ISC identifier"
for f in lib/md4.c lib/md5.c; do
    grep -q 'Alexander Peslyak' "$f" ||
        fail "$f no longer credits the author of its MD4/MD5 fallback"
    grep -q 'heavily cut-down "BSD license"' "$f" ||
        fail "$f no longer carries the public-domain fallback grant"
done
for f in lib/Makefile.in include/Makefile.in include/curl/Makefile.in; do
    grep -q 'Free Software Foundation' "$f" ||
        fail "$f no longer carries the automake notice that travels with it"
done
echo "4c. the ISC, public-domain and automake notices are where NOTICE.md says they are"

# ---------------------------------------------------------------- 5. the pin

# `$4`, not `$3`. These are markdown table rows and awk splits on whitespace,
# so `$1` is the leading `|`, `$2` the key, `$3` the `|` that closes the key
# cell and `$4` the value. Reading `$3` yielded the separator, so the check
# reported "UPSTREAM.md records no Artifact row" on a table that has one.
artifact=$(awk '/^\| Artifact \| `/ { gsub(/`/, "", $4); gsub(/\|/, "", $4); print $4; exit }' UPSTREAM.md)
[ -n "$artifact" ] || fail "UPSTREAM.md records no Artifact row"
header_version=$(awk '/^#define LIBCURL_VERSION "/ { gsub(/"/, "", $3); print $3; exit }' include/curl/curlver.h)
[ -n "$header_version" ] || fail "include/curl/curlver.h carries no LIBCURL_VERSION"
[ "$artifact" = "curl-$header_version.tar.xz" ] ||
    fail "UPSTREAM.md pins $artifact but include/curl/curlver.h holds $header_version"
release_digest=$(awk '/^\| sha256 \| `/ { gsub(/`/, "", $4); gsub(/\|/, "", $4); print $4; exit }' UPSTREAM.md)
echo "$release_digest" | grep -qE '^[0-9a-f]{64}$' ||
    fail "the sha256 UPSTREAM.md records is not a digest: $release_digest"
echo "5. UPSTREAM.md pins $artifact, which is the version include/curl/curlver.h carries"

# ---------------------------------------------------------------- 6. fork tags

# Every fork-authored source, build, packaging and script file carries
# SPDX-License-Identifier: curl on its own line inside the file's header
# comment. Position inside the block is deliberately not pinned: in this
# workspace the tag usually closes the header, below the lines that say what
# the file does not claim, and a rule demanding the first line would contradict
# the packages that already follow this convention. Files belonging to another
# owner may not have landed yet, so an absent file is skipped rather than
# failed -- a present one without the tag is a licence finding and names itself.
# The documentation and digest records are prose and data and carry the grant in
# prose; NOTICE.md names each of them.
fork_files=""
add_fork() {
    for p in "$@"; do
        if [ -e "$p" ]; then fork_files="$fork_files $p"; fi
    done
}
add_fork build.zig build.zig.zon build_support/* zig/* runtime/* \
    consumer/build.zig consumer/build.zig.zon consumer/src/main.zig \
    tests.zig smoke.zig tools/*.sh package.nix flake.nix devenv.nix \
    devenv.yaml .envrc .github/workflows/verify.yml cross-test.profile.sh \
    .gitignore
missing_tags=""
for p in $fork_files; do
    # zig/translate.h is excluded on purpose: it is the aggregate translation
    # header this build generates over the facade, and NOTICE.md records its
    # grant in prose rather than a tag inside generated bytes.
    if [ "$p" = "zig/translate.h" ]; then
        continue
    fi
    if ! grep -q 'SPDX-License-Identifier: curl' "$p"; then
        missing_tags="$missing_tags $p"
    fi
done
[ -z "$missing_tags" ] ||
    fail "fork-authored files with no SPDX-License-Identifier: curl:$missing_tags"
echo "6. every fork-authored source, build, packaging and script file present carries its SPDX tag"

echo
echo "provenance checks passed"
echo "not checked here: the sha256 of $artifact itself, which UPSTREAM.md records"
echo "as observed from the downloaded bytes and cross-checked by the detached"
echo "signature over those bytes; the tarball is not in this tree."