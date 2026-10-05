# cross-test settings profile for the libcurl SDK.
#
# `cross-test` looks for this file at the root of the project it is run from
# (or names it with --profile; --no-profile ignores it). It is trusted Bash that
# the harness `source`s, so this file is *settings only*: ordinary variable
# assignments and nothing else. No command runs, no compiler is probed, and no
# path in here names a host.
#
# There is deliberately no CROSS_MATRIX. The published 53-platform Zig 0.16
# Tier 1/2 table is the matrix this package is checked against, and a matrix
# named here would replace it. There is no TARGETS array either, for the same
# reason: a subset selected here would narrow the run rather than add to it.
# Both belong on the command line, where --targets selects from the active
# matrix and never adds to it.
#
# There are no `cross_build_command` / `cross_artifact` / `cross_run_command`
# hooks here either, so the harness keeps its own runner detection: a host
# target runs, a foreign target runs under whatever executor the harness finds
# (QEMU user mode, Wine, wasmtime), and a foreign target with no executor is
# reported as build-only coverage -- compiled, never executed, and never counted
# as a pass. Nothing in this file selects a runner on the package's behalf.
#
# A cell compiles the whole 196-unit closure of `lib/Makefile.inc:439-446` --
# `LIB_CFILES`, `LIB_VAUTH_CFILES`, `LIB_VDNS_CFILES`, `LIB_VTLS_CFILES`,
# `LIB_VQUIC_CFILES`, `LIB_VSSH_CFILES` and `LIB_CURLX_CFILES` together -- and
# on top of that the mbed-TLS closure, because the TLS backend is compiled from
# the sibling package rather than taken from the system. Four build jobs: a
# matrix cell is the parallelism bottleneck rather than any single unit, and
# this is the same figure the other SDKs in this workspace use for a tree of
# this size.
#
# One thing about this package that a cell gets right for free and that is
# worth stating, because it is easy to assume otherwise: the generated
# `curl_config.h` comes from a host-target C generator configured from the
# target's own facts (OS tag, architecture, pointer width, endianness, libc) as
# command-line arguments. So compiling a foreign target here does not copy the
# build machine's platform macros onto it; running the generator on the host is
# how a cross cell is configured *correctly*.
#
# Nothing here narrows the gate to what is expected to work. Which platforms
# libcurl itself supports is decided by the vendored sources and by what the
# generator emits for each target, and `build.zig` gives the test binary a Run
# step for every target, which is what leaves the executor's choice open. A
# cell that fails is a fact to record and diagnose; it is not a reason to drop
# the cell, sample the tests, or remap Debug to an optimized mode to make it
# pass.
#
# PENDING-VERIFICATION: every one of these 53 cells also has to resolve the
# package's single dependency, the sibling mbed-TLS package declared as a
# relative path in build.zig.zon. That sibling is present on disk, so a failure
# to resolve it is a defect rather than an expected condition; no cell of this
# matrix has been run yet.
#
# SPDX-License-Identifier: curl

CROSS_BUILD_STEP=test
CROSS_BUILD_JOBS=4

# Deadline for one `zig build test -Dtarget=...`, covering the compile of the
# 196 libcurl units, the mbed-TLS closure and the test binary, plus the run.
CROSS_BUILD_TIMEOUT=3600

# Per-test-binary deadline, passed on as `zig build --test-timeout`. It is set
# generously because this profile does not know what the behavioural tests will
# cost on a slow interpreter cell, not because anything slow is expected. If a
# cell does hit it, that is a fact to record and diagnose.
CROSS_TIMEOUT=1800

# The configuration, named rather than left to the defaults.
#
# `build.zig` has two delivery options and both defaults are the ordinary
# linked, static build. Neither default is relied on here, because a cell that
# silently changed kind would still exit zero.
#
#   * `-Dlinkage=static`. The two linkages are not interchangeable over this
#     matrix, and one of them has no answer on a cell at all: WASI has no
#     shared object for a C library to be built into, so `-Dlinkage=dynamic`
#     cannot be the answer for `wasm32-wasi`.
#   * `-Druntime=false`. The linked dispatch, not the generated one. This is the
#     one that would be most tempting to omit, because a linked cell still
#     compiles and still runs the behavioural tests; what it would not be is a
#     runtime cell. The loader's Unix backend calls `dlopen`, which WASI does
#     not have either, and a runtime root additionally needs a real provider
#     named by the caller -- an explicit path or an explicit bare name, with no
#     fallback -- so `-Druntime=true` has cells it cannot answer as well.
#
# So the published 53-platform matrix is the static LINKED closure, which every
# cell can satisfy. The other configurations are verified separately and on
# their own terms: the shared artifact with `zig build -Dlinkage=dynamic` plus
# the installed C consumer, and the runtime route with
# `zig build test -Druntime=true` on the host, which needs a real provider and
# is therefore not something a compile-and-run matrix cell can stand for.
# Narrowing the matrix is not what this does -- all 53 cells stay, and none of
# them is a cell pretending to be a configuration it is not.
#
# No `-Dtls` appears here on purpose. That option overrides the package's own
# dependency resolution, and an override chosen by a settings file on someone
# else's machine would be exactly the substitution this workspace refuses: a
# cell must build against the mbed-TLS the manifest names or not build.
CROSS_BUILD_ARGS=(-Dlinkage=static -Druntime=false)