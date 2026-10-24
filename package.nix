# SPDX-License-Identifier: curl
# See FORK-LICENSE.md for grant scope; COPYING is upstream's verbatim grant.
# NOTICE.md inventories per-file licensing.
#

{ lib
, stdenv
, zig
, patchelf
, fetchFromGitHub
, mbedTlsSrc ? fetchFromGitHub {
    owner = "CoffeeImpliesCode";
    repo = "mbed-tls";
    rev = "c9463b540139f5440f1dc20976532ccd5b7cb765";
    hash = "sha256-tEjYqhFannLpZlFRMv7np3ngvFQeEoimEpVoRDW4VeY=";
  }
  # Select the static or dynamic artifact produced by `build.zig`.
, linkage ? "static"
, optimize ? "ReleaseSafe"
}:

let
  requestedLinkage =
    if builtins.elem linkage [ "" "static" "dynamic" ] then linkage
    else throw "package.nix: linkage must be \"\", \"static\" or \"dynamic\", not ${toString linkage}";

  # Exclude build outputs, version control, and developer-tool state from the source.
  src = lib.cleanSourceWith {
    name = "libcurl-source";
    src = ./.;
    filter = path: _type:
      let name = builtins.baseNameOf (toString path); in
      !(lib.elem name [
        ".git"
        ".direnv"
        ".devenv"
        ".zig-cache"
        "zig-cache"
        "zig-pkg"
        "zig-out"
        "result"
      ]);
  };

# patchelf handles ELF, not Mach-O; normalize rpaths only for ELF outputs.
isElfTarget = !stdenv.hostPlatform.isDarwin;
in

# Refuse cross builds; this derivation packages the compiler's native output.
assert stdenv.buildPlatform.system == stdenv.hostPlatform.system;

stdenv.mkDerivation {
  pname = "libcurl";
  version = "8.22.0";

  inherit src;

  strictDeps = true;
  dontPatch = true;

  # Let installPhase run the single `zig build install` command.
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ zig ] ++ lib.optional isElfTarget patchelf;

  # Propagate the C runtime required by the vendored C library.
  propagatedBuildInputs = [ stdenv.cc.libc ];

  doCheck = false;
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Keep Zig caches under TMPDIR and outside the unpacked source tree.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    mkdir -p "$ZIG_GLOBAL_CACHE_DIR/p"
    cp -r --no-preserve=mode ${mbedTlsSrc} "$ZIG_GLOBAL_CACHE_DIR/p/mbed_tls-3.6.7-SuSKykiIhQBFmMDGAXrRs_TsxGbaITJHF8VDaj5Qx1LI"

    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      ${lib.optionalString (requestedLinkage != "") "-Dlinkage=${requestedLinkage}"}

    # Remove temporary Zig cache paths while preserving dependency and `$ORIGIN` rpaths.
    # Resolve soname symlinks before rewriting the ELF object.
    ${lib.optionalString isElfTarget ''
      for elf in "$out"/lib/*.so*; do
        [ -f "$elf" ] || continue
        elf=$(readlink -f "$elf")
        rpath=$(patchelf --print-rpath "$elf") || rpath=""
        kept=""
        rest=$rpath
        while [ -n "$rest" ]; do
          entry="''${rest%%:*}"
          case "$entry" in
            "$TMPDIR"/*) ;;
            *) if [ -z "$kept" ]; then kept=$entry; else kept=$kept:$entry; fi ;;
          esac
          if [ "$entry" = "$rest" ]; then rest=""; else rest="''${rest#*:}"; fi
        done
        [ "$kept" = "$rpath" ] || patchelf --set-rpath "$kept" "$elf"
      done
    ''}

    runHook postInstall
  '';


  enableParallelBuilding = true;

  meta = {
    description = "libcurl, the client-side transfer library, built from the curl 8.22.0 release sources";
    longDescription = ''
      The complete libcurl library of the curl 8.22.0 release -- the whole
      196-unit compile closure of `lib/Makefile.inc`, the public headers of
      `include/curl/` and upstream's licence, README and release notes --
      compiled from this repository with Zig, with no autotools, no CMake and
      no build-time download, and with mbed-TLS as its TLS backend resolved
      through the standard Zig dependency mechanism. Ships the static archive or
      the shared object, the public headers, a pkg-config file and the licence
      and provenance records.
    '';

    # The SPDX identifier and grant file come from the upstream package.
    license = "curl";
    licenseFile = "COPYING";
    platforms = lib.platforms.unix;
  };
}