// SPDX-License-Identifier: curl
// See FORK-LICENSE.md for what that identifier covers.
//!
//! Zig 0.16 build for libcurl 8.22.0.
//!
//! The library is upstream's own C, byte for byte: all 196 units of
//! `CSOURCES` in `lib/Makefile.inc:439-441`, and nothing else. No CMake, no
//! autotools, no Make, no build-time download and no installed `libcurl` as a
//! default; every unit is compiled from `lib/` in this repository. What this
//! file adds is the one thing upstream generates at configure time and this
//! package must not hand-write: `curl_config.h`, which
//! `lib/curl_setup.h:140` includes by bare name.
//!
//! Upstream reference: the official `curl-8.22.0.tar.xz` release,
//! `include/curl/curlver.h:35` (`LIBCURL_VERSION "8.22.0"`) and `:39-41`
//! (`LIBCURL_VERSION_MAJOR 8`, `_MINOR 22`, `_PATCH 0`), `:60`
//! (`LIBCURL_VERSION_NUM 0x081600`). The release digest belongs in
//! `UPSTREAM.md`, which the provenance owner writes; this script does not
//! restate one.
//!
//! Entry points
//! -----------
//!   zig build           install the artifact, the twelve public headers, the
//!                        relocatable `libcurl.pc`, and the licence and
//!                        provenance records; and compile the example
//!   zig build test      run the behavioural tests for the selected target
//!   zig build smoke     run the example program
//!   zig build consumer  build the separate `consumer/` package, and run it
//!                        when this host can execute the selected target
//!   zig build check     compile the library, the facade, the tests, the
//!                        example and all 196 C units for the five buildable
//!                        check targets, running nothing. `wasm32-wasi` is named
//!                        in `refused_check_targets` and stops the build with
//!                        its reason instead of being compiled
//!
//!   cross-test       the same `test` step, for the published 53-platform
//!                   Zig 0.16.0 Tier 1/2 table rather than the host alone,
//!                   with `cross-test.profile.sh` pinning
//!                   `CROSS_BUILD_ARGS=(-Dlinkage=static -Druntime=false)`, so
//!                   the published matrix and the `check` baseline below are
//!                   the same static linked closure.
//!
//! Options
//! -------
//!   -Dlinkage=static   a static archive, `libcurl.a`. The default.
//!   -Dlinkage=dynamic  a real shared object with the libtool-derived ABI
//!                      identity, `libcurl.so.4.8.0` and soname `libcurl.so.4`.
//!                      See "ABI identity and the bare loader name" below.
//!   -Druntime=true     resolve the native entry points at run time instead of
//!                      linking them. Orthogonal to `-Dlinkage`. Default off.
//!   -Dtls=<path>       override the mbed-TLS package location. **Refused
//!                      while the mbed-TLS package declares no such option**;
//!                      see "What -Dtls does, and why it refuses".
//!   -Dca-bundle=<pem>  compiled into `CURL_CA_BUNDLE`.
//!   -Dca-path=<dir>    compiled into `CURL_CA_PATH`.
//!   -Dtarget=<triple>  build for one target; `check` then checks that target
//!                      only instead of the whole matrix.
//!   -Doptimize=<mode>  the caller's mode, passed to every graph below.
//!
//! There is deliberately **no option that turns TLS off**. A build that cannot
//! resolve mbed-TLS stops at configure time with a message naming the
//! dependency; see "TLS, and why it cannot be off".
//!
//! The 196 units
//! -------------
//! `lib/Makefile.inc:439-441` is the closure, and this build compiles all of
//! it. The seven groups and their counts, read out of that file:
//!
//!   group            make variable        lines        units
//!   LIB_CFILES       :174-301             :175-301     127
//!   LIB_VAUTH_CFILES :68-81               :69-81        13
//!   LIB_VDNS_CFILES  :87-97               :88-97        10
//!   LIB_VTLS_CFILES  :107-123             :108-123      16
//!   LIB_VQUIC_CFILES :144-152             :145-152       8
//!   LIB_VSSH_CFILES  :165-168             :166-168       3
//!   LIB_CURLX_CFILES :26-45               :27-45        19
//!                                          total        196
//!
//! Nothing may be dropped, and nothing here is a smaller list than upstream's.
//! That matters because upstream's own design is that a unit whose feature macro
//! is absent still compiles - to an empty translation unit - rather than being
//! left out of the list. Read the first `#if` of each and it is a guard, not an
//! include:
//!
//!   `lib/vquic/cf-ngtcp2.c:26`   `#if defined(USE_NGTCP2) && defined(USE_NGHTTP3)`
//!   `lib/vssh/libssh2.c:26`       `#ifdef USE_LIBSSH2`
//!   `lib/openldap.c:27`          `#if !defined(CURL_DISABLE_LDAP) && defined(USE_OPENLDAP)`
//!   `lib/ldap.c:28`              `#if !defined(CURL_DISABLE_LDAP) && !defined(USE_OPENLDAP)`
//!   `lib/curl_gssapi.c:26`       `#ifdef HAVE_GSSAPI`
//!   `lib/curl_sspi.c:26`         `#ifdef USE_WINDOWS_SSPI`
//!   `lib/memdebug.c:26`          `#ifdef CURL_MEMDEBUG`
//!   `lib/amigaos.c:26`           `#ifdef __AMIGA__`
//!   `lib/system_win32.c:26`      `#ifdef _WIN32`
//!   `lib/http2.c:26`             `#if !defined(CURL_DISABLE_HTTP) && defined(USE_NGHTTP2)`
//!   `lib/psl.c:26`               `#ifdef USE_LIBPSL`
//!   `lib/vtls/openssl.c`         `#ifdef USE_OPENSSL`
//!   `lib/curl_ntlm_core.c:26`    `#ifdef USE_CURL_NTLM_CORE`
//!   `lib/http_ntlm.c:26`         `#if !defined(CURL_DISABLE_HTTP) && defined(USE_NTLM)`
//!
//! A unit in the list whose guard is absent contributes no object symbols and
//! costs nothing at link time; a unit *missing* from the list would take a
//! protocol or a hash algorithm with it. That is the difference this list
//! preserves, and it is why `curl_sources` below is a transcription with
//! `Makefile.inc` line numbers in its comments rather than a glob.
//!
//! Generated input
//! ---------------
//! `lib/curl_setup.h:138-140` is
//!
//!     #ifdef HAVE_CONFIG_H
//!     #include "curl_config.h"
//!
//! so `HAVE_CONFIG_H` goes on the C compile line, and the header it names comes
//! from `build_support/curl_config_gen.c`. Per AGENTS.md section 5 that is a
//! deterministic build step from a host-target generator, never a hand-written
//! stand-in, and four properties of it are the whole point:
//!
//!   * It runs **for the host** and is **given the target's facts as argv**.
//!     Running it on an x86_64 Linux build host to configure
//!     `aarch64-macos-none` is correct; copying the host's platform macros onto
//!     a cross target is the failure AGENTS.md section 5 forbids. The program
//!     contains no `#ifdef` on any host macro and includes no host header.
//!   * Its output `LazyPath` is `.generated`, and this file never calls
//!     `LazyPath.getPath` on it. `getPath4`
//!     (`lib/std/Build.zig:2488-2510`) panics for a `.generated` path whose
//!     `gen.file.path` is still unset, and that is unset until the make phase
//!     assigns it. So the path reaches the compile line as a `LazyPath` and is
//!     resolved in a dependent make step, never during `build()`.
//!   * Its **directory** goes on both lines that need it: the C compile line,
//!     because `lib/curl_setup.h:140` includes `curl_config.h` by bare name, and
//!     the translate-c line, because `zig/translate.h` is compiled for the same
//!     target and the translation must see the same header the C saw or it will
//!     describe a different ABI. `LazyPath.dirname` is what produces that
//!     directory (`lib/std/Build.zig:2377-2421`).
//!   * The 35 rows that ask whether the target **has a header file** are decided
//!     by a measured answer, not by the OS family. See `addHeaderProbe` below and
//!     "Header existence is a probe, not a family" in
//!     `build_support/curl_config_gen.c`.
//!   * The 47 rows that ask whether the target **declares a function** are
//!     decided by a measured answer, for the same reason and one step further
//!     out: a header is a file, and a function is a *declaration*, so no
//!     `__has_*` operator can answer the second question. See
//!     `addFunctionProbe` below and "Function existence is a probe, not a
//!     family" in `build_support/curl_config_gen.c`. `HAVE_ACCEPT4` was the
//!     proof: the Darwin headers Zig ships declare neither `accept4` nor
//!     `memrchr`, and the family mask claimed both, so `lib/cf-socket.c:2298`
//!     and `lib/cookie.c:168` called functions the target does not have.
//!
//! TLS, and why it cannot be off
//! -----------------------------
//! `USE_MBEDTLS` is put on the C compile line and on the translation line. It
//! is upstream's own documented selector: `lib/curl_setup.h:727-730` turns any
//! one of `USE_GNUTLS`, `USE_OPENSSL`, `USE_MBEDTLS`, `USE_WOLFSSL`,
//! `USE_SCHANNEL` or `USE_RUSTLS` into `USE_SSL`, and `lib/vtls/vtls.c:693` and
//! `:712` read it to pick the backend. No other `USE_*SSL*` macro is defined
//! anywhere in this package, so `lib/vtls/openssl.c`, `lib/vtls/gtls.c`,
//! `lib/vtls/wolfssl.c`, `lib/vtls/rustls.c` and `lib/vtls/schannel.c` are empty
//! translation units and mbed-TLS is the only backend.
//!
//! The mbed-TLS package is reached only through the standard dependency
//! mechanism - `build.zig.zon` carries exactly one `.dependencies` entry,
//! `b.dependency("mbed-tls", ...)`, and there is no vendored copy, no
//! fork-private bridge and no header copied into this tree. A build that cannot
//! resolve it stops at configure time naming it; it never produces a TLS-less
//! libcurl. Link order is `mbedtls`, `mbedx509`, `mbedcrypto`, which is the
//! order the driver fixed and the order `addGraph` uses.
//!
//! What the mbed-TLS side has to answer, and how this build answers it
//! -----------------------------------------------------------------------
//! Three values in the generated header are facts about the mbed-TLS *headers*
//! rather than about the target. They are named here because a reader of the
//! generated `curl_config.h` sees the results and cannot see where they came
//! from. All three are **PENDING-VERIFICATION**: `mbed-tls/` is not on disk yet
//! and no gate has run.
//!
//!   * `MBEDTLS_VERSION_NUMBER` is `0x03060700` (mbed-TLS 3.6.7), so the build
//!     takes the **3.x** side of `lib/vtls/mbedtls.c:47`. That branch is
//!     load-bearing: mbed-TLS 4.0 moved the primitives to TF-PSA-Crypto and
//!     removed the legacy `mbedtls_*` entry points, so `lib/vtls/mbedtls.c:37-55`
//!     and everything else in the tree that calls them would not link.
//!   * `HAVE_MBEDTLS_DES_CRYPT_ECB` is defined, because `mbedtls_des_crypt_ecb`
//!     is declared at `mbedtls/des.h:266` and `MBEDTLS_DES_C` is enabled in that
//!     configuration. `lib/curl_setup.h:759` keys `USE_CURL_NTLM_CORE` off
//!     exactly this macro, so it is what makes `CURL_ENABLE_NTLM` above it mean
//!     anything.
//!   * `MBEDTLS_SSL_ALPN` is enabled, so the `HAS_ALPN_MBEDTLS` branch at
//!     `lib/vtls/mbedtls.c:73` would be live. It stays dead in this
//!     configuration because HTTP/2 needs nghttp2 and there is no second
//!     dependency: `lib/http2.c:26` needs `USE_NGHTTP2`, which `curl_config_gen.c`
//!     leaves undefined. The two facts are recorded here so nobody reads the
//!     ALPN branch as a capability this build has.
//!
//! The generator refuses to guess any of the three: `--mbedtls-des-crypt-ecb
//! yes|no` is a required argument with no default, and a value outside it stops
//! the run before a byte is written.
//!
//! ABI identity and the bare loader name
//! -------------------------------------
//! Two different numbers answer two different questions, and stating only one
//! of them is how a reader ends up thinking `libcurl.so.8` exists:
//!
//!   * The **release** version is `8.22.0`, from `include/curl/curlver.h:35`.
//!     It is what `build.zig.zon .version` must equal, what `libcurl.pc`'s
//!     `Version:` must say, and what `curl_version()` returns at run time
//!     (`lib/version.c:543`). `build` refuses to configure when the manifest and
//!     the header disagree.
//!   * The **ABI** version is libtool's `current - age`, and it is not a
//!     release number. `lib/Makefile.soname:26-28` carries the triple
//!     `VERSIONCHANGE=12`, `VERSIONADD=0`, `VERSIONDEL=8`; `lib/Makefile.soname:30-31`
//!     turns it into `-version-info 12:0:8` and `:34` states the
//!     `current[:revision][:age]` gloss; and `lib/CMakeLists.txt:268-271` reads
//!     that same vendored file and computes `_cmasesoname` as
//!     `VERSIONCHANGE - VERSIONDEL` = **4**, with `:272` making the full
//!     `_cmakeversion` **4.8.0** and `:277` applying them as `SOVERSION` and
//!     `VERSION`. `lib/CMakeLists.txt:303` then *defines*
//!     `CURL_LIBCURL_VERSIONED_SYMBOLS_SONAME` from those numbers - so the macro
//!     `lib/Makefile.soname:24` says to keep in sync is produced by a file this
//!     package does vendor.
//!
//! So `-Dlinkage=dynamic` installs `libcurl.so.4.8.0` with soname
//! `libcurl.so.4`. **`libcurl.so.4` is also the bare name a caller hands to
//! `dlopen`** under the runtime route's `LoadSource.system`: the soname is the
//! name the loader resolves, which is why it and not the versioned file name is
//! the one to document. That pairing is stated here once and is the only place
//! in this package where the two file names appear.
//!
//! The version script is upstream's own template rather than something written
//! here: `lib/libcurl.vers.in` is four lines - a node name
//! `CURL_<PREFIX><SONAME>`, then `global: curl_*; local: *;` - and
//! `lib/CMakeLists.txt:289-290` picks prefix `MBEDTLS_` under `CURL_USE_MBEDTLS`
//! while `:303` supplies soname `4`, so the node is `CURL_MBEDTLS_4`. For COFF,
//! `lib/libcurl.def` is upstream's own export list, 100 `curl_*` entries and no
//! `Curl_*`, and it is used verbatim.
//!
//! What -Dtls does, and why it refuses
//! ------------------------------------
//! `-Dtls` is declared as `?std.Build.LazyPath` and means "override the
//! mbed-TLS package location". It **refuses** rather than pretending, and the
//! reason is a property of Zig 0.16's own API:
//!
//! `Build.dependency(name, args)` (`lib/std/Build.zig:2055-2071`) resolves a
//! package's root from the `.dependencies` entry in `build.zig.zon` and offers
//! no per-call path override; the `args` it forwards are the *dependency's* own
//! `-D` options. The `mbed-tls` package declares none that relocates its root -
//! it resolves everything through `b.path("...")` relative to its own package -
//! so forwarding `-Dtls` would reach a map that ignores it. Ignoring an option
//! the caller set is a no-op fallback, which AGENTS.md section 1 forbids, and a
//! silent no-op on a TLS backend is the worst place to have one.
//!
//! So `build` stops with a message naming the dependency, the two ways the
//! override could become real (edit this manifest's `.path`, or add a package-
//! root option to `mbed-tls/build.zig`), and the fact that no gate has
//! established which. It is not a stub: the default path, `-Dtls` absent,
//! resolves `b.dependency("mbed-tls", ...)` and is the configuration this
//! package ships.
//!
//! Per-target configuration
//! ------------------------
//! Everything that describes the target's C library is in one table inside
//! `build_support/curl_config_gen.c`, and it is a table rather than branching
//! code so a reader can diff it against `lib/curl_config-cmake.h.in` row by row.
//! What this file contributes is the argv: `--os`, `--arch`,
//! `--pointer-width`, `--endian`, `--libc`, `--mbedtls-des-crypt-ecb`,
//! `--ca-bundle`, `--ca-path`, `--curl-version`, `--output`. The generator
//! validates all of them and refuses rather than defaulting.
//!
//! Four configuration decisions are forced rather than chosen, and all four are
//! recorded in the generator at the row that carries them:
//!
//!   * **`CURL_DISABLE_LDAP` and `CURL_DISABLE_LDAPS` are set.** `lib/ldap.c:28`
//!     is `#if !defined(CURL_DISABLE_LDAP) && !defined(USE_OPENLDAP)` and the
//!     unit then includes `<lber.h>` and `<ldap.h>` unguarded
//!     (`lib/ldap.c:59`, `:61`). A dependency set with exactly one entry has no
//!     LDAP, so leaving this unset does not build - it fails on a missing
//!     header. The cost is real and named: this libcurl speaks no `ldap://` and
//!     no `ldaps://`, and `lib/protocol.c:192` and `:205` turn both scheme
//!     entries into ZERO_NULL.
//!   * **No HTTP/2.** `lib/http2.c:26` needs `USE_NGHTTP2`, which needs nghttp2,
//!     which would be a second dependency. HTTP/1.1 only.
//!   * **No content encoding beyond `identity`.** `lib/content_encoding.c:29`
//!     is `#ifdef HAVE_LIBZ` and the same unit reads the brotli and zstd rows,
//!     so all three are off and the whole unit compiles out.
//!   * **No Public Suffix List.** `lib/psl.c:26` is `#ifdef USE_LIBPSL`, so
//!     `lib/cookie.c:804`'s public-suffix rejection is compiled out. This one
//!     has a security reading and is worth stating plainly: cookie rejection is
//!     coarser without a PSL. A second dependency is the fix and it is not taken
//!     here because the driver fixed the dependency surface at exactly one
//!     entry.
//!
//! `wasm32-wasi` and the mbed-TLS backend
//! --------------------------------------
//! `wasm32-wasi` is refused outright, and the reason is a fact about the TLS
//! backend rather than about curl or about the toolchain's libc.
//!
//! `MBEDTLS_NET_C` is compiled in for every unix-like and Windows target and
//! **out** for `wasm32-wasi`: the mbed-TLS sources `#error` unless
//! `MBEDTLS_PLATFORM_IS_UNIXLIKE || _WIN32`, and that macro is built from
//! `unix` / `__unix` / `__unix__` / (`__APPLE__` && `__MACH__`) / `__HAIKU__` /
//! `__midipix__` / `_WIN32` - none of which WASI's clang defines. So
//! `mbedtls_net_connect` and `mbedtls_net_accept` exist on Linux, macOS and
//! Windows and not on WASI, and `lib/vtls/mbedtls.c` calls both
//! (`mbedtls_net_connect` for the handshake, `mbedtls_net_accept` for the
//! listener side).
//!
//! There is no configuration this package can write that changes that: it is a
//! compile-time `#error` inside the dependency, not a macro on this side's
//! line. So the target is named in `refused_check_targets`, `refusalFor`
//! holds the reason, `refuseTarget` prints it and stops, and
//! `checkMatrixPartition` fails any build of this package if the refusal ever
//! lapses without the row having been moved back and proved. Nothing is dropped
//! silently (AGENTS.md section 6) and nothing is patched past.
//!
//! What this is not: not a claim that WASI cannot host curl, and not a claim
//! about the WASI libc. `lib/curl_setup.h:200-203`, `lib/curlx/nonblock.c:52-70`
//! and `lib/socketpair.c:34-52` would all have answers there - the generator's
//! own family table carries a refusal for `--os wasi` with these words - and
//! `lib/curl_setup.h:470-473` would leave `USE_EVENTFD` undefined so
//! `lib/socketpair.c` would take its `HAVE_PIPE` arm. The cell comes back when
//! the mbed-TLS package's `MBEDTLS_NET_C` covers WASI, or when
//! `lib/vtls/mbedtls.c` stops needing `mbedtls_net_*`. Either is the dependency's
//! or upstream's to make, and this package makes neither.
//!
//! Two further delivery facts about WASI, kept separate from the refusal above:
//! it has no dynamic linker (`deliveredLinkage` refuses `-Dlinkage=dynamic`
//! there), and the runtime route's Unix backend calls `dlopen`, which WASI does
//! not have. Neither is why the row is refused.
//!
//! Windows
//! -------
//! `lib/config-win32.h` is upstream's own hand-written Windows configuration
//! and this build reads it as a statement of what a Windows C build of this
//! release can rely on. It does **not** install or include it:
//! `lib/curl_setup.h:138-140` sends a `HAVE_CONFIG_H` build to the generated
//! header instead, and `lib/config-win32.h:29-31` is itself
//! `#error This manual configuration requires MSVC 2010-2013` for anything that
//! is not MSVC, so it could not be used by `x86_64-windows-gnu` at all.
//!
//! Two rows it sets are deliberately **not** followed, and both are named
//! rather than quietly dropped:
//!
//!   * `USE_WINDOWS_SSPI` (`lib/config-win32.h` has no such row, but the whole
//!     Windows SSPI arrangement rests on it). `lib/curl_sspi.h:30` includes
//!     `<sspi.h>` under it and linking the unit needs `-lssldbl` or `-lssp` plus
//!     `-lsecur32`. This package cannot confirm those for a GNU toolchain
//!     without running a gate, so `lib/curl_sspi.c:26`, `lib/socks_sspi.c:27`
//!     and `lib/vauth/*_sspi.c` are empty translation units and
//!     `lib/curl_setup.h:744-753` leaves `USE_SPNEGO` and `USE_KERBEROS5`
//!     undefined on Windows as well as everywhere else. Negotiate, Kerberos and
//!     NTLM-over-SSPI are therefore absent on the Windows row; NTLM itself is
//!     not, because `lib/curl_setup.h:762` takes it from `USE_CURL_NTLM_CORE`
//!     through `USE_MBEDTLS && HAVE_MBEDTLS_DES_CRYPT_ECB`.
//!   * `USE_RESOLV_THREADED` (`lib/config-win32.h:103-106` defaults it on). The
//!     threaded resolver needs a working threads implementation, which on
//!     Windows is a link line rather than a header. This build uses
//!     `CURLRES_SYNCH` on Windows (`lib/curl_setup.h:711-712`), which is slower
//!     per lookup and correct.
//!
//! `lib/socketpair.c` does not need `HAVE_SOCKETPAIR` there: with no
//! `USE_EVENTFD`, no `HAVE_PIPE` and no `HAVE_SOCKETPAIR` it takes the
//! loopback-socket implementation at `lib/socketpair.c:129-140`, which is the
//! fourth arm and the one whose `#error` at `:90` lives in the
//! `HAVE_SOCKETPAIR`-without-`USE_UNIX_SOCKETS` arm this build never enters.

const std = @import("std");

const manifest = @import("build.zig.zon");

/// `build.zig.zon .version`, parsed. The parse is the loud part: a manifest whose
/// `.version` is not a semantic version fails to configure here rather than
/// being silently compared as something else.
const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon: .version is not a semantic version");

/// Upstream's release version, read out of `include/curl/curlver.h:35`
/// (`LIBCURL_VERSION "8.22.0"`) and `:39-41` (major 8, minor 22, patch 0). It is
/// the version of the C library this package builds, and `build.zig.zon
/// .version` carries the same string; `build` refuses to configure when the two
/// drift apart, so `libcurl.pc`'s `Version:`, the recorded release and the
/// header a consumer includes cannot describe three different releases.
///
/// It is a *release* number and nothing more. The shared object's ABI identity
/// is a different number, derived differently; see `abi_version`.
const upstream_version: std.SemanticVersion = .{ .major = 8, .minor = 22, .patch = 0 };

/// Upstream's release as a string, for the generator's header comment and for
/// `libcurl.pc`. A separate constant rather than a runtime format of
/// `upstream_version` so that `LIBCURL_VERSION_NUM`'s hexadecimal form
/// (`include/curl/curlver.h:60`, `0x081600`) and this decimal form cannot be
/// confused for one another.
const upstream_version_string = "8.22.0";

/// The shared object's ABI version: libtool's `current - age`, which
/// `lib/CMakeLists.txt:271` computes from the triple at
/// `lib/Makefile.soname:26-28` as 12 - 8 = 4, and `:272` completes to 4.8.0.
/// Zig's `Compile.version` takes the full triple and derives `SOVERSION` from
/// its major, which is the 4. This is **not** the release version: `8.22.0` and
/// `4.8.0` answer different questions and both appear in the installed tree.
const abi_version: std.SemanticVersion = .{ .major = 4, .minor = 8, .patch = 0 };

/// The ELF version-script node prefix for this backend.
/// `lib/CMakeLists.txt:289-290` picks `MBEDTLS_` when `CURL_USE_MBEDTLS` is set
/// and `CURL_LIBCURL_VERSIONED_SYMBOLS_PREFIX` is not; this build sets only
/// `USE_MBEDTLS`, so `MBEDTLS_` is the prefix upstream's own rule produces.
const version_script_prefix = "MBEDTLS_";

/// Package id, the name a dependent writes in its dependency map, the one
/// registered module and the C artifact. They are one name on purpose:
/// `dep.module("libcurl")` and `dep.artifact("libcurl")` describe the same
/// library, and `libcurl.a` is what Zig emits for an artifact called `libcurl`
/// because `lib/std/Build/Step/Compile.zig` prepends the platform's `lib`
/// prefix. It is also the name a C consumer's `-lcurl` needs.
const lib_name = "libcurl";

/// The mbed-TLS package's name in *this* manifest's dependency map. The hyphen
/// is forced: a ZON struct field name cannot be an identifier, so the key is
/// written `.@"mbed-tls"`. The package's own `.name` in
/// `mbed-tls/build.zig.zon` is `.mbed_tls` for the same reason and it does not
/// affect this key. What it does affect is the module and artifact names below,
/// which stay unhyphenated because they are strings.
const tls_dependency_name = "mbed-tls";

/// The three mbed-TLS archives, in the order the driver fixed: `mbedtls` needs
/// symbols from `mbedx509`, and `mbedx509` needs symbols from `mbedcrypto`, so
/// this order is a link-order requirement and not a preference.
///
/// The sibling also publishes `dep.module("mbedtls")`, and this package
/// deliberately does not import it. Nothing in libcurl's own Zig surface names
/// an mbed-TLS type: `zig/translate.h` includes `<curl/curl.h>`, which is opaque
/// about the backend, and `CURLOPT_SSL_OPTIONS` and `curl_ssl_ctx_callback` are
/// an `unsigned long` and an opaque `void *` at the boundary. The mbed-TLS
/// headers are reached from the C side by `-I` alone, because the sibling
/// installs its generated configuration as the canonical
/// `mbedtls/mbedtls_config.h` - see `add_c_library`. A dependent that wants
/// those types asks the sibling for them directly; importing them here would
/// put a second, duplicate copy of the mbed-TLS declarations into every
/// consumer of this package's module.
const tls_artifacts = [_][]const u8{ "mbedtls", "mbedx509", "mbedcrypto" };

/// Where the sibling's public headers are, relative to its package root.
///
/// `src/include`, not `include`: `Dependency.path` resolves against the
/// dependency's source root (`mbed-tls/build.zig.zon` `include_dir` at
/// `mbed-tls/build.zig:129` is the same string), and a package root does not
/// hold its own installed `include/`.
const tls_public_include = "src/include";

/// Whether the resolved mbed-TLS declares `mbedtls_des_crypt_ecb`, which is a
/// fact about its headers and not about the target being built.
///
/// PENDING-VERIFICATION: `mbed-tls/` is not on disk. The value is `yes` for
/// mbed-TLS 3.6.7, whose `MBEDTLS_VERSION_NUMBER` is `0x03060700` and which
/// declares `mbedtls_des_crypt_ecb` at `mbedtls/des.h:266` with `MBEDTLS_DES_C`
/// enabled. It is load-bearing: `lib/curl_setup.h:759` makes it one of five
/// conditions for `USE_CURL_NTLM_CORE`, so setting it to `no` removes
/// `lib/curl_ntlm_core.c`'s body and with it NTLM. If `mbed-tls/` ever moves to
/// 4.x this must change together with the version note in the module comment,
/// because 4.0 removed the legacy `mbedtls_*` crypto entry points entirely.
const mbedtls_des_crypt_ecb = "yes";

/// The Zig facade, owned by the API role. It re-exports the translated headers
/// as `c` by importing them under the name `translate`, so this file registers
/// that name and no other.
const facade_source = "zig/root.zig";

/// The aggregate translation header, owned by the API role.
const translate_header = "zig/translate.h";

/// The import name the facade sees the translated headers under.
/// `local://libcurl-facade-surface.md:15` fixes it as `translate`, not lua's
/// `c`, and the API owner codes against it.
const translate_import_name = "translate";

/// The import name the facade sees the runtime loader core under, in the linked
/// configuration only. One instance per build: `graph.createModule` creates the
/// core the generated dispatch uses, so a second instance here would be a
/// nominally different `LoadSource`/`LoadError`.
const loader_import_name = "rt";

/// Test root and example root, both owned by the Behaviour role.
const test_source = "tests.zig";
const example_source = "smoke.zig";

/// Upstream's C, and the generated header's home. Every internal include in
/// `lib/` is quoted and relative to `lib/`, so one include path given to every
/// C compilation is what keeps all of it resolvable; `include/` is on the line
/// too because `lib/curl_setup.h:342` includes `<curl/system.h>` and
/// `lib/cf-h1-proxy.c:29` includes `<curl/curl.h>`.
const source_dir = "lib";
const public_include_dir = "include";

/// The one generated input. `lib/curl_setup.h:140` includes it by bare name, so
/// its directory - not its path - is what goes on a compile line.
const config_generator_source = "build_support/curl_config_gen.c";
const config_header_name = "curl_config.h";

/// The header-existence probe, compiled **for the target** and never run. Its
/// preprocessor output is the `--header-facts` input `curl_config_gen.c` reads.
/// `addHeaderProbe` below is where it is compiled and why.
const header_probe_source = "build_support/curl_headers_probe.c";

/// The function-existence probe, compiled **for the host** as a *collector* and
/// run; the collector compiles one tiny probe **for the target** per function and
/// writes the `--function-facts` input `curl_config_gen.c` reads.
/// `addFunctionProbe` below is where it is built and why it is a collector
/// rather than a compile.
const function_probe_source = "build_support/curl_existence_probe.c";

/// The name of the collector's output. A real artifact with a real cache key,
/// for the reason `curl_header_facts.txt` is one: the generator takes it as a
/// tracked file input, so it has to be a path the build graph owns.
const function_facts_name = "curl_function_facts.txt";

/// The 196 units of `CSOURCES` (`lib/Makefile.inc:439-441`), transcribed in
/// upstream's own order and with the make variable and line range each group
/// came from.
///
/// This is a transcription and not a glob, deliberately. `lib/` holds 398 files
/// and upstream's closure is 196 of them; a glob would compile the other 202,
/// including the two hand-written configurations this build does not include
/// (`lib/config-win32.h`, `lib/config-mac.h`) and the build-system files it does
/// not execute. And a list is checkable: it can be read back out of this file
/// and diffed against `Makefile.inc`, which a glob cannot.
const curlx_sources = [_][]const u8{
    // LIB_CURLX_CFILES, lib/Makefile.inc:26-45, entries at :27-45. 19 units.
    "lib/curlx/base64.c",
    "lib/curlx/basename.c",
    "lib/curlx/dynbuf.c",
    "lib/curlx/fopen.c",
    "lib/curlx/inet_ntop.c",
    "lib/curlx/inet_pton.c",
    "lib/curlx/multibyte.c",
    "lib/curlx/nonblock.c",
    "lib/curlx/snprintf.c",
    "lib/curlx/strcopy.c",
    "lib/curlx/strdup.c",
    "lib/curlx/strerr.c",
    "lib/curlx/strparse.c",
    "lib/curlx/timediff.c",
    "lib/curlx/timeval.c",
    "lib/curlx/version_win32.c",
    "lib/curlx/wait.c",
    "lib/curlx/warnless.c",
    "lib/curlx/winapi.c",
};

const vauth_sources = [_][]const u8{
    // LIB_VAUTH_CFILES, lib/Makefile.inc:68-81, entries at :69-81. 13 units.
    "lib/vauth/cleartext.c",
    "lib/vauth/cram.c",
    "lib/vauth/digest.c",
    "lib/vauth/digest_sspi.c",
    "lib/vauth/gsasl.c",
    "lib/vauth/krb5_gssapi.c",
    "lib/vauth/krb5_sspi.c",
    "lib/vauth/ntlm.c",
    "lib/vauth/ntlm_sspi.c",
    "lib/vauth/oauth2.c",
    "lib/vauth/spnego_gssapi.c",
    "lib/vauth/spnego_sspi.c",
    "lib/vauth/vauth.c",
};

const vdns_sources = [_][]const u8{
    // LIB_VDNS_CFILES, lib/Makefile.inc:87-97, entries at :88-97. 10 units.
    "lib/vdns/asyn-ares.c",
    "lib/vdns/asyn-base.c",
    "lib/vdns/asyn-thrdd.c",
    "lib/vdns/cf-dns.c",
    "lib/vdns/dnscache.c",
    "lib/vdns/doh.c",
    "lib/vdns/hostip.c",
    "lib/vdns/hostip4.c",
    "lib/vdns/hostip6.c",
    "lib/vdns/httpsrr.c",
};

const vtls_sources = [_][]const u8{
    // LIB_VTLS_CFILES, lib/Makefile.inc:107-123, entries at :108-123. 16 units.
    // `lib/vtls/mbedtls.c` is the one unit here whose body is live; the other
    // fifteen are empty translation units because their `USE_*` backend macro is
    // undefined. See the module comment on the TLS decision.
    "lib/vtls/apple.c",
    "lib/vtls/cipher_suite.c",
    "lib/vtls/gtls.c",
    "lib/vtls/hostcheck.c",
    "lib/vtls/keylog.c",
    "lib/vtls/mbedtls.c",
    "lib/vtls/openssl.c",
    "lib/vtls/rustls.c",
    "lib/vtls/schannel.c",
    "lib/vtls/schannel_verify.c",
    "lib/vtls/vtls.c",
    "lib/vtls/vtls_config.c",
    "lib/vtls/vtls_scache.c",
    "lib/vtls/vtls_spack.c",
    "lib/vtls/wolfssl.c",
    "lib/vtls/x509asn1.c",
};

const vquic_sources = [_][]const u8{
    // LIB_VQUIC_CFILES, lib/Makefile.inc:144-152, entries at :145-152. 8 units.
    "lib/vquic/capsule.c",
    "lib/vquic/cf-capsule.c",
    "lib/vquic/cf-ngtcp2.c",
    "lib/vquic/cf-ngtcp2-cmn.c",
    "lib/vquic/cf-ngtcp2-proxy.c",
    "lib/vquic/cf-quiche.c",
    "lib/vquic/vquic.c",
    "lib/vquic/vquic-tls.c",
};

const vssh_sources = [_][]const u8{
    // LIB_VSSH_CFILES, lib/Makefile.inc:165-168, entries at :166-168. 3 units.
    "lib/vssh/libssh.c",
    "lib/vssh/libssh2.c",
    "lib/vssh/vssh.c",
};

const core_sources = [_][]const u8{
    // LIB_CFILES, lib/Makefile.inc:174-301, entries at :175-301. 127 units.
    "lib/altsvc.c",
    "lib/amigaos.c",
    "lib/api.c",
    "lib/bufq.c",
    "lib/bufref.c",
    "lib/cf-h1-proxy.c",
    "lib/cf-h2-proxy.c",
    "lib/cf-haproxy.c",
    "lib/cf-https-connect.c",
    "lib/cf-ip-happy.c",
    "lib/cf-recvbuf.c",
    "lib/cf-setup.c",
    "lib/cf-socket.c",
    "lib/cfilters.c",
    "lib/conncache.c",
    "lib/connect.c",
    "lib/content_encoding.c",
    "lib/cookie.c",
    "lib/creds.c",
    "lib/cshutdn.c",
    "lib/curl_addrinfo.c",
    "lib/curl_endian.c",
    "lib/curl_fnmatch.c",
    "lib/curl_fopen.c",
    "lib/curl_get_line.c",
    "lib/curl_gethostname.c",
    "lib/curl_gssapi.c",
    "lib/curl_memrchr.c",
    "lib/curl_ntlm_core.c",
    "lib/curl_range.c",
    "lib/curl_sasl.c",
    "lib/curl_sha512_256.c",
    "lib/curl_share.c",
    "lib/curl_sspi.c",
    "lib/curl_threads.c",
    "lib/curl_trc.c",
    "lib/cw-out.c",
    "lib/cw-pause.c",
    "lib/dict.c",
    "lib/dynhds.c",
    "lib/easy.c",
    "lib/easygetopt.c",
    "lib/easyoptions.c",
    "lib/escape.c",
    "lib/fake_addrinfo.c",
    "lib/file.c",
    "lib/fileinfo.c",
    "lib/formdata.c",
    "lib/ftp.c",
    "lib/ftplistparser.c",
    "lib/getenv.c",
    "lib/getinfo.c",
    "lib/gopher.c",
    "lib/hash.c",
    "lib/headers.c",
    "lib/hmac.c",
    "lib/hsts.c",
    "lib/http.c",
    "lib/http1.c",
    "lib/http2.c",
    "lib/http_aws_sigv4.c",
    "lib/http_httpsig.c",
    "lib/curl_ed25519.c",
    "lib/http_chunks.c",
    "lib/http_digest.c",
    "lib/http_negotiate.c",
    "lib/http_ntlm.c",
    "lib/http_proxy.c",
    "lib/idn.c",
    "lib/if2ip.c",
    "lib/imap.c",
    "lib/ldap.c",
    "lib/llist.c",
    "lib/macos.c",
    "lib/md4.c",
    "lib/md5.c",
    "lib/memdebug.c",
    "lib/mime.c",
    "lib/mprintf.c",
    "lib/mqtt.c",
    "lib/multi.c",
    "lib/multi_ev.c",
    "lib/multi_ntfy.c",
    "lib/netrc.c",
    "lib/openldap.c",
    "lib/parsedate.c",
    "lib/peer.c",
    "lib/pingpong.c",
    "lib/pop3.c",
    "lib/progress.c",
    "lib/protocol.c",
    "lib/proxy.c",
    "lib/psl.c",
    "lib/rand.c",
    "lib/ratelimit.c",
    "lib/request.c",
    "lib/rtsp.c",
    "lib/select.c",
    "lib/sendf.c",
    "lib/setopt.c",
    "lib/sha256.c",
    "lib/slist.c",
    "lib/smb.c",
    "lib/smtp.c",
    "lib/socketpair.c",
    "lib/socks.c",
    "lib/socks_gssapi.c",
    "lib/socks_sspi.c",
    "lib/splay.c",
    "lib/strcase.c",
    "lib/strequal.c",
    "lib/strerror.c",
    "lib/system_win32.c",
    "lib/telnet.c",
    "lib/tftp.c",
    "lib/thrdpool.c",
    "lib/thrdqueue.c",
    "lib/transfer.c",
    "lib/uint-bset.c",
    "lib/uint-hash.c",
    "lib/uint-hashset.c",
    "lib/uint-spbset.c",
    "lib/uint-table.c",
    "lib/url.c",
    "lib/urlapi.c",
    "lib/version.c",
    "lib/ws.c",
};

/// The whole closure, in the order `CSOURCES` names it
/// (`lib/Makefile.inc:439-441`): `$(LIB_CFILES) $(LIB_VAUTH_CFILES)
/// $(LIB_VDNS_CFILES) $(LIB_VTLS_CFILES) $(LIB_VQUIC_CFILES) $(LIB_VSSH_CFILES)
/// $(LIB_CURLX_CFILES)`.
///
/// Concatenated at comptime so the count is a compile-time fact rather than a
/// number somebody typed: `curl_source_count` below is what `build` prints, and
/// it is 196 because the list is, not because a comment says so.
const curl_sources = blk: {
    var all: [core_sources.len + vauth_sources.len + vdns_sources.len +
        vtls_sources.len + vquic_sources.len + vssh_sources.len +
        curlx_sources.len][]const u8 = undefined;
    var n: usize = 0;
    for ([_][]const []const u8{
        core_sources[0..],
        vauth_sources[0..],
        vdns_sources[0..],
        vtls_sources[0..],
        vquic_sources[0..],
        vssh_sources[0..],
        curlx_sources[0..],
    }) |group| {
        for (group) |unit| {
            all[n] = unit;
            n += 1;
        }
    }
    break :blk all;
};

const curl_source_count = curl_sources.len;

/// The twelve headers upstream installs, from `include/curl/Makefile.am:24-26`'s
/// `pkginclude_HEADERS`, and nothing else.
///
/// `include/curl/` also holds `README.md`, `Makefile.am` and `Makefile.in`.
/// None of the three is in `pkginclude_HEADERS` and none is installed here:
/// the Makefiles are build-system files for a build this package does not
/// execute, and the README is upstream's note about the header directory rather
/// than a declaration a consumer includes.
const public_headers = [_][]const u8{
    "curl.h",
    "curlver.h",
    "easy.h",
    "mprintf.h",
    "stdcheaders.h",
    "multi.h",
    "typecheck-gcc.h",
    "system.h",
    "urlapi.h",
    "options.h",
    "header.h",
    "websockets.h",
};

/// The licence and provenance records `zig build` installs under
/// `share/licenses/libcurl/`.
///
/// curl's grant is a standalone file - the tarball's `COPYING` - so unlike Lua
/// there is no choosing which file carries it. It is installed verbatim because
/// a package that ships a binary and not the licence text has removed an
/// obligation a private repository does not remove (AGENTS.md section 8), and
/// because `.paths` in `build.zig.zon` has to name it or a fetched copy of this
/// package would not contain it at all.
const licence_records = [_][]const u8{
    "COPYING",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
    "UPSTREAM.sha256",
    "README",
    "RELEASE-NOTES",
    "CHANGELOG.md",
    "FORK-NOTES.md",
};

/// Language level for every C translation unit, pinned.
///
/// curl's own C is C89-with-selections and its headers are careful about it, so
/// nothing here asks for anything newer than C99; the one thing C99 buys is
/// `//` comments in this build's own additions. The level is pinned rather than
/// inherited from the host clang so that "what dialect did this compile as" is a
/// fact about this build.
///
/// `gnu99` and not `c99`, and the difference is a feature-test macro rather than
/// a language one. glibc's `features.h` defines `_DEFAULT_SOURCE` only when
/// `__STRICT_ANSI__` is absent, and `-std=c99` sets it; with it set, `<unistd.h>`
/// hides `gethostname`, `<string.h>` hides `strerror_r`, `<stdlib.h>` hides
/// `explicit_bzero` and `<stdio.h>` hides `fseeko`. Upstream's own sources reach
/// all four, and upstream's own build passes no `-std=` at all, so every compiler
/// it has ever been built with used a `gnu` dialect. `gnu99` says C99 and keeps
/// that visibility, which is what "C99" has to mean for a POSIX library.
const c_flags = [_][]const u8{"-std=gnu99"};

/// The flags the collector itself is compiled with, and the one flag string it
/// passes to each `zig cc` it forks.
///
/// `-std=c11 -Wall -Wextra -Wpedantic` because the collector is build-machine
/// code that runs on every configure, for the same reason `generator_flags`
/// carries them: a warning here would stop an unrelated package's build at
/// configure time.
///
/// `probe_flags_arg` is a *single* string because the collector forwards one
/// `argv` entry to each probe rather than parsing a flag list. `-std=gnu99` is
/// `c_flags[0]`, the dialect the 196 library units get, and the two must agree:
/// a probe compiled as a different dialect than the closure asks a different
/// question about which declarations the target has.
const collector_flags = [_][]const u8{
    "-std=c11",
    "-Wall",
    "-Wextra",
    "-Wpedantic",
};
const probe_flags_arg = "-std=gnu99";

/// Flags for the host generator. `-Wall -Wextra -Wpedantic` because
/// `curl_config_gen.c` is build-machine code that runs on every configure and a
/// warning there is a warning on every build. Not `-Werror`: a new host
/// compiler's diagnostic should stop the driver at a gate with a receipt, not
/// stop an unrelated package's build at configure time.
const generator_flags = [_][]const u8{
    "-std=c11",
    "-Wall",
    "-Wextra",
    "-Wpedantic",
};

/// The cross-compilation matrix `check` walks when no target is named. The
/// order is the one this workspace uses everywhere.
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
};

/// The rows `check` does not walk because this build refuses them.
///
/// The row is not quietly absent and it is not quietly built: `refusalFor`
/// holds the reason, `refuseTarget` prints it and stops, and
/// `checkMatrixPartition` fails any build of this package if `refusalFor` ever
/// stops refusing it without the row having been moved back and proved.
/// See "wasm32-wasi and the mbed-TLS backend" in the module comment.
const refused_check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// What one target's graph produced, handed back to `build` and to
/// `add_target_check`.
const Graph = struct {
    /// The C archive or shared object. Never optional in this package: there is
    /// no system mode and no delivery that builds nothing.
    c_lib: *std.Build.Step.Compile,
    /// The facade module, published or private.
    module: *std.Build.Module,
};

/// Where the `--libc` value for the generator comes from, and why it is not
/// `@tagName(target.result.abi)`.
///
/// The generator needs a *libc* name, and Zig's resolved target carries an ABI
/// name that is not one: `x86_64-linux-musl`, `x86_64-windows-gnu` and
/// `aarch64-macos-none` are three ABIs and four libcs. Mapping is a small
/// explicit function rather than a string transform so that a target whose ABI
/// this build does not recognise is refused by name instead of being handed to
/// the generator as an unknown libc the generator would then reject with a less
/// useful message.
fn generatorLibc(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.os.tag) {
        // The two families where the libc is a genuine choice this build makes
        // per ABI, and therefore where an unrecognised ABI has to stop rather
        // than fall through to a default: glibc and musl differ in
        // `HAVE_GLIBC_STRERROR_R` versus `HAVE_POSIX_STRERROR_R`, which
        // `curl_config_gen.c` decides from this string, and in the `CURL_OS` it
        // writes.
        .linux => switch (target.result.abi) {
            .gnu, .gnuabin32, .gnuabi64, .gnux32, .gnueabi, .gnueabihf => "gnu",
            .musl, .musleabi, .musleabihf, .muslabi64 => "musl",
            else => std.debug.panic(
                "libcurl: no --libc value for OS {s} with ABI {s}. " ++
                    "curl_config_gen.c's Linux family has exactly two answers - gnu " ++
                    "and musl - because HAVE_GLIBC_STRERROR_R and " ++
                    "HAVE_POSIX_STRERROR_R are mutually exclusive and " ++
                    "lib/strerror.c reaches them through whichever the platform " ++
                    "has. Add the ABI to generatorLibc.",
                .{ @tagName(target.result.os.tag), @tagName(target.result.abi) },
            ),
        },
        // Darwin's libc is libSystem and its name is the only one curl_config.h
        // ever needs for it; the per-family rows that differ are the socket and
        // `struct sockaddr_in6` ones, and those are keyed on the OS tag.
        //
        // Mac Catalyst is here because it is Darwin: Mach-O, libSystem, and the
        // same headers. `std.Target.Os.Tag` keeps it a separate tag because it is
        // a separate *platform*, and this function maps a platform to a C
        // library, so the platform distinction stops here. Before this line
        // `maccatalyst` fell through to `sysv`, which is not what Mac Catalyst
        // links: the `aarch64-maccatalyst` and `x86_64-maccatalyst` cells of the
        // published 53-platform run were refused by the generator for
        // `--os maccatalyst` and would have been configured as SysV had it got
        // that far.
        .macos, .ios, .tvos, .watchos, .visionos, .maccatalyst => "darwin",
        // Windows: `x86_64-windows-gnu` is mingw, `x86_64-windows-msvc` is
        // msvcrt. Neither ships `lib/libcurl.def`'s sibling `libcurl.lib`, so the
        // ABI name reaches the generator only as the string that separates the
        // two C libraries in its accepted list; the Windows-specific rows are
        // keyed on the OS tag alone.
        .windows => switch (target.result.abi) {
            .msvc => "msvcrt",
            else => "mingw",
        },
        // The BSDs and the SysV family. Neither this build's six check targets
        // nor `cross-test.profile.sh` names one, but a caller may, and the
        // generator's per-family rows are written for them rather than for a
        // generic "posix" the table deliberately does not have.
        .freebsd, .netbsd, .openbsd, .dragonfly => "bsd",
        else => "sysv",
    };
}

/// Pointer width for the target as the two strings `curl_config_gen.c` accepts,
/// and a refusal for an architecture this file cannot describe.
///
/// `std.Target` in this compiler's `lib/std/Target.zig` declares `cpu`, `os`,
/// `abi`, `ofmt` and `dynamic_linker` and no pointer-width field, so the width
/// is stated here. It is not a guess about the architectures: a 32-bit ABI and a
/// 64-bit ABI are the two facts `lib/curl_setup.h:630-632` reasons about, and
/// each prong below is the width its instruction set defines.
///
/// WHY A SWITCH AND NOT A LIST OF NAMES
/// -----------------------------------
/// The previous form was a `[]const struct { []const u8, []const u8 }` searched
/// by `@tagName`. A list can only be as current as the last time somebody
/// remembered it, and this one was not: it carried `ia64`, `sparcel`, `sparcv9`
/// and `v850`, none of which `std.Target.Cpu.Arch` declares in this compiler
/// (`lib/std/Target.zig` lists the deliberately omitted LLVM tags, `sparcel`
/// among them), and it lacked `aarch64_be` and `thumbeb`, so
/// `aarch64_be-linux`, `aarch64_be-netbsd` and `thumbeb-linux` stopped the build
/// by name from `pointerWidthBits`.
///
/// A `switch` on the enum has no such failure mode, and it has no `else`: adding
/// an architecture to the pinned compiler turns this into a *compile error in
/// build.zig naming the missing architecture*, which is a refusal the compiler
/// can see rather than a runtime panic on a target nobody tried.
///
/// The three prongs that panic are the ones whose pointer width the generator
/// cannot use, and they stay an explicit named refusal rather than being rounded
/// up: `--pointer-width` accepts `32` and `64` only, because every `SIZEOF_*` row
/// is either one of those or derived from one of them.
fn pointerWidthBits(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.cpu.arch) {
        // 64-bit.
        .aarch64, .aarch64_be, .alpha, .amdgcn, .bpfeb, .bpfel, .hppa64, .kvx,
        .loongarch64, .mips64, .mips64el, .nvptx, .nvptx64, .powerpc64,
        .powerpc64le, .riscv64, .riscv64be, .s390x, .sparc64, .spirv64, .ve,
        .wasm64, .x86_64,
        => "64",

        // 32-bit. `thumb` and `thumbeb` are Thumb in an AArch32 profile, so both
        // are 32-bit, and the big-endian spelling of every big-endian-capable
        // architecture is the same width as its little-endian sibling: the byte
        // order is `--endian`'s business, never the width's.
        .arc, .arceb, .arm, .armeb, .csky, .hexagon, .hppa, .kalimba, .lanai,
        .loongarch32, .m68k, .microblaze, .microblazeel, .mips, .mipsel,
        .or1k, .powerpc, .powerpcle, .propeller, .riscv32, .riscv32be, .sh,
        .sheb, .sparc, .spirv32, .thumb, .thumbeb, .wasm32, .x86, .xcore,
        .xtensa, .xtensaeb,
        => "32",

        // A pointer width the generator cannot express. Refused by name, not
        // rounded: `avr`, `msp430` and `x86_16` are 16-bit targets, and every
        // `SIZEOF_*` row is either 32 or 64 or derived from one of them.
        .avr, .msp430, .x86_16,
        => std.debug.panic("libcurl: no --pointer-width for architecture {s}. " ++
            "curl_config_gen.c derives SIZEOF_SIZE_T, SIZEOF_LONG, SIZEOF_OFF_T, " ++
            "SIZEOF_CURL_SOCKET_T and SIZEOF_TIME_T from --pointer-width, which " ++
            "accepts 32 and 64 only, and this architecture's pointers are " ++
            "16-bit. lib/curl_setup.h:630-632 rejects a configuration where long " ++
            "exceeds size_t, so any other width here would be a guess that fails " ++
            "as a compile error rather than as a refusal.", .{
            @tagName(target.result.cpu.arch),
        }),
    };
}

/// Compiles `build_support/curl_headers_probe.c` for the *target* and returns
/// the file of `yes|no` answers the generator reads as `--header-facts`.
///
/// WHY A PROBE AND NOT A FAMILY
/// ---------------------------
/// 35 rows of `lib/curl_config-cmake.h.in` say "Define to 1 if you have the <x>
/// header file". That is a statement about a directory on the target, and no
/// OS tag, architecture, pointer width, byte order or libc name determines it.
/// Deciding those rows from the family mask asserts a fact about the target's
/// headers that nobody checked, and on the glibc Zig ships it was wrong:
/// `<netinet/in6.h>` and `<sys/utime.h>` are both absent, so `HAVE_NETINET_IN6_H
/// 1` turned on the five `#include <netinet/in6.h>` sites at `lib/urldata.h:50-52`,
/// `lib/curl_addrinfo.c:29-31`, `lib/vdns/hostip.c:29-31`, `lib/vdns/dnscache.c:29-31`
/// and `lib/vtls/hostcheck.c:32-34`, and the 196-unit closure failed with 100
/// `file not found` errors. Upstream avoids this with `AC_CHECK_HEADERS`, which
/// runs the target compiler once per header; this is the same shape for one
/// preprocessor run.
///
/// WHICH COMPILER, AND WHY IT IS THE TARGET'S
/// -----------------------------------------
/// `b.graph.zig_exe` is the compiler already running this build script, and it
/// is invoked with `-target <the target's own triple>`, so its answer comes from
/// that target's libc headers - the same `zig build-lib` will use for the 196
/// units below. That is what AGENTS.md section 5 asks for: a per-target
/// generated input. Two consequences are named rather than left to chance:
///
///   * Running it on the build host is not a leak. The host supplies the
///     *compiler*; the triple supplies the *headers being asked about*. This is
///     the same inversion `curl_config_gen.c` uses, and the reason the generator
///     itself must not include the header: it runs on the host and would answer
///     for the host's libc, which is wrong for all five cross targets.
///   * The probe deliberately gets **no** `-I` for this tree's `lib/` or
///     `include/`. A header this package ships must not be able to satisfy a
///     question about the target's C library. Nothing under either directory is
///     named `netinet/`, `net/`, `arpa/`, `sys/`, `linux/` or `proto/`, so the
///     search the probe performs is the target's own either way.
///
/// `-E` rather than a compile, because the question is whether a file is
/// reachable on the include path and `__has_include` answers exactly that, in
/// one invocation instead of 35. `-std=gnu99` is the same dialect the library
/// units get, so the two see the same feature-test environment; the answer did
/// not change with or without `-D_GNU_SOURCE` on any of the six check targets,
/// which is why the probe does not need the macro the generated header carries.
///
/// The probe's output is a `.generated` LazyPath recorded as an input file of
/// the generator's run step (`Run.addPrefixedFileArg`,
/// `lib/std/Build/Step/Run.zig:346-359`), which is what makes the generator wait
/// for it: `addPrefixedFileArg` calls `lp.addStepDependencies`, so the ordering
/// is the graph's rather than a comment's. `getPath` is never called here.
fn addHeaderProbe(b: *std.Build, target: std.Build.ResolvedTarget) std.Build.LazyPath {
    const triple = target.result.zigTriple(b.allocator) catch
        @panic("libcurl: the header probe needs a target triple it can spell");

    const probe = b.addSystemCommand(&.{ b.graph.zig_exe, "cc" });
    probe.setName(b.fmt("probe target headers for {s}", .{triple}));
    probe.addArg("-target");
    probe.addArg(triple);
    for (c_flags) |flag| probe.addArg(flag);
    probe.addArg("-E"); // preprocess only: the probe is asked, never run
    probe.addFileArg(b.path(header_probe_source));
    // `-o -` would print to stdout, which a Run step cannot hand to the next
    // step as a file input; an owned output file is what makes the answers a
    // real artifact with a real cache key.
    probe.addArg("-o");
    return probe.addOutputFileArg("curl_header_facts.txt");
}

/// Builds and runs `build_support/curl_existence_probe.c` as a *collector*, and
/// returns the file of `yes|no` answers the generator reads as
/// `--function-facts` and, from the same file, as `--member-facts`.
///
/// WHY A COLLECTOR AND NOT A STEP PER ROW
/// -------------------------------------
/// 47 rows of `lib/curl_config-cmake.h.in` say "Define to 1 if you have the `x'
/// function" and one says "Define to 1 if struct sockaddr_in6 has the
/// sin6_scope_id member". A function is a *declaration* and a struct member is a
/// *field*, and no `__has_*` operator asks about either, so the answer cannot
/// come from a preprocess run the way the 35 header rows' does: it has to come
/// from the compiler's semantic phase, which means a compile per row. That is
/// upstream's shape too - `AC_CHECK_FUNCS` runs the target compiler once per
/// function, `AC_COMPILE_IFELSE` runs it once per struct member at
/// `configure.ac:1812-1831`, and CMake's `check_function_exists` is one
/// `try_compile` per symbol.
///
/// The question the build graph cannot answer is what to do with the exit
/// status. A compile that fails is a *failed step*, so a build with one step per
/// row would stop at the first name the target lacks - which is the answer, not a
/// failure, and is exactly the answer `HAVE_ACCEPT4` needed on Darwin. There is
/// no std build step for "run this, tolerate a non-zero exit, and record what the
/// exit meant", so the loop lives in the collector: one host program that forks
/// the compiler once per row and turns each exit status into one line. Both
/// classes then cost one build step and one facts file, the same shape
/// `addHeaderProbe` gives the header class. The two kinds of line share that file
/// and are told apart by their `CURL_FUNCTION` and `CURL_MEMBER` markers, which
/// is why `addGeneratedConfig` hands the generator one `LazyPath` under two
/// option names.
///
/// WHICH COMPILER, AND WHY IT IS THE TARGET'S
/// -------------------------------------------
/// The collector is compiled for `b.graph.host` and is *given* the compiler and
/// the triple; it runs `b.graph.zig_exe cc -target <triple>` for each probe, so
/// every answer comes from the target's own headers - the same ones
/// `zig build-lib` will use for the 196 units. The collector itself is host
/// code that happens to be part of this package's configuration, exactly as
/// `curl_config_gen.c` is, and it is given no `-I` for this tree's `lib/` or
/// `include/` either.
///
/// `-DCURL_EXISTENCE_COLLECTOR` is what selects the collector half. The other
/// half of the file is the table, and the collector renders each probe from it
/// as source text, so the probe the target compiler sees is built at run time
/// rather than being a second file this package has to keep in step.
fn addFunctionProbe(b: *std.Build, target: std.Build.ResolvedTarget) std.Build.LazyPath {
    const triple = target.result.zigTriple(b.allocator) catch
        @panic("libcurl: the existence probe needs a target triple it can spell");

    const module = b.createModule(.{
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        // libc, for `fork`/`execv`/`waitpid`/`fopen`/`fprintf`. The collector is
        // the second executable this build compiles for the host and it is
        // small; the target probes it forks are never linked.
        .link_libc = true,
    });
    module.addCSourceFiles(.{
        .files = &.{function_probe_source},
        .flags = &collector_flags,
    });
    // Before `addExecutable`, because the macro has to be in the module's flag
    // set by the time the compile step is created from it. It selects the
    // collector half of the file; without it the file is the table, which has
    // no `main` and would not link.
    module.addCMacro("CURL_EXISTENCE_COLLECTOR", "1");
    const collector = b.addExecutable(.{
        .name = b.fmt("{s}-existence-probe-host", .{lib_name}),
        .root_module = module,
    });

    const run = b.addRunArtifact(collector);
    run.setName(b.fmt("probe target functions and members for {s}", .{triple}));
    // Argument order is the collector's, and it is fixed: the compiler to run,
    // the triple to run it for, one flag string, the target's libc, and where
    // to write the answers.
    run.addArg(b.graph.zig_exe);
    run.addArg(triple);
    // `-std=gnu99` is the same dialect the library units get, so the probe and
    // the closure see the same feature-test environment - which is load-bearing:
    // `memrchr` and `accept4` are absent from glibc's `<string.h>` and
    // `<sys/socket.h>` without `_GNU_SOURCE`.
    run.addArg(probe_flags_arg);
    // The libc, and it is the *same* string the generator gets for `--libc`
    // below. The probe needs it because `_GNU_SOURCE` is not a Linux fact, it
    // is a glibc fact: musl gates `memrchr` behind the same macro, so a probe
    // that assumed "Linux implies `_GNU_SOURCE`" would answer for a libc the
    // generated header is not compiled with. Deriving that condition twice is
    // what broke the six musl Linux cells the first time; `generatorLibc` is now
    // the single place it is decided, and this is the hand-off.
    run.addArg(generatorLibc(target));
    // An owned output file, for the reason `curl_header_facts.txt` is one: the
    // generator takes it as a tracked file input, so it has to be a path the
    // build graph owns rather than a file the collector invented. The collector
    // derives its scratch directory from this file's own directory, so there is
    // no second path to create and no chance of the two disagreeing.
    return run.addOutputFileArg(function_facts_name);
}

/// Builds and runs `curl_config_gen.c` for one target, returning the
/// `curl_config.h` it wrote.
///
/// The generator is compiled for `b.graph.host` - the machine running the build
/// - and is given the *target's* facts as argv. That inversion is the whole
/// design: the program holds no platform knowledge of its own, so running it on
/// the host to configure a cross target is correct rather than a leak. See
/// "Generated input" in the module comment.
///
/// The returned path is `.generated` and is never resolved here. `run`'s
/// `addOutputFileArg` (`lib/std/Build/Step/Run.zig:279-300`) records the run step
/// as the path's owner, so any dependee that adds the path to its include line
/// picks up the dependency on the run automatically, and `LazyPath.getPath` -
/// which panics for an unresolved `.generated` path - is never called from
/// `build()`.
///
/// The generator is given one more input it cannot derive from the arguments: the
/// header-existence answers, as `--header-facts`. Those come from `addHeaderProbe`
/// for the same target, passed as a file argument rather than as argv text because
/// the answer is a build-graph step's output and not a value `build()` could know.
/// Recording it with `addPrefixedFileArg` is what orders the two steps.
fn addGeneratedConfig(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    ca_bundle: ?[]const u8,
    ca_path: ?[]const u8,
) std.Build.LazyPath {
    const generator_module = b.createModule(.{
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        // libc, for `fprintf`/`fopen`/`strcmp`/`exit`. The generator is the only
        // executable this build compiles for the host and it is small.
        .link_libc = true,
    });
    generator_module.addCSourceFiles(.{
        .files = &.{config_generator_source},
        .flags = &generator_flags,
    });
    const generator = b.addExecutable(.{
        .name = b.fmt("{s}-config-gen-host", .{lib_name}),
        .root_module = generator_module,
    });

    // The step name is left alone: `addOutputFileArg` renames the step after the
    // argument it adds (`lib/std/Build/Step/Run.zig:315-317`), and the name it
    // produces - `run curl_config-gen-host (curl_config.h)` - is already the one
    // a reader of `--summary all` wants.
    const run = b.addRunArtifact(generator);

    run.addArg("--os");
    run.addArg(@tagName(target.result.os.tag));
    run.addArg("--arch");
    run.addArg(@tagName(target.result.cpu.arch));
    run.addArg("--pointer-width");
    run.addArg(pointerWidthBits(target));
    // `std.builtin.Endian` is `.little` or `.big` and `@tagName` spells them
    // exactly as `curl_config_gen.c` accepts them
    // (`lib/std/Target.zig:1648`, `Cpu.Arch.endian`).
    run.addArg("--endian");
    run.addArg(@tagName(target.result.cpu.arch.endian()));
    run.addArg("--libc");
    run.addArg(generatorLibc(target));
    run.addArg("--mbedtls-des-crypt-ecb");
    run.addArg(mbedtls_des_crypt_ecb);
    // Required, no default: the 35 header-existence rows are decided from this
    // file and from nothing else. `addPrefixedFileArg` makes the probe's output a
    // tracked input of this run step, so the generator cannot start before the
    // probe has finished (`lib/std/Build/Step/Run.zig:346-359`).
    run.addArg("--header-facts");
    run.addPrefixedFileArg("", addHeaderProbe(b, target));
    // Required, no default, for the same reason: the 47 function-existence rows
    // ask whether the TARGET declares a name, and the one member-existence row
    // asks whether the target's own headers let curl assign a field. No argument
    // above determines either. The same `addPrefixedFileArg` ordering applies, so
    // the generator cannot start before the collector has finished - which
    // matters more here than for the header probe, because the collector's
    // output is the result of 48 compiles rather than one.
    //
    // One `addFunctionProbe` call, one step, one output file, given twice under
    // the two names the generator reads it by. `addFunctionProbe` creates the Run
    // step when it is called, so calling it twice would run the collector twice;
    // one call and one `LazyPath` keeps it to one.
    const existence_facts = addFunctionProbe(b, target);
    run.addArg("--function-facts");
    run.addPrefixedFileArg("", existence_facts);
    run.addArg("--member-facts");
    run.addPrefixedFileArg("", existence_facts);
    run.addArg("--curl-version");
    run.addArg(upstream_version_string);
    // The CA options are optional on the generator's side because an absent
    // option means "do not define the row": `lib/getinfo.c:161-169` and
    // `lib/version.c:561-567` both read `CURL_CA_PATH`/`CURL_CA_BUNDLE` under
    // `#ifdef`, so leaving them out is how a build says "no built-in store"
    // rather than naming a path it does not have.
    if (ca_bundle) |value| {
        run.addArg("--ca-bundle");
        run.addArg(value);
    }
    if (ca_path) |value| {
        run.addArg("--ca-path");
        run.addArg(value);
    }
    run.addArg("--output");
    return run.addOutputFileArg(config_header_name);
}

/// Builds one target's C library and facade.
///
/// `public` chooses between the package module set - what a dependent reaches
/// through `dep.module("libcurl")` - and a private module. A cross-target check
/// needs the private form: `b.addModule` registers by name against the whole
/// build, so registering `libcurl` once per matrix target would leave only the
/// last reachable and silently stop checking the rest.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
    ca_bundle: ?[]const u8,
    ca_path: ?[]const u8,
    public: bool,
) Graph {
    // Every route into this file passes through here: `build` for the published
    // graph and for `-Dtarget=`, and `addTargetCheck` for each matrix cell.
    // `runConsumer` reaches it too, one process later - it shells out to a
    // nested `zig build` in `consumer/` that resolves this package as a
    // dependency, and that nested build runs this `build()`. The refusal is here
    // rather than in `build` so that naming the target by hand and walking the
    // matrix cannot be given two different answers. Nothing has been compiled
    // when this runs: it is a configure-time stop, not a warning hung off a
    // later step.
    if (refusalFor(target.result.os.tag) != null) refuseTarget(b, target);

    const config_header = addGeneratedConfig(b, target, ca_bundle, ca_path);
    // The directory, not the file: `lib/curl_setup.h:140` includes
    // `curl_config.h` by bare name. `LazyPath.dirname` on a `.generated` path
    // walks up one level inside the cache's output directory
    // (`lib/std/Build.zig:2377-2421`), which is where the file will be.
    const config_dir = config_header.dirname();

    // Resolved here and handed down, so the include path and the three link
    // lines on `c_mod` and the archives `module.linkLibrary` pulls in all come
    // from one resolution of one dependency.
    const tls = resolveTls(b, target, optimize);

    const c_lib = add_c_library(b, target, optimize, linkage, config_dir, tls, artifactName(b, target, public));

    // The translation, for the same target and the same configuration. The
    // generated header's directory is on this line too, and it has to be: the
    // translation must see the header the C saw, or it will describe a different
    // ABI than the archive it is paired with.
    const translate = b.addTranslateC(.{
        .root_source_file = b.path(translate_header),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // Three paths, and each one is a different answer to "where did curl's own
    // header come from". `include/curl/system.h` and `include/curl/curl.h` from
    // `include/`; `lib/curl_setup.h` and the `curlx/`, `vauth/`, `vdns/`, `vtls/`
    // and `vquic/` headers by their quoted relative paths from `lib/`; and
    // `curl_config.h` from the generator's cache directory.
    translate.addIncludePath(b.path(public_include_dir));
    translate.addIncludePath(b.path(source_dir));
    translate.addIncludePath(config_dir);
    // The same `USE_MBEDTLS` the C was compiled with. Without it on this line
    // the translation would describe a libcurl with no TLS backend, and every
    // `CURL_VERSION_*` constant derived from it would disagree with the archive.
    // `BUILDING_LIBCURL` is the other half and it is not cosmetic:
    // `include/curl/curl.h:124-138` reads it to decide `__declspec(dllimport)`
    // against `__declspec(dllexport)`, so a translation without it would describe
    // a *consumer's* view of the header rather than the library's own.
    translate.defineCMacro("USE_MBEDTLS", "1");
    translate.defineCMacro("BUILDING_LIBCURL", "1");
    // `CURL_STATICLIB` for a static delivery: `include/curl/curl.h:124` reads it
    // to define `CURL_EXTERN` as nothing at all, which is right for an archive
    // and wrong for a DLL consumer. Only where `__declspec` exists does it
    // change anything - everywhere else `CURL_EXTERN` is already plain `extern` -
    // so on ELF and Darwin this is upstream's own behaviour rather than a
    // portability exception.
    if (deliveredLinkage(target, linkage) == .static) {
        translate.defineCMacro("CURL_STATICLIB", "1");
    }

    const module = if (public)
        b.addModule(lib_name, .{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            // libc in both branches. Under `-Druntime` that is the loader's
            // `dlopen` and nothing else; the mode's cost, stated.
            .link_libc = true,
        });

    // Where the runtime-loading seam is
    // ---------------------------------
    // `runtime/graph.zig`, which the Runtime role owns, exposes
    //
    //     pub fn createModule(
    //         b: *std.Build,
    //         translate: *std.Build.Step.TranslateC,
    //         target: std.Build.ResolvedTarget,
    //         optimize: std.builtin.OptimizeMode,
    //     ) *std.Build.Module
    //
    //     pub fn createCoreModule(
    //         b: *std.Build,
    //         target: std.Build.ResolvedTarget,
    //         optimize: std.builtin.OptimizeMode,
    //     ) *std.Build.Module
    //
    // and `-Druntime` substitutes the first for `translate.createModule()`.
    // It takes the `TranslateC` step this function has already built, so the
    // generated dispatch keeps the exact translated type and constant namespace
    // rather than compiling a second copy of the native declarations: the type
    // behind `curl_easy_init` in the facade and the declaration in the dispatch
    // table are one type.
    //
    // `-Dlinkage` is orthogonal and keeps meaning what it means: it selects
    // which artifact this build *delivers* and installs, never which one the
    // module dispatches through.
    //
    // The `rt` import exists for the linked branch only, and the reason is the
    // nominal type rather than the code: `graph.createModule` creates the one
    // core-module instance the generated dispatch uses and re-exports
    // `LoadSource`/`LoadError` from it; a second instance created here for the
    // facade would be a *different* `LoadSource`, and `load(source)` would be
    // handing the facade's type to a function expecting the dispatch's. One
    // instance per build, no more. `zig/root.zig` picks between the two with a
    // comptime branch on `runtime_loaded`, so a module a configuration does not
    // need is never resolved and never compiled.
    if (runtime_loaded) {
        // A loaded provider must arrive through the platform loader, so the
        // module links no archive and no mbed-TLS archive either. Linking them as
        // well would let the linker resolve the same symbols statically and the
        // runtime route would quietly be a linked one. The artifacts are still
        // built and installed, because delivery and dispatch are separate
        // questions: the whole point of the mode is that a caller may name a
        // provider this tree did not build - and a provider it did, which for
        // this package is `libcurl.so.4` (see the module comment).
        module.addImport(translate_import_name, graph.createModule(b, translate, target, optimize));
    } else {
        // The translated headers are imported, never registered.
        // `addModule("translate")` would make `dep.module("translate")` resolve
        // and hand a dependent the same declarations without the library that
        // satisfies them; `libcurl.c` on the facade is the supported way in.
        module.addImport(translate_import_name, translate.createModule());
        module.addImport(loader_import_name, graph.createCoreModule(b, target, optimize));
        // `Module.linkLibrary` records the library as an `.other_step`
        // (`lib/std/Build/Module.zig:649-659`), `Step.Compile.getCompileDependencies`
        // walks those (`:2083-2108`), and every `system_lib` the walk finds goes
        // onto the dependee's own link line (`:1064-1088`). That is how
        // `tests.zig`, `smoke.zig` and the consumer inherit the archive and the
        // three mbed-TLS archives from the one module that names them, without
        // each of them naming them again.
        module.linkLibrary(c_lib);
    }

    // The same two source include paths the archive's own module has, on the
    // module a dependent actually imports, so a dependent that compiles its own
    // C against this package finds the same headers the core was compiled with.
    //
    // `include/` rather than the install tree's `include/curl/`, because
    // `lib/curl_setup.h:342` includes `<curl/system.h>` - with the directory
    // component - and because `installHeader`'s "added to that module's include
    // search path" note (`lib/std/Build/Step/Compile.zig:555-556`) is about the
    // *emitted* include tree, which is a build-cache artefact rather than a path
    // a published module can name. Adding both would give two roots that hold
    // the same twelve headers.
    module.addIncludePath(b.path(public_include_dir));
    module.addIncludePath(b.path(source_dir));

    return .{ .c_lib = c_lib, .module = module };
}

/// Resolves the mbed-TLS package, or stops.
///
/// Zig 0.16 has no "optional dependency": `findPkgHashOrFatal`
/// (`lib/std/Build.zig:2058`) aborts the configure when the name is not in
/// `.dependencies`. That is the behaviour this package wants, and it is why the
/// "no TLS off" rule needs no code of its own here - but the message that comes
/// out would name the hash rather than the dependency, so this wrapper names
/// `mbed-tls` and says what is wrong before re-panicking.
///
/// The include path is the sibling's installed `include/`, and it is the *only*
/// thing this build needs from it on a compile line: that directory holds the
/// `mbedtls/*.h` and `psa/*.h` the C includes, and the sibling installs its
/// generated configuration as the canonical `mbedtls/mbedtls_config.h`, so a
/// dependent gets the configuration the library was compiled with and needs no
/// `MBEDTLS_CONFIG_FILE`, no `MBEDTLS_USER_CONFIG_FILE` and no PSA define.
/// `#include <psa/crypto_config.h>` at `lib/vtls/mbedtls.c:41` is a no-op without
/// one: that header's whole body sits inside
/// `#if defined(MBEDTLS_PSA_CRYPTO_CONFIG)`.
fn resolveTls(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Dependency {
    return b.dependency(tls_dependency_name, .{
        .target = target,
        .optimize = optimize,
        // `-Dlinkage` and `-Druntime` are the sibling's own options and both
        // default sensibly, so they are not forwarded. Forwarding this build's
        // linkage would make the TLS backend's delivery depend on libcurl's
        // delivery for no stated reason, and a mismatch here is a link error
        // rather than a fallback.
    });
}


/// `add_c_library` receives the already-resolved dependency rather than
/// resolving its own. Two `b.dependency` calls with the same name and the same
/// argument map are cached by `Build.graph.dependency_cache`
/// (`lib/std/Build.zig:131-137`, keyed on the build root string and the user
/// input options), so a second call would be harmless - but one call is one
/// place where the dependency can fail, and the include path and the three link
/// lines then provably come from the same resolution.
///
/// It also takes the generated header's *directory*, not the header: see
/// `addGraph`, which is where the header and that directory are produced.

/// Compiles the 196 units for one target: `CSOURCES` and nothing else.
///
/// `requested` is the linkage the caller asked for. What it selects is the
/// artifact and nothing else about the compilation: the same 196 units are
/// compiled either way, and `lib/Makefile.inc` has no linkage branch to copy.
fn add_c_library(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    requested: std.builtin.LinkMode,
    config_dir: std.Build.LazyPath,
    tls: *std.Build.Dependency,
    name: []const u8,
) *std.Build.Step.Compile {
    const linkage = deliveredLinkage(target, requested);
    const c_lib = b.addLibrary(.{
        .name = name,
        .linkage = linkage,
        // See "ABI identity and the bare loader name". `version` is null for a
        // static archive, which has no soname and no versioned file name.
        .version = if (linkage == .dynamic) abi_version else null,
        // The COFF export list is upstream's own: `lib/libcurl.def` holds 100
        // `curl_*` entries and no `Curl_*`, so it names exactly the public API
        // and every `Curl_`-prefixed internal stays unexported. Globbing
        // `curl_*` instead would be a list nobody reviewed.
        //
        // Using it verbatim is only safe if every entry survives this
        // configuration, because a `.def` naming a symbol the DLL does not
        // define is a link error and not a warning. Checked against the list:
        // there is no `curl_ldap_*` entry in it at all, so `CURL_DISABLE_LDAP`
        // costs nothing here; and the three entries that *are* conditional -
        // `curl_easy_option_by_id`, `curl_easy_option_by_name` and
        // `curl_easy_option_next`, which need `CURL_DISABLE_GETOPTIONS` to be
        // absent - `lib/easygetopt.c:28` is that `#ifndef` and `:53`, `:59` and
        // `:65` are the three definitions - are all live, because this build keeps
        // `curl_easy_options` enabled for the published facade's `optionByName`
        // and `optionById`. The `curl_mime_*`, `curl_ws_*`, `curl_form*`,
        // `curl_share_*`, `curl_slist_*` and `curl_multi_*` families need no
        // optional library and are all live as well.
        .win32_module_definition = if (linkage == .dynamic and target.result.ofmt == .coff)
            b.path("lib/libcurl.def")
        else
            null,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            // libc, because all 196 units reach the C library for their own
            // vocabulary: `<sys/types.h>` and `<sys/socket.h>` from
            // `curl_setup.h`, `<string.h>` and `<stdio.h>` across most of
            // `LIB_CFILES`, `<netdb.h>` for the resolver, `<poll.h>` for the
            // multi interface.
            .link_libc = true,
            // Position-independent for every linkage, not just the shared one.
            // A static archive is not required to be PIC, so this used to leave
            // `pic` unset and the 196 C units non-PIC. That is fine on every
            // other architecture in the published matrix, and wrong on
            // `mips-linux-musleabi`: a non-PIC `jal` into a PIC callee does not
            // put the callee's address in `$t9`, and musl's `sigsetjmp` derives
            // `$gp` from `$t9` before its own PIC call. The one call site that
            // reaches it is upstream's `lib/vdns/hostip.c:890`,
            // `sigsetjmp(curl_jmpenv, 1)`, which is why `setjmp`, `malloc` and
            // `printf` from the same objects are unaffected and only the
            // resolver's SIGALRM path faults. Reproduced outside this tree with
            // three lines and this compiler: the non-PIC build dies on SIGSEGV
            // under `qemu-mips`, the same source with `-fPIC` runs.
            //
            // Measured, both linkages static, because the obvious worry is that
            // this bloats the archive: it does not. On `mips-linux-musleabi`
            // `libcurl.a` goes from 19747232 bytes to 18801176, so position
            // independence makes that archive 946056 bytes *smaller*; on the
            // `x86_64-linux-gnu` host it is 20717210 bytes either way, the same
            // size with different contents, because the inference `null` left
            // to the build system already chose PIC for that target. Do not
            // "fix" this back to the inference without re-running those two
            // sizes: the archive is not what pays for the mips32 cells.
            .pic = true,
        }),
    });
    const c_mod = c_lib.root_module;

    // Three include paths, in the order they matter. `lib/` first, because every
    // internal include in this tree is quoted and relative to it -
    // `lib/curl_setup.h:140` includes `"curl_config.h"`, and
    // `lib/vtls/mbedtls.c:60-69` names ten of its siblings by bare name.
    c_mod.addIncludePath(b.path(source_dir));
    // `include/`, because `lib/curl_setup.h:342` includes `<curl/system.h>` and
    // `lib/cf-h1-proxy.c:29` includes `<curl/curl.h>` by installed path.
    c_mod.addIncludePath(b.path(public_include_dir));
    // The generator's output directory, last and separately, because it is the
    // one that did not exist when this package was written.
    c_mod.addIncludePath(config_dir);

    // The three macros that make this a libcurl with mbed-TLS, on the line that
    // compiles the *definitions*:
    //
    //   `HAVE_CONFIG_H`  makes `lib/curl_setup.h:138-140` include the generated
    //                    `curl_config.h` instead of `lib/config-win32.h` or
    //                    `lib/config-mac.h`. Without it the two hand-written
    //                    configurations are what the C sees, and
    //                    `lib/config-win32.h:29-31` refuses anything that is not
    //                    MSVC 2010-2013, so five of the six check targets would
    //                    stop in a header this package does not even install.
    //   `USE_MBEDTLS`    the backend selector; see the module comment.
    //   `BUILDING_LIBCURL`  `lib/curl_setup.h:27-29` uses it to define
    //                    `CURL_NO_OLDIES`, and `:1488-1500` redirects
    //                    `curlx_strdup`/`curlx_malloc`/`curlx_free` to
    //                    `Curl_c*`. Without it every unit would allocate with
    //                    the public allocator and the internal accounting in
    //                    `lib/curl_memrchr.c` and `lib/rand.c` would not see it.
    //   `CURL_STATICLIB`  only for a static delivery, from
    //                    `include/curl/curl.h:124`. Windows-relevant only, and
    //                    inert everywhere else.
    c_mod.addCMacro("HAVE_CONFIG_H", "1");
    c_mod.addCMacro("USE_MBEDTLS", "1");
    c_mod.addCMacro("BUILDING_LIBCURL", "1");
    if (linkage == .static) c_mod.addCMacro("CURL_STATICLIB", "1");

    // `-lm`: curl's own `lib/curlx/` and `lib/urlapi.c` use `pow`, `sqrt` and
    // friends, and on every Unix this generator accepts the maths functions live
    // in a separate archive. There is no upstream `LIBS` line to copy -
    // `lib/Makefile.inc` is a source list and nothing else - so this is a fact
    // about the platform, and on Darwin and Windows the same names are in libc
    // and the linker resolves them there.
    //
    // `-ldl` is *not* added: nothing in this configuration calls `dlopen` from
    // C. The runtime route's loader is Zig, compiled into the facade's module,
    // and `zig` resolves `dl` itself.
    if (separateLibm(target.result.os.tag)) c_mod.linkSystemLibrary("m", .{});

    // Windows: the three import libraries this configuration's C actually calls
    // into, for the same reason `-lm` is above and with the same shape - a fact
    // about the platform, stated here because there is no upstream `LIBS` line
    // to copy.
    //
    //   ws2_32     the whole Winsock family. `lib/cf-socket.c` calls `socket`,
    //              `select`, `accept`, `connect`, `bind`, `listen`, `send`,
    //              `recv`, `sendto`, `recvfrom`, `ioctlsocket`, `getaddrinfo`,
    //              `freeaddrinfo`, `gethostname`, `getpeername`, `getsockname`,
    //              `setsockopt`, `inet_pton` and the `WSA*` event and error
    //              calls; mbed-TLS calls `inet_pton` too
    //              (`src/library/x509_crt.c:2875-2880`).
    //   iphlpapi   `if_nametoindex`, from `lib/peer.c:162`.
    //   bcrypt     `BCryptGenRandom`, from `lib/curlx/winapi.c:118` and from
    //              mbed-TLS's `src/library/entropy_poll.c:60`.
    //
    // Without them the link failed with 38 `lld-link: undefined symbol` errors on
    // `aarch64-windows`, and the first six were the odd-looking
    // `__declspec(dllimport) WSACreateEvent`. That spelling is the whole
    // diagnosis rather than a separate problem: mingw-w64's `winsock2.h:36`
    // declares the family `WINSOCK_API_LINKAGE`, which is `DECLSPEC_IMPORT`, so
    // every reference to it becomes a `__declspec(dllimport)` reference, and
    // `lld-link` can only satisfy one when the matching import library is on the
    // link line. Adding the three libraries removes all 38.
    //
    // They go on `c_mod`, the same module the three mbed-TLS archives go on, so a
    // dependee inherits them through the `other_step` walk described in the
    // module comment rather than each naming them again.
    if (target.result.os.tag == .windows) {
        c_mod.linkSystemLibrary("ws2_32", .{});
        c_mod.linkSystemLibrary("iphlpapi", .{});
        c_mod.linkSystemLibrary("bcrypt", .{});
    }

    // The mbed-TLS public headers.
    //
    // `Dependency.path` resolves against the dependency's *source* root, so the
    // directory is `src/include` and not `include`: a package root does not hold
    // its own installed `include/`, and `lib/*.c` reaches `mbedtls/version.h` by
    // that spelling in four units (`lib/vtls/mbedtls.c:37`, `lib/sha256.c:33`,
    // `lib/md5.c:41`, `lib/curl_ntlm_core.c:77`).
    //
    // Those headers include `mbedtls/build_info.h`, which uses upstream's own
    // `mbedtls/mbedtls_config.h` when `MBEDTLS_CONFIG_FILE` is not defined, and
    // this build compiles against that default. It is deliberate: the
    // configuration the sibling generated exists only inside the sibling's build
    // cache, is named there through `-DMBEDTLS_CONFIG_FILE`, and is installed
    // under the canonical name only into the sibling's own install prefix, which
    // is a build output this build has no `LazyPath` for. Reaching into a
    // sibling's cache layout would be a worse dependency than compiling against
    // upstream's shipped default, and `MBEDTLS_CONFIG_FILE` is a compile flag
    // this package does not own.
    c_mod.addIncludePath(tls.path(tls_public_include));
    // Link order is the driver's: `mbedtls`, `mbedx509`, `mbedcrypto`. A static
    // archive that references symbols in the next one has to be listed first, so
    // this order is a requirement and not a preference. Three
    // `linkSystemLibrary`-style calls, in order, on the one module that holds
    // the references; dependees inherit them through the `other_step` walk the
    // module comment above describes.
    for (tls_artifacts) |artifact| {
        c_mod.linkLibrary(tls.artifact(artifact));
    }

    for (curl_sources[0..]) |source| {
        c_mod.addCSourceFile(.{
            .file = b.path(source),
            .flags = &c_flags,
        });
    }

    if (linkage == .dynamic) setVersionScript(b, c_lib, target);

    // The twelve headers of `include/curl/Makefile.am:24-26`, under
    // `include/curl/` as `pkgincludedir` there names. Installing them also puts
    // them on the include path of anything that links this artifact
    // (`lib/std/Build/Step/Compile.zig:555-556`), so a C consumer needs nothing
    // from this tree to call it.
    for (public_headers) |header| {
        c_lib.installHeader(
            b.path(b.fmt("{s}/curl/{s}", .{ public_include_dir, header })),
            b.fmt("curl/{s}", .{header}),
        );
    }

    return c_lib;
}

/// Gives an ELF shared object upstream's own export surface.
///
/// The script is `lib/libcurl.vers.in`, four lines of content: a node named
/// `CURL_<PREFIX><SONAME>` holding `global: curl_*; local: *;`. Both variables
/// come from files this package vendors - `lib/CMakeLists.txt:289-290` picks
/// `MBEDTLS_` under `CURL_USE_MBEDTLS`, and `lib/CMakeLists.txt:303` supplies
/// the soname this file computes as 4 - so the script is a substitution of two
/// upstream values and not a list this build invented.
///
/// Mach-O has no version script that GNU ld or lld reads the same way, so this
/// does nothing for Darwin, and that is reported by `build` rather than left to
/// be discovered with `nm -D`: a `libcurl.4.dylib` from this build exports
/// curl's internals as well as its API.
fn setVersionScript(
    b: *std.Build,
    c_lib: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
) void {
    if (target.result.ofmt != .elf) return;
    const script = b.addWriteFiles().add("libcurl.map", b.fmt(
        \\# Generated by build.zig from upstream's own lib/libcurl.vers.in.
        \\# Node name: lib/CMakeLists.txt:289-290 chooses the prefix
        \\# CURL_LIBCURL_VERSIONED_SYMBOLS_PREFIX = "{s}" for CURL_USE_MBEDTLS,
        \\# and lib/CMakeLists.txt:303 supplies CURL_LIBCURL_VERSIONED_SYMBOLS_SONAME,
        \\# which lib/CMakeLists.txt:271 computes from lib/Makefile.soname:26-28 as
        \\# VERSIONCHANGE - VERSIONDEL.
        \\CURL_{s}{d}
        \\{{
        \\  global: curl_*;
        \\  local: *;
        \\}};
        \\
    , .{ version_script_prefix, version_script_prefix, abi_version.major }));
    c_lib.setVersionScript(script);
}

/// The name one library artifact carries in this build graph.
///
/// The published graph installs `libcurl.a`, or `libcurl.so.4.8.0` with
/// `libcurl.so.4` beside it, which are the names upstream's own Makefiles give
/// its results. A check graph installs nothing, so its artifact carries the
/// target triple instead: five targets share one build graph and five steps all
/// called `libcurl` make `--summary all` useless for telling them apart.
fn artifactName(b: *std.Build, target: std.Build.ResolvedTarget, public: bool) []const u8 {
    if (public) return lib_name;
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    return b.fmt("{s}-{s}", .{ lib_name, triple });
}

/// Installs `lib/pkgconfig/libcurl.pc`.
///
/// curl's release tarball ships `libcurl.pc.in` and this package deliberately
/// does not vendor it - the vendored closure is `lib/`, `include/` and three
/// root files, so there is no `.in` to read. Every field below is therefore this
/// fork's and each is written against what this build actually installs:
/// `prefix` is `${pcfiledir}`-relative so the installed file is correct wherever
/// `--prefix` put it, `libdir`/`includedir` match the two directories
/// `add_c_library` installs into, and the mbed-TLS archives go in
/// `Libs.private` - a static `libcurl.a` consumer has to link them, and a shared
/// one has to have them at run time, so neither can be left out. They are
/// `-L"$prefix/lib"` rather than bare names because that is where the sibling
/// installs them.
fn addPkgConfig(
    b: *std.Build,
    linkage: std.builtin.LinkMode,
    separate_m: bool,
) void {
    const files = b.addWriteFiles();
    // The returned step is bound to the install step. `addInstallFileWithDir`
    // *creates* a `Step.InstallFile` and nothing else - dropping the return value
    // builds nothing and installs nothing, and the omission is silent: the step
    // exists, it is simply never in the graph, so an install missing its `.pc`
    // would still report success.
    const install_pc = b.addInstallFileWithDir(
        files.add("libcurl.pc", b.fmt(
            \\# libcurl.pc for the libcurl {s} SDK.
            \\#
            \\# Generated by this package's build.zig, addPkgConfig. Upstream ships
            \\# libcurl.pc.in, which this package does not vendor - the closure is
            \\# lib/, include/, COPYING, README and RELEASE-NOTES - so every field
            \\# here is this fork's and names what this build installs.
            \\prefix=${{pcfiledir}}/../..
            \\exec_prefix=${{prefix}}
            \\libdir=${{prefix}}/lib
            \\includedir=${{prefix}}/include
            \\
            \\Name: libcurl
            \\Description: libcurl {s}, with mbed-TLS as its only TLS backend
            \\Version: {s}
            \\
            \\Requires:
            \\Libs: -L"${{libdir}}" -lcurl
            \\Libs.private: -L"${{libdir}}" -lmbedtls -lmbedx509 -lmbedcrypto{s}
            \\Cflags: -I"${{includedir}}"{s}
            \\
        , .{
            // `upstream_version_string` rather than a formatted
            // `std.SemanticVersion`. The header's `LIBCURL_VERSION` at
            // `include/curl/curlver.h:35` is a *string*, and `Version:` in a
            // `.pc` file is compared as one against the same field in a
            // consumer's own records - so the string is what has to travel, and
            // `build` has already refused to configure unless the manifest
            // version and this string are the same release.
            upstream_version_string,
            upstream_version_string,
            upstream_version_string,
            // `-lm`, only where the maths functions are a separate archive. See
            // `add_c_library`.
            if (separate_m) " -lm" else "",
            // `CURL_STATICLIB` only for a static delivery, from
            // `include/curl/curl.h:124`. On a shared install it must not be here:
            // a consumer of the DLL needs `__declspec(dllimport)`, which
            // `include/curl/curl.h:124-138` only produces when `CURL_STATICLIB` is
            // absent and `_WIN32` is set.
            if (linkage == .static) " -DCURL_STATICLIB" else "",
        })),
        .prefix,
        "lib/pkgconfig/libcurl.pc",
    );
    b.getInstallStep().dependOn(&install_pc.step);
}

/// Installs the carried licence texts and provenance records under
/// `share/licenses/libcurl/`.
///
/// A private repository removes no upstream obligation. curl's grant is a
/// standalone file, so what installs is that file: `COPYING`, verbatim, which is
/// the whole of it. `README` and `RELEASE-NOTES` are upstream's own words about
/// the release and are installed because `README` is the release note a reader
/// of the tarball expects to find and `RELEASE-NOTES` is what it points at -
/// upstream does that pointing, so splitting them would break the reference.
/// The rest are this fork's records.
fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |record| {
        const install_record = b.addInstallFileWithDir(
            b.path(record),
            .prefix,
            b.fmt("share/licenses/{s}/{s}", .{ lib_name, std.fs.path.basename(record) }),
        );
        b.getInstallStep().dependOn(&install_record.step);
    }
}

/// Whether this target keeps the C maths functions in a separate archive.
///
/// Every Unix this build configures splits them out; Darwin and Windows keep
/// them in libc. `lib/curlx/` and `lib/urlapi.c` use them unconditionally, so
/// this is a link line and not a configure choice.
fn separateLibm(os_tag: std.Target.Os.Tag) bool {
    return switch (os_tag) {
        .linux, .freebsd, .netbsd, .openbsd, .dragonfly, .illumos => true,
        else => false,
    };
}

/// Whether this target's OS has a dynamic linker at all, and therefore whether
/// it can carry a shared object.
///
/// Windows uses its PE/COFF loader without an interpreter path. Other shared
/// targets need a dynamic linker. WASI has neither - and that is why
/// `checkMatrixPartition`'s refused row would be refused for a second, weaker
/// reason if the mbed-TLS one were ever fixed.
fn targetHasDynamicLinker(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows or
        std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// The linkage this build delivers, or a refusal when the target cannot carry
/// what was asked for.
///
/// There is no substitution here, deliberately. Handing back an archive under the
/// name of a requested shared object would be a result the caller did not ask
/// for and cannot tell from support. So a shared request on a target whose OS
/// has no dynamic linker stops here, with a message that names the target, the
/// reason and the way out.
///
/// `add_c_library`, `addGraph`, `addPkgConfig` and `build` all resolve through
/// this one function, so the artifact, the translation it is paired with and the
/// installed `libcurl.pc` cannot describe different linkages.
fn deliveredLinkage(
    target: std.Build.ResolvedTarget,
    requested: std.builtin.LinkMode,
) std.builtin.LinkMode {
    if (requested == .dynamic and !targetHasDynamicLinker(target)) {
        // `std.debug.panic` with a format string, not `@panic` on a concatenated
        // string: `@tagName` of a run-time tag is not comptime known, and `++` on
        // a slice being concatenated has to be. `std.debug.panic` takes the same
        // format and arguments as every other print in this file
        // (`lib/std/debug.zig`).
        std.debug.panic(
            "libcurl: -Dlinkage=dynamic was asked for {s}, which has no dynamic " ++
                "linker: std.Target.DynamicLinker.kind is .none for it, so it cannot " ++
                "carry a shared object at all. This build does not substitute a static " ++
                "archive for a requested shared object. Build that target with the " ++
                "default -Dlinkage=static, which is also what cross-test.profile.sh " ++
                "pins for the published 53-platform matrix.",
            .{@tagName(target.result.os.tag)},
        );
    }
    return requested;
}

/// Why a target has no buildable libcurl here, or null when it has one.
///
/// A summary line and a long form, and nothing else: no warning, no fallback, no
/// substituted function. The reasoning behind the one entry is written out in
/// full under "wasm32-wasi and the mbed-TLS backend" in the module comment, and
/// `build_support/curl_config_gen.c` refuses `--os wasi` with the same words so
/// the refusal cannot be bypassed by calling the generator directly.
const Refusal = struct {
    /// One line, printed with the target triple in front of it.
    summary: []const u8,
    /// The long form printed before the build fails.
    detail: []const u8,
};

fn refusalFor(os_tag: std.Target.Os.Tag) ?Refusal {
    if (os_tag == .wasi) {
        return .{
            .summary = "libcurl has no buildable configuration for wasm32-wasi with this TLS backend: mbed-TLS compiles its mbedtls_net_* family out on WASI and lib/vtls/mbedtls.c calls mbedtls_net_connect and mbedtls_net_accept.",
            .detail =
            \\The reason is inside the TLS backend, not in curl and not in this
            \\toolchain's C library.
            \\
            \\MBEDTLS_NET_C is compiled in for every unix-like and Windows target
            \\and compiled out for wasm32-wasi. The mbed-TLS sources stop the
            \\build unless MBEDTLS_PLATFORM_IS_UNIXLIKE or _WIN32 is defined, and
            \\that macro is built from unix / __unix / __unix__ /
            \\(__APPLE__ && __MACH__) / __HAIKU__ / __midipix__ / _WIN32 - none of
            \\which WASI's clang defines. So mbedtls_net_connect and
            \\mbedtls_net_accept exist on Linux, macOS and Windows and do not
            \\exist on WASI.
            \\
            \\lib/vtls/mbedtls.c needs both. It uses mbedtls_net_connect to reach
            \\the peer during the handshake and mbedtls_net_accept for the
            \\listening side, and there is no third spelling in that unit to fall
            \\back to.
            \\
            \\Nothing on this side's compile line changes that. It is a
            \\compile-time #error inside the dependency, not a macro, so there is
            \\no configuration this package can write that gets a mbed-TLS-backed
            \\libcurl onto WASI.
            \\
            \\What WASI could otherwise have had, so that the cost of the refusal
            \\is on the record rather than guessed: lib/curl_setup.h:200-203 would
            \\read NEED_REENTRANT, lib/curlx/nonblock.c:52-70 would take its
            \\HAVE_FCNTL_O_NONBLOCK arm and lib/socketpair.c:52-64 its HAVE_PIPE
            \\arm, and lib/curl_setup.h:470-473 would leave USE_EVENTFD undefined
            \\so eventfd is not reached. build_support/curl_config_gen.c carries
            \\that family and refuses --os wasi with these words. Separately, WASI
            \\has no dynamic linker, so deliveredLinkage refuses
            \\-Dlinkage=dynamic there, and the runtime route's Unix backend calls
            \\dlopen, which WASI does not have. Neither is why this row is refused.
            \\
            \\The target is refused rather than patched past: no source is edited,
            \\no TLS backend is swapped for one that is not in the dependency
            \\surface, and no unit is dropped from the 196. Build for a target
            \\this package names a configuration for: x86_64-linux-gnu,
            \\aarch64-linux-gnu, riscv64-linux-gnu, aarch64-macos-none,
            \\x86_64-windows-gnu.
            \\
            \\This is a statement about this pinned lib/vtls/mbedtls.c against this
            \\mbed-TLS build for this toolchain's WASI target, not a claim that
            \\WASI cannot host curl. The cell comes back when the mbed-TLS package
            \\compiles MBEDTLS_NET_C for WASI, or when lib/vtls/mbedtls.c stops
            \\needing mbedtls_net_*. Either is the dependency's or upstream's to
            \\make, and this package makes neither.
            ,
        };
    }

    return null;
}

/// Prints why `target` cannot be built, and fails the build.
///
/// A real refusal, not a warning and not a stub: `zig build`, `zig build check`
/// and `zig build check -Dtarget=<this target>` all stop here, before a compiler
/// is invoked, and `zig build consumer -Dtarget=<this target>` stops in the
/// nested build it launches - which is this package's own `build()` again.
/// `addGraph` is the only caller.
fn refuseTarget(b: *std.Build, target: std.Build.ResolvedTarget) noreturn {
    const refusal = refusalFor(target.result.os.tag) orelse
        @panic("build.zig internal error: refusalFor returned null for a target addGraph refused");
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    std.log.err("libcurl: {s}: {s}\n{s}", .{ triple, refusal.summary, refusal.detail });
    @panic("libcurl: refusing a target this package has no buildable configuration for");
}

/// Keeps the two halves of the matrix honest against each other.
///
/// The point of naming `refused_check_targets` is that the row is not quietly
/// absent, and the point of naming `check_targets` is that every row in it is
/// real. Both are re-derived here through the same `refusalFor` that
/// `refuseTarget` stops with, so a change that makes a refused target buildable
/// fails any build of this package rather than quietly shrinking what `check`
/// proves.
fn checkMatrixPartition(b: *std.Build) void {
    for (check_targets) |query| {
        const resolved = b.resolveTargetQuery(query);
        if (refusalFor(resolved.result.os.tag) != null) {
            @panic(b.fmt(
                "build.zig: {s} is in check_targets but this build refuses its operating system",
                .{resolved.result.zigTriple(b.allocator) catch @panic("unspellable check target")},
            ));
        }
    }
    for (refused_check_targets) |query| {
        const resolved = b.resolveTargetQuery(query);
        if (refusalFor(resolved.result.os.tag) == null) {
            @panic(b.fmt(
                "build.zig: {s} is in refused_check_targets but refusalFor no longer refuses it; move it to check_targets and prove it builds",
                .{resolved.result.zigTriple(b.allocator) catch @panic("unspellable check target")},
            ));
        }
    }
}

/// Compiles the library, the facade, the tests and the example for one matrix
/// target and attaches all of them to `step`.
///
/// Building the test binary and the example is what makes this a check of the
/// facade rather than of an unreferenced archive: Zig analyses a function body
/// only when something calls it, and `tests.zig` and `smoke.zig` call the
/// facade. The full 196-unit closure is compiled by the same graph, so a target
/// that cannot build libcurl fails here rather than at the first install.
/// Nothing is run here, so every result this step produces is compile evidence
/// and not a claim that a cross-built binary executed.
fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
    ca_bundle: ?[]const u8,
    ca_path: ?[]const u8,
) void {
    const cross_target = b.resolveTargetQuery(query);
    // The triple names the cross artifacts. Five targets in one build graph
    // otherwise produce five steps called `libcurl`, which makes
    // `--summary all` useless for telling them apart.
    const triple = cross_target.result.zigTriple(b.allocator) catch @panic("unspellable target");

    const cross = addGraph(b, cross_target, optimize, linkage, runtime_loaded, ca_bundle, ca_path, false);

    const test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addTest(.{
        .name = b.fmt("{s}-tests-{s}", .{ lib_name, triple }),
        .root_module = test_mod,
    }).step);

    const example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addExecutable(.{
        .name = b.fmt("{s}-smoke-{s}", .{ lib_name, triple }),
        .root_module = example_mod,
    }).step);

    // The archive itself is depended on explicitly rather than only through the
    // modules above. It is already in the graph through `module.linkLibrary`, and
    // naming it here would add nothing but would make the dependency visible in
    // `--summary all` as its own step.
    step.dependOn(&cross.c_lib.step);
}

/// Runs the consumer package as its own `zig build` in `consumer/`.
///
/// The consumer is a separate package on purpose: a manifest dependency here
/// would close a cycle, because its manifest points back at this package by
/// path. Running it as a separate build is what makes the proof real - that a
/// package which only writes `b.dependency("libcurl", ...)` and
/// `dep.module("libcurl")` gets a working, correctly linked library, with the
/// archive and the three mbed-TLS archives arriving through the module and
/// nothing else.
///
/// Everything this build resolved travels with it: the target and CPU, the
/// optimize mode, the delivery and dispatch shapes, both CA options, the
/// executor switches, both cache directories, the install prefix, the job width
/// and the summary. An argument left behind would be a proof of a configuration
/// nobody asked for.
///
/// Run when this host can execute the selected target, and install otherwise:
/// `hostCanExecute` asks exactly what `std.Build.Step.Run` asks of a foreign
/// binary, so the decision here and the nested run cannot disagree. An executor
/// counts only when its `-f` switch was given; a target with none installs,
/// which is compile evidence and never a semantic pass.
fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
    ca_bundle: ?[]const u8,
    ca_path: ?[]const u8,
) *std.Build.Step.Run {
    const triple = target.query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    // The same query's other half. The triple above names the architecture, the
    // OS and the ABI; it carries no CPU model and no feature set
    // (`lib/std/Target/Query.zig`, `zigTriple`), and `cpu` is a separate option
    // of its own (`lib/std/Build.zig`, `standardTargetOptions`).
    // `serializeCpu` writes `native` for a query that named no CPU and
    // `baseline` for a cross query that named none, and `Target.Query.parseCpu`
    // recognises both spellings, so the nested `standardTargetOptions` resolves
    // this build's selection rather than one of its own.
    const cpu = target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    // `b.graph.zig_exe` is the compiler running this build script, so the nested
    // build is the same toolchain rather than whatever is on PATH.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path("consumer"));
    run.addArg(if (hostCanExecute(target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    // The model and its feature set, for the reason the serialization above
    // gives. Without it the nested build would compile the consumer at a
    // baseline CPU on a host that built the library for something else, and the
    // step would prove a configuration nobody asked for.
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    // The delivery and dispatch options have to reach the nested build or the
    // consumer would silently check the default graph and say nothing about the
    // configuration that was asked for. Both spellings of `-Druntime` go, not
    // only the true one, so a cell's configuration is stated rather than inferred
    // from a default and the flag cannot be dropped on the way down.
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(linkage)}));
    run.addArg(b.fmt("-Druntime={s}", .{if (runtime_loaded) "true" else "false"}));
    // The two CA options are the only ones whose *values* are facts about the
    // library rather than about the consumer, and a consumer that installs and
    // links against the same tree needs the same `CURL_CA_BUNDLE` in its own
    // headers if it ever prints `CURLINFO_SSL_VERIFYPEER` material. Both go, only
    // when set, because the option is a `?[]const u8` and `-Dca-bundle` with no
    // value is a different thing from no option at all.
    if (ca_bundle) |value| run.addArg(b.fmt("-Dca-bundle={s}", .{value}));
    if (ca_path) |value| run.addArg(b.fmt("-Dca-path={s}", .{value}));
    // `-Dtls` is not forwarded because this build refuses it; see the module
    // comment. Forwarding a refused option would make the nested build stop on
    // an option the caller never asked for.
    //
    // Both cache directories travel, so the nested build neither re-downloads a
    // toolchain nor keeps a second cache beside the package - and so a
    // `--cache-dir` the gate passed this build is the one the consumer uses.
    // `Cache.Directory.path` is `?[]const u8`: it is null when the directory is
    // the process working directory, which is not expressible as an absolute
    // path. In that case the flag is dropped rather than guessed at, and the
    // nested build takes its own default - which is a statement the caller can
    // see in its output, not a silent one.
    if (b.cache_root.path) |path| {
        run.addArg("--cache-dir");
        run.addArg(path);
    }
    if (b.graph.global_cache_root.path) |path| {
        run.addArg("--global-cache-dir");
        run.addArg(path);
    }
    // `-j`, because a nested build that defaults to its own job width would
    // either oversubscribe the machine or underuse it. `max_jobs` is the
    // resolved width and it is `?u32`, so a build that was not told a width
    // forwards nothing and lets the nested build decide, which is the only
    // answer available and is not a guess.
    if (b.graph.max_jobs) |jobs| {
        run.addArg("-j");
        run.addArg(b.fmt("{d}", .{jobs}));
    }
    run.addArg("--summary");
    run.addArg("all");
    // `--prefix` is deliberately *not* forwarded. The nested build installs
    // into its own cache-managed output directory because its step is
    // `install`, not because it was told where to put things; a `--prefix` here
    // would make the consumer write into this build's install tree, which is
    // not what any caller of `zig build consumer` asked for.
    // `b.args` is what the caller passed after `--`, forwarded so
    // `zig build consumer -- <args>` reaches the consumer's program.
    if (b.args) |args| run.addArgs(args);

    return run;
}

/// Whether this host can execute a binary built for `target`.
///
/// Native only, and the reason is Zig 0.16's own: `Step.Run.make` reaches
/// `failForeign` for any non-native artifact, and `failForeign`
/// (`lib/std/Build/Step/Run.zig:2754-2778`) ends in
/// `run.step.fail("unable to spawn foreign binary ...")` for every `stdio`
/// mode - the `else` arm, reached because a nested `zig build` is a plain
/// system command, not `.check` or `.zig_test`. There is no
/// `Build.graph.enabled_executors` in this version and nothing in
/// `lib/compiler/build_runner.zig` sets `skip_foreign_checks`, so a foreign
/// consumer cannot be run from here at all.
///
/// So the nested build is asked for `run` when this host can execute the
/// target's binaries and for `install` when it cannot, and an install is compile
/// evidence and never a semantic pass. Stating that is the whole point: a
/// cross-built consumer that compiled is not a consumer that ran.
fn hostCanExecute(target: std.Build.ResolvedTarget) bool {
    return target.query.isNative();
}

/// Where the runtime-loading seam lives. `runtime/graph.zig` is owned by the
/// Runtime role; the module comment above this function's caller names the exact
/// two entry points and what each one is given.
const graph = @import("runtime/graph.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage: std.builtin.LinkMode = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Deliver the C library as a static archive (the default, and what " ++
            "cross-test.profile.sh pins for the published matrix) or as a real " ++
            "shared object with upstream's libtool-derived ABI identity, " ++
            "libcurl.so.4.8.0 with soname libcurl.so.4. The ABI number is " ++
            "lib/Makefile.soname:26-28 read through lib/CMakeLists.txt:271 - " ++
            "current minus age, 12 minus 8 - and it is not the release version. " ++
            "This selects the delivery and never the source list: all 196 units " ++
            "are compiled either way.",
    ) orelse .static;

    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve the native entry points at run time instead of linking them. " ++
            "The facade keeps the same translated headers and the same public " ++
            "types; each selected native function becomes a dispatch through one " ++
            "process-lifetime table that an explicit load(source) fills, and the " ++
            "module links no archive and no mbed-TLS archive. Independent of " ++
            "-Dlinkage, which still decides which artifact this build delivers " ++
            "and installs. Default off, and a linked build is unchanged in every " ++
            "respect.",
    ) orelse false;

    // `-Dtls` cannot be honoured today, and saying so is the point. See "What
    // -Dtls does, and why it refuses" in the module comment for the whole
    // argument; the short form is that Zig 0.16 resolves a package's root from
    // `build.zig.zon` and has no per-call override
    // (`lib/std/Build.zig:2055-2071`), and the mbed-TLS package declares no
    // option that relocates its own root. Forwarding it would reach a map that
    // ignores it, and a silently ignored TLS-backend override is the one place
    // a no-op is unacceptable.
    const tls_override = b.option(
        std.Build.LazyPath,
        "tls",
        "Override the mbed-TLS package location. REFUSED while the mbed-TLS " ++
            "package declares no package-root option: Zig 0.16's " ++
            "Build.dependency resolves a package root from build.zig.zon and " ++
            "forwards only the dependency's own -D options to it, and mbed-tls " ++
            "accepts none that moves its root. To relocate it, change the .path " ++
            "of the mbed-tls entry in this package's build.zig.zon, or add a " ++
            "package-root option to mbed-tls/build.zig. There is no -Dno-tls and " ++
            "no way to build a libcurl without a TLS backend.",
    );
    if (tls_override) |_| {
        std.debug.panic(
            "libcurl: -Dtls was given a path, and this build cannot honour it. " ++
                "The TLS backend is reached only through the standard dependency " ++
                "mechanism: build.zig.zon carries exactly one .dependencies entry, " ++
                ".@\"mbed-tls\" = .{{ .path = \"../mbed-tls\" }}, and build.zig " ++
                "resolves it with b.dependency(\"mbed-tls\", .{{ .target, .optimize }}). " ++
                "Zig 0.16.0 resolves a package's root from that entry and offers " ++
                "no per-call override - lib/std/Build.zig:2055-2071 - so the only " ++
                "arguments this build can pass are the dependency's own options, " ++
                "and the mbed-tls package declares none that relocates its root " ++
                "(it resolves every path through b.path relative to itself). " ++
                "Forwarding the flag would therefore reach a map that ignores it, " ++
                "and a silently ignored TLS-backend override is worse than no " ++
                "override at all: it would leave a caller believing the backend " ++
                "came from somewhere it did not. Two changes make it real, and " ++
                "neither is made here: change the .path of the mbed-tls entry in " ++
                "libcurl/build.zig.zon, or add a package-root option to " ++
                "mbed-tls/build.zig and name it here. There is no option on this " ++
                "package that disables TLS, and this build will not silently " ++
                "produce a libcurl without a backend.",
            .{},
        );
    }

    // The CA options, compiled into the generated header rather than passed at
    // run time, because that is what upstream's own configuration does with them:
    // `lib/getinfo.c:161-169` and `lib/version.c:561-567` read `CURL_CA_PATH`
    // and `CURL_CA_BUNDLE` from `curl_config.h` as the values
    // CURLINFO_CAINFO and CURLINFO_CAPATH report before an application has set
    // anything. A path relative to the build machine would be wrong to compile
    // in, so the value is exactly what the caller typed and nothing is
    // normalised, resolved or made absolute: it lands in the header verbatim and
    // a consumer that installed this tree elsewhere can see what it was.
    const ca_bundle = b.option(
        []const u8,
        "ca-bundle",
        "PEM file path compiled into CURL_CA_BUNDLE, the default CA bundle " ++
            "libcurl reports through CURLINFO_CAINFO. Passed verbatim to " ++
            "build_support/curl_config_gen.c; unset leaves the row undefined, " ++
            "which is how a build says 'no built-in store'.",
    );
    const ca_path = b.option(
        []const u8,
        "ca-path",
        "PEM directory path compiled into CURL_CA_PATH, the default CA path " ++
            "libcurl reports through CURLINFO_CAPATH. Passed verbatim to " ++
            "build_support/curl_config_gen.c.",
    );

    // `build.zig.zon .version` and the version read out of the header are one
    // fact. `std.SemanticVersion.parse` fails loudly rather than wrapping a
    // non-version, and the comparison catches a manifest edited without the
    // source it describes. `include/curl/curlver.h:35` is where the string is
    // from; `upstream_version` states it.
    if (manifest_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches LIBCURL_VERSION, read " ++
            "out of include/curl/curlver.h:35; see UPSTREAM.md");
    }

    // Two lists, one decision function, checked before any graph is configured: a
    // row cannot be quietly wrong in either direction, and a caller finds out
    // from `zig build` rather than from a gate.
    checkMatrixPartition(b);

    const published = addGraph(
        b,
        target,
        optimize,
        linkage,
        runtime_loaded,
        ca_bundle,
        ca_path,
        true,
    );

    const delivered = deliveredLinkage(target, linkage);

    // The artifact, its twelve headers, the pkg-config file and the licence
    // records. `installArtifact` also puts the headers on the include path of
    // whatever links this artifact, which is what makes an installed
    // `libcurl.a` usable with nothing but `-lcurl` and `-I`.
    b.installArtifact(published.c_lib);
    addPkgConfig(b, delivered, separateLibm(target.result.os.tag));
    installLicenceRecords(b);

    // `zig build` also compiles the example. The example is the cheapest thing
    // that proves the facade, the translated headers and the C archive agree on
    // types, symbols and link-time dependencies. It is compiled, not installed:
    // it is a proof, not a deliverable.
    const example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport(lib_name, published.module);
    const example = b.addExecutable(.{
        .name = b.fmt("{s}-smoke", .{lib_name}),
        .root_module = example_mod,
    });
    b.getInstallStep().dependOn(&example.step);

    // A run artifact already depends on building the executable, which depends
    // on compiling the C and linking the facade. `zig build smoke` deliberately
    // does not depend on the install step: installing is `zig build`'s job and
    // conflating the two would make a smoke run depend on the install layout.
    const run_example = b.addRunArtifact(example);
    run_example.has_side_effects = true;
    if (b.args) |args| run_example.addArgs(args);
    b.step("smoke", "Run the deterministic example program").dependOn(&run_example.step);

    // The test root is `tests.zig`, which names the test blocks; a root that only
    // re-exported them would discover no tests and still exit zero.
    // `addRunArtifact` is used rather than a plain compile so that this is a real
    // runnable test step for whatever `-Dtarget` names: a foreign target is left
    // to whichever executor the cross-test harness detects, and this build does
    // not decide that.
    const test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, published.module);
    const unit_tests = b.addTest(.{
        .name = b.fmt("{s}-tests", .{lib_name}),
        .root_module = test_mod,
    });
    const run_tests = b.addRunArtifact(unit_tests);
    run_tests.has_side_effects = true;
    b.step("test", "Run the behavioural tests").dependOn(&run_tests.step);

    // The separate consumer package, built as its own `zig build`. It runs when
    // this host can execute the selected target and installs when it cannot,
    // which is `hostCanExecute` rather than a query predicate: a cross-compiled
    // consumer binary cannot run here, and a native one can run under an enabled
    // executor. An install is compile evidence and nothing more.
    b.step("consumer", "Build or run the consumer/ package for the selected target")
        .dependOn(&runConsumer(
        b,
        target,
        optimize,
        delivered,
        runtime_loaded,
        ca_bundle,
        ca_path,
    ).step);

    // The cross-target gate. Compiling the tests, the example and all 196 C
    // units for each target is what makes this a check of the facade rather than
    // of an unreferenced archive. Nothing runs here.
    //
    // One matrix whatever the delivery, and the default `-Dlinkage=static` is the
    // same configuration `cross-test.profile.sh` pins for the published 53-cell
    // matrix, so the fast baseline and the published matrix agree.
    const check_step = b.step(
        "check",
        "Compile the native library, the facade, the tests, the example and " ++
            "the whole 196-unit closure for the five buildable check targets " ++
            "without running any of them",
    );
    if (!target.query.isNative()) {
        addTargetCheck(
            b,
            check_step,
            target.query,
            optimize,
            linkage,
            runtime_loaded,
            ca_bundle,
            ca_path,
        );
    } else {
        // `[0..]`, not `.*`: `.*` is for dereferencing a single optional or
        // error-union payload, so the pointer-to-array has to become a slice
        // before it can be iterated.
        for (check_targets[0..]) |query| {
            addTargetCheck(
                b,
                check_step,
                query,
                optimize,
                linkage,
                runtime_loaded,
                ca_bundle,
                ca_path,
            );
        }
    }

    // Which platform configuration this compiled, and which artifact it hands
    // back, are facts worth reading out of the build rather than inferring from a
    // cache directory. These are configure-time lines, not gate results: nothing
    // has been compiled when they print.
    std.debug.print(
        "libcurl: {d} C units (CSOURCES, lib/Makefile.inc:439-441), USE_MBEDTLS=1, " ++
            "BUILDING_LIBCURL=1, HAVE_CONFIG_H=1\n",
        .{curl_source_count},
    );
    std.debug.print("libcurl: {s}\n", .{switch (delivered) {
        .static => "static archive libcurl.a (the default, and what cross-test.profile.sh pins)",
        .dynamic => b.fmt(
            "shared object libcurl.so.{d}.{d}.{d}, soname libcurl.so.{d} " ++
                "(lib/Makefile.soname:26-28 through lib/CMakeLists.txt:271; the dlopen name is the soname)",
            .{
                abi_version.major,
                abi_version.minor,
                abi_version.patch,
                abi_version.major,
            },
        ),
    }});
    std.debug.print(
        "libcurl: {s} {s}\n",
        .{ @tagName(target.result.os.tag), switch (target.result.abi) {
            .gnu => "gnu",
            .musl => "musl",
            .gnuabin32 => "gnuabin32",
            .musleabi => "musleabi",
            .msvc => "msvcrt",
            .none => "no-abi",
            else => @tagName(target.result.abi),
        } },
    );
    if (ca_bundle) |value| {
        std.debug.print("libcurl: CURL_CA_BUNDLE compiled in as \"{s}\"\n", .{value});
    }
    if (ca_path) |value| {
        std.debug.print("libcurl: CURL_CA_PATH compiled in as \"{s}\"\n", .{value});
    }
    if (runtime_loaded) {
        // Dispatch is a separate fact from delivery, and a runtime-loaded build
        // links nothing into the facade module: the caller names a provider with
        // an explicit `load(source)` and the symbols arrive through the platform
        // loader. Printing it here is what keeps "the artifact is still built and
        // installed" from reading as "the module links it".
        std.debug.print(
            "libcurl: runtime-loaded dispatch (-Druntime=true); the facade module " ++
                "links no archive and a provider is named by an explicit load(source). " ++
                "Under -Dlinkage=dynamic the name this build installs is the soname " ++
                "above; under -Dlinkage=static a caller must name its own provider.\n",
            .{},
        );
    }
    // The version script is ELF-only, so a Mach-O or COFF shared object from this
    // build exports curl's internals as well as its API: Mach-O has no version
    // script GNU ld or lld reads the same way, and COFF's export list is
    // `lib/libcurl.def`, which does restrict the surface but is not versioned.
    // Said here rather than left to be discovered by `nm -D`.
    if (delivered == .dynamic and target.result.ofmt != .elf) {
        std.debug.print(
            "libcurl: {s} takes no ELF version script here, so the shared object " ++
                "exports curl's Curl_-prefixed internals as well as its curl_* API\n",
            .{@tagName(target.result.ofmt)},
        );
    }
    // What this configuration cannot have, printed so a reader of a build log
    // does not have to find it in this file. All four are forced by the
    // one-entry dependency surface and each is explained at the
    // `curl_config_gen.c` row that carries it. The fourth is the one with a
    // security reading and it is stated as plainly here as it is there: no PSL,
    // so cookie rejection is coarser.
    std.debug.print(
        "libcurl: no HTTP/2 (lib/http2.c:26 needs USE_NGHTTP2), no content " ++
            "encoding (lib/content_encoding.c:29 needs HAVE_LIBZ), no " ++
            "ldap:// or ldaps:// (lib/ldap.c:59-61 includes <lber.h> and " ++
            "<ldap.h>), and no Public Suffix List (lib/psl.c:26 needs " ++
            "USE_LIBPSL, so lib/cookie.c's public-suffix rejection is " ++
            "compiled out). The dependency surface is one entry: the mbed-TLS " ++
            "package.\n",
        .{},
    );
}
