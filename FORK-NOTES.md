# Fork notes

The working record for this SDK: what was decided, where the fact came from,
and what each decision does **not** prove.

**No gate has been run.** Nothing in this file is a receipt. Statements read out
of a file or a manifest are `SOURCE-CONFIRMED`; decisions are `CONSTRAINT`;
anything reasoned but unexecuted is a `HYPOTHESIS`; every landed correction with
no gate behind it is `PENDING-VERIFICATION`; §11 is the list of what the driver
still has to run and what is still open.

## 1. The import, and what verifies it

A release tarball, imported whole and verified by sha256. `SOURCE-CONFIRMED`:
`curl-8.22.0.tar.xz`, released 2026-09-02, 2953092 bytes, sha256
`f7ef3ae8a22e521f289803fe93543eb64c329b58aa73a9e224dfd915a2a5f4f7`, extracting
to 4406 files totalling 22 239 154 bytes.

**There was no `git clone`, no submodule and no history**, so there is no commit
SHA to record and no patch series: a release name is not a commit, and inventing
a revision from one would be a fabricated identifier. The identity of the
imported bytes is the release digest and the per-file digests.

418 files, 6535699 bytes, out of 4406 in the archive. `sha256sum -c
UPSTREAM.sha256` checks the bytes; `tools/check-provenance.sh` additionally
checks the exact file set, which a checksum run cannot see — a file added under
`lib/` or `include/` with no recorded digest would pass `sha256sum -c` and mean
nothing.

**The digest is observed, not quoted, and the reason is worth keeping.** curl.se
publishes detached signatures and **no checksum file**: a request for
`curl-8.22.0.tar.xz.sha256` returned HTTP 404, which is how this package knows
there is no upstream digest to print. The digest above was therefore computed
with `sha256sum` over the downloaded bytes, and it is cross-checked
independently by the detached signature over those same bytes: `gpg --verify`
reported a good signature from the key named in `UPSTREAM.md`, with unsigned
trust because the key was fetched separately. This repository does **not** claim
the digest appears in a curl checksum column. There is no such column.

**Bound to:** this project, and the same rule applies to any tarball-only import
in this workspace — record the digest you computed, say that you computed it,
and do not let a signature stand in for a checksum file that does not exist.

## 2. The source closure: 196 units, and four files that are not among them

`SOURCE-CONFIRMED`: the seven C groups and seven header groups of
`lib/Makefile.inc` are the closure definition, read out of upstream rather than
derived. 196 C units — 127 + 13 + 10 + 16 + 8 + 3 + 19 — and 187 headers —
132 + 2 + 6 + 17 + 9 + 2 + 19. `build.zig` compiles all 196, transcribed in
upstream's own order with the make variable and line range of each group in the
comments rather than globbed.

**Why a transcription and not a glob.** A glob cannot be diffed against
`Makefile.inc`, so an upstream release that added a unit would silently not be
compiled by a fork whose list was a glob, and the first sign would be a link
error naming a symbol nobody expected to be missing. A transcription carries the
line range beside each group, so the check is a text comparison.

**Why nothing is dropped.** Upstream's own design is that a unit whose feature
macro is absent still compiles — to an empty translation unit — and is never
left out of the list. The first `#if` of each unit is a guard, not an include:
`lib/vquic/cf-ngtcp2.c:26`, `lib/vssh/libssh2.c:26`, `lib/openldap.c:27`,
`lib/curl_gssapi.c:26`, `lib/memdebug.c:26`, `lib/amigaos.c:26`,
`lib/system_win32.c:26`, `lib/http2.c:26`, `lib/psl.c:26`,
`lib/curl_ntlm_core.c:26`. Of the 196, 11 have no `#if` at all, 14 open on
`DEBUGBUILD`, 13 on `HAVE_NETINET_IN_H` and 9 on `_WIN32`.

A unit in the list whose guard is absent costs nothing at link time; a unit
*missing* from the list would take a protocol or a hash algorithm with it.
`HYPOTHESIS`, reasoned and not run: a future release that adds a unit and does
not add it to `Makefile.inc`'s groups would not be caught by any check in this
repository. Not observed; not worth provoking.

Four vendored files are upstream's directory rather than its compile list:
`dllmain.c` (the Windows DLL entry point) and `config-mac.h`, `config-os400.h`,
`config-win32.h` (the platform configuration headers `curl_setup.h` selects at
compile time). They are vendored because they are part of `lib/`, and digested
because they are bytes from the tarball — neither fact makes them compiled
units, and `tools/check-provenance.sh` checks both directions: every listed unit
must be present and digested, and the digested files no list names must be
exactly those four.

The load-bearing reason nothing else is vendored: every `#include "..."` in the
387 files a build can reach resolves inside `lib/` or `include/`, with exactly
two exceptions — `lib/curl_setup.h:140` and `lib/curl_ntlm_core.c:84`'s
`cipher.mih` inside the OS/400 branch. So "which directories are vendored" is
answerable from the sources rather than from preference.

## 3. The one generated input

`lib/curl_setup.h:138-140` sends a `HAVE_CONFIG_H` build to `curl_config.h`,
which does not exist in the tarball. Upstream generates it two ways, from
`lib/curl_config.h.in` (`#undef USE_MBEDTLS` at `:840`, autoconf's autoheader
output) and from `lib/curl_config-cmake.h.in` (`#cmakedefine USE_MBEDTLS 1` at
`:663`).

This package uses **neither** and runs no configure step.
`build_support/curl_config_gen.c` is a host-target C generator handed the
target's OS, architecture, pointer width, endianness and libc as argv. Three
properties of it are the whole point:

* It runs **for the host** and is **given the target's facts**. Running it on an
  x86_64 Linux build host to configure `aarch64-macos-none` is correct; copying
  the host's platform macros onto a cross target is the failure AGENTS.md §5
  forbids. The program contains no `#ifdef` on any host macro and includes no
  host header.
* Its output is a `.generated` `LazyPath` and `build.zig` never calls
  `LazyPath.getPath` on it. `getPath4` (`lib/std/Build.zig:2488-2510`) panics
  for a `.generated` path whose `gen.file.path` is still unset, and that is unset
  until the make phase assigns it — so the path reaches the compile line as a
  `LazyPath` and is resolved in a dependent make step, never during `build()`.
* Its **directory** goes on both lines that need it: the C compile line, because
  `curl_setup.h:140` includes `curl_config.h` by bare name, and the translate
  line, because `zig/translate.h` is compiled for the same target and the
  translation must see the same header the C saw or it will describe a different
  ABI.

The generator validates every argument and refuses rather than defaulting. It is
compiled with `-std=c11 -Wall -Wextra -Wpedantic` and deliberately **not**
`-Werror`: it is build-machine code that runs on every configure, and a new host
compiler's diagnostic should stop the driver at a gate with a receipt rather
than stop an unrelated package's build at configure time. The library's own
dialect is pinned at `-std=c99` for the opposite reason: "what dialect did this
compile as" should be a fact about this build, not something inherited from the
host clang.

The one thing this generated header carries that is **not** a fact about the
target is §4.

## 4. TLS: mbed-TLS, and the three answers the generator will not guess

`USE_MBEDTLS` is upstream's own documented selector. `lib/curl_setup.h:727-730`
turns any one of `USE_GNUTLS`, `USE_OPENSSL`, `USE_MBEDTLS`, `USE_WOLFSSL`,
`USE_SCHANNEL` or `USE_RUSTLS` into `USE_SSL`; `lib/vtls/vtls.c:693` and `:712`
read it to pick the backend; it opens `lib/vtls/mbedtls.c:32`. **No other
`USE_*SSL*` macro is defined anywhere in this package**, so
`lib/vtls/openssl.c`, `gtls.c`, `wolfssl.c`, `rustls.c` and `schannel.c` are
empty translation units.

Three values in the generated header are facts about the mbed-TLS *headers*
rather than about the target. All three are `PENDING-VERIFICATION` and all three
are now readable from the sibling:

* **`MBEDTLS_VERSION_NUMBER` is `0x03060700` — mbed-TLS 3.6.7.** `SOURCE-CONFIRMED`
  from the sibling's `src/include/mbedtls/build_info.h:27-30`
  (`MBEDTLS_VERSION_MAJOR 3`, `MINOR 6`, `PATCH 7`) and from its
  `build.zig.zon` `.version = "3.6.7"`. The build therefore takes the **3.x** side
  of `lib/vtls/mbedtls.c:47`, and that branch is load-bearing: mbed-TLS 4.0 moved
  the primitives to TF-PSA-Crypto and removed the legacy `mbedtls_*` entry
  points, so `lib/vtls/mbedtls.c:37-55` and everything else in the tree that
  calls them would not link.
* **`HAVE_MBEDTLS_DES_CRYPT_ECB` is defined**, because `mbedtls_des_crypt_ecb` is
  declared at `mbedtls/des.h:266` and `MBEDTLS_DES_C` is enabled in that
  configuration. `lib/curl_setup.h:759` keys `USE_CURL_NTLM_CORE` off exactly
  this macro, so it is what makes `CURL_ENABLE_NTLM` above it mean anything.
* **`MBEDTLS_SSL_ALPN` is enabled**, so the `HAS_ALPN_MBEDTLS` branch at
  `lib/vtls/mbedtls.c:73` would be live. It stays dead in this configuration
  because HTTP/2 needs nghttp2 and there is no second dependency (§5). Recorded
  so nobody reads the ALPN branch as a capability this build has.

The generator refuses to guess any of the three: `--mbedtls-des-crypt-ecb
yes|no` is a required argument with no default, and a value outside it stops the
run before a byte is written.

### The wire, and what is not yet observed about it

**`PENDING-VERIFICATION`.** `build.zig.zon` carries exactly one `.dependencies`
entry, `.@"mbed-tls" = .{ .path = "../mbed-tls" }`, and `build.zig` resolves it
with `b.dependency("mbed-tls", ...)` and links `mbedtls`, `mbedx509`,
`mbedcrypto` in that order. There is no vendored copy, no fork-private bridge and
no header copied into this tree.

The sibling package **is present on disk** at `../mbed-tls` — observed from a
directory listing, and nothing more. That is a stronger statement than
"declared" and a much weaker one than "linked": **no build has resolved the
dependency, no archive has been produced, no `curl_config.h` has been generated,
and no TLS handshake has happened.** Every claim in the three bullets above is
`SOURCE-CONFIRMED` from the sibling's headers and manifest; none of them is
`OBSERVED` from a compile. The first observation the driver owes is a
`zig build` that resolves the dependency, runs the generator, and links all three
archives.

Link order is not cosmetic: `mbedtls` needs symbols from `mbedx509` and
`mbedx509` needs symbols from `mbedcrypto`, so the reverse order does not link.
`SOURCE-CONFIRMED` from the sibling's own archives' dependency structure as
`build.zig` records it.

### Why `-Dtls` refuses rather than forwarding

`-Dtls` means "override the mbed-TLS package location", and it stops the build
with a message. The reason is a property of Zig 0.16's own API:
`Build.dependency(name, args)` (`lib/std/Build.zig:2055-2071`) resolves a
package's root from the `.dependencies` entry and offers no per-call path
override; the `args` it forwards are the *dependency's* own `-D` options. Every
`b.option(` call in the sibling's `build.zig` is one of `-Dsystem`, `-Dlinkage`
or `-Druntime`, and none of those relocates the package root — the sibling
resolves every path through `b.path` relative to itself.

Forwarding the flag would therefore reach a map that ignores it, and **a
silently ignored TLS-backend override is worse than no override at all**: it
leaves a caller believing the backend came from somewhere it did not. Two
changes make it real — edit this manifest's `.path`, or add a package-root
option to the sibling — and neither is made here. It is not a stub: with `-Dtls`
absent, the default path is the configuration this package ships.

## 5. The four features a one-entry dependency set forces

`build.zig.zon` has one dependency because the driver fixed the dependency
surface at exactly one entry. Four configuration decisions are forced by that
rather than chosen, and each is recorded at the row that carries it in the
generator. The costs are named, not absorbed:

* **`CURL_DISABLE_LDAP` and `CURL_DISABLE_LDAPS`.** `lib/ldap.c:28` is
  `#if !defined(CURL_DISABLE_LDAP) && !defined(USE_OPENLDAP)` and the unit then
  includes `<lber.h>` and `<ldap.h>` unguarded (`lib/ldap.c:59`, `:61`). A
  one-entry dependency set has no LDAP, so leaving this unset does not build — it
  fails on a missing header. **This libcurl speaks no `ldap://` and no
  `ldaps://`**, and `lib/protocol.c:192` and `:205` turn both scheme entries
  into `ZERO_NULL`.
* **No HTTP/2.** `lib/http2.c:26` needs `USE_NGHTTP2`, which needs nghttp2, which
  would be a second dependency. HTTP/1.1 only. The same reasoning is why the
  `HAS_ALPN_MBEDTLS` branch stays dead (§4) and why `curl_pushheader_bynum` and
  `curl_pushheader_byname` resolve to their stub symbols (§9).
* **No content encoding beyond `identity`.** `lib/content_encoding.c:29` is
  `#ifdef HAVE_LIBZ` and the same unit reads the brotli and zstd rows, so all
  three are off and the whole unit compiles out. No zlib means no
  `Content-Encoding: gzip` on the wire from this build.
* **No Public Suffix List.** `lib/psl.c:26` is `#ifdef USE_LIBPSL`, so
  `lib/cookie.c:804`'s public-suffix rejection is compiled out. **This one has a
  security reading and is worth stating plainly: cookie rejection is coarser
  without a PSL.** A second dependency is the fix and it is not taken here.

Also absent by the same one-entry rule, and named because a reader of the vtls
list will wonder: no GSS-API, no libssh2, no nghttp2/ngtcp2/nghttp3, no
libidn2, no Unix Sockets. `lib/curl_gssapi.c`, `lib/socks_gssapi.c`,
`lib/vauth/krb5_gssapi.c` and the three vssh units compile to empty translation
units.

`CONSTRAINT`: a future wave that needs any of these needs a second dependency
entry, and that is a driver decision rather than a build-graph edit.

## 6. ABI identity: two numbers that answer different questions

The release version is `8.22.0`, from `include/curl/curlver.h:35`. It is what
`build.zig.zon .version` must equal, what `libcurl.pc`'s `Version:` must say and
what `curl_version()` returns at run time (`lib/version.c:543`).

The ABI version is libtool's `current - age`, and it is **not** a release
number. `lib/Makefile.soname:26-28` carries `VERSIONCHANGE=12`, `VERSIONADD=0`,
`VERSIONDEL=8`; `:30-31` turns it into `-version-info 12:0:8`; `:34` states the
`current[:revision][:age]` gloss; and `lib/CMakeLists.txt:268-271` reads that
same vendored file and computes `_cmasesoname` as 12 − 8 = **4**, with `:272`
making `_cmakeversion` **4.8.0** and `:277` applying them as `SOVERSION` and
`VERSION`. `lib/CMakeLists.txt:303` then *defines*
`CURL_LIBCURL_VERSIONED_SYMBOLS_SONAME` from those numbers — so the macro
`lib/Makefile.soname:24` says to keep in sync is produced by a file this package
does vendor.

`-Dlinkage=dynamic` therefore installs `libcurl.so.4.8.0` with soname
`libcurl.so.4`. **Stating only the release number is how a reader ends up
believing `libcurl.so.8` exists.** Both numbers appear in the installed tree, and
`zig build` prints the delivery line every time before anything is compiled.

**`libcurl.so.4` is also the bare name a caller hands to `dlopen`** under the
runtime route's `LoadSource.system`: the soname is the name the loader resolves,
which is why it and not the versioned file name is the one to document. That
pairing is stated once, in `build.zig`'s module comment, and it is the only place
in this package where the two file names appear together.

The version script is upstream's own template rather than something written
here: `lib/libcurl.vers.in` is four lines — a node name `CURL_<PREFIX><SONAME>`,
then `global: curl_*; local: *;` — and `lib/CMakeLists.txt:289-290` picks prefix
`MBEDTLS_` under `CURL_USE_MBEDTLS` while `:303` supplies soname 4, so the node
is `CURL_MBEDTLS_4`. This build substitutes those two upstream values and invents
no list. For COFF, `lib/libcurl.def` is used verbatim: 100 `curl_*` entries and
no `Curl_*`, so it names exactly the public API and every `Curl_`-prefixed
internal stays unexported. Mach-O has no version script GNU ld or lld reads the
same way, so none is set there — which is upstream's own silence, not an omission
by this build.

## 7. `wasm32-wasi`, and what would bring the cell back

The sixth baseline target is **refused**, and the reason is a fact about the TLS
backend rather than about curl or about the toolchain's libc.

`MBEDTLS_NET_C` is compiled in for every unix-like and Windows target and **out**
for `wasm32-wasi`: the mbed-TLS sources `#error` unless
`MBEDTLS_PLATFORM_IS_UNIXLIKE || _WIN32`, and that macro is built from `unix` /
`__unix` / `__unix__` / (`__APPLE__` && `__MACH__`) / `__HAIKU__` /
`__midipix__` / `_WIN32` — none of which WASI's clang defines. So
`mbedtls_net_connect` and `mbedtls_net_accept` exist on Linux, macOS and Windows
and not on WASI, and `lib/vtls/mbedtls.c` calls both: `mbedtls_net_connect` for
the handshake, `mbedtls_net_accept` for the listener side.

**There is no configuration this package can write that changes that.** It is a
compile-time `#error` inside the dependency, not a macro on this side's line. So
the target is named in `refused_check_targets`, `refusalFor` holds the reason,
`refuseTarget` prints it and stops, and `checkMatrixPartition` fails any build of
this package if the refusal ever lapses without the row having been moved back
and proved. Nothing is dropped silently and nothing is patched past.

**This is not a claim that WASI cannot host curl.** `lib/curl_setup.h:200-203`,
`lib/curlx/nonblock.c:52-70` and `lib/socketpair.c:34-52` would all have answers
there, the generator's own family table carries a refusal for `--os wasi` with
those words, and `lib/curl_setup.h:470-473` would leave `USE_EVENTFD` undefined so
`socketpair.c` would take its `HAVE_PIPE` arm. **The cell comes back when the
dependency's `MBEDTLS_NET_C` covers WASI, or when `lib/vtls/mbedtls.c` stops
needing `mbedtls_net_*`.** Either is the dependency's or upstream's to make, and
this package makes neither.

Two further delivery facts about WASI, kept separate from the refusal above: it
has no dynamic linker, so `deliveredLinkage` refuses `-Dlinkage=dynamic` there;
and the runtime route's Unix backend calls `dlopen`, which WASI does not have.
**Neither is why the row is refused**, and conflating them would make the
refusal look like a delivery limit rather than a dependency one.

**Bound to:** the mbed-TLS package as it stands, and to a target whose clang does
not define any of the six macros above. A wave with a different backend, or a
sibling that grows a WASI network layer, must re-derive this rather than inherit
it.

## 8. Windows: two rows deliberately not followed

`lib/config-win32.h` is upstream's own hand-written Windows configuration and
this build reads it as a statement of what a Windows C build of this release can
rely on. It does **not** install or include it: `lib/curl_setup.h:138-140` sends
a `HAVE_CONFIG_H` build to the generated header instead, and
`lib/config-win32.h:29-31` is itself `#error This manual configuration requires
MSVC 2010-2013` for anything that is not MSVC, so it could not be used by
`x86_64-windows-gnu` at all.

Two rows it sets are deliberately **not** followed, and both are named rather
than quietly dropped:

* **`USE_WINDOWS_SSPI`.** `lib/curl_sspi.h:30` includes `<sspi.h>` under it, and
  linking the unit needs `-lssldbl` or `-lssp` plus `-lsecur32`. This package
  cannot confirm those for a GNU toolchain without running a gate, so
  `lib/curl_sspi.c:26`, `lib/socks_sspi.c:27` and `lib/vauth/*_sspi.c` are empty
  translation units and `lib/curl_setup.h:744-753` leaves `USE_SPNEGO` and
  `USE_KERBEROS5` undefined on Windows as well as everywhere else.
  **Negotiate, Kerberos and NTLM-over-SSPI are absent on the Windows row.**
  **NTLM itself is not**, because `lib/curl_setup.h:762` takes it from
  `USE_CURL_NTLM_CORE` through `USE_MBEDTLS && HAVE_MBEDTLS_DES_CRYPT_ECB`
  (§4). `HYPOTHESIS`, reasoned and not run: on a Windows row without SSPI, a
  server offering only Negotiate fails with `CURLE_LOGIN_DENIED` or
  `CURLE_AUTH_ERROR` rather than falling back to Basic or NTLM. Not observed.
* **`USE_RESOLV_THREADED`.** `lib/config-win32.h:103-106` defaults it on. The
  threaded resolver needs a working threads implementation, which on Windows is a
  link line rather than a header. This build uses `CURLRES_SYNCH` on Windows
  (`lib/curl_setup.h:711-712`), which is slower per lookup and correct.

`lib/socketpair.c` does not need `HAVE_SOCKETPAIR` on that row: with no
`USE_EVENTFD`, no `HAVE_PIPE` and no `HAVE_SOCKETPAIR` it takes the
loopback-socket implementation at `lib/socketpair.c:129-140`, which is the
fourth arm and the one whose `#error` at `:90` lives in an arm this build never
enters.

`dllmain.c` is vendored and digested but **not** compiled, and that is upstream's
doing rather than this build's: it is not on any of the seven `Makefile.inc`
groups, and it is the MSVC DLL entry point, which Zig's `-target
x86_64-windows-gnu` toolchain does not use. `SOURCE-CONFIRMED`: the file exists
in the vendored set, is not in the compiled list, and is the fourth digested file
no list names (§2).

## 9. The runtime route and the ABI boundary

`runtime/loader.zig` is the state machine and the platform layer;
`runtime/generate.zig` builds the dispatch from whatever the translation step
actually produced; `runtime/graph.zig` wires them together; `runtime/library.zig`
is what makes them libcurl's, and is the file another SDK replaces.

**The core never names a symbol of its own.** The synchronization binding is
`runtime/sync.c` compiled with `RT_SYNC_PREFIX=curl_rt`, and two spellings of
that prefix have to agree: `runtime/library.zig` names
`curl_rt_lock`/`_unlock`/`_wait`/`_broadcast`/`_thread_self`, and
`runtime/graph.zig` defines the macro. A build where they disagree does not link,
and that is the whole error report — there is no runtime path that could hide it.
That is what lets two SDKs, or two configurations of one SDK, hold their own
loader state in one process without sharing any of it.

**`provider_optional` and `provider_excluded` are both empty**, and that took
checking rather than assuming. curl is the first SDK in this workspace whose
public surface is partly behind `CURL_DISABLE_*` build macros, so the obvious
classification would be "optional" — and that would be wrong, because every
gated family defines its symbols again in the `#else` branch:
`lib/ws.c:2027-2071` for the four `curl_ws_*`, `lib/headers.c:396-425`,
`lib/easygetopt.c:78-97`, `lib/mime.c:2179-2282` for the twelve `curl_mime_*`,
`lib/formdata.c:842-864`, and `lib/http2.c:2981-2997`. `lib/libcurl.def` is the
same 100 names in every configuration. `curl_pushheader_bynum` is the case that
makes the point: routing it as *required* would make **this package's own shared
object fail this package's own load**, because `USE_NGHTTP2` cannot be defined
here (§5). It is routed because upstream exports it unconditionally; if a future
provider ever lacks it, the honest fix is a build-time decision recorded in
`runtime/graph.zig`, not a guess made in a comment.

**The translation carries a large slab of the C library, and that is not the
provider's.** `include/curl/curl.h:65-66,74-75` opens `<stdio.h>`, `<limits.h>`,
`<sys/types.h>` and `<time.h>`, `:102-105` adds `<sys/socket.h>` and
`<sys/time.h>`, and `:77-85` puts `<winsock2.h>` and `<ws2tcpip.h>` in the
Windows closure — where `any-windows-any/winsock2.h:23` includes `<windows.h>`
unconditionally and so reaches the entire Win32 SDK. A translation step emits a
declaration for every function it parses. Asking a provider for `printf` would
either fail the load outright or resolve it out of the C library the provider
depends on, so these are classified as noise and the declarations stay direct.

### The one thing the loader checks, and why it is that

**All 100 exported names are present in a libcurl built with no TLS backend at
all.** Resolving the whole table therefore proves the file is a libcurl of this
API family and says nothing about how it was configured — and this package has
exactly one configuration it will ship. A runtime-loaded provider is the one
place that promise can be broken without anything failing to build, so it is
where the check belongs.

Before anything is published, the provider's own `curl_version_info` must
report an `age` at least this header's `CURLVERSION_NOW` (`curl.h:3132-3136`
defines what that number is for: "what kind of struct the caller expects"), a
non-null `ssl_version`, and the `CURL_VERSION_SSL` feature bit. The last two are
exactly "this provider was built with a TLS backend", read out of the provider:
`lib/version.c:547` initialises `ssl_version` to `NULL` and only
`lib/version.c:604-607` replaces it under `USE_SSL`, and `:515-517` sets the
feature bit under the same macro. A refusal closes the candidate and publishes
nothing, so the module stays unloaded and the caller can choose another provider
or retry.

`curl_global_init` and `curl_easy_init` are deliberately **not** called by the
loader. `curl.h:2771-2775` says global init "should be invoked exactly once for
each application that uses libcurl", and a loader runs inside whatever
application loaded it — spending that one call would leave the application unable
to make it. `curl_version_info` is safe to call before global init, and the
reason is in the C rather than in a promise: `lib/version.c:604-607` reaches the
SSL version only under `USE_SSL`, `lib/vtls/vtls.c:686-703` selects
`&Curl_ssl_mbedtls` at compile time so the pointer is never null before init, and
everything else the function reads is `static` storage or another library's
version string.

**The five things the boundary actually turns on**, restated in
[`README.zig.md`](README.zig.md) for a reader consuming the module: `curl_off_t`
is a 64-bit signed type by upstream's own rule (`system.h:36-43`) and appears in
variadic `CURLOPT_*`/`CURLINFO_*` positions; `curl_socket_t` is `int` off Windows
and pointer-sized `SOCKET` on it; `long` is a parameter type in curl's own API
(`curl_multi_timeout`, `curl_global_init`), so LP64 and ILP32 disagree;
`struct curl_version_info_data` grows by appending, which is what the `age` check
is about; and twenty-nine function-pointer types cross in both directions, called
by the provider's C with the provider's calling convention.

**Resolving the symbols and translating the header is the boundary. They are not
proof that a provider is compatible, and this package does not add more checks
than it can observe.**

## 10. Tests, and where their answers come from

`tests.zig` is this package's own suite and **nothing in it reaches off the
machine**. No test names a host and no test resolves a name: every transfer goes
to an HTTP server the file starts itself, on `127.0.0.1` on a port the kernel
picks. That makes the suite a statement about libcurl and this facade rather than
about whether a network exists, and it cannot turn flaky when a name server does.
The one place the server is bypassed is the connection-refused test, which
deliberately connects to a port where nothing is listening — a refusal produced
by the local kernel, not a remote answer.

Three kinds of answer, and they are not interchangeable:

* **The fixture body is a recording, pinned two ways.** `fixture_body` is a byte
  string committed in the file and `fixture_digest_hex` is its SHA-256, taken
  before any library code ran. Neither is produced by the code under test, so
  neither can agree with it; the fixture's length is asserted against the digest's
  covered length so the two cannot drift apart unnoticed. The body was chosen for
  three properties a write-callback test can check: it contains a line that
  *looks* like a response header (`X-Not-A-Header:`), so a body contaminated by
  the response head would be visible rather than plausible; it ends in a newline
  and is 95 bytes long, so a dropped or duplicated trailing byte changes the
  length as well as the content; and it has no byte above 0x7e, so a separate
  `binary_body` fixture can carry the NUL and the two high bytes.
* **Protocol expectations are stated, not observed.** The header-callback test
  asserts the shape RFC 9110 requires of a response head, and the
  percent-encoding test derives its expectation from the character classes
  RFC 3986 defines, computing it in Zig rather than asking libcurl what it would
  have said.
* **A same-code round trip appears, and only as a supplement.** The
  malformed-percent-triplet and reset tests compare libcurl's output with input
  libcurl was given. On their own they would prove only that the code agrees with
  itself; each says so in its own comment.

curl's own `docs/` tree is not vendored, so nothing is cited to a documentation
page. Everything about upstream behaviour is cited to a file under `lib/` or
`include/`, with a line.

**No test here claims a leak oracle, and none could.** libcurl allocates through
`Curl_cmalloc`, which defaults to libc `malloc` (`lib/easy.c:109`) and is not
`std.testing.allocator`. What a test *can* check is the ownership transition this
package's facade owns: that `deinit` releases the handle, that an `SList` line
the caller destroys after `append` does not change what goes on the wire, that a
getter's borrow is the caller's to read and not to free, and that releasing a
handle leaves the caller's header list alone. Where the facade hands back a
pointer libcurl owns, the test frees it with `freeEscaped`, which routes to
`curl_free` (`lib/escape.c:190`); freeing those bytes with `testing.allocator`
would be a real bug, so no test does it.

`smoke.zig` carries the same 95 fixture bytes and the same digest, written out
twice on purpose: `tests.zig` is the test root and `smoke.zig` is a separate
build root, and a shared file would have to appear in `build.zig.zon`'s `.paths`.
The digest is what makes the duplication safe — if the two copies drifted, one of
the two programs would fail rather than quietly check its own bytes.

`consumer/` is the same argument one level out: a package that did not write this
one, depending through a relative path rather than a fetch, so the proof cannot
depend on a published state of the world.

**No gate has run any of it.** No test has been executed, in either optimization
mode, and there is no test count to quote.

## 11. What the driver still has to run, and what is still open

**Added 2026-10-05, after the 53-target matrix of that date.** Four host gates
were run on the configuration changes in §13 and the exit codes below are
`OBSERVED`, not `VERIFIED`; only the driver may move them. Compiler:
`$ZIG_GLOBAL_CACHE_DIR/p/N-V-__8AAFFSVRWqblwBIcA-Yqv-u7sbjsJoww8K0mWaHbmJ/zig`,
Zig 0.16.0, run from the tree root with
`-j8 --cache-dir $HOST_SCRATCH_ROOT/cache/foundation-libs/wave10/libcurl
--summary all`.

| gate | exit |
|---|---|
| `zig build` | 0 |
| `zig build test` | 0 |
| `zig build smoke` | 0 |
| `zig build check` | 0 |

Still open: the 53-target matrix has **not** been re-run against these changes,
so the cross-test classification in §13 is per-cell and observed one cell at a
time, not a matrix result. `zig build test -Drelease=safe` is also still owed
here; it was not run.


### Gates this package is owed

Every one of these is a `PENDING-VERIFICATION` row in
[`README.md`](README.md)'s support matrix. Nothing below has been run, and no
result for any of it exists anywhere in this repository.

1. `zig build` — the first observation this package needs at all, and the one
   that exercises the whole TLS wire: the dependency resolves, the generator
   runs, `curl_config.h` is produced, all 196 units compile, the twelve headers
   and `libcurl.pc` and the nine records install.
2. `zig build -Dlinkage=dynamic` — the shared object, its soname
   `libcurl.so.4`, and the two export lists (`CURL_MBEDTLS_4` on ELF,
   `lib/libcurl.def` verbatim on COFF).
3. `zig build test` in Debug **and** ReleaseSafe, and the test count each one
   reports. No count is claimed here.
4. `zig build smoke`.
5. `zig build check` — the five buildable targets compiled and nothing run. Any
   refusal printed is a result to record.
6. `zig build test smoke -Druntime=true` with a real provider named, which
   requires a real shared object first.
7. `zig build consumer`, and `cd consumer && zig build run` entered directly.
8. `"$HOME/.local/bin/cross-test"` from the package root — all 53 cells, with
   `build_only` and executed cells recorded separately.
9. `tools/check-provenance.sh`.

### Two open questions this documentation does not close

* **Does the example install?** `build.zig` compiles the example executable
  `libcurl-smoke` and adds `example.step` to the install step, while its own
  comment says "It is compiled, not installed: it is a proof, not a
  deliverable." The install listing from gate 1 settles it, and
  [`README.md`](README.md)'s consumption section states the file's own claim
  rather than a guess.
* **Which of the two MD4/MD5 grant paths compiles.** `NOTICE.md` records that
  `lib/md4.c` has no mbed-TLS branch, so its public-domain/BSD fallback is what
  compiles with this configuration, while `lib/md5.c` has an mbed-TLS branch
  taken only when `PSA_WANT_ALG_MD5` is defined in the generated header. The
  consequence for a consumer is the same either way, which is why it is recorded
  per file rather than settled here; the generated header from gate 1 answers it.

### Three stale statements in files owned by other roles

Each was true when written and describes the moment it was written. None is
wrong, and none is closed by this documentation. They are listed so the
integration owner can decide, and the parent has taken them.

* `UPSTREAM.md`, "The TLS backend is upstream's own macro": "That wire is
  `PENDING-VERIFICATION`: at the time this file was written, `../mbed-tls` was
  not on disk."
* `cross-test.profile.sh`, closing paragraph: "That sibling is not on disk yet,
  so a run launched today is expected to fail at configure time on every cell."
* `.github/workflows/verify.yml`, header: "Every job below except `source` and
  `preflight` is **expected to fail until the `mbed-tls/` sibling package
  lands**."

The sibling is on disk now. The linkage is still `PENDING-VERIFICATION` — the
sibling's *presence* is not a build (§4) — so those files' substantive claims
hold; only their statements about when the failure starts no longer describe the
next run. `.github/workflows/verify.yml`'s `preflight` job is the check that
answers it, and `cross-test.profile.sh`'s paragraph is the record that should
say so once a cell has been observed.

**Bound to:** a document written before a dependency's sibling landed. The lesson
is about the *order of events*, not about this library: a provenance or CI
record that asserts when a failure begins goes stale the moment the dependency
arrives, and the correction belongs with the record rather than in a reader's
head.

### Two things that are open by design and are not defects

* `flake.lock` and `devenv.lock` are absent. `build.zig.zon` says they belong to
  the driver and are deliberately absent from `.paths` until they exist, because
  naming a path that is not there would make `zig fetch` hash a missing entry.
* `consumer/build.zig.zon`'s `.fingerprint` is the documented placeholder
  `0x0000000000000000`. It cannot be computed without running Zig, and a worker
  does not run Zig. `zig build` reports a fingerprint mismatch by name, so a
  placeholder that was never replaced cannot be mistaken for a package that
  resolved correctly.

## 12. A C string argument is a type, not a comment

**Condition.** A Zig facade that hands a caller-supplied `[]const u8` to a C
function that measures with `strlen`, by scanning the caller's pointer with
`std.mem.span` to manufacture the terminator.

**Symptom.** Ten of seventeen loopback-fixture tests failing at once with three
different-looking errors, none of them pointing at the facade: a body-digest
mismatch, a `404 no such fixture route` for a route the test registered, and
`CURLE_URL_MALFORMAT` for a URL that is visibly well formed in the source. The
fixture was right; the request it answered was not the request the test asked
for. Instrumenting the fixture and printing `request.head.target` is what made
it legible — it read `/fixture.txt` followed by 128 bytes of `0xAA`.

**Fix.** Never scan memory the caller did not promise. Where the C contract
requires a NUL, the Zig signature is `[:0]const u8` and the compiler enforces
it; the caller writes the terminator (`buf[n] = 0; buf[0..n :0]`). Applies here
to `Easy.setUrl`, `SList.append` and `optionByName`. Note that
`std.fmt.bufPrint` does **not** terminate what it writes, which is the shape
that triggers it: every URL in this package is built with `bufPrint` into a
stack buffer.

**Targets bound.** Zig 0.16.0. Not C-compiler specific: the same mistake in C
would be a read past the buffer, caught by none of the three modes.

### The same name, three ways, in `lib/multi.c`

**Condition.** Two upstream spellings that `#define` to the same value but are
tested separately.

**Symptom.** `Multi.drive` looped `MultiNeverFinished` - 10 000 passes, no
completion. `CURL_SOCKET_TIMEOUT` is `#define`d to `CURL_SOCKET_BAD`
(`multi.h:288`), but `multi_socket` branches on `CURL_SOCKET_TIMEOUT` alone
(`lib/multi.c:3279`); any other value reaches
`Curl_multi_ev_dirty_xfers(multi, s)` (`:3288`), which marks nothing when the
descriptor has no entry (`lib/multi_ev.c:589-591`). So
`curl_multi_socket_action(CURL_SOCKET_BAD, 0, &running)` started transfers and
could not finish them. `curl_multi_socket_all` (`multi.h:325`) is the
non-deprecated replacement and passes `checkall = TRUE`.

**Fix.** When a header `#define`s two names to one value, do not read the
macro's documentation for the branch - read where the value is *tested*.

**Targets bound.** curl 8.22.0, whose `multi_socket` carries the `checkall`
parameter.

### A loop that consumes the notification it reports

`drive` had to remove a message to learn a transfer's `CURLcode`, and threw it
away, so a caller could not learn which handle had finished - the only thing
the multi interface exists to say. It now holds that one message and `readInfo`
returns it first. The same class of bug was a `Message.easy` pointing at a
**local** in `readInfo`: a pointer handed to a caller that pointed at a returned
frame. Borrowed views now live in the `Multi`, rotated over
`message_view_slots`.

**Rule.** A pointer that escapes a function must point at storage that outlives
the call. A local returned by address is not a borrow; it is a defect that
survives until something reads it.

## 13. The 53-target matrix, cause by cause, and what is still not this tree's

**Condition.** The 53-platform cross-test run of 2026-10-05 (run id
`20261005-191821-33801-16383`, harness exit 1, 0 passes, 47 refusals, 6
compiled-not-executed) attributed 17 refused cells to this fork under five
cause letters. Four of the five are fixed here; the fifth is not this tree's and
never was.

**Symptom, symptom, fix — and the one that was misfiled.** Cause D was reported
as "libcurl's own `build.zig` returns `error.UnknownArchitecture` for an
architecture its arch table does not carry". That message is not in this tree.
`OBSERVED`, read out of the run's own per-cell logs
(`runs/20261005-191821-33801-16383/build-<target>.log`):

```
error: UnknownArchitecture
/vol/fob-vol7/mi19/gertullj/foundation-libs/mbed-tls/zig/config_gen.zig:245:13
```

That is the sibling's `Params.known` table. This tree's own arch table appears
in the *same* logs as a different refusal, from this tree's generator:

```
curl_config_gen: refusing to write curl_config.h.
  unknown --arch "hexagon": this table cannot say whether that architecture's
  <netinet/in.h> declares struct sockaddr_in6's sin6_scope_id, ...
```

Per cell, for the nine cells cause D listed: the mbed-TLS message appears in
all nine; this tree's refusal appears in three of them (`hexagon-linux`,
`mipsel-linux`, `thumb-linux`). The other six were never this tree's failure.

**Fix.** Two different tables were at fault and both are gone rather than
widened.

- `curl_config_gen.c` carried `arch_has_scope_id()`, two closed lists of
  architectures with and without `struct sockaddr_in6`'s `sin6_scope_id`. It is
  deleted. The row now carries `X_MEMBER` and is answered from
  `--member-facts`, which `build_support/curl_existence_probe.c` produces by
  compiling upstream's `configure.ac:1826-1829` body for the target - the same
  technique upstream uses at `configure.ac:1812-1831`. `riscv32-linux`,
  `armeb-linux` and `powerpc64-linux` build after this (exit 0).
- `build.zig`'s `pointerWidthBits` was a name list searched by `@tagName`. It is
  an exhaustive `switch` on `std.Target.Cpu.Arch` with no `else`, so it cannot
  be narrower than the compiler's own architecture set again.

**Targets bound.** Zig 0.16.0 `std.Target.Cpu.Arch`, curl 8.22.0, the six
baseline check targets plus the published 53-platform matrix.

### What is still open, and it is not this tree's

`OBSERVED`, single-cell `zig build` / `zig build test` after the change:

| cell | exit | first error | owner |
|---|---|---|---|
| `riscv32-linux` | 0 | - | closed here |
| `armeb-linux` | 0 | - | closed here |
| `powerpc64-linux` | 0 | - | closed here |
| `hexagon-linux` | 1 | `mbed-tls/zig/config_gen.zig:245` `UnknownArchitecture` | sibling |
| `mipsel-linux` | 1 | same | sibling |
| `thumb-linux` | 1 | same | sibling |
| `thumb-windows` | 1 | same | sibling |
| `powerpc64le-linux` | 1 | same | sibling |
| `aarch64_be-linux` | 1 | same | sibling |
| `aarch64_be-netbsd` | 1 | same | sibling |
| `thumbeb-linux` | 1 | same | sibling |
| `aarch64-maccatalyst` | 1 | host cannot execute a Mach-O binary | build-only |
| `x86_64-maccatalyst` | 1 | host cannot execute a Mach-O binary | build-only |
| `aarch64-windows` | 1 | host cannot execute a PE binary | build-only |

Zero libcurl-side refusals remain in any of the nine cause-D cells and in any of
the three cause-F cells. What is left in them is the sibling's arch table, and
no edit in this tree can reach it.

### Cause H, assessed honestly

`wasm32-wasi` is refused by name in `build.zig`'s `refusalFor`, and by
`curl_config_gen.c`'s `enum_for_os` with the same words. The reason is a
`#error` inside the dependency: mbed-TLS compiles `MBEDTLS_NET_C` out on WASI
because `MBEDTLS_PLATFORM_IS_UNIXLIKE` and `_WIN32` are both undefined there,
and `lib/vtls/mbedtls.c` calls `mbedtls_net_connect` and `mbedtls_net_accept`.
That is a real boundary of this pinned `lib/vtls/mbedtls.c` against this
mbed-TLS build, stated once and refused twice, and it is not a skip: it is
recorded here, in `build.zig` and in the generator, with the file and the reason.

### Cause I, and what `__declspec(dllimport)` in a linker message means

**Condition.** `aarch64-windows` failed to link with 38
`lld-link: undefined symbol` errors, the first of them
`__declspec(dllimport) WSACreateEvent`.

**Symptom.** The `__declspec(dllimport)` in the *symbol name* looks like a
compiler bug and is not one. mingw-w64's `winsock2.h:34-40` defines
`WINSOCK_API_LINKAGE` as `DECLSPEC_IMPORT` whenever `DECLSPEC_IMPORT` exists,
and declares the whole Winsock family with it at `:1003` onward, so every
reference is a `__declspec(dllimport)` reference and `lld-link` prints the
decoration back. Reproduced outside this tree with two lines:

```
$ZIG cc -target x86_64-windows-gnu -std=gnu99 w.c -o w.exe
lld-link: error: undefined symbol: __declspec(dllimport) WSACreateEvent
$ZIG cc -target x86_64-windows-gnu -std=gnu99 w.c -o w.exe -lws2_32
(exit 0)
```

**Fix.** `build.zig` adds `ws2_32`, `iphlpapi` and `bcrypt` on Windows.

**Rule.** A `dllimport` reference is satisfiable only by an import library; the
decoration in the message names the header's declaration, not the defect.

**Targets bound.** mingw-w64 headers as shipped with Zig 0.16.0, `lld-link`, and
the curl units that call into `ws2_32`, `iphlpapi` and `bcrypt`.

## 14. Two standing rules from the owner, and one of them caught me

### Nothing goes in `/tmp` or `/var/tmp`

Every byte goes under `$HOST_SCRATCH_ROOT`, resolved by
`source "$HOME/.local/lib/host-scratch.sh" || exit 1`, which is
`/home/tmp2/gertullj` here. That includes scratch directories, caches, build
output, logs, diffs, backups and fallback paths, and it includes anything a tool
would default there rather than paths you name yourself. The repository trees
and `$HOME` are on NFS and hold neither.

**I broke this once**, while checking whether `zig fmt --check` complained about
my own edits rather than about pre-existing drift in the package:

    "$ZIG" fmt --check tests.zig smoke.zig zig/root.zig consumer/src/main.zig \
        > /tmp/fmtout 2>&1; cat /tmp/fmtout; rm -f /tmp/fmtout

Deleting it immediately is not compliance - the byte was on a filesystem the
workspace does not permit, on the shared system `/tmp`, for the length of the
command. The correct form writes to `"$HOST_SCRATCH_ROOT"/scratch/...` like every
other probe in this package. A self-cleaning violation is still a violation, and
the reason the rule exists is that a leftover or a fallback silently outlives the
command that made it.

The check I was actually after did not need a file at all: run
`zig fmt` on a **copy** under approved scratch and `diff` it against the original,
which is what was done instead, and it showed the only remaining drift was
pre-existing (`runtime/graph.zig` fails `zig fmt --check` untouched, and the
package has never been formatter-clean). So the violation bought nothing.

### A matrix is only evidence if every cell saw one source state

Hash the fork-owned sources before a run and again after it, gate on a quiet
window, and **discard** any run whose cells span two source states. Do not
reinterpret it.

The refined rule matters more than the hash: **mtime or hash stability is not
sufficient**, because a file can sit unchanged while a concurrent rename leaves
it half-merged and not compiling. The gate must also compile the changed file
with the flags `build.zig` actually passes.

This package is the worked example. A concurrent merge renamed
`build_support/curl_functions_probe.c` to `curl_existence_probe.c` without
updating `build.zig`, so all five gates failed at once with
`failed to check cache: ... FileNotFound` - a binary "the tree is red" with no
location. Compiling the renamed file on its own would have said immediately that
the name was the whole problem.

Two mistakes of mine worth recording, because both cost someone else:

* I told the libcurl matrix owner that "the tree moved during your run" when
  their own fingerprints proved it had not. I asserted it from having edited two
  files in that timeframe instead of checking their window. They discounted a
  clean matrix on my word, and the cause-A signal in it - the most useful thing
  in the run - would have been lost.
* I then compiled the settled probe standalone with a stale
  `-DCURL_FUNCTIONS_COLLECTOR` and got `use of undeclared identifier 'NULL'`,
  which I dismissed as noise because the real build was green. It was my own
  macro, not a source defect. So the standalone check only means something when
  the flags match `build.zig` exactly - which is the half of the rule that is
  easy to leave out.

**Re-check every `file:line` before reporting it.** Build graphs shift under a
worker mid-session here. Two of this file's own citations went stale within an
hour of being written - `build.zig:1152` became `:1192` and
`curl_config_gen.c:2463-2464` became `:2784` - and both were corrected on
re-reading. Cite a span by title or symbol where a range is at risk.

### A pass/fail triple throws away the finding that matters

The 53-cell run that closed this package reported `18 pass, 19 refused, 2
runtime_fail, 14 compiled_not_executed`. The two `runtime_fail` cells are
`mips-linux` and `mipsel-linux`, and the whole of what they say is in the split:
**the build succeeds, the tests execute, and 13 of 17 crash under qemu** while
the 4 that open no socket pass.

Write that cell as "fail" and both halves are lost - a reader cannot tell a build
that is clean from one that is broken, and cannot tell an emulator boundary from
a defect in this package. Summarised as a boolean, the cell says almost nothing.

So when a matrix result is reduced to a count, the reduction must keep
`build / compile / run` separate for any cell that is not a clean pass. A cell
whose build is green and whose run is not is a different finding from a cell that
will not build, and the two converge to the same word.

The same shape applies to the 14 `compiled_not_executed` cells: they are
build-only coverage in substance and carry no test count, and calling them
"passed" would be the same error in the opposite direction.

**The same loss happens in the other direction, with a count that shrinks.** A
refused cause going 7 cells to 18 is not a measure of how big that boundary is;
it is a measure of how many cells got *through the layer in front of it*. And a
cause class that shrinks because something above it broke is indistinguishable,
from the count alone, from one that shrinks because something above it was
fixed. Neither direction can be read without the layer each cell stopped at -
which is why `pass / refused / runtime_fail / build_only` had to stay split, and
why no single number could have separated "the toolchain refuses 18 cells" from
"18 cells stopped reaching the toolchain".

### A sibling's writes are part of this package's build inputs

**A matrix is only as stable as every tree it compiles.** Hashing this package's
own fork-owned sources is necessary and not sufficient: `libcurl` has exactly one
dependency surface - the mbed-TLS sibling - and a write to that tree is a write
to this package's build inputs by another route.

Observed on 2026-10-05: `mbed-tls/` was edited at 22:40:44 and again at 22:48:19,
inside a libcurl matrix run, and a cell then printed

    config_gen.zig:1:1: error: file contents changed during update

- the build watching its dependency change underneath it, which is the clearest
possible statement of the problem. That quarantined 8 cells and forced a re-run
of the whole matrix, and no amount of care with this package's own files would
have prevented it.

**The rule.** Hash the sibling as well as the tree under test, before and after.
Treat any write to a dependency during a run as disqualifying for the cells that
depend on it, exactly as if the tree under test had moved. And record which tree
a failure belongs to, because `config_gen.zig` exists in both packages and a
bare filename in a log line does not say which one produced it.

This is the same failure as moving one's own tree, one level down, and the
blind spot runs in both directions. The instinct to guard arrives only after you
have been burned by your own edits. The converse is no safer: a worker who is
**forbidden** to edit a tree tends to assume it therefore cannot move, and it
can. "I am read-only here, so this tree is stable" is not a safety property - it
is the absence of the one check that would have caught it.

### `wasm32-wasi`: two refusals, and which one fires

Recorded precisely because two people described this cell differently and both
descriptions were locally correct.

`build.zig` refuses first, as a **pre-compilation panic**:
`refusalFor` (`build.zig:1962`) returns a `Refusal` whose `.summary` is the
one-line cause, `refuseTarget` (`build.zig:2027`) panics at `:2032`, and the
guard sits at `build.zig:1333` inside `addGraph`. The generator is never reached,
which is why a run-3 report attributing the refusal to the config generator was
wrong about the mechanism.

The generator refuses the same target independently, at
`curl_config_gen.c:2196`, with the same reason and ending "See build.zig,
refusalFor". That is defence in depth, not duplication by accident: it would fire
if `build.zig`'s guard were bypassed, and it is the refusal that protects the
generator when it is invoked on its own.

So the accurate statement is: **`build.zig` refuses first and the generator
refuses too**, and a log line naming either one is not on its own a correction of
the other. `FORK-NOTES.md` §7 says both refuse, and that is still right.

The refusal is not a test skip and is not a suppression: no test step runs, the
cell log contains no "skipped", and the cause names the call sites -
`lib/vtls/mbedtls.c` calls `mbedtls_net_connect` and `mbedtls_net_accept`, and
`MBEDTLS_NET_C` is compiled out because `MBEDTLS_PLATFORM_IS_UNIXLIKE` and
`_WIN32` are both undefined under WASI's clang. The owner's decision on
2026-10-05 was to leave it declared rather than change the TLS backend, which
would alter the configuration every other cell builds against to buy one cell.

### The mips32 `runtime_fail`: `sigsetjmp` and `$gp`, not qemu

**Condition.** `mips-linux` and `mipsel-linux` built, ran, and crashed 13 of 17
tests under `/bin/qemu-mips` and `/bin/qemu-mipsel`. All 13 faults landed on one
address per cell - `0x1420001a` big-endian, `0x8fc4003c` little-endian - which is
outside the image (text ends near `0x00e00000`, `.bss` near `0x010bdc00`), so it
is a wild jump rather than a bad store. The 4 that passed open no socket.

**Symptom.** `qemu-mips -d in_asm,exec` puts the last blocks before the fault in
`curl_simple_lock_lock`, then `resolv_alarm_timeout`, then `sigsetjmp`. That is
upstream's resolver SIGALRM path: `lib/vdns/hostip.c:888` locks
`curl_jmpenv_lock` and `:890` calls `sigsetjmp(curl_jmpenv, 1)`. `sigsetjmp`'s
prologue is the whole story:

    0x00db4740:  lui   gp,0x30
    0x00db4744:  addiu gp,gp,13600
    0x00db4748:  beqz  a1,0xdb4780
    0x00db474c:  addu  gp,gp,t9
    ...
    0x00db4758:  lw    t9,-32744(gp)
    0x00db475c:  jalr  t9

musl is built PIC, so `sigsetjmp` derives `$gp` from `$t9`, which on o32 must hold
the callee's own address. A caller emits that only by going through `$t9`. The
caller here does not: the trace shows a bare `jal 0xdb4740` and no `la t9`. So
`$gp` is built from a stale `$t9`, `lw t9,-32744(gp)` reads rubbish, and `jalr t9`
leaves for `0x1420001b`.

**Why the caller emits a bare `jal`.** `add_c_library`'s module said
`.pic = if (linkage == .dynamic) true else null`, and the matrix is static
linkage. `null` is not `false`, it is "let the build system infer", and on
`mips-linux-musleabi` the inference is non-PIC. Non-PIC MIPS cannot go through
`$t9`, so it calls by PC-relative `jal`, and musl's PIC `sigsetjmp` then has no
`$t9` to work with.

**Fix.** `build.zig:1605` names `.pic = true` for the C module for both linkages.
`build.zig` is the only file changed; `lib/vdns/hostip.c` is vendored and byte for
byte unchanged.

**What it costs.** Measured, both linkages static, and it is not what it looks
like:

| target | `libcurl.a` before | after | delta |
|---|---|---|---|
| `mips-linux-musleabi` | 19747232 | 18801176 | **-946056** |
| `x86_64-linux-gnu` (host) | 20717210 | 20717210 | 0, different contents |

Position independence makes the mips32 archive *smaller* and leaves the host
archive the same size, because the inference `null` left to the build system had
already chosen PIC for `x86_64-linux-gnu`. **Do not put `.pic` back to the
inference** to "recover" anything - there is nothing to recover, and the two cells
that need it cannot run at all without it.

**Targets bound.** Zig 0.16.0's musl as shipped with it, `qemu-mips` /
`qemu-mipsel` 10.0.13, and the o32 calling convention.

**Rule.** `null` for a codegen option is not "off", it is "whatever the build
system guesses", and on one architecture in a 53-cell matrix that guess is the
whole bug. An inference is a decision nobody made and nobody wrote down.

### The isolation, in three lines, because "it is qemu" was the wrong first answer

Every other 32-bit cell passed under the same qemu - `arm-linux`, `armeb-linux`,
`thumb-linux`, `thumbeb-linux`, `riscv32-linux`, `x86-linux`, `powerpc-linux` -
and `mips64-linux` passed all 17. That is what makes "emulator boundary" the
attractive first answer and the wrong one. Four one-function programs, built
non-PIC for `mips-linux-musleabi` with this compiler, run under this qemu:

| program | result |
|---|---|
| `printf("printf ok")` | runs |
| `malloc` + `free` | runs |
| `setjmp(jb)` | runs |
| `sigsetjmp(jb, 1)` | **SIGSEGV** |

Same source with `-fPIC`: runs. One flag, one function, one cell pair - and
`setjmp` surviving while `sigsetjmp` does not is itself the diagnosis, because
musl's `sigsetjmp` only reaches its `$gp`-relative call when `savemask` is
nonzero, which is exactly the `beqz a1` branch above.

## 15. A probe that measures nothing is not the same as a probe that measures "no"

**Condition.** A fork answers per-target questions by compiling one
translation unit per row and reading the compiler's exit status - this package's
`build_support/curl_existence_probe.c`, upstream's `AC_CHECK_FUNCS`, CMake's
`check_function_exists`, Zig's `std.zig.CrossTarget`. Every one of them is sound
only while the exit status means "the compiler rejected this *declaration*".

**Symptom.** None, at the level of the build. A collector handed a `zig` path
that does not exist, an unparsable triple, or a flag string `zig cc` does not
know, wrote **48 of 48 `no` and exited 0** on every one of those inputs. The
facts file was complete, one line per row, in the right order, with a marker the
generator recognises - and every downstream consistency check passed, because
each one asks "is there an answer for this row?", and the answer was there. What
the generated `curl_config.h` then said was that the target declares none of the
functions curl calls. The failure is *silent in the direction that matters*:
the checks that exist are all satisfiable by a uniform wrong answer.

**Fix, two parts, because two different things were wrong.** `execv` returning
means no compiler ever ran, so `run_probe` now holds a close-on-exec pipe:
end-of-file is "the compiler owns the process", one byte is "it never did", and
the second is a refusal. But `zig cc` *did* start in the other two cases and
exited 1 - the same status as `use of undeclared identifier` - so the exit
status cannot carry that distinction and something before the rows must. One
**control probe** now compiles a unit with no header, no macro and no target
symbol before any row is asked; every target's compiler accepts it, so a failure
there means the toolchain invocation itself is unusable, and the run refuses and
writes no facts file at all.

**Targets bound.** Any host program in this workspace that forks a compiler and
reads a child's exit status as an answer. Version-bound to nothing observed
here: the mechanism is `execv` plus `waitpid`, which is the same on every
platform this workspace builds. It is *not* the same hazard as a build step,
because a build step's own failure is its own exit status - which is why
`addHeaderProbe` never needed this and `addFunctionProbe` does: one is a system
command whose status the build runner reads, the other is a host program that has
to *interpret* a status.

**The generalisable rule, and it is the part worth keeping.** A consistency
check proves the *shape* of a data file, never the *truth* of its contents. Ask
what a check would do about the wrongest answer that still satisfies it, and if
the answer is "accept it", the check needs a control beside it. "Every row has
a fact" is satisfied by 48 identical `no`s; the control probe is what makes the
uniform answer impossible. The same question applies to a probe that exits 0 on
fewer arguments than it was built to receive - which this collector already got
right (`argc != 6` refuses), and which is worth stating as a thing to *keep*
rather than a thing that happened to be fine.

## 16. Had the two cells, used them to predict the sign instead of to ask

**What I got right.** The premise. `null` in the module option is not "false",
it is "let the build infer from the target and linking mode" — and an
unconditional `true` overrides that inference rather than merely forcing it on
where it was wanted. The inference was the bug.

**What I got wrong.** Everything downstream of the premise. I predicted that
unconditional PIC would bite "when a static archive is linked directly into a
non-PIC executable", named `mips-linux` and `mipsel-linux` as the sensitive
pair, and offered `.pic = linkage == .dynamic` plus an explicit `true` on the
wrapper module as the narrower fix.

Measured: **the opposite**. Those two cells went from building and crashing 13 of
17 to building and passing 17 of 17. Non-PIC had been the defect — the inference
chose non-PIC for `mips-linux-musleabi` and musl is PIC, so `lib/vdns/hostip.c`
called musl's PIC `sigsetjmp` through a bare `jal` that never loaded `$t9`. My
"narrower fix" would have preserved the bug on exactly the cells it was meant to
protect. The size worry was wrong too: PIC made `mips-linux-musleabi`'s
`libcurl.a` **946056 bytes smaller**, and `x86_64-linux-gnu` was unchanged in size
because the inference had already chosen PIC there.

**The lesson, which is about method and not about PIC.** I had named those two
cells as *the discriminator* and then spent the message reasoning about them
instead of building them both ways, which is a two-minute measurement and would
have given the sign directly. A hypothesis formed from a correct premise can
still point the wrong way, and the cells that will settle it are usually the ones
already in hand. When the pair that differs is "the 32-bit cell fails, the 64-bit
cell passes", the 64-bit cell is not a control — it is the answer, because it is
the same inference having chosen differently. Read the difference before
predicting it.
