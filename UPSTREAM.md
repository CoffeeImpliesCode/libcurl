# Upstream

Which upstream this SDK is built from, what was taken from it byte for byte,
and what was not taken at all.

## Canonical source

| | |
|---|---|
| Project | curl |
| Authoritative site | <https://curl.se/> |
| Artifact | `curl-8.22.0.tar.xz` |
| URL | <https://curl.se/download/curl-8.22.0.tar.xz> |
| Released | 2026-09-02 |
| Size | 2953092 bytes |
| sha256 | `f7ef3ae8a22e521f289803fe93543eb64c329b58aa73a9e224dfd915a2a5f4f7` |
| Signature | `curl-8.22.0.tar.xz.asc`, 488 bytes, detached PGP, RSA key `27ED EAF2 2F3A BCEB 50DB 9A12 5CC9 08FD B71E 12C2`, Daniel Stenberg \<daniel@haxx.se\> |
| Digests published at | **nowhere** — read the next section before trusting the row above |

`SOURCE-CONFIRMED`: every value in that table was read from the downloaded
artifact or from a file curl publishes, never assumed. The version inside the
tree agrees with it — `include/curl/curlver.h:35` is
`#define LIBCURL_VERSION "8.22.0"`, `:39-41` are major 8, minor 22, patch 0,
and `:60` is `#define LIBCURL_VERSION_NUM 0x081600`.

### Where the digest came from, and what independently cross-checks it

curl.se publishes **detached signatures, not a checksum file**. A request for
`curl-8.22.0.tar.xz.sha256` returned HTTP 404, which is how this package knows
there is no upstream digest to quote. So the digest above is **observed**: it
was computed with `sha256sum` over the bytes that were downloaded, and nothing
upstream printed it. It is **cross-checked** independently by the detached
signature over those same bytes: `gpg --verify` reported a good signature from
the key above, with unsigned trust because the key was fetched separately and
is not in a local web of trust. The fingerprint is not taken from the
signature alone — curl.se/docs/verify.html names it as the release manager's
key, and that page carries the spaced form
`27ED EAF2 2F3A BCEB 50DB 9A12 5CC9 08FD B71E 12C2` verbatim.

Two consequences worth stating plainly, because this is the kind of claim that
gets fabricated in the other direction:

* This file does **not** say the digest was printed in curl's checksum column.
  There is no checksum column for this artifact.
* This file records **no commit SHA and no tag**, because a release tarball has
  no VCS import to point at. `curl-8.22.0` is a release name, not a commit.

`tools/check-provenance.sh` cannot recompute the tarball digest: the tarball is
not shipped in this repository. What it can check is the file set this release
was imported into, and it says so in its own output rather than implying a
tarball it never saw.

## What upstream is

curl is two programs in one release: the `curl` command-line transfer tool and
**libcurl**, the C library the tool is written on top of. This SDK takes the
library and nothing of the tool.

The release tarball is large because it carries everything needed to build and
test both: 4406 files, 22 239 154 bytes after extraction. libcurl itself — the
`lib/` and `include/` directories and the three licence/release files — is 418
of those files and 6535699 bytes, which is what this tree holds.

Upstream builds all of it with autotools and CMake, both generated from the
same `Makefile.inc` file list. This SDK uses neither; `build.zig` compiles the
same source list. See README.md, "Native-build deviations".

## The preserved upstream README

The release tarball ships a file called `README`, which is upstream's own
release note and **not** a fork README. It is preserved here under its own
name, unaltered: `README`, 1461 bytes, sha256
`4e3177f14f86cac279e34a80001da61fdf0476f68cf647c9b52f5422d7a132a0`, and it is
one of the 418 records in [`UPSTREAM.sha256`](UPSTREAM.sha256), so a plain
`sha256sum -c` covers it.

There is deliberately **no second copy** under the `README.upstream.md` name
that other forks in this workspace use. Two reasons, and both are about not
shipping an unchecked file: `build.zig.zon`'s `.paths` is the package file
filter and does not name one, and a copy that the digest record does not cover
would be a file in the tree that nothing in this repository verifies. The
canonical fork document is [`README.md`](README.md).

## What is in the tarball, and what is vendored here

Vendored, whole and byte for byte:

| Path | Files | Bytes | What it is |
|---|---:|---:|---|
| `lib/` | 398 | 6199635 | the library: sources, internal headers, and upstream's own build-system files |
| `include/` | 17 | 302333 | the 12 public headers plus `Makefile.am`, `Makefile.in` and `README.md` |
| `COPYING` | 1 | 1088 | the `curl` licence text, verbatim, sha256 `82f2f4427d6545ee5aaac4f0b80428da6cc8ba41c2cf5da3a03680ec327b9681` |
| `RELEASE-NOTES` | 1 | 31182 | upstream's release note for 8.22.0 |
| `README` | 1 | 1461 | upstream's release note, preserved above |

The two source directories are the tarball's directories whole: 398 and 17
files, and the byte counts above are the counts in the extracted archive, not
an approximation of them.

Not vendored, each for a stated reason:

* `src/` (97 files) — the command-line tool. It is a different program that
  happens to link libcurl; this SDK publishes the library.
* `tests/` (2645 files) — upstream's own test suite, discussed below.
* `docs/` (1071), `scripts/` (35), `projects/` (64), `CMake/` (31), `m4/` (25),
  the autotools files at the archive root (`configure`, `configure.ac`,
  `Makefile.am`, `Makefile.in`, `aclocal.m4`, `acinclude.m4`, `libtool`-era
  companions), `CMakeLists.txt` and `libcurl.pc.in` — none of it is referenced
  by the compile closure.

### The load-bearing reason: the closure is two directories

The exclusion list above is not a preference. Every `#include "..."` in the
196 C units, the 187 headers upstream lists, `dllmain.c` and the three platform
configuration headers — the 387 files a build of this library can reach —
resolves to a file inside `lib/` or inside `include/`, with exactly two
exceptions:

* `lib/curl_setup.h:140` — `#include "curl_config.h"`, the generated header
  this fork generates itself (see below).
* `lib/curl_ntlm_core.c:84` — `#include "cipher.mih"`, the OS/400 middleware
  header, inside the `#elif defined(USE_OS400CRYPTO)` branch at `:83`.

`<curl/curl.h>`, `<curl/system.h>`, `<curl/mprintf.h>` and `<curl/urlapi.h>`
appear as angle includes six times inside `lib/` and resolve into
`include/curl/`. Everything else in angle brackets is a system header. So a
build that has `lib/` and `include/` plus the generated `curl_config.h` has the
whole closure, and nothing outside `src/`, `tests/`, `docs/`, `scripts/`,
`projects/`, `CMake/`, `m4/` or the autotools files is reachable from a
compiled unit.

## The core closure, as upstream lists it

`lib/Makefile.inc:439-446` is the definition, read out of upstream rather than
derived:

```make
CSOURCES = $(LIB_CFILES) $(LIB_VAUTH_CFILES) $(LIB_VDNS_CFILES) \
  $(LIB_VTLS_CFILES) $(LIB_VQUIC_CFILES) $(LIB_VSSH_CFILES) $(LIB_CURLX_CFILES)
HHEADERS = $(LIB_HFILES) $(LIB_VAUTH_HFILES) $(LIB_VDNS_HFILES) \
  $(LIB_VTLS_HFILES) $(LIB_VQUIC_HFILES) $(LIB_VSSH_HFILES) $(LIB_CURLX_HFILES)
```

Counting the names in those seven C groups and those seven header groups gives:

* **196 C units** — `LIB_CFILES` 127, `LIB_VAUTH_CFILES` 13, `LIB_VDNS_CFILES`
  10, `LIB_VTLS_CFILES` 16, `LIB_VQUIC_CFILES` 8, `LIB_VSSH_CFILES` 3,
  `LIB_CURLX_CFILES` 19.
* **187 headers** — `LIB_HFILES` 132, `LIB_VAUTH_HFILES` 2, `LIB_VDNS_HFILES`
  6, `LIB_VTLS_HFILES` 17, `LIB_VQUIC_HFILES` 9, `LIB_VSSH_HFILES` 2,
  `LIB_CURLX_HFILES` 19.

`build.zig` compiles all 196. Upstream's own design is that a unit whose
feature macro is absent still stays on the list and compiles to an empty
translation unit; it is never dropped from the list. Read the first `#if` of
each unit and it is the same story 196 times: `lib/vquic/cf-ngtcp2.c:26`
(`USE_NGTCP2` and `USE_NGHTTP3`), `lib/vssh/libssh2.c:26` (`USE_LIBSSH2`),
`lib/openldap.c:27` (`!CURL_DISABLE_LDAP && USE_OPENLDAP`),
`lib/curl_gssapi.c:26` (`HAVE_GSSAPI`), `lib/memdebug.c:26`
(`CURL_MEMDEBUG`), `lib/amigaos.c:26` (`__AMIGA__`), `lib/system_win32.c:26`
(`_WIN32`). Of the 196, 11 have no `#if` at all, 14 open on `DEBUGBUILD`, 13 on
`HAVE_NETINET_IN_H` and 9 on `_WIN32`; the rest open on a feature or
platform macro of their own. Never substitute a smaller source list.

Which of those units produces code in this fork's configuration depends on the
macros the generated `curl_config.h` carries, and that is `build.zig`'s
decision, not a fact this file can assert. It is `PENDING-VERIFICATION` until
the driver runs the build.

The vendored `lib/` is larger than the closure, and the difference is four
files upstream does not put on either list: `dllmain.c`, the Windows DLL entry
point, and `config-mac.h`, `config-os400.h`, `config-win32.h`, the platform
configuration headers `curl_setup.h` selects at compile time. They are vendored
because they are part of upstream's directory, and they are digested because
they are bytes from the tarball — but neither fact makes them compiled units,
and `tools/check-provenance.sh` checks both directions of that: every listed
unit must be present and digested, and the digested files that no list names
must be exactly those four.

## The one generated input

`lib/curl_setup.h:140` includes `curl_config.h`, which does not exist in the
tarball. Upstream generates it two ways, from `lib/curl_config.h.in`
(`#undef USE_MBEDTLS` at `:840`, autoconf's autoheader output) and from
`lib/curl_config-cmake.h.in` (`#cmakedefine USE_MBEDTLS 1` at `:663`). This
package uses neither and runs no configure step: per AGENTS.md §5 the generated
input is a deterministic build step from a host-target C generator,
`build_support/curl_config_gen.c`, compiled for the host and run with the
target's facts as arguments. It is the only file this fork generates outside
the runtime-loading route, and both it and the runtime dispatch land in the
build cache rather than in this tree. `PENDING-VERIFICATION`.

## The TLS backend is upstream's own macro

The backend is mbed-TLS, selected by upstream's own macro:
`USE_MBEDTLS` appears in the `USE_SSL` derivation at `lib/curl_setup.h:727`, in
the backend dispatch at `lib/vtls/vtls.c:693` and again in the available-backend
table at `:712`, and it opens `lib/vtls/mbedtls.c:32`. No other `USE_*SSL*`
macro is defined anywhere in this package.

mbed-TLS is **not vendored in this tree**. It is consumed through the Zig
dependency mechanism from the sibling package, and there is no fork-private
bridge and no fallback. The sibling package is present on disk; the wire itself
is `PENDING-VERIFICATION`, because no gate has yet run against it.

## Upstream's test suite is in the tarball, and this fork does not ship it

This is not Lua's situation, where the release tarball has no tests at all.
curl's tarball carries 2645 files under `tests/`: the suite is driven by perl —
`tests/Makefile.am:120` runs `@PERL@ ... $(srcdir)/runtests.pl`, and the
`tests` target at `:146-147` runs `perlcheck` first — and its programs link the
`tests/libtest/` C helper library, with `tests/unit/` holding 84 unit-test
sources of its own.

Two consequences are binding here. This SDK does **not** claim to ship, build
or run that suite, and no build step fetches one to stand in for it: a fetched
suite would be a different source tree than the pinned release, with no
recorded digest, and a `zig build test` step that quietly downloaded it would
be testing something this package does not name. The SDK's own behavioural
tests are independent known answers and are described in README.zig.md.

## Import mechanism

A release tarball, imported whole. There is no upstream Git history in this
tree, no commit SHA to record, and no patch series: the tree either matches the
tarball or a deviation is recorded. `UPSTREAM.sha256` is the check that it does,
together with the exact-file-set check in `tools/check-provenance.sh`.

The one observation about these bytes so far is recorded in
[`NOTICE.md`](NOTICE.md), "What this fork changed in upstream files": the
integration owner of this package ran `sha256sum -c UPSTREAM.sha256` in the
package root and observed it exit 0 with no mismatched record. That is a
checksum run the integration owner performed, not one of the driver's gates,
and this file claims nothing beyond it.

If a future wave re-syncs to another release, the correct sequence is: download
the new tarball, verify its detached signature and the digest observed from
those bytes, replace the imported files, update `UPSTREAM.sha256`,
`UPSTREAM.md`, `NOTICE.md` and `README.md`, and add a numbered `CHANGELOG.md`
entry — in one change.

## Third-party material in this repository

None. No dependency is vendored, no table is downloaded and no external header
is fetched into the tree. mbed-TLS is consumed through the Zig dependency
mechanism from `../mbed-tls` and appears here only as a dependency name.

Upstream's own tree does carry material with its own terms inside `lib/` — two
ISC files inherited from BIND 4.9.4 and a public-domain MD4/MD5
implementation — and that is upstream's business inside its release, recorded
per file in [`NOTICE.md`](NOTICE.md) rather than summarised into one label. It
is not a vendored third-party package and there is no dependency closure here
to describe.