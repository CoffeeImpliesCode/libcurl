# libcurl

A Zig package for curl's client-side transfer library, built from upstream libcurl 8.22.0. It provides a typed Zig facade, translated C declarations, and an optional runtime loader.

## Source deviations from upstream

- No changes are made to upstream files under `lib/` or `include/`, or to `COPYING`, `README`, and `RELEASE-NOTES`; they match the 8.22.0 release archive.
- The fork adds the Zig facade in `zig/`, runtime-loading support in `runtime/`, and Zig build support with a target-specific configuration generator.

## Build deviations

- The Zig build compiles the upstream C source list with `-std=gnu99`; it does not use CMake, autotools, or Make, and has no system-libcurl mode.
- The build generates `curl_config.h` from target facts with `build_support/curl_config_gen.c`; it does not run configure.
- mbed-TLS is the only TLS backend and is the `mbed-tls` package dependency declared in `build.zig.zon`, not vendored here. Other optional dependencies are absent: no HTTP/2, LDAP, zlib/brotli/zstd content encoding beyond identity, public-suffix list, IDN2, or GSS-API. Requests for unavailable features may return libcurl's not-built-in errors; cookie-domain checks are coarser without the public-suffix list.
- C consumers receive the 12 public headers under `include/curl/` and `libcurl.pc`.

## Support matrix

| Configuration | Targets or boundary |
| --- | --- |
| Baseline build targets | `x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu` |
| Cross-test profile | `cross-test.profile.sh` records the 53-platform static-link matrix. |
| Not supported | `wasm32-wasi`: mbed-TLS does not provide the network routines required by `lib/vtls/mbedtls.c`. |

## Consumption

Add the package to the consumer's `build.zig.zon`:

```zig
.dependencies = .{
    .libcurl = .{ .path = "../libcurl" },
},
```

Mbed-TLS resolves through libcurl's manifest dependency; consumers need no sibling mbed-TLS checkout when that dependency uses a URL.

Add the named Zig module `libcurl`; it links the `libcurl` artifact through the module (no separate link call):

```zig
const dep = b.dependency("libcurl", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("libcurl", dep.module("libcurl"));
```

For C consumers, include `<curl/curl.h>` and link `libcurl`; use `pkg-config --cflags --libs libcurl` for the package's link flags.

The static archive is `libcurl.a`; on ELF targets, the shared artifact is `libcurl.so.4.8.0` with SONAME `libcurl.so.4`.

| Build option | Effect |
| --- | --- |
| `-Dtarget=<triple>`, `-Doptimize=<mode>` | Select the target and optimization mode. |
| `-Dlinkage=static\|dynamic` | Select the linked artifact; defaults to `static`. |
| `-Druntime=true` | Use explicit runtime loading instead of link-time symbols; defaults to `false`. Call `libcurl.load` with a `.path` or `.system` source before other libcurl calls. |
| `-Dca-bundle=<pem>`, `-Dca-path=<dir>` | Set the compiled CA bundle file or CA directory. |
| `-Dtls=<path>` | Rejected; the mbed-TLS dependency root has no build-option override. |

Runtime tests and smoke runs read `LIBCURL_TEST_PROVIDER`. The consumer run requires a command-line provider:

```sh
zig build test smoke -Druntime=true
zig build consumer -Druntime=true -- --provider /absolute/path/to/libcurl.so.4
```

Set `LIBCURL_TEST_PROVIDER` to that provider's absolute path before the first command. Delivery linkage remains independent of runtime loading.

See `README.zig.md` for facade APIs and ownership rules.
