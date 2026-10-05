# Changelog

Numbered, newest last. Each entry says what changed and what it did **not**
prove.

**No gate has been run for this package.** Every entry below lands as
`PENDING-VERIFICATION`; nothing here is a receipt for a build, a test, a smoke
run or a cross-target check, and there is no test count to quote anywhere in this
file. Statements read out of files are marked `SOURCE-CONFIRMED` and name the
file and line they came from. Only the driver may move anything to `VERIFIED`,
and only beside an observed run.

## 1. 2026-10-05 — the generated configuration stops guessing about targets

Five gaps in the fork's own configuration machinery, all found by the 53-target
cross-test run of 2026-10-05 and all fixed in fork-authored files. Every landed
correction is `PENDING-VERIFICATION`; the per-cell observations below are
`OBSERVED` from single-cell builds on the pinned Zig 0.16.0, not from a matrix.

### What landed

**`_GNU_SOURCE` is derived once, not twice.** `build.zig`'s `generatorLibc` is
the single place that decides the target's C library, and both the generated
header and the existence probe now take that string from it. Before this, the
probe defined `_GNU_SOURCE` on every `__linux__` target while
`curl_config_gen.c` emitted it only for `libc == "gnu"`, so a musl target got
`HAVE_MEMRCHR 1` without the macro musl gates `memrchr` behind. Upstream's own
`configure.ac:719-725` keys the macro on `$host_os` and not on the libc, so the
glibc-only condition in the generator was the deviation.

**`HAVE_SOCKADDR_IN6_SIN6_SCOPE_ID` is measured, not tabulated.** The generator
carried two closed lists of architectures and refused by name anything in
neither; `armeb`, `powerpc64`, `powerpc64le`, `hexagon`, `mipsel`, `thumb` and
`riscv32` were in neither, which is seven cells of the published matrix. The row
now carries `X_MEMBER` and its answer comes from `--member-facts`, which
`build_support/curl_existence_probe.c` produces by compiling upstream's own
`configure.ac:1826-1829` body (`struct sockaddr_in6 s; s.sin6_scope_id = 0;`)
for the target. The architecture lists are deleted rather than widened, so no
architecture can be missing from a list that no longer exists, and the row is
measured on every family instead of asserted on four of them.
`build_support/curl_functions_probe.c` is renamed
`build_support/curl_existence_probe.c`, its collector half is selected by
`-DCURL_EXISTENCE_COLLECTOR`, and it writes one facts file carrying both classes,
told apart by their `CURL_FUNCTION` and `CURL_MEMBER` markers.

**The pointer-width table cannot fall behind the compiler again.**
`build.zig`'s `pointerWidthBits` is an exhaustive `switch` on
`std.Target.Cpu.Arch` with no `else`, so adding an architecture to the pinned
compiler is now a compile error in `build.zig` naming it. The list it replaces
carried `ia64`, `sparcel`, `sparcv9` and `v850`, none of which this compiler
declares, and lacked `aarch64_be` and `thumbeb`. The three architectures whose
pointers are 16-bit (`avr`, `msp430`, `x86_16`) stay an explicit named refusal,
because `--pointer-width` accepts 32 and 64 only.

**Mac Catalyst is Darwin.** `generatorLibc` returned `sysv` for
`std.Target.Os.Tag.maccatalyst` and `family_for_os` refused `--os maccatalyst`
outright. It is Mach-O and links libSystem, so it belongs to the macOS family on
both sides.

**The Windows link names its import libraries.** `aarch64-windows` failed with
38 `lld-link: undefined symbol` errors. mingw-w64's `winsock2.h:36` declares the
whole Winsock family `WINSOCK_API_LINKAGE`, which is `DECLSPEC_IMPORT`, so the
`__declspec(dllimport) WSACreateEvent` in the message is the *shape* of the
problem and not a separate one: `lld-link` can satisfy such a reference only
when the import library is on the link line. `build.zig` now adds `ws2_32`,
`iphlpapi` (for `lib/peer.c:162`) and `bcrypt` (for
`lib/curlx/winapi.c:118`) on `c_mod`, beside the existing `-lm`.

### What each change does not prove

- The 53-target matrix has **not** been re-run. The per-cell statements below
  are single-cell `zig build` / `zig build test` runs.
- `riscv32-linux`, `armeb-linux` and `powerpc64-linux` build (exit 0) after the
  change. `powerpc64le-linux`, `hexagon-linux`, `mipsel-linux`, `thumb-linux`,
  `thumb-windows`, `aarch64_be-linux`, `aarch64_be-netbsd` and `thumbeb-linux`
  still fail, and every one of those failures is now in the sibling `mbed-tls`
  package (`mbed-tls/zig/config_gen.zig:245`, `error.UnknownArchitecture`) with
  zero libcurl-side refusals left. This tree cannot close them.
- `aarch64-maccatalyst`, `x86_64-maccatalyst` and `aarch64-windows` now
  configure, compile and link (17 or 18 of 19 build steps) and stop only because
  the host cannot execute a Mach-O or PE binary. That is build-only coverage,
  not a pass.
- Cause D as the diagnostic report classified it was *misattributed*: the
  `error.UnknownArchitecture` in those nine cells comes from
  `mbed-tls/zig/config_gen.zig:245`, not from this tree's `build.zig`. See
  `FORK-NOTES.md` §12 for the per-cell evidence.
- Only the driver may move any gate here to `VERIFIED`.

## 2. 2026-10-05 — the libcurl 8.22.0 SDK is added

The first entry in this file is this addition: a standalone foundation library
for libcurl, mirroring the existing forks, built from the official release
tarball with no CMake, no autotools, no Make and no build-time download.

### What landed

**The import.** The upstream release `curl-8.22.0.tar.xz` (published 2026-09-02,
2953092 bytes, sha256
`f7ef3ae8a22e521f289803fe93543eb64c329b58aa73a9e224dfd915a2a5f4f7`) was imported
whole: the 398 files of `lib/`, the 17 files of `include/`, and `COPYING`,
`README` and `RELEASE-NOTES`. **418 files, 6535699 bytes**, every one recorded
by digest in `UPSTREAM.sha256`.

`SOURCE-CONFIRMED`: no vendored file has been edited. There is no portability
patch, no reformat and no header edited to remove a declaration upstream wrote.
The import is a release tarball and not a VCS import — there is no clone, no
history, no commit SHA and no patch series, because the artifact has no version
control to point at. curl.se publishes a detached signature and **no checksum
file** for this artifact, so the digest above was observed from the downloaded
bytes and cross-checked by that signature; both facts are stated in
`UPSTREAM.md` rather than glossed.

**The build graph** (`build.zig`, `build.zig.zon`): all 196 units of
`CSOURCES` (`lib/Makefile.inc:439-441`) compiled in upstream's own order, two
deliveries (`-Dlinkage=static`/`dynamic`), `-Druntime` for the load-at-runtime
route, `-Dca-bundle` and `-Dca-path`, the twelve installed headers, a generated
`libcurl.pc`, and the nine installed licence and provenance records. Five steps
exist: the default install step, `test`, `smoke`, `consumer` and `check`.

**The typed Zig surface** (`zig/root.zig`, `zig/translate.h`): a documented facade
over the same library, with the translated header reached as `pub const c` on the
same module.

**The runtime-loading route** (`runtime/loader.zig`, `runtime/library.zig`,
`runtime/graph.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h`):
one process-lifetime table, explicit `path` or `system` provider selection, no
fallback, no automatic retry, atomic publication, an ordinary
pre-initialization panic in every optimization mode. Linked calls stay direct.

**The package's own tests, example, consumer and provenance records**, and the
full documentation set: `README.md`, `README.zig.md`, `UPSTREAM.md`,
`UPSTREAM.sha256`, `NOTICE.md`, `FORK-LICENSE.md`, `FORK-NOTES.md` and this file.

### Recorded facts, each read out of the source rather than assumed

* **196 C units and 187 headers**, counted from the seven groups of
  `lib/Makefile.inc`: `LIB_CFILES` 127, `LIB_VAUTH_CFILES` 13, `LIB_VDNS_CFILES`
  10, `LIB_VTLS_CFILES` 16, `LIB_VQUIC_CFILES` 8, `LIB_VSSH_CFILES` 3,
  `LIB_CURLX_CFILES` 19; and `LIB_HFILES` 132, `LIB_VAUTH_HFILES` 2,
  `LIB_VDNS_HFILES` 6, `LIB_VTLS_HFILES` 17, `LIB_VQUIC_HFILES` 9,
  `LIB_VSSH_HFILES` 2, `LIB_CURLX_HFILES` 19. **No unit is dropped.** Upstream's
  own design is that a unit whose feature macro is absent still compiles — to an
  empty translation unit — and the list is never shortened. A smaller list would
  take a protocol or a hash algorithm with it.
* **The closure is two directories.** Every `#include "..."` reachable from a
  compiled unit resolves inside `lib/` or `include/`, with exactly two
  exceptions: `lib/curl_setup.h:140`'s generated `curl_config.h`, and
  `lib/curl_ntlm_core.c:84`'s `cipher.mih` inside the OS/400 branch at `:83`.
  That is why nothing outside those two directories is vendored.
* **Four vendored files are upstream's directory rather than its compile list**:
  `dllmain.c` and the platform configuration headers `config-mac.h`,
  `config-os400.h` and `config-win32.h`. `tools/check-provenance.sh` requires the
  digested files that no list names to be exactly those four.
* **`curl_config.h` is generated, not written.** `build_support/curl_config_gen.c`
  runs for the host and is handed the *target's* facts as argv; its output path
  is `.generated` and is never resolved during `build()`, and its **directory**
  goes on both the C compile line and the translate line.
* **The TLS backend is upstream's own macro and cannot be turned off.**
  `USE_MBEDTLS` reaches the `USE_SSL` derivation at `lib/curl_setup.h:727-730`,
  the dispatch at `lib/vtls/vtls.c:693,712` and the unit at
  `lib/vtls/mbedtls.c:32`. No other `USE_*SSL*` macro is defined anywhere in this
  package, so the other fifteen vtls units are empty translation units. There is
  **no option that disables TLS**, and a build that cannot resolve the
  dependency stops at configure time naming it.
* **The dependency surface is exactly one entry**, so there is no zlib, brotli,
  zstd, nghttp2, libpsl, libidn2, GSS-API or LDAP, and `build.zig` names each
  feature that loses at the macro that decides it. Four consequences are forced
  and recorded: `CURL_DISABLE_LDAP`/`CURL_DISABLE_LDAPS` (so this libcurl speaks
  no `ldap://` and no `ldaps://`), no HTTP/2, no content encoding beyond
  `identity`, and no Public Suffix List — the last of which has a security
  reading, because cookie rejection is coarser without one.
* **`wasm32-wasi` is refused by name and with a reason.** `MBEDTLS_NET_C` is
  compiled out there — the mbed-TLS sources `#error` unless
  `MBEDTLS_PLATFORM_IS_UNIXLIKE || _WIN32`, none of which WASI's clang defines —
  and `lib/vtls/mbedtls.c` calls both `mbedtls_net_connect` and
  `mbedtls_net_accept`. That is a compile-time `#error` inside the dependency, so
  no configuration this package writes can change it. The row is in
  `refused_check_targets`, `checkMatrixPartition` enforces the partition, and
  nothing is dropped silently.
* **Two `lib/config-win32.h` rows are deliberately not followed**, and both are
  named rather than quietly dropped: `USE_WINDOWS_SSPI` (its link line cannot be
  confirmed for a GNU toolchain without a gate) and `USE_RESOLV_THREADED` (this
  build uses `CURLRES_SYNCH` on Windows). NTLM itself survives on Windows
  because `lib/curl_setup.h:762` takes it from `USE_CURL_NTLM_CORE` through
  `USE_MBEDTLS && HAVE_MBEDTLS_DES_CRYPT_ECB`.
* **The ABI version is 4.8.0 and it is not the release version.**
  `lib/Makefile.soname:26-28` carries `VERSIONCHANGE=12`, `VERSIONADD=0`,
  `VERSIONDEL=8`; `lib/CMakeLists.txt:268-271` computes 12 − 8 = 4 and `:272`
  completes it to 4.8.0. `-Dlinkage=dynamic` installs `libcurl.so.4.8.0` with
  soname `libcurl.so.4`, and that soname is also the bare name a caller hands to
  `dlopen` under the runtime route's `LoadSource.system`.
* **The version script and the COFF export list are upstream's own.** The script
  node is `CURL_MBEDTLS_4`, from `lib/libcurl.vers.in` plus
  `lib/CMakeLists.txt:289-290,303`; `lib/libcurl.def` is used verbatim and holds
  100 `curl_*` entries and no `Curl_*`.
* **One version, checked against the header.** `build.zig` refuses to configure
  unless `build.zig.zon`'s `.version` equals the 8.22.0 read out of
  `include/curl/curlver.h:35`, and it parses the manifest as a semantic version
  rather than comparing it as text.
* **`-Dtls` refuses instead of pretending.** Zig 0.16's `Build.dependency`
  resolves a package root from the manifest with no per-call override
  (`lib/std/Build.zig:2055-2071`), and the sibling declares no option that
  relocates its own root, so forwarding the flag would reach a map that ignores
  it. `build` stops with a message naming the dependency, the two ways the
  override could become real, and the fact that no gate has established which.
  With `-Dtls` absent, the default path is the configuration this package ships.
* **`provider_optional` and `provider_excluded` are both empty**, and that took
  checking. curl's surface is partly behind `CURL_DISABLE_*` build macros, but
  every gated family keeps its stub symbols in the `#else` branch
  (`lib/ws.c:2027-2071`, `lib/headers.c:396-425`, `lib/easygetopt.c:78-97`,
  `lib/mime.c:2179-2282`, `lib/formdata.c:842-864`, `lib/http2.c:2981-2997`),
  and `lib/libcurl.def` is the same 100 names in every configuration.
* **The provider check is the one symbol resolution cannot make.** All 100 names
  are present in a libcurl built with no TLS backend at all, so resolving the
  table says nothing about configuration. The loader therefore asks the provider:
  `age` at least this header's `CURLVERSION_NOW`, a non-null `ssl_version`, and
  the `CURL_VERSION_SSL` feature bit.
* **There is no system mode.** `build.zig` has no `-Dsystem` option and no
  delivery that builds nothing, which is what makes "this package never
  substitutes an installed libcurl" a property of the graph rather than a
  promise.

### What it does not prove

Nothing in this entry is a receipt. **No build has been attempted, no test has
been executed, no smoke run has been run, no cross-target check has been
compiled, no cross-test cell has been built or run, and no gate has observed the
provenance script.** The one observation that exists anywhere in this package is
a `sha256sum -c UPSTREAM.sha256` run the integration owner performed and recorded
in `NOTICE.md`; it is a checksum run, not one of the driver's gates, and it
proves only that the recorded digests match the recorded bytes.

The TLS wire in particular is `PENDING-VERIFICATION`: the sibling mbed-TLS
package is present on disk at `../mbed-tls` — observed from a directory listing
and nothing more — and `build.zig.zon` names it, but **no build has resolved it,
no archive has been linked and no configuration header has been produced**.

Three statements in files owned by other roles were true when they were written
and are now stale, because the sibling landed after them:
`UPSTREAM.md` ("at the time this file was written, `../mbed-tls` was not on
disk"), `cross-test.profile.sh` ("that sibling is not on disk yet, so a run
launched today is expected to fail at configure time on every cell") and
`.github/workflows/verify.yml` ("every job below except `source` and
`preflight` is expected to fail until the `mbed-tls/` sibling package lands").
None of them is wrong about the moment it describes, and none of them is a
claim this entry can close. They are recorded in
[`FORK-NOTES.md`](FORK-NOTES.md) §11 for the integration owner.

Two further items are open by design and are not defects: `flake.lock` and
`devenv.lock` are absent because they belong to the driver, and
`consumer/build.zig.zon`'s `.fingerprint` is a documented placeholder for the
same reason.

### What is not here

curl's own test suite is in the tarball and this package does not ship, build or
run it: 2645 files under `tests/`, driven by perl
(`tests/Makefile.am:120`), linking `tests/libtest/`, with 84 unit sources under
`tests/unit/`. No build step downloads a suite to stand in for it, because a
fetched suite would be a different source tree than the pinned release with no
recorded digest. The SDK's own behavioural tests are independent known answers
and are described in [`README.zig.md`](README.zig.md).
## 3. 2026-10-05 — three facade defects behind ten red tests and the smoke crash

The behavioural suite reported 7 of 17 passing, and every failure was a
loopback-fixture transfer; `zig build smoke` died with `General protection
exception` in `Server.accept` (`std/Io/net.zig:1443`). **Every one of those had
the same cause, and it was not the fixture server.** The fixture was answering
correctly to a request that was not the request the test asked for.

### The NUL scan over memory the caller never promised

`Easy.setUrl` (`zig/root.zig:1497`), `SList.append` (`:2285`) and
`optionByName` (`:1333`) each took a `[]const u8` and passed
`std.mem.span(@as([*:0]const u8, @ptrCast(x.ptr))).ptr` to C. `mem.span` reads
*forward* looking for a NUL, and none of those three callers had promised a NUL.

Measured: with a URL built by `std.fmt.bufPrint` into `[128]u8`, the fixture
received the request target

    /fixture.txt%AA%AA%AA...%AA      (128 bytes of 0xAA)

`0xAA` is Zig's `undefined` fill, so those were the untouched bytes after the
URL. `responseFor` found no route, answered `404 no such fixture route`, and the
SHA-256 of that body is `ba68aaf264eaa6891a6f0f250b10b4fa3a8be8e328a7c4444d484d95eb36906c`
- the digest every failing test reported. The `/binary` route failed for the
same reason, and `UrlMalformat` from the two multi tests was the same corrupted
URL reaching libcurl's parser.

Upstream requires the terminator and says so: `Curl_setstropt` computes
`size_t slen = s ? strlen(s) : 0;` (`lib/setopt.c:84`) and
`curl_slist_append` copies `strlen(line)` (`lib/slist.c:87`). So the honest
signature is `[:0]const u8` and the compiler says it. **This is a public API
change**: `setUrl`, `SList.append` and `optionByName` now take `[:0]const u8`.
A caller holding a non-terminated slice writes the NUL itself
(`buf[0..n :0]` after writing `buf[n] = 0`), which is what `tests.zig`,
`smoke.zig` and `consumer/src/main.zig` now do.

### `Multi.drive` never let a transfer finish

`drive` drove the loop with `curl_multi_socket_action(multi, CURL_SOCKET_BAD, 0,
&running)`, described in its own doc comment as upstream's "no descriptor, just
run the timers" call. **That description does not hold.**
`CURL_SOCKET_TIMEOUT` is `#define`d to `CURL_SOCKET_BAD` (`multi.h:288`), but
`multi_socket` tests the two separately: it takes the timeout branch only for
`CURL_SOCKET_TIMEOUT` (`lib/multi.c:3279`), and every other value goes to
`Curl_multi_ev_dirty_xfers(multi, s)` (`:3288`), which looks the descriptor up
and **marks no transfer dirty when there is no entry**
(`lib/multi_ev.c:589-591`).

So the call ran only what was already dirty. Enough to start a transfer, not
enough to finish one: once the connect completed, the only thing that would
re-dirty it is the readiness event for that descriptor, and the descriptor was
never named. `drive` now uses `curl_multi_socket_all` (`multi.h:325`), upstream's
non-deprecated replacement for `curl_multi_perform`, which passes
`checkall = TRUE` and reassesses every active transfer.

`drive` also removed the very message it needed a caller to be able to read
back, so a caller could never learn *which* handle finished. It now keeps that
one message (`Multi.held`) and `readInfo` hands it back before asking libcurl
again. `readInfo` returned `&view` where `view` was **a local**, handing the
caller a pointer to a frame that had already returned; the views now live in the
`Multi` in a rotating window of `message_view_slots`.

### Two test expectations libcurl's own source contradicts

Neither assertion was weakened; each was corrected against the C library.

* `tests.zig:676` claimed "libcurl's write unit is `sizeof(size_t)`". Upstream's
  call is `nwritten = wcb((char *)CURL_UNCONST(buf), 1, blen, wcb_data)`
  (`lib/cw-out.c:190`) - the unit is **one** byte and `nitems` carries the
  length. The assertion now expects `1`.
* `tests.zig:952` expected the fixture body alone when no header callback is
  set. With none set, `cw_get_writefunc` falls back to `fwrite_func`
  (`lib/cw-out.c:159-160`), so the head arrives in the same sink: the SHA-256 of
  head-then-body is exactly the `c4df5f2c...` the test reported. The test now
  checks the head is present and the body **after** it matches the independent
  digest.

Two `expectEqual(@as(*curl.Easy, &easy), completion.easy)` comparisons became
`completion.isFor(&easy)`. `Message.easy` is a view this module made around
upstream's `CURLMsg.easy_handle`, and the module's own doc says in as many
words not to compare its address; `isFor` compares the `CURL` both sides name.

### What this entry does not claim

No gate result is recorded here. `build`, `test` (Debug), `test`
(ReleaseSafe), `smoke` and the consumer run were executed by the change author
and their exit codes are reported to the driver, not moved to `VERIFIED` here.
`zig build check` is **not** addressed by this entry: the aarch64-macos failure
is the function-existence class recorded separately, and it was red when this
was written.

## 4. 2026-10-05 — `consumer/build.zig.zon` carries its SPDX tag

`consumer/build.zig.zon:1-2` now opens with

```
// SPDX-License-Identifier: curl
// See ../FORK-LICENSE.md for what that identifier covers.
```

**Why.** `NOTICE.md` claims every fork-authored source, build, packaging and
script file carries `SPDX-License-Identifier: curl`, and
`tools/check-provenance.sh:333-354` asserts it against `add_fork`, whose list
includes `consumer/build.zig.zon`. The file was the one present fork file
without the tag, so the checker's own census and NOTICE.md's claim disagreed
with the bytes.

**Which way it was decided, and why not the other.** The alternative was to
record the file as a deliberate omission, the way `zlib/NOTICE.md:238-243`
records its own `consumer/build.zig.zon`. That record was rejected here: the
sibling manifests `proj/build.zig.zon:1`, `mbed-tls/consumer/build.zig.zon:1-2`
and `re2/consumer/build.zig.zon:1-2` all carry a tag, so an untagged consumer
manifest in this workspace is the exception rather than the convention, and
AGENTS.md section 8 requires a package to carry the licence, not to be excused
from naming it. Adding the tag also makes NOTICE.md's sentence true instead of
needing a new exception paragraph.

The two header lines are the file's own sibling convention:
`consumer/build.zig:1-2` and `consumer/src/main.zig:1-2` already carry the same
two lines, and `build.zig.zon:1-2` carries the same pair with a one-level
shorter path. No holder, licence name or digest was invented; the identifier is
the one `NOTICE.md:41` already counts 408 times in the vendored tree.

**What this does not prove.** Only the SPDX census. It says nothing about the
build, the ten tests, the smoke crash or `zig build check`, which the entry
titled "three facade defects behind ten red tests and the smoke crash"
records as still red.

## 5. 2026-10-05 — the function probe derived the libc condition twice

`zig build check` was green on the six cross targets and the host gates were
green, and the 53-target cross-test matrix still refused six Linux cells.
**The probe was the cause, and it was introduced by the entry titled "the
generated configuration stops guessing about targets" - the work that added the
function-existence probe.** (Entries here are numbered, and numbering shifts when
several land in one day, so this reference is by title on purpose: an earlier
version of this sentence said "entry 2", which by then pointed at the facade
defects below and named the wrong change entirely.)

### The fault

`build_support/curl_existence_probe.c` - then named `curl_functions_probe.c`,
since renamed as the header and member probes were folded into it - defined
`_GNU_SOURCE` in every probe under `#if defined(__linux__)`. `curl_config_gen.c` defines that macro under
exactly one condition: `family == FAM_LINUX && strcmp(libc, "gnu") == 0`
(`curl_config_gen.c:2784`). On a musl target the probe therefore compiled
*with* the macro and saw musl's `memrchr`, while the closure compiled *without*
it. The generator emitted `HAVE_MEMRCHR 1`, so `lib/curl_memrchr.h:28` did not
install upstream's own fallback and `lib/curl_memrchr.c:28` compiled nothing -
and the function the closure then called is one musl only declares behind the
macro. `lib/cookie.c:168`, `lib/urlapi.c:858` and `lib/urlapi.c:1329` all failed
with "call to undeclared function 'memrchr'".

`_GNU_SOURCE` is a **glibc** fact, not a Linux fact. Writing it as if it were a
platform fact is what let two artifacts decide the same question separately and
disagree.

### The fix

The condition is now decided in one place and handed to both. `build.zig:1192`
passes `generatorLibc(target)` - the same string the generator receives for
`--libc` - as a fifth argument to the collector, which selects
`probe_preamble_gnu` only for `"gnu"` and `probe_preamble_none` otherwise. Since
`generatorLibc` answers `"mingw"`/`"msvcrt"` for Windows and `"darwin"` for
Darwin, `libc == "gnu"` is exactly the generator's own condition and nothing
wider.

### OBSERVED

`zig build test -Dtarget=<t>`, each on its own cache: `x86_64-linux` 0,
`aarch64-linux` 0, `arm-linux` 0, `mips64-linux` 0, `powerpc-linux` 0 - five
of the six green end to end, the sixth being `mips-linux` below.
`mips-linux` **builds** - the `memrchr` refusal is gone - and then its test binary
aborts under qemu with `Segmentation fault at address 0x8fc100ac`, 4 pass / 13
crash of 17. The 4 that pass are exactly the tests that open no socket and all
13 that do crash at the same address, while `mips64-linux` runs the identical
suite green under the same emulator. That is recorded as a qemu-user runtime
boundary for 32-bit big-endian MIPS, not as a pass and not as a source defect.

The generated `curl_config.h` now reads `/* #undef HAVE_MEMRCHR */` with no
`_GNU_SOURCE` line for `x86_64-pc-linux-musl`, and `#define HAVE_MEMRCHR 1`
with `_GNU_SOURCE` defined for `x86_64-pc-linux-gnu` - the pair that is the
regression test for this defect.

Host gates after the fix, all re-run: `build` 0, `test` (Debug) 0,
`test -Doptimize=ReleaseSafe` 0, `smoke` 0, `check` 0. `check` was additionally
re-verified from a removed cache directory: exit 0, 91/91 steps.

### What the matrix says now, on a byte-stable tree

A third 53-cell run, taken while this tree was byte-identical throughout, reports
**18 pass, 19 refused, 2 runtime_fail, 14 compiled_not_executed**. Every pass ran
the full suite and exited 0 - none of them is build-only coverage.

The 18 passing cells include `x86_64-linux`, `aarch64-linux`, `arm-linux`,
`powerpc-linux` and `mips64-linux` - the Linux family this entry was about - plus
`aarch64_be-linux`, `armeb-linux`, `hexagon-linux`, `loongarch64-linux`,
`mips64el-linux`, `powerpc64-linux`, `powerpc64le-linux`, `riscv32-linux`,
`riscv64-linux`, `s390x-linux`, `thumb-linux`, `thumbeb-linux` and `x86-linux`.

**Five of the six causes this package owned are closed, and four of them were not
closed by this entry.** The concurrent merge replaced two closed architecture
lists with an `X_MEMBER` row measured from upstream's own `configure.ac` body, so
`error.UnknownArchitecture` no longer appears anywhere in this tree and the cells
it held now build and run; the named pointer-width panic, `maccatalyst`, and the
windows-gnu link failure are likewise gone. What remains attributable to
libcurl is one cell:

* `wasm32-wasi` is refused by a **named boundary**, not a silent skip: mbed-TLS
  compiles `mbedtls_net_*` out on WASI while `lib/vtls/mbedtls.c` calls
  `mbedtls_net_connect`/`mbedtls_net_accept`. Recording it is the whole claim.

The other 18 refusals are not closable from here: twelve are the pinned Zig 0.16.0
`translate-c` failing on the compiler's own BSD headers (`#pragma` in
`generic-netbsd/sys/endian.h:74`, `generic-openbsd/mips64/endian.h:40`), and six
are `translate-c`'s own generated `translate.zig` failing for 32-bit FreeBSD with
`@bitCast must have a known result type`, in a file that lives in the harness
cache and in neither tree.

**`mips-linux` and `mipsel-linux` are their own class and are not passes**: the
build succeeds, the tests execute, and 13 of 17 crash under qemu while the 4 that
open no socket pass. Both 32-bit MIPS ends are affected and `mips64-linux` is
not, under the same emulator. The fault address differs between runs - `0x8fc100ac`
in the run that dumped cores, `0x1420001a` in the later run that did not - so the
address is a property of the emulator's state, not a stable identifier, and only
the shape is claimed.

One caveat attached by the matrix owner rather than smoothed over:
`mbed-tls/build.zig` was rewritten inside that run's window. libcurl was
byte-identical across it, so this is a dependency and not this tree, but cells
depending on it may span two of its states.

## 6. 2026-10-05 — the mips32 cells now execute all 17 tests

**`.pic` is named for both linkages.** `add_c_library`'s C module said
`.pic = if (linkage == .dynamic) true else null`, and the cross-test matrix is
static linkage, so `pic` was left to the build system to infer. On
`mips-linux-musleabi` the inference is non-PIC, and musl is PIC:
`lib/vdns/hostip.c:890` (`sigsetjmp(curl_jmpenv, 1)`) then reaches musl's
`sigsetjmp` through a bare `jal` that never puts the callee's address in `$t9`,
so `sigsetjmp` derives a rubbish `$gp` and `jalr`s through it. The build was
clean, the 4 of 17 tests that open no socket passed, and 13 of 17 crashed on one
wild address per cell. `build.zig` is the only file changed; the vendored
resolver is byte for byte unchanged.

**Cost, measured rather than assumed:** `libcurl.a` on `mips-linux-musleabi` goes
from 19747232 to 18801176 bytes, and on the `x86_64-linux-gnu` host it is
20717210 either way with different contents. Position independence makes that
archive smaller on the target that needs it and is size-neutral on the one that
did not.

**What this does not prove.** The isolation is four one-function programs on
`mips-linux-musleabi` under this qemu: `printf`, `malloc`+`free` and `setjmp` run
non-PIC, `sigsetjmp` does not, and the same source with `-fPIC` runs. That
identifies the flag as the cause. The 53-cell matrix on this tree is
`PENDING-VERIFICATION` until that run is reported.

**Rule.** `null` for a codegen option is not "off", it is "whatever the build
system guesses", and on one architecture in a 53-cell matrix that guess was the
whole defect.

## 7. 2026-10-05 — the existence probe could answer all 48 rows "no" and exit 0

**A refused measurement and a measured absence were the same event.** Every
refusal path in `build_support/curl_existence_probe.c` was already correct: the
argument count is checked (`argc != 6` refuses with exit 2), an unknown
declaration group is refused, an over-long render is refused, a refusal in
either loop is counted and makes the program exit non-zero. Two paths were not
on that list, and both ended in a *complete, internally consistent* facts file
in which every row read `no`.

**1. A compiler that could not be executed.** `run_probe` forked and called
`execv`; when `execv` returned, the child called `_exit(2)`, and the parent saw
an ordinary non-zero exit status - which is exactly what "the target does not
declare this function" also produces. A `zig` path that does not exist gave
**48 of 48 `no` and exit 0**, and `check_function_rows` had nothing to object
to, because every row did have an answer. `run_probe` now carries a
close-on-exec pipe: end-of-file means the compiler owns the process, a byte
means `execv` returned, and the second case is a refusal rather than an answer.

**2. A compiler that ran and rejected its own command line.** This one the exec
pipe cannot see, because `zig cc` did start: an unparsable triple and an unknown
flag each exited 1, which is the same status as `use of undeclared identifier`.
Each produced **48 of 48 `no` and exit 0**. The distinction is not available from
the exit status, so it is made before any row is asked: one **control probe**
compiles a translation unit with no header, no macro and no target symbol in it,
which every target's compiler accepts. If the control fails, nothing the run
could say about any row would be an answer, so the run refuses and writes no
facts file at all.

**Also fixed:** five comments and one `refuse()` message in
`build_support/curl_config_gen.c` named `curl_functions_probe.c`, the file's
name before the rename recorded in entry 1. The refusal message is what a reader
sees when a fact is missing, and it was pointing at a path that does not exist.

**Scope.** `build_support/curl_existence_probe.c` and
`build_support/curl_config_gen.c` only. No vendored file was touched, and no
existing test, gate or refusal was weakened: the control probe and the exec pipe
can only turn a silent `no` into a loud refusal.

**What this does not prove.** Both fixes are verified on this host with the
pinned Zig 0.16.0, on the five failure inputs above and on six targets that
must still answer normally; the runs are in `OBSERVED` below. The 53-cell matrix
is not re-run here and stays with its owner.

### OBSERVED

Pinned Zig 0.16.0, `-DCURL_EXISTENCE_COLLECTOR=1`, `-std=gnu99` per probe, run
2026-10-06. Receipt: `$HOST_SCRATCH_ROOT/scratch/foundation-libs/gates/f-probe-refusal.log`.
One invocation per row; "facts file" is whether one was written at all, which is
the observable that separates a refusal from an answer.

| input | exit | facts file |
|---|---|---|
| healthy `x86_64-linux-gnu` | 0 | 48 lines, 45 yes / 3 no |
| `zig` path does not exist | 2 | none |
| unparsable triple | 2 | none |
| unknown flag string | 2 | none |
| four arguments, no output path | 2 | none |
| six arguments | 2 | none |

Before these two fixes the same three toolchain inputs each gave **exit 0 and 48
of 48 `no`**. The six `check` targets through the real build graph each produced
a distinct per-target answer set with the control probe present, so the fix does
not make the probe uniformly refuse.
