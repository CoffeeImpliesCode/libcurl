# Notice

## Upstream licence

Upstream identifies its licence as `curl`, not `MIT`. The licence text is `COPYING`.

Copyright attribution in `COPYING`:

> (c) 1996 - 2026, Daniel Stenberg, <daniel@haxx.se>, and many contributors, see the THANKS file

`COPYING` says `All rights reserved.` Its permission clause reads:

> Permission to use, copy, modify, and distribute this software for any purpose with or without fee

The warranty disclaimer includes `OF THIRD PARTY RIGHTS`. Its advertising clause reads:

> the name of a copyright holder shall not be used in advertising or otherwise to promote the sale, use or other dealings in this Software without prior written authorization

| Upstream path group | Licence and exception |
|---|---|
| `lib/**`, `include/**`, `COPYING`, `README`, `RELEASE-NOTES` | `curl`, except the rows below |
| `lib/curlx/inet_ntop.c` | ISC; `Copyright (C) 1996-2022 Internet Software Consortium.` |
| `lib/curlx/inet_pton.c` | ISC; `Copyright (c) Internet Software Consortium.` |
| `lib/vssh/vssh.c` | `curl AND ISC`; `Copyright (C) Daniel Stenberg, <daniel@haxx.se>, et al.` |
| `lib/md4.c`, `lib/md5.c` | `curl`; each contains Alexander Peslyak (Solar Designer)'s public-domain dedication and a two-clause BSD fallback grant |
| `lib/Makefile.in`, `include/Makefile.in`, `include/curl/Makefile.in` | `curl` and the FSF Automake notice |
| `README`, `RELEASE-NOTES`, `lib/curl_config.h.in`, `lib/libcurl.def`, `lib/libcurl.vers.in`, `COPYING` | `curl`; no SPDX line |

The MD4 and MD5 dedication reads:

> This software was written by Alexander Peslyak in 2001. No copyright is claimed, and the software is hereby placed in the public domain. In case this attempt to disclaim copyright and place the software in the public domain is deemed null and void, then the software is Copyright (c) 2001 Alexander Peslyak and it is hereby released to the general public under the following terms

Each file calls the embedded two-clause grant a `heavily cut-down BSD license` (`lib/md4.c:211`, `lib/md5.c:258`).

The Automake notice includes this grant:

> This Makefile.in is free software; the Free Software Foundation gives unlimited permission to copy and/or distribute it, with or without modifications, as long as this notice is preserved.

It also says `distributed in the hope that it will be useful … WITHOUT ANY WARRANTY`. The three `Makefile.in` files carry this copyright line:

> Copyright (C) 1994-2021 Free Software Foundation, Inc.

SPDX census: 408 files have one `curl` line; `lib/Makefile.in` has three `curl` lines; two files use `ISC`; `lib/vssh/vssh.c` uses `curl AND ISC`; six files have no SPDX line, as listed above.

## Other upstream attributions

Other copyright holders appear in 49 upstream files. These files remain under the applicable upstream licence above.

- Red Hat, Inc. and five credited authors (`lib/vssh/libssh.c`); Howard Chu (`lib/openldap.c`); Jacob Hoffman-Andrews, kpcyrd, and Daniel McCarney (`lib/vtls/rustls.c`).
- Marc Hoersken and Mark Salisbury (`lib/vtls/schannel.c`, `lib/vtls/schannel_verify.c`); Jan Venekamp (`lib/vtls/apple.h`, `lib/vtls/cipher_suite.c`, `lib/vtls/cipher_suite.h`); Hoi-Ho Chan (`lib/vtls/mbedtls.c`, `lib/vtls/mbedtls.h`).
- Steve Holme (`lib/system_win32.c`, `lib/system_win32.h`, `lib/curlx/version_win32.c`, `lib/curlx/version_win32.h`, `lib/vauth/vauth.c`, `lib/vauth/vauth.h`, `lib/vauth/krb5_gssapi.c`, `lib/vauth/digest_sspi.c`, `lib/curl_ntlm_core.c`).
- Linus Nielsen Feltzing (`lib/conncache.c`, `lib/conncache.h`, `lib/cshutdn.c`, `lib/cshutdn.h`); Björn Stenberg (`lib/mqtt.c`, `lib/mqtt.h`); Bill Nagel, Exacq Technologies (`lib/smb.c`, `lib/smb.h`); Markus Moeller (`lib/socks_gssapi.c`, `lib/socks_sspi.c`).
- Florin Petriuc (`lib/sha256.c`, `lib/curl_sha256.h`); Evgeny Grin (`lib/curl_sha512_256.c`, `lib/curl_sha512_256.h`); Simon Josefsson (`lib/vauth/gsasl.c`).

## Fork-authored files

Fork-authored files are covered by the `curl` terms in `FORK-LICENSE.md`, by the owner's per-project authorization; no upstream copyright or permission is claimed for them.

| Group | Paths |
|---|---|
| Build and ABI | `build.zig`, `build.zig.zon`, `build_support/` |
| Zig facade | `zig/root.zig`, `zig/translate.h` |
| Runtime loading | `runtime/loader.zig`, `runtime/generate.zig`, `runtime/graph.zig`, `runtime/library.zig`, `runtime/sync.c`, `runtime/sync.h` |
| Tests and consumer | `tests.zig`, `smoke.zig`, `consumer/build.zig`, `consumer/build.zig.zon`, `consumer/src/main.zig` |
| Packaging | `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`, `cross-test.profile.sh`, `.gitignore` |
| Provenance and licence | `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `FORK-LICENSE.md`, `tools/check-provenance.sh` |
| Documentation | `README.md`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md` |

No fork-authored files are under `lib/` or `include/`. The upstream names at the package root are `COPYING`, `README`, and `RELEASE-NOTES`; the fork README is `README.md`.

Fork-authored source, build, packaging, and script files carry `SPDX-License-Identifier: curl`. The documentation and digest records `NOTICE.md`, `UPSTREAM.md`, `UPSTREAM.sha256`, `README.md`, `README.zig.md`, `FORK-LICENSE.md`, `CHANGELOG.md`, and `FORK-NOTES.md` have no SPDX line; their grant is in `FORK-LICENSE.md`. The checked-in `zig/translate.h` has no SPDX line because it is generated from the facade.
