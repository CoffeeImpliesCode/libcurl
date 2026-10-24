# Fork notes

libcurl 8.22.0. Upstream files under `lib/` and `include/` are unchanged; this fork adds the Zig facade, target configuration and runtime loading.

## Source deviations

- `build_support/curl_config_gen.c` generates `curl_config.h` from explicit target facts because this build does not run upstream configure.
- `build_support/curl_headers_probe.c` compiles header checks for the target so generated settings reflect target headers.
- `build_support/curl_existence_probe.c` probes target functions and members; a control compile distinguishes an unusable compiler from absent features.
- `zig/root.zig` adds the Zig facade; NUL-terminated inputs prevent C string functions from reading past caller buffers.
- `zig/translate.h` gives translate-c the target's C declarations. Translation sets `CURL_DISABLE_TYPECHECK` to exclude GNU C static warning helpers, whose assembly bodies become unresolved externs. Installed C headers retain their option checks.
- `runtime/loader.zig` adds platform-specific provider loading and state management. Missing-symbol errors name the required export.
- `runtime/generate.zig` builds dispatch from translated declarations. Variadic wrappers accept scalar arguments or tuples; aliases retain the same call shape.
- `runtime/graph.zig` connects dispatch and loading, sets the synchronization prefix, and supplies symbol-name lists as generated input files rather than process arguments. Libc declarations, including glibc's `dysize`, stay direct.
- `runtime/library.zig` binds the generic runtime to libcurl's API.
- `runtime/sync.c` and `runtime/sync.h` add prefixed synchronization symbols so SDK instances do not share loader state.

## Build graph

- The nested consumer build cannot inherit outer job or cache-directory options through `std.Build`; it uses its own job default and inherited cache environment.
- `build.zig` compiles the 196 C units in upstream's `lib/Makefile.inc` order with `-std=gnu99`; it does not use CMake, autotools or Make.
- A host-built generator receives target OS, architecture, pointer width, endianness, libc and probe results. Its generated header is an input to both C compilation and translate-c; no configure step runs.
- The only package dependency is `mbed-tls`, declared in `build.zig.zon`. The build links `mbedtls`, `mbedx509` and `mbedcrypto` in that order; `-Dtls` cannot relocate the dependency and is refused.
- The build installs the C headers, `libcurl.pc` and licence records. The pkg-config file is generated for these artifacts, with TLS archives in `Libs.private` for static consumers.
- Dynamic delivery uses libtool-derived ABI version `libcurl.so.4.8.0` with SONAME `libcurl.so.4`; ELF symbol versions use a generated map, while COFF uses upstream's `lib/libcurl.def`.
- The C module is PIC for both link modes so MIPS o32 calls into musl's PIC `sigsetjmp` use the required `$t9` convention. Windows links `ws2_32`, `iphlpapi` and `bcrypt`.

## Platform and feature boundaries

- Baseline targets: `x86_64-linux-gnu`, `aarch64-linux-gnu`, `riscv64-linux-gnu`, `aarch64-macos-none` and `x86_64-windows-gnu`.
- The configuration generator accepts only 32- and 64-bit pointer widths; `avr`, `ez80`, `msp430`, `spork8` and `x86_16` targets are refused.
- `wasm32-wasi` is refused because this mbed-TLS build omits `MBEDTLS_NET_C`, which libcurl's mbed-TLS backend needs. WASI also lacks dynamic linking and the runtime loader's `dlopen` support; those are separate limits.
- Windows GNU builds omit SSPI authentication (Negotiate, Kerberos and NTLM-over-SSPI) and use the synchronous resolver; core NTLM remains available.
- The single-dependency build has no HTTP/2, LDAP/LDAPS, gzip/brotli/zstd content decoding, Public Suffix List, IDN2, GSS-API, SSH or QUIC support. Without the PSL, cookie public-suffix rejection is unavailable.
