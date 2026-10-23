# Upstream

## Source identity

| Field | Value |
|---|---|
| Project | curl / libcurl |
| Upstream site | <https://curl.se/> |
| Release | 8.22.0, 2026-09-02 |
| Source artifact | `curl-8.22.0.tar.xz` |
| URL | <https://curl.se/download/curl-8.22.0.tar.xz> |
| Artifact size | 2,953,092 bytes |
| SHA-256 | `f7ef3ae8a22e521f289803fe93543eb64c329b58aa73a9e224dfd915a2a5f4f7` |
| Signature | `curl-8.22.0.tar.xz.asc`, 488 bytes; detached PGP signature by Daniel Stenberg, RSA key `27ED EAF2 2F3A BCEB 50DB 9A12 5CC9 08FD B71E 12C2` |
| VCS identity | None; source is a release tarball |
| Digest manifest | `UPSTREAM.sha256` |

## Imported files

The import contains 418 files and 6,535,699 bytes from the release: `lib/`, `include/`, `COPYING`, upstream `README`, and `RELEASE-NOTES`. The vendored files are unmodified. `README` is upstream's file; the fork README is `README.md`.

| Path | Files | Bytes |
|---|---:|---:|
| `lib/` | 398 | 6,199,635 |
| `include/` | 17 | 302,333 |
| `COPYING` | 1 | 1,088 |
| `RELEASE-NOTES` | 1 | 31,182 |
| `README` | 1 | 1,461 |

## Upstream files not imported

- `src/` (97 files), the command-line tool.
- `tests/` (2,645 files).
- `docs/` (1,071 files), `scripts/` (35), `projects/` (64), `CMake/` (31), and `m4/` (25).
- Root autotools files: `configure`, `configure.ac`, `Makefile.am`, `Makefile.in`, `aclocal.m4`, `acinclude.m4`, and libtool-era companions.
- `CMakeLists.txt` and `libcurl.pc.in`.

`UPSTREAM.sha256` records the imported file digests.
