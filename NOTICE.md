# Notice

Two separate things are recorded here: what the canonical native source is and
which grant covers each of its files, and what this fork wrote on top of it.
[`FORK-LICENSE.md`](FORK-LICENSE.md) carries the grant for the second group.

## The upstream term

curl's grant is the `curl` licence, and its authoritative copy in this tree is
upstream's own file:

* `COPYING` — 1088 bytes, sha256
  `82f2f4427d6545ee5aaac4f0b80428da6cc8ba41c2cf5da3a03680ec327b9681`, the
  first record in [`UPSTREAM.sha256`](UPSTREAM.sha256). Its title line is
  `COPYRIGHT AND PERMISSION NOTICE` (`:1`), the copyright runs
  `(c) 1996 - 2026, Daniel Stenberg, <daniel@haxx.se>, and many contributors,
  see the THANKS file` (`:3-4`), the permission is `:8-10`, the warranty
  disclaimer `:12-18` and the advertising clause `:20-22`.

**It is a permissive MIT/X derivative, not stock MIT**, and the difference is
worth four lines because a downstream scanner will notice it. Stock MIT says
"Permission is hereby granted, free of charge"; curl says "Permission to use,
copy, modify, and distribute this software for any purpose with or without
fee" (`COPYING:8-9`), which is the X11 phrasing. curl adds `All rights
reserved.` after the copyright (`:6`). curl's warranty disclaimer adds
`OF THIRD PARTY RIGHTS` to the enumeration (`:14`). And curl keeps the
advertising clause at `:20-22`, which stock MIT does not have: *the name of a
copyright holder shall not be used in advertising or otherwise to promote the
sale, use or other dealings in this Software without prior written
authorization*. So `curl`, not `MIT`, is the identifier upstream itself writes
into its files, and it is the identifier this fork uses.

### How the tree declares it, and how that was counted

Every file was checked by reading it: one pass over the 418 paths
[`UPSTREAM.sha256`](UPSTREAM.sha256) names, collecting each
`SPDX-License-Identifier` line from each file. The result is **not** one label:

| Identifier as written | Files | Which |
|---|---:|---|
| `SPDX-License-Identifier: curl` (one line) | 408 | the vendored `.c`, `.h`, `.am`, `.inc`, `.pl`, `.rc` and markdown files, including the internal headers and the build-system files this fork does not execute; the six untagged files listed below are the exceptions |
| `SPDX-License-Identifier: curl` (three such lines) | 1 | `lib/Makefile.in`, which repeats the block once per list it carries |
| `SPDX-License-Identifier: ISC` | 2 | `lib/curlx/inet_ntop.c`, `lib/curlx/inet_pton.c` |
| `SPDX-License-Identifier: curl AND ISC` | 1 | `lib/vssh/vssh.c` |
| **no SPDX line at all** | 6 | `COPYING`, `README`, `RELEASE-NOTES`, `lib/curl_config.h.in`, `lib/libcurl.def`, `lib/libcurl.vers.in` |

412 of the 418 files therefore carry an SPDX identifier and 409 of those carry
`curl` as the identifier. The claim that "every vendored file carries
`SPDX-License-Identifier: curl`" is close and not true, and the six exceptions
are named individually below rather than left to a reader's guess.

## Inventory of the upstream files

418 files, 6535699 bytes, digests in [`UPSTREAM.sha256`](UPSTREAM.sha256). The
term is `curl` unless the row says otherwise.

| Path | Count | Term | Notice in the file |
|---|---:|---|---|
| `COPYING` | 1 | curl | **the licence text itself**, verbatim; no SPDX tag, because the file *is* the notice |
| `README` | 1 | curl | **none in the file** — upstream's release note, which points readers at `docs/`, which this fork does not vendor |
| `RELEASE-NOTES` | 1 | curl | **none in the file** — a change log; no licence block and no SPDX tag |
| `include/curl/*.h` | 12 | curl | the standard block and `SPDX-License-Identifier: curl`; these are the public headers (`curl.h`, `curlver.h`, `easy.h`, `header.h`, `mprintf.h`, `multi.h`, `options.h`, `stdcheaders.h`, `system.h`, `typecheck-gcc.h`, `urlapi.h`, `websockets.h`) |
| `include/curl/Makefile.am`, `include/Makefile.am` | 2 | curl | the standard block and tag |
| `include/README.md` | 1 | curl | the standard block in an HTML comment, `:2-4` |
| `include/Makefile.in`, `include/curl/Makefile.in` | 2 | curl **and** the FSF automake notice | automake's own notice at `:4-13`, then the curl block and tag further down |
| `lib/**/*.c` | 197 | curl, with three exceptions below | the standard block and tag; 196 are the compile closure and `dllmain.c` is the Windows entry point upstream does not list |
| `lib/**/*.h` | 190 | curl | the standard block and tag; internal headers, plus `config-mac.h`, `config-os400.h` and `config-win32.h`, which are platform configuration headers rather than a listed unit |
| `lib/Makefile.am`, `lib/Makefile.inc`, `lib/Makefile.soname`, `lib/CMakeLists.txt`, `lib/optiontable.pl`, `lib/libcurl.rc` | 6 | curl | the standard block and tag; build-system and resource files this fork **does not execute** — `lib/Makefile.inc` is read, as the closure record, but no rule of it is run |
| `lib/Makefile.in` | 1 | curl **and** the FSF automake notice | automake's notice at `:4-13`, then three curl blocks at `:37`, `:62` and `:1279` |
| `lib/curl_config.h.in`, `lib/curl_config-cmake.h.in` | 2 | curl | the first is **untagged**: `lib/curl_config.h.in:3` is `/* !checksrc! disable COPYRIGHT all */`, upstream's own instruction that this generated input carries no notice. The second carries the standard block and `:663` `#cmakedefine USE_MBEDTLS 1` |
| `lib/libcurl.def` | 1 | curl | **none in the file** — a bare `EXPORTS` symbol list |
| `lib/libcurl.vers.in` | 1 | curl | **none in the file** — a linker version script with `@...@` substitutions |

### Files whose notice is not simply curl

These are the six places where a single label over this tree would be wrong.
Each is named with its term and its line.

**`lib/curlx/inet_ntop.c` — ISC.** `Copyright (C) 1996-2022 Internet Software
Consortium.` at `:2`, the full ISC permission at `:4-15`, and
`SPDX-License-Identifier: ISC` at `:17`. There is no curl identifier anywhere
in the file. This is upstream's BIND-derived `inet_ntop`, and the ISC grant is
what makes redistributing the unit lawful.

**`lib/curlx/inet_pton.c` — ISC.** `:1` records the provenance in upstream's own
words, *"This is from the BIND 4.9.4 release, modified to compile by
itself"*; `Copyright (c) Internet Software Consortium.` at `:3`, the ISC
permission at `:5-16`, `SPDX-License-Identifier: ISC` at `:18`. Again no curl
identifier in the file.

**`lib/vssh/vssh.c` — `curl AND ISC`, a dual grant.** `:8` credits
`Copyright (C) Daniel Stenberg, <daniel@haxx.se>, et al.`, `:10-16` point at
`COPYING` and <https://curl.se/docs/copyright.html>, and `:21` is
`SPDX-License-Identifier: curl AND ISC`. That line offers a consumer either
term; the file's own prose points only at `COPYING`, so this inventory records
both identifiers rather than picking one. The ISC side of the pair is the grant
that appears verbatim in the two `curlx/inet_*.c` files above.

**`lib/md4.c` and `lib/md5.c` — public domain, inside curl files.** Both files
are `curl` overall (`SPDX-License-Identifier: curl` at `:21` in each), and both
carry a second, different grant in a nested block: `lib/md4.c:196-212` and
`lib/md5.c:243-259` hold Alexander Peslyak's (Solar Designer) dedication —
*"This software was written by Alexander Peslyak in 2001. No copyright is
claimed, and the software is hereby placed in the public domain. In case this
attempt to disclaim copyright and place the software in the public domain is
deemed null and void, then the software is Copyright (c) 2001 Alexander Peslyak
and it is hereby released to the general public under the following terms"*,
ending in a two-clause BSD that the file itself calls *"a heavily cut-down
BSD license"* (`:211` and `:258`). The blocks sit inside the `#else` at
`lib/md4.c:186` and `lib/md5.c:232`, so they are the fallback taken when no
crypto backend supplies that digest. That is reachable in this configuration
rather than certainly dead: `lib/md4.c` has branches for OpenSSL (`:47`),
wolfSSL (`:56`), Apple CommonCrypto (`:83`) and Win32 crypto (`:111`) and **no
mbed-TLS branch**, so with `USE_MBEDTLS` and no other backend the fallback is
what compiles. `lib/md5.c` does have an mbed-TLS branch (`:123`), and it is
taken only when `PSA_WANT_ALG_MD5` is defined in the generated
`curl_config.h`; otherwise the fallback is. Which of the two applies is
`PENDING-VERIFICATION`, because it depends on the configuration header this
fork generates. The consequence for a consumer is the same either way and is
why it is written here: the terms ship with the source.

**`lib/Makefile.in`, `include/Makefile.in`, `include/curl/Makefile.in` — the FSF
automake notice.** `:1` is `# Makefile.in generated by automake 1.16.5 from
Makefile.am.`, `:4` is `# Copyright (C) 1994-2021 Free Software Foundation,
Inc.`, and `:6-8` is its grant: *"This Makefile.in is free software; the Free
Software Foundation gives unlimited permission to copy and/or distribute it,
with or without modifications, as long as this notice is preserved"*, followed
by `:10-13` "distributed in the hope that it will be useful … WITHOUT ANY
WARRANTY". That is a separate grant travelling inside a curl file, and it
travels precisely because this fork vendors build-system files it does not
execute: no make rule in any of the three is ever run here, but the bytes are
in the tree and in the digest record.

**`COPYING`, `README`, `RELEASE-NOTES`, `lib/curl_config.h.in`,
`lib/libcurl.def`, `lib/libcurl.vers.in` — no SPDX line, and what they carry
instead.** `COPYING` carries the licence text itself. `README` and
`RELEASE-NOTES` are upstream prose: `README` is 25 lines of ASCII-art logo and
a paragraph telling the reader to study `COPYING` for distribution terms, and
`RELEASE-NOTES` is 8.22.0's change log. `lib/curl_config.h.in` disables its own
notice check at `:3`. `lib/libcurl.def` and `lib/libcurl.vers.in` are symbol
and version-script templates with no comment block at all. None of the six is
unlicensed: they are covered by the same grant as the rest of the tarball, and
`lib/libcurl.rc:57` is the one place upstream restates it in another form —
`VALUE "License", "https://curl.se/docs/copyright.html\0"`, with `:56` setting
`VALUE "LegalCopyright"` from `LIBCURL_COPYRIGHT`, the macro
`include/curl/curlver.h:30-31` defines.

### Author credits that are not a different term

Forty-nine files name an author other than the standard
`Copyright (C) Daniel Stenberg, <daniel@haxx.se>, et al.` line, and every one
of them is still `curl`. They are listed here because a per-file inventory that
quietly drops them would misreport the copyright line, not the licence:

* `lib/vssh/libssh.c:8` — `Copyright (C) Red Hat, Inc.`, with the five Red Hat
  authors named at `:10-11`.
* `lib/openldap.c:9` — `Copyright (C) Howard Chu, <hyc@openldap.org>`.
* `lib/vtls/rustls.c:8-10` — Jacob Hoffman-Andrews, kpcyrd and Daniel McCarney.
* `lib/vtls/schannel.c:9-10` and `lib/vtls/schannel_verify.c:8-9` — Marc
  Hoersken and Mark Salisbury.
* `lib/vtls/apple.h:10`, `lib/vtls/cipher_suite.c:8`, `lib/vtls/cipher_suite.h:10`
  — Jan Venekamp.
* `lib/vtls/mbedtls.c:9`, `lib/vtls/mbedtls.h:11` — Hoi-Ho Chan.
* Steve Holme in `lib/system_win32.c:8`, `lib/system_win32.h:10`,
  `lib/curlx/version_win32.c:8`, `lib/curlx/version_win32.h:10`,
  `lib/vauth/vauth.c:8`, `lib/vauth/vauth.h:10`, `lib/vauth/krb5_gssapi.c:8`,
  `lib/vauth/digest_sspi.c:8`, and `lib/curl_ntlm_core.c:105`.
* Linus Nielsen Feltzing in `lib/conncache.c:8`, `lib/conncache.h:11`,
  `lib/cshutdn.c:8`, `lib/cshutdn.h:11`.
* Björn Stenberg in `lib/mqtt.c:9`, `lib/mqtt.h:10`. Bill Nagel (Exacq
  Technologies) in `lib/smb.c:9`, `lib/smb.h:10`. Markus Moeller in
  `lib/socks_gssapi.c:9`, `lib/socks_sspi.c:9`. Florin Petriuc in `lib/sha256.c:8`
  and `lib/curl_sha256.h:10`. Evgeny Grin in `lib/curl_sha512_256.c:8` and
  `lib/curl_sha512_256.h:10`. Simon Josefsson in `lib/vauth/gsasl.c:8`.

## There is no vendored third-party material

No dependency is vendored, no table is downloaded, no external header is
fetched into this tree. mbed-TLS is consumed through the Zig dependency
mechanism from `../mbed-tls` and appears in this repository only as a
dependency name. There is no generated table beyond `curl_config.h`, which this
fork generates into the build cache. The ISC and public-domain material
described above is inside upstream's own release, not a package this fork
pulls in, so there is no dependency closure here to describe — and saying so
plainly is more accurate than implying one.

## What this fork changed in upstream files

**Nothing.** All 418 recorded files are the tarball's bytes, unedited, and the
418 are the complete vendored set. The integration owner of this package ran
`sha256sum -c UPSTREAM.sha256` in the package root and observed it exit 0 with
no mismatched record, and counted 415 files under `lib/` and `include/` plus
`COPYING`, `RELEASE-NOTES` and `README`. That is a checksum run the integration
owner performed, **not** one of the driver's gates, and no other result is
claimed here. `UPSTREAM.sha256` plus the exact-file-set check in
`tools/check-provenance.sh` are what make the claim checkable rather than
asserted; any future native edit has to move those digests in the same change,
with a numbered entry in [`CHANGELOG.md`](CHANGELOG.md).

`STATUS`: `SOURCE-CONFIRMED` from the recorded digests and from reading the
files named above. This inventory says nothing about a build. README.md carries
whatever the driver observed, and every gate it has not covered is marked
`PENDING-VERIFICATION` there; those are that file's observations, not this
one's.

Upstream's attribution obligation is unaffected by any of the above: a consumer
who receives a libcurl binary, static library, shared object or header set still
owes the notice in `COPYING`, and that file travels with the imported tree.
Where the installed copy places it is the packaging owner's decision and is not
asserted here.

## Fork-specific notice

Every file below was written for this fork. **None of it carries an upstream
copyright, no upstream permission is claimed over it, and no upstream author is
attributed to any of it.** It is released under the `curl` terms recorded in
[`FORK-LICENSE.md`](FORK-LICENSE.md), by the owner's per-project authorization:

* **Build and ABI** — `build.zig`, `build.zig.zon`, and `build_support/`, whose
  `curl_config_gen.c` is the host-target C generator for `curl_config.h`.
* **Zig facade** — `zig/root.zig` and `zig/translate.h`, the aggregate
  translation header.
* **Runtime-loading route** — `runtime/loader.zig`, `runtime/generate.zig`,
  `runtime/graph.zig`, `runtime/library.zig`, `runtime/sync.c`,
  `runtime/sync.h`.
* **Behaviour** — `tests.zig`, `smoke.zig`, and `consumer/` (`build.zig`,
  `build.zig.zon`, `src/main.zig`).
* **Packaging** — `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`,
  `.envrc`, `.github/workflows/verify.yml`, `cross-test.profile.sh`,
  `.gitignore`.
* **Provenance and licence** — `UPSTREAM.md`, `UPSTREAM.sha256` (a data
  record read line by line by `sha256sum -c`, not a source file with a header
  comment to tag), `NOTICE.md`, `FORK-LICENSE.md`,
  `tools/check-provenance.sh`.
* **Documentation** — `README.md`, `README.zig.md`, `CHANGELOG.md`,
  `FORK-NOTES.md`.

The fork adds **no** file under `lib/`, `include/`, and **no** file at the
package root that shadows an upstream name: the only upstream names at the
root are `COPYING`, `README` and `RELEASE-NOTES`, and this fork's own README is
`README.md`.

### Which of those files carry the SPDX tag

Every fork-authored **source, build, packaging and script** file carries
`SPDX-License-Identifier: curl` on its own line inside the file's header
comment. The position inside the block is deliberately not pinned: in this
workspace the tag closes the header, below the lines that say what the file
does not claim, and `tools/check-provenance.sh` checks for the tag's presence
rather than its line. The eight
documentation and digest records — this file, `UPSTREAM.md`,
`UPSTREAM.sha256`, `README.md`, `README.zig.md`, `FORK-LICENSE.md`,
`CHANGELOG.md`, `FORK-NOTES.md` — are prose and data with no comment position a
tag is expected in, and their grant is the same `curl` text; they are named
individually here so that a scanner finding no identifier in `README.md` reads a
recorded reason rather than an apparent gap.

`zig/translate.h` is recorded here as carrying the same grant in prose: it is a
C header generated from the facade, and the tag line inside a generated
translation is a build-time artefact of that generation rather than a fact
about the checked-in bytes.

The per-file tag census over the fork files is `PENDING-VERIFICATION` while the
other owners of this package are still landing their files;
`tools/check-provenance.sh` asserts the tag on every fork source, build,
packaging and script file that is present in the tree, and names the file that
fails if one is missing.