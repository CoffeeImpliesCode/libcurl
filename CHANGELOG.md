# Changelog

- Runtime loading keeps glibc's `dysize` linked to libc instead of requiring it from the provider.
- Fix variadic result assertions and exclude GNU C typecheck helpers from translated runtime exports; missing-symbol errors name the export.
- Runtime dispatch accepts scalar variadic arguments and reads translated C version records through indexed pointers.
- Runtime dispatch generation reads symbol-name files, avoiding process argument-size limits for static and dynamic delivery.
- Port to Zig 0.17.0.
- Probe launch and control-compile failures now stop configuration instead of reporting missing features.
- Static C builds set position-independent code explicitly, fixing mips32 musl.
- The existence probe derives `_GNU_SOURCE` from the target libc, fixing `memrchr` detection on musl.
- Target configuration probes IPv6 scope-id members and supports the relevant pointer widths, macOS Catalyst, and Windows import libraries.
- `Easy.setUrl`, `SList.append`, and `optionByName` now require NUL-terminated strings.
- `Multi.drive` completes active transfers and retains completion messages; `readInfo` views live in `Multi`.
- Added a libcurl 8.22.0 Zig SDK with generated configuration, static and dynamic linkage, runtime loading, and a typed facade.
