# libcurl

libcurl 8.22.0 — curl's client-side transfer library — as a complete standalone
Zig SDK: the whole compiled closure of upstream's own `CSOURCES`, the twelve
public headers, a typed Zig surface, the raw translated C route and an optional
runtime-loading route, built from the official release tarball with no CMake,
no autotools, no Make and no build-time download.

* Upstream: the `curl-8.22.0.tar.xz` release, 2026-09-02, 2953092 bytes, sha256
  `f7ef3ae8a22e521f289803fe93543eb64c329b58aa73a9e224dfd915a2a5f4f7`, with a
  good detached-PGP signature from Daniel Stenberg's release key — see
  [`UPSTREAM.md`](UPSTREAM.md), which also records that curl.se publishes **no**
  checksum file for this artifact and that the digest above was therefore
  observed from the downloaded bytes and cross-checked by that signature.
* Native source: unmodified. All 418 vendored files — `lib/`, `include/`,
  `COPYING`, `README` and `RELEASE-NOTES` — are recorded by digest in
  [`UPSTREAM.sha256`](UPSTREAM.sha256).
* Licence: the `curl` term for upstream's own files, per file and with six
  exceptions the inventory names; the same `curl` term for this fork's own
  files by the owner's per-project authorization — see [`NOTICE.md`](NOTICE.md)
  and [`FORK-LICENSE.md`](FORK-LICENSE.md). Upstream's grant is `COPYING`,
  reproduced verbatim and installed.
* Upstream's own release note is preserved under its own name as `README`,
  byte for byte. There is deliberately **no** `README.upstream.md`; see
  "The preserved upstream README" below.
* **The TLS backend is a dependency, not a vendored library.** mbed-TLS comes
  from the sibling package `../mbed-tls` through the standard Zig dependency
  mechanism. It is `PENDING-VERIFICATION`: the sibling is on disk and the
  manifest resolves it, but no gate has been run and no link has happened.
* **No gate has been run for this package.** Every row of the matrix below is
  `PENDING-VERIFICATION` and the driver owns those results. There is no build
  result, no test count and no test run to quote anywhere in this repository.

## Native-source deviations

**None.** Every file under `lib/` and `include/`, plus `COPYING`, `README` and
`RELEASE-NOTES`, is byte-identical to the release tarball. No portability patch,
no reformat, no `#if` wrapped around a platform workaround, and no header edited
to remove a declaration upstream wrote.

That is a checkable claim rather than an assertion:

```sh
sha256sum -c UPSTREAM.sha256          # the bytes
tools/check-provenance.sh             # the bytes, the exact file set, the notices
```

A checksum run alone cannot see a file that appears under `lib/` or `include/`
with no recorded digest, so the file *set* is a separate check from the digests,
and `tools/check-provenance.sh` checks both directions. Any future native edit
has to move those digests, add a per-file record to [`NOTICE.md`](NOTICE.md)
and add a numbered entry to [`CHANGELOG.md`](CHANGELOG.md) in the same change,
and needs an observed failure to justify it.

`NOTICE.md` records the one observation that exists: the integration owner of
this package ran `sha256sum -c UPSTREAM.sha256` in the package root and observed
it exit 0 with no mismatched record. That is a checksum run the integration owner
performed, **not** one of the driver's gates, and this repository claims nothing
beyond it.

Five upstream facts shape this SDK, all read out of the source rather than
assumed:

* **The import is the compiled and installed closure, not the whole release.**
  The tarball is 4406 files and 22 239 154 bytes after extraction; 418 of those
  files, 6535699 bytes, are what this tree holds. `src/` (97 files, the
  command-line tool — a different program that happens to link libcurl),
  `tests/` (2645), `docs/` (1071), `scripts/` (35), `projects/` (64),
  `CMake/` (31), `m4/` (25) and the autotools files at the archive root are not
  vendored, each for a stated reason in [`UPSTREAM.md`](UPSTREAM.md).
* **The closure is two directories, and that is load-bearing rather than
  convenient.** Every `#include "..."` in the 196 C units, the 187 headers,
  `dllmain.c` and the three platform configuration headers resolves inside `lib/`
  or `include/`, with exactly two exceptions, both named in `UPSTREAM.md`:
  `lib/curl_setup.h:140`'s generated `curl_config.h`, and
  `lib/curl_ntlm_core.c:84`'s `cipher.mih`, which sits inside the OS/400 branch.
* **196 units are compiled, and a unit whose feature macro is absent still
  stays.** That is upstream's own design — the first `#if` of each unit is a
  guard, not an include (`lib/vquic/cf-ngtcp2.c:26`, `lib/vssh/libssh2.c:26`,
  `lib/openldap.c:27`, `lib/memdebug.c:26`, `lib/system_win32.c:26`), so an
  unselected backend compiles to an empty translation unit rather than leaving
  the list. A *smaller* list would take a protocol or a hash algorithm with it.
* **Four vendored files are upstream's directory rather than its compile list**:
  `dllmain.c`, the Windows DLL entry point, and `config-mac.h`, `config-os400.h`
  and `config-win32.h`, the platform configuration headers `curl_setup.h` selects
  at compile time. They are vendored because they are part of `lib/`, and
  digested because they are bytes from the tarball; neither fact makes them
  compiled units, and `tools/check-provenance.sh` requires the digested files
  that no list names to be exactly those four.
* **Upstream's test suite is in the tarball and this fork does not ship it.**
  2645 files under `tests/`, driven by perl (`tests/Makefile.am:120`), linking
  `tests/libtest/`, with 84 unit sources under `tests/unit/`. No build step here
  downloads a suite to stand in for it. This SDK's own tests are independent
  known answers, described in [`README.zig.md`](README.zig.md).

### The preserved upstream README

The release tarball ships a file called `README`, which is upstream's own
release note and **not** a fork README. It is preserved here under its own
name, unaltered, and it is one of the 418 records in
[`UPSTREAM.sha256`](UPSTREAM.sha256), so a plain `sha256sum -c` covers it.

There is deliberately **no second copy** under the `README.upstream.md` name
other forks here use, for two reasons, both about not shipping an unchecked file:
`build.zig.zon`'s `.paths` is the package file filter and does not name one, and
a copy the digest record does not cover would be a file in the tree that nothing
in this repository verifies. The canonical fork document is this file.

### What this package does not import

Not one line of the import re-implements anything, and no third-party material
is vendored. `zig/root.zig` is a facade: it turns a null into one honest error,
tells borrowed from owned strings apart, and names the ownership boundary. Every
value that comes back out of it was produced by the C under `lib/`.

The ISC and public-domain material inside `lib/` — two BIND-derived files in
`lib/curlx/`, a dual grant on `lib/vssh/vssh.c`, and Alexander Peslyak's
dedication inside `lib/md4.c` and `lib/md5.c` — is upstream's own business
inside its own release, recorded per file in [`NOTICE.md`](NOTICE.md) rather
than summarised into one label.

## Native-build deviations

What the compiled package does that upstream's two build systems do not. Each is
a fork decision with a stated reason; none changes an algorithm, and none edits
an upstream file.

* **Zig builds it; upstream's build systems are unused.** `build.zig` compiles
  all 196 units of `lib/Makefile.inc:439-441`, transcribed in upstream's own
  order with the make variable and line range of each group in its comments
  rather than globbed: `LIB_CFILES` 127, `LIB_VAUTH_CFILES` 13, `LIB_VDNS_CFILES`
  10, `LIB_VTLS_CFILES` 16, `LIB_VQUIC_CFILES` 8, `LIB_VSSH_CFILES` 3,
  `LIB_CURLX_CFILES` 19. A glob could not be diffed against `Makefile.inc`; a
  transcription can.
* **The one generated input is generated, not hand-written.**
  `lib/curl_setup.h:138-140` sends a `HAVE_CONFIG_H` build to `curl_config.h`,
  which does not exist in the tarball. `build_support/curl_config_gen.c` is a
  host-target C generator handed the *target's* OS, architecture, pointer width,
  endianness and libc as argv, and its output directory goes on both the C
  compile line and the translate line. It runs no configure step, reads neither
  `lib/curl_config.h.in` nor `lib/curl_config-cmake.h.in`, and contains no
  `#ifdef` on any host macro.
* **`-std=c99` is pinned.** curl's own C is C89-with-selections and its headers
  are careful about it, so nothing here asks for anything newer; the level is
  pinned rather than inherited from the host clang so that "what dialect did
  this compile as" is a fact about this build.
* **The TLS backend is upstream's own macro, and it cannot be turned off.**
  `USE_MBEDTLS` goes on the C compile line and on the translation line;
  `lib/curl_setup.h:727-730` turns any one of six `USE_*` macros into `USE_SSL`
  and `lib/vtls/vtls.c:693,712` reads it. No other `USE_*SSL*` macro is defined
  anywhere in this package, so `lib/vtls/openssl.c`, `gtls.c`, `wolfssl.c`,
  `rustls.c` and `schannel.c` are empty translation units and `lib/vtls/mbedtls.c`
  is the only live backend. **There is no `-Dno-tls` option and no option that
  disables TLS**: a build that cannot resolve the dependency stops at configure
  time naming it, and never produces a TLS-less libcurl.
* **Two deliveries, one source list.** `-Dlinkage=static` (the default) produces
  `libcurl.a`; `-Dlinkage=dynamic` produces a shared object carrying upstream's
  own libtool-derived ABI identity, `libcurl.so.4.8.0` with soname
  `libcurl.so.4`. The option selects the delivery and never the source list — all
  196 units compile either way. See "ABI identity and the bare loader name".
* **A typed Zig surface beside the raw one.** `zig/root.zig` publishes a
  documented facade over the same library; the translated header is reached as
  `c` **on that same module**, not registered as a module of its own, so a
  dependent cannot get the declarations without the library that satisfies them.
* **Optional runtime loading.** `-Druntime=true` replaces
  `translate.createModule()` with `runtime/graph.zig`'s `createModule`, which
  generates a dispatch from the same translation step's output and links no
  archive. It is orthogonal to `-Dlinkage`: the artifact is still built and
  installed, because a caller may name a provider this tree did not build.
* **`-Dtls` refuses instead of pretending.** It means "override the mbed-TLS
  package location", and Zig 0.16's `Build.dependency` (`lib/std/Build.zig:2055-2071`)
  resolves a package root from the manifest with no per-call override, while the
  sibling declares no option that relocates its own root. Forwarding the flag
  would reach a map that ignores it, and a silently ignored TLS-backend override
  is the worst place to have one. So `build` stops with a message naming the
  dependency, the two ways the override could become real, and the fact that no
  gate has established which. It is not a stub: with `-Dtls` absent, the default
  `b.dependency("mbed-tls", ...)` path is the configuration this package ships.
* **A single dependency entry, and each absent feature is named at its macro.**
  `build.zig.zon` carries exactly one `.dependencies` entry, so there is no
  zlib, brotli, zstd, nghttp2, libpsl, libidn2, GSS-API or LDAP. Four
  configuration decisions are forced by that and each is recorded at the row
  that carries it:
  * `CURL_DISABLE_LDAP` and `CURL_DISABLE_LDAPS` are set, because `lib/ldap.c:59,61`
    includes `<lber.h>` and `<ldap.h>` unguarded and a one-entry dependency set
    has no LDAP. The cost is real and named: this libcurl speaks no `ldap://`
    and no `ldaps://`.
  * **No HTTP/2.** `lib/http2.c:26` needs `USE_NGHTTP2`, which needs nghttp2,
    which would be a second dependency. HTTP/1.1 only.
  * **No content encoding beyond `identity`.** `lib/content_encoding.c:29` is
    `#ifdef HAVE_LIBZ` and the same unit reads the brotli and zstd rows.
  * **No Public Suffix List.** `lib/psl.c:26` is `#ifdef USE_LIBPSL`, so
    `lib/cookie.c:804`'s public-suffix rejection is compiled out. This one has a
    security reading and is worth stating plainly: cookie rejection is coarser
    without a PSL.
* **`wasm32-wasi` is refused, by name and with a reason.** `MBEDTLS_NET_C` is
  compiled in for every unix-like and Windows target and **out** for WASI: the
  mbed-TLS sources `#error` unless `MBEDTLS_PLATFORM_IS_UNIXLIKE || _WIN32`,
  none of which WASI's clang defines, so `mbedtls_net_connect` and
  `mbedtls_net_accept` do not exist there — and `lib/vtls/mbedtls.c` calls both.
  That is a compile-time `#error` inside the dependency, not a macro on this
  side's line, so no configuration this package can write changes it. The row is
  named in `refused_check_targets`, `refusalFor` holds the reason, and
  `checkMatrixPartition` fails any build of this package if the refusal ever
  lapses without the row having been moved back and proved. This is **not** a
  claim that WASI cannot host curl; the cell comes back when the dependency's
  `MBEDTLS_NET_C` covers WASI, or when `lib/vtls/mbedtls.c` stops needing
  `mbedtls_net_*`, and either is the dependency's or upstream's to make.
* **Two `lib/config-win32.h` rows are deliberately not followed, and both are
  named.** `USE_WINDOWS_SSPI` cannot be confirmed for a GNU toolchain without
  running a gate, so `lib/curl_sspi.c`, `lib/socks_sspi.c` and `lib/vauth/*_sspi.c`
  are empty translation units and Negotiate, Kerberos and NTLM-over-SSPI are
  absent on the Windows row; NTLM itself is not, because
  `lib/curl_setup.h:762` takes it from `USE_CURL_NTLM_CORE` through
  `USE_MBEDTLS && HAVE_MBEDTLS_DES_CRYPT_ECB`. `USE_RESOLV_THREADED` defaults on
  upstream and this build uses `CURLRES_SYNCH` on Windows instead, which is
  slower per lookup and correct. `lib/config-win32.h` is read as a statement of
  what a Windows build may rely on; it is not installed or included.
* **The version script and the export list are upstream's own, not written
  here.** `lib/libcurl.vers.in` is four lines, `lib/CMakeLists.txt:289-290` picks
  prefix `MBEDTLS_` under `CURL_USE_MBEDTLS` and `:303` supplies soname 4, so
  the node is `CURL_MBEDTLS_4`; this build substitutes those two upstream values
  and invents no list. For COFF, `lib/libcurl.def` is used verbatim — 100
  `curl_*` entries and no `Curl_*`, so it names exactly the public API.
* **A generated, relocatable `libcurl.pc`.** Upstream ships `libcurl.pc.in` and
  this package deliberately does not vendor it, so every field is this fork's and
  each is written against what this build installs. `prefix` is
  `${pcfiledir}`-relative; the three mbed-TLS archives go in `Libs.private`
  because a static consumer has to link them and a shared one has to have them
  at run time; `-lm` appears only where the maths functions are a separate
  archive (`build.zig`'s `separateLibm`); `-DCURL_STATICLIB` only for a static
  delivery, from `include/curl/curl.h:124`, because a DLL consumer needs
  `__declspec(dllimport)` and `curl.h:124-138` produces it only when
  `CURL_STATICLIB` is absent.
* **The full installed closure, from one writer.** The artifact, the twelve
  public headers upstream installs (`include/curl/Makefile.am:25-26`) under
  `curl/`, `lib/pkgconfig/libcurl.pc`, and `share/licenses/libcurl/` holding nine
  records: `COPYING` — upstream's own grant, verbatim — `README`,
  `RELEASE-NOTES`, `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`,
  `FORK-LICENSE.md`, this file's `CHANGELOG.md` and `FORK-NOTES.md`. A private
  repository removes no upstream obligation, which is why `COPYING` is named in
  `build.zig.zon`'s `.paths` rather than reached through `lib/`: a materialised
  copy without it would fail at install.
* **One version, one ABI number, stated apart.** `build.zig` refuses to
  configure unless `build.zig.zon`'s `.version` equals the 8.22.0 read out of
  `include/curl/curlver.h:35`, so the manifest, the `libcurl.pc` `Version:` field
  and `curl_version()` cannot describe three different releases. It parses the
  manifest string as a semantic version rather than comparing it as text.

### ABI identity and the bare loader name

Two different numbers answer two different questions, and stating only one of
them is how a reader ends up believing `libcurl.so.8` exists:

* The **release** version is `8.22.0`, from `include/curl/curlver.h:35`. It is
  what `build.zig.zon .version` must equal, what `libcurl.pc`'s `Version:` says
  and what `curl_version()` returns at run time (`lib/version.c:543`).
* The **ABI** version is libtool's `current - age`: `lib/Makefile.soname:26-28`
  carries `VERSIONCHANGE=12`, `VERSIONADD=0`, `VERSIONDEL=8`, `:30-31` turns it
  into `-version-info 12:0:8`, and `lib/CMakeLists.txt:268-271` computes
  `_cmasesoname` as 12 − 8 = **4**, with `:272` completing `_cmakeversion` to
  **4.8.0**. `lib/CMakeLists.txt:303` then *defines*
  `CURL_LIBCURL_VERSIONED_SYMBOLS_SONAME` from those numbers — so the macro
  `lib/Makefile.soname:24` says to keep in sync is produced by a file this
  package does vendor.

`libcurl.so.4` is also the bare name a caller hands to `dlopen` under the
runtime route's `LoadSource.system`: the soname is the name the loader resolves,
which is why it and not the versioned file name is the one to document.

### The three mbed-TLS answers the generator will not guess

Three values in the generated header are facts about the mbed-TLS *headers*
rather than about the target, and a reader of `curl_config.h` sees the results
without seeing where they came from:

* `MBEDTLS_VERSION_NUMBER` is `0x03060700` — mbed-TLS 3.6.7, read out of the
  sibling's `src/include/mbedtls/build_info.h:27-30` and its `build.zig.zon`
  `.version` — so the build takes the **3.x** side of `lib/vtls/mbedtls.c:47`.
  That branch is load-bearing: mbed-TLS 4.0 moved the primitives to
  TF-PSA-Crypto and removed the legacy `mbedtls_*` entry points, so
  `lib/vtls/mbedtls.c:37-55` and everything else in the tree that calls them
  would not link.
* `HAVE_MBEDTLS_DES_CRYPT_ECB` is defined because `mbedtls_des_crypt_ecb` is
  declared at `mbedtls/des.h:266` and `MBEDTLS_DES_C` is enabled in that
  configuration. `lib/curl_setup.h:759` keys `USE_CURL_NTLM_CORE` off exactly
  this macro, so it is what makes `CURL_ENABLE_NTLM` mean anything.
* `MBEDTLS_SSL_ALPN` is enabled, so the `HAS_ALPN_MBEDTLS` branch at
  `lib/vtls/mbedtls.c:73` would be live. It stays dead in this configuration
  because HTTP/2 needs nghttp2 and there is no second dependency. The two facts
  are recorded so nobody reads the ALPN branch as a capability this build has.

`--mbedtls-des-crypt-ecb yes|no` is a **required** argument with no default, and
a value outside it stops the generator before a byte is written.

**The wire itself is `PENDING-VERIFICATION`.** The sibling package is on disk at
`../mbed-tls` — that is observed from a directory listing, nothing more — and
`build.zig.zon` names it as `.@"mbed-tls" = .{ .path = "../mbed-tls" }`. No build
has resolved it, no archive has been linked, and the three values above are
`SOURCE-CONFIRMED` from the sibling's headers, not from a compile. The driver
owes the first observation: a `zig build` that resolves, configures and links
all three archives in the order `mbedtls`, `mbedx509`, `mbedcrypto`.
[`UPSTREAM.md`](UPSTREAM.md) and `cross-test.profile.sh` both carry a
point-in-time note that the sibling was not on disk when they were written;
those notes now describe the past and the two files are named in
[`FORK-NOTES.md`](FORK-NOTES.md) §11.

### History of these deviations

The deviations above are the current state and all of them landed when this
package was added. [`CHANGELOG.md`](CHANGELOG.md) numbers them, and
[`FORK-NOTES.md`](FORK-NOTES.md) records the evidence and the open questions
behind each one — the source-closure decision, the generated header, the TLS
wire and the four forced features, the WASI refusal, the two Windows rows, the
`-Dtls` refusal, the ABI numbers, the runtime seam and what the driver still
has to run.

## Current support matrix

**Every row is `PENDING-VERIFICATION`.** No gate has been run for this package,
no build has been attempted, no test has been executed, and there is no test
count to report. The driver runs these; this table is the contract it runs them
against.

| Gate | Command | Status |
|---|---|---|
| Install step, static delivery | `zig build -j8 --summary all` | PENDING-VERIFICATION |
| Install step, shared delivery | `zig build -Dlinkage=dynamic -j8 --summary all` | PENDING-VERIFICATION |
| Behavioural tests, Debug | `zig build test -j8 --summary all` | PENDING-VERIFICATION |
| Behavioural tests, ReleaseSafe | `zig build test -Doptimize=ReleaseSafe -j8 --summary all` | PENDING-VERIFICATION |
| Example program | `zig build smoke -j8 --summary all` | PENDING-VERIFICATION |
| Five-target compile-only check | `zig build check -j8 --summary all` | PENDING-VERIFICATION |
| Runtime-loaded route, explicit provider | `zig build test smoke -Druntime=true -j8 --summary all` | PENDING-VERIFICATION |
| Consumer package, entered directly | `cd consumer && zig build run -j8 --summary all` | PENDING-VERIFICATION |
| Consumer package, through the parent | `zig build consumer -j8 --summary all` | PENDING-VERIFICATION |
| Published platform matrix | `"$HOME/.local/bin/cross-test"` from the package root | PENDING-VERIFICATION |
| Provenance, digests and notices | `tools/check-provenance.sh` | PENDING-VERIFICATION |

Every command takes the driver's `-j8` and `--summary all`, plus its own
`--cache-dir` under the approved cache root.

The options are this package's own: `-Dlinkage`, `-Druntime`, `-Dtls`,
`-Dca-bundle`, `-Dca-path`, plus `-Dtarget` and `-Doptimize`. **There is no
`-Dsystem` option**: system-library mode is not part of this package, so there
is nothing to gate and nothing to skip. `build.zig` has no delivery that builds
nothing, which is what makes the record "this package never substitutes an
installed libcurl" a property of the graph rather than a promise.

### The five-target check, and what it is not

`zig build check` compiles the native library, the translation, the facade, the
tests and the example for each of the five buildable baseline targets and
**runs nothing**:

`x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`,
`x86_64-windows-gnu`, `riscv64-linux-gnu`.

`wasm32-wasi` is the sixth baseline target and is **not** in that list. It is
named in `refused_check_targets`, it stops the build with its reason instead of
being compiled, and `checkMatrixPartition` enforces the partition against
`refusalFor` so a target can only be added to one list by an edit that says
which. It is refused because of the mbed-TLS backend, not because of curl or
the toolchain's libc; the reasoning is in "Native-build deviations" above.

**A successful foreign compile is `build_only`, and it is never a pass.** It is
coverage of the compiler, not evidence about behaviour. `check` itself runs
nothing, so no test number may be read out of it — not even "the tests
compiled".

Two further refusals, kept separate from the WASI one: `deliveredLinkage` needs
a platform with a dynamic linker, so `-Dlinkage=dynamic` is refused on
`wasm32-wasi`; and the runtime route's Unix backend calls `dlopen`, which WASI
does not have. Neither is why the row is refused.

### The full platform matrix

The 53-platform matrix is **not** a `zig build` step. It is run by the
host-local `cross-test` harness, driven by `cross-test.profile.sh` from the
package root, and it supplies native or foreign execution itself. The profile
names the configuration explicitly —
`CROSS_BUILD_ARGS=(-Dlinkage=static -Druntime=false)` — so the published matrix
is the same static *linked* closure `zig build check` proves for the five
buildable targets, and none of the 53 cells pretends to be a configuration it is
not. `build_only` cells there are compiled-not-run coverage and are recorded
separately from executed ones, never as passes. Nothing about that run has been
observed for this package.

The profile also states, and the driver should hold it to, that every cell also
has to resolve the single dependency. A cell that fails is a fact to record and
diagnose; it is not a reason to drop the cell, sample the tests, or remap Debug
to an optimized mode to make it pass.

### Continuous integration is not a substitute for any of the above

`.github/workflows/verify.yml` is this fork's own file — curl's CI is not copied
here and could not be, because it lives in curl's Git repository and not in the
tarball this package was imported from. It has five jobs: `preflight` (is the
sibling package present in the checkout's parent directory?), `source` (the 418
digests and `tools/check-provenance.sh`, which need no compiler), `native`,
`cross` and `consumer`. It contains no `continue-on-error`, no `if:` that skips
a step and no matrix row allowed to fail, because a tolerated failure is
indistinguishable from a gate that was quietly dropped. It does not contain the
53-platform matrix — `cross-test` is a host-local tool a GitHub runner does not
have — and it does not stand in for it.

## Consumption

### From Zig, typed

`@import("libcurl")` is the documented facade published by `zig/root.zig`.
`zig build` installs it as the module a dependent names:

```zig
// build.zig of the dependent
const libcurl = b.dependency("libcurl", .{});
exe.root_module.addImport("libcurl", libcurl.module("libcurl"));
```

```zig
// the dependent's source
const libcurl = @import("libcurl");

pub fn main() !void {
    try libcurl.globalInit(libcurl.InitFlags.default_flags);
    defer libcurl.globalCleanup();

    var easy = try libcurl.Easy.init();
    defer easy.deinit();
    try easy.setUrl("https://example.invalid/");
    try easy.perform();
}
```

Three things belong here rather than being left to be discovered, and all three
are stated at their definitions in [`README.zig.md`](README.zig.md):

* **Global initialization is not optional and is refcounted.** Every
  `globalInit` needs its own `globalCleanup`, and `globalCleanup` must not run
  while any `Easy` or `Multi` is still open. A program that skips the pair works
  anyway — upstream initializes itself from the first `curl_easy_init` — which
  is exactly why a passing transfer is not evidence that the explicit lifecycle
  ran.
* **Every pointer this module returns is owned by libcurl's own allocator**, not
  by Zig. `escape` and `unescape` hand back `Curl_cmalloc`-family memory that
  `freeEscaped` releases through `curl_free`. Handing one to
  `std.heap.page_allocator` or to `defer testing.allocator.free(...)` is a
  mismatched free, not a leak, and no test framework here can be a leak oracle
  for it.
* **Callbacks are not Zig error boundaries.** A short count from a
  `WriteCallback` is curl's "stop this transfer" signal, not a Zig error.

The escaped raw route is one name away and is the same library:

```zig
const c = @import("libcurl").c;   // the translated <curl/curl.h> and its closure
```

`c` is re-exported **on the `libcurl` module**, not published as a module of
its own: registering it separately would hand a dependent the declarations
without the library that satisfies them.

### From Zig, as an archive

`dep.artifact("libcurl")` returns the compiled `libcurl.a` (or the shared
object under `-Dlinkage=dynamic`) for a dependent that wants to link or
`install` it rather than import the module.

### From C

The installed tree carries upstream's own twelve public headers and the library,
so a C consumer needs an include path and `-lcurl`:

```c
#include <curl/curl.h>

CURL *h = curl_easy_init();
curl_easy_setopt(h, CURLOPT_URL, "https://example.invalid/");
curl_easy_perform(h);
curl_easy_cleanup(h);
```

```sh
cc -I"$prefix/include" prog.c -L"$prefix/lib" -lcurl -o prog
```

For a static delivery on a non-glibc platform, `pkg-config` adds the mbed-TLS
archives and, where the maths functions are separate, `-lm`; `CURL_STATICLIB`
is present for a static install and must be absent for a shared one, because
`include/curl/curl.h:124-138` only produces `__declspec(dllimport)` when it is.

The installed layout, in full:

```
include/curl/curl.h
include/curl/curlver.h
include/curl/easy.h
include/curl/header.h
include/curl/mprintf.h
include/curl/multi.h
include/curl/options.h
include/curl/stdcheaders.h
include/curl/system.h
include/curl/typecheck-gcc.h
include/curl/urlapi.h
include/curl/websockets.h
lib/libcurl.a                       # or libcurl.so.4.8.0 with soname libcurl.so.4
lib/pkgconfig/libcurl.pc
share/licenses/libcurl/COPYING
share/licenses/libcurl/README
share/licenses/libcurl/RELEASE-NOTES
share/licenses/libcurl/UPSTREAM.md
share/licenses/libcurl/UPSTREAM.sha256
share/licenses/libcurl/NOTICE.md
share/licenses/libcurl/FORK-LICENSE.md
share/licenses/libcurl/CHANGELOG.md
share/licenses/libcurl/FORK-NOTES.md
```

`pkg-config --cflags --libs libcurl` reports the same thing from the installed
`libcurl.pc`, whose `prefix` is `pcfiledir`-relative and so correct wherever
`--prefix` put it. `zig build` additionally *compiles* the example executable
`libcurl-smoke`; `build.zig`'s own comment states it is compiled and not
installed, and the driver's install listing settles that — see
[`FORK-NOTES.md`](FORK-NOTES.md) §11.

### Runtime loading

`-Druntime=true` swaps the linked calls for calls through one process-lifetime
table, selected explicitly:

```zig
const libcurl = @import("libcurl");

fn start() !void {
    try libcurl.load(.{ .path = "/usr/lib/libcurl.so.4" });  // an absolute path
    try libcurl.load(.{ .system = "libcurl.so.4" });         // the soname
}
```

There is **no path-to-system fallback, no automatic retry and no implicit
unload**; `unload` exists and is explicit. Calling any native entry point before
a successful load stops the program with a message naming the function, in every
optimization mode — that is a programming error rather than a recoverable
condition, because the table does not exist yet and there is no partial state to
fall back on.

One load has **not** been observed for this package. All 100 exported names are
present in a libcurl built with *no* TLS backend at all, because every disabled
family keeps its stub symbols, so resolving the whole table proves the file is a
libcurl of this API family and says nothing about how it was configured. The one
check the loader adds is therefore the one symbol resolution cannot make: the
provider's own `curl_version_info` must report an `age` at least this header's
`CURLVERSION_NOW`, a non-null `ssl_version`, and the `CURL_VERSION_SSL` feature
bit. All three are read out of the provider, and a refusal closes the candidate
without publishing anything.

The full ABI boundary — `curl_off_t`, `curl_socket_t`, `long` widths, the
appending version struct, the provider's allocator and the twenty-nine
function-pointer types that cross in both directions — is stated in
[`README.zig.md`](README.zig.md) and in `runtime/library.zig`.

### Packaging

`package.nix` is one source-only derivation, consumed by both `flake.nix` and
`devenv.nix` so the two entry points cannot describe different packages; it
builds the `.static` and `.dynamic` variants of this same tree and restates no
C flag, names no source file, copies no header and writes no `.pc`. `flake.nix`
exposes `packages.<system>.static`, `.dynamic` and `.default`. `devenv.nix`,
`devenv.yaml` and `.envrc` are the canonical development shell. `flake.lock` and
`devenv.lock` belong to the driver and are absent from `build.zig.zon`'s
`.paths` until they exist, because naming a path that is not there would make
`zig fetch` hash a missing entry.

## Commands

```sh
zig build                                            # library, headers, .pc, licence records; compiles the example
zig build -Dlinkage=dynamic                          # the same, as libcurl.so.4.8.0 with soname libcurl.so.4
zig build test                                       # Debug
zig build test -Doptimize=ReleaseSafe
zig build smoke
zig build consumer                                   # the separate consumer/ package
zig build check                                      # five buildable targets, compiles only, runs nothing
sha256sum -c UPSTREAM.sha256                         # the upstream bytes
tools/check-provenance.sh                            # the bytes, the exact file set, the notices
"$HOME/.local/bin/cross-test"                        # the published platform matrix
```

## Documents in this repository

| File | What it is |
|---|---|
| [`README.md`](README.md) | this file: deviations, matrix, consumption |
| [`README.zig.md`](README.zig.md) | the public API of `zig/root.zig`, its ownership rules and the runtime ABI boundary |
| [`UPSTREAM.md`](UPSTREAM.md) | which upstream, what was taken, what was not, and how it was imported |
| [`UPSTREAM.sha256`](UPSTREAM.sha256) | the digest of every vendored upstream file |
| [`NOTICE.md`](NOTICE.md) | the per-file licence inventory, upstream and fork |
| [`FORK-LICENSE.md`](FORK-LICENSE.md) | the grant for this fork's own files |
| [`FORK-NOTES.md`](FORK-NOTES.md) | the working record: decisions, evidence and open questions |
| [`CHANGELOG.md`](CHANGELOG.md) | the numbered history, newest last |
| [`README`](README) | upstream's own release note for 8.22.0, byte for byte |
| [`RELEASE-NOTES`](RELEASE-NOTES) | upstream's 8.22.0 change log, byte for byte |
| [`COPYING`](COPYING) | the `curl` licence, as the release carries it |