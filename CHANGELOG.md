# Changelog

- Port to Zig 0.17.0.
- Probe launch and control-compile failures now stop configuration instead of reporting missing features.
- Static C builds set position-independent code explicitly, fixing mips32 musl.
- The existence probe derives `_GNU_SOURCE` from the target libc, fixing `memrchr` detection on musl.
- Target configuration probes IPv6 scope-id members and supports the relevant pointer widths, macOS Catalyst, and Windows import libraries.
- `Easy.setUrl`, `SList.append`, and `optionByName` now require NUL-terminated strings.
- `Multi.drive` completes active transfers and retains completion messages; `readInfo` views live in `Multi`.
- Added a libcurl 8.22.0 Zig SDK with generated configuration, static and dynamic linkage, runtime loading, and a typed facade.
