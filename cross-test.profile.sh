# cross-test settings for libcurl with Zig 0.16.
# The harness sources this settings-only profile from the package root.
# Leave matrix and runner selection to the harness; do not narrow its 53 targets.
# Target-derived config keeps foreign builds independent of host platform macros.
# Use static linked delivery with the manifest's required mbed-TLS backend.
# SPDX-License-Identifier: curl

CROSS_BUILD_STEP=test
CROSS_BUILD_JOBS=4

# Per-cell build and run deadline, in seconds.
CROSS_BUILD_TIMEOUT=3600

# Per-test-binary run deadline, in seconds.
CROSS_TIMEOUT=1800

# Keep the matrix configuration explicit: static delivery, linked dispatch, and no TLS override.
CROSS_BUILD_ARGS=(-Dlinkage=static -Druntime=false)