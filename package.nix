# Source-only package derivation for the libcurl SDK.
#
# One file, consumed by both flake.nix and devenv.nix, so the two entry points
# cannot describe different packages. It builds nothing but this repository: the
# native source is the vendored curl 8.22.0 libcurl library closure -- every
# C unit of the 196-unit compile closure read out of `lib/Makefile.inc:439-446`,
# every public header of `include/curl/`, upstream's `COPYING`, `README` and
# `RELEASE-NOTES` -- and build.zig owns every compile flag, the generated
# `curl_config.h`, the pkg-config file and the whole installed layout. Nothing
# here restates a C flag, names a source file, copies a header, writes a `.pc`
# or fetches a tarball.
#
# curl ships three upstream build systems inside the vendored tree -- autotools
# (`lib/Makefile.am`, `lib/Makefile.in`), CMake (`lib/CMakeLists.txt`) and the
# hand-written `lib/Makefile.inc` -- and `configure`/`CMakeLists.txt` at the top
# level are deliberately *not* vendored, because the compile closure does not
# touch anything outside `lib/`, `include/`, the generated config header and the
# system C library. None of the three is executed here, and no system-installed
# libcurl, mbed-TLS or pkg-config can stand in for a source result: the one
# command in installPhase below is the same `zig build` this package runs
# everywhere else, and a second C recipe would be a second set of facts with no
# gate that could keep the two in agreement.
#
# No lock file is written here. `flake.lock` and `devenv.lock` belong to the
# driver.
#
# SPDX-License-Identifier: curl
# See FORK-LICENSE.md for what that identifier covers, and NOTICE.md for the
# per-file inventory; the upstream grant itself is `COPYING`, shipped verbatim.
# The pin this derivation builds from is curl 8.22.0, read out of the vendored
# tree rather than restated from a release announcement: `include/curl/curlver.h:35`
# is `#define LIBCURL_VERSION "8.22.0"`, `:39-41` are major 8 / minor 22 /
# patch 0, and `:60` is `LIBCURL_VERSION_NUM 0x081600`. The `version` attribute
# below is that same string, and this is where it is checked: `UPSTREAM.sha256`
# holds 418 SHA-256 records covering every vendored file, `COPYING` among them,
# and `UPSTREAM.md` is where the import itself is recorded -- an upstream release
# tarball, imported whole, with no VCS revision, because the artifact has no
# version control and therefore no commit to name. `UPSTREAM.md` is the
# provenance owner's file and was not on disk when this was written, so nothing
# below depends on its contents.
#

{ lib
, stdenv
, zig
, patchelf
  # Zig's own `std.builtin.LinkMode` spelling, passed straight through as
  # `-Dlinkage`. "static" and "dynamic" are two variants of one derivation, and
  # `""` passes nothing at all so the SDK's own default policy runs unchanged.
  # Upstream builds both: `lib/Makefile.inc` drives a static archive, and the
  # shared object is what `lib/Makefile.soname` and `lib/libcurl.vers.in` exist
  # for, so neither variant is the odd one out here.
, linkage ? "static"
, optimize ? "ReleaseSafe"
}:

let
  requestedLinkage =
    if builtins.elem linkage [ "" "static" "dynamic" ] then linkage
    else throw "package.nix: linkage must be \"\", \"static\" or \"dynamic\", not ${toString linkage}";

# PENDING-VERIFICATION -- the sibling dependency.
#
# `build.zig.zon` declares exactly one dependency and it is a *relative path*,
# `.{ .path = "../mbed-tls" }`, so `zig build` resolves it against the directory
# that holds this package. The source that reaches the derivation therefore has
# to contain `mbed-tls/` beside `libcurl/`, or the build cannot configure at
# all: there is no vendored copy of mbed-TLS, no fork-private bridge and no
# fallback. A `lib.fileset.unions` of the two directories, rooted at the shared
# parent, is the mechanism that produces exactly that shape -- and because it
# names both paths, nothing else in this workspace can ride along into the store
# copy the way a whole-parent source filter would let it.
#
# `mbed-tls/` was not on disk when this file was written: the sibling package
# has not landed. Naming the path anyway is deliberate, because it makes the
# failure honest -- this derivation cannot evaluate while the sibling is
# missing, and the reason printed is the absent directory, not a libcurl that
# quietly has no TLS backend. The alternatives were considered and rejected on
# the record: `lib.fileset.maybeMissing` would let the package configure and
# then fail (or, worse, succeed without TLS), which the package contract
# forbids outright; `pkgs.mbedtls` would be a system-installed default standing
# in for a source result; `fetchurl` would be a build-time download.
#
# What the driver still has to wire, and this file cannot do for it: the
# `mbed-tls/` package itself, whose build graph must expose the module
# `dep.module("mbedtls")` and the three separate artifacts `mbedtls`,
# `mbedx509` and `mbedcrypto` that `build.zig` links, in that order. Until it
# does, every gate that configures this package is expected to fail here, and
# that failure is the receipt -- not a defect in this file.

  # Everything except build outputs, version control and developer-tool state.
  # Filtering by directory name rather than by an allow list means a file added
  # here later is packaged without editing this file, while `.zig-cache/`,
  # `zig-out/`, `zig-pkg/`, `.devenv/`, `.direnv/` and `result` stay out of a
  # published input at any depth, including under `consumer/`. The vendored
  # upstream build-system files -- `lib/Makefile.am`, `lib/Makefile.in`,
  # `lib/Makefile.inc`, `lib/Makefile.soname`, `lib/CMakeLists.txt`,
  # `lib/curl_config.h.in`, `lib/curl_config-cmake.h.in`, `lib/libcurl.def`,
  # `lib/libcurl.rc`, `lib/libcurl.vers.in`, `lib/optiontable.pl` and the two
  # under `include/curl/` and `include/` -- are deliberately kept: they are
  # upstream material with digests in UPSTREAM.sha256, the audit surface is the
  # whole upstream tree, and no name in the filter below matches any of them.
  src = lib.cleanSourceWith {
    name = "libcurl-source";
    src = lib.fileset.toSource {
      root = ../.;
      fileset = lib.fileset.unions [
        (lib.fileset.directory ./.)
        (lib.fileset.directory ../mbed-tls)
      ];
    };
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

# patchelf rewrites ELF rpaths and does not read Mach-O, so the rpath
# normalisation in the install phase exists for ELF targets only, and the tool is
# a build input exactly where that code runs.
isElfTarget = !stdenv.hostPlatform.isDarwin;
in

# These packages build for the compiler's own native target. A cross build here
# would mean hand-building a libc-suffixed triple that has to track nixpkgs, so
# this derivation refuses one instead of silently producing a host-architecture
# library under a foreign name. The comparison is against stdenv's own
# platforms, which are pure values; `builtins.currentSystem` is not evaluable
# in a sandbox and is not used. A remote builder is unaffected: this compares
# build against host, not against any particular machine.
assert stdenv.buildPlatform.system == stdenv.hostPlatform.system;

stdenv.mkDerivation {
  pname = "libcurl";
  version = "8.22.0";

  inherit src;

  strictDeps = true;
  dontPatch = true;

  # The real work is one `zig build install` in installPhase below. Disabling
  # the configure and build phases keeps the Zig setup hook from running a
  # first, differently-flagged build of its own; `dontInstall` is deliberately
  # NOT set, because that is what would disable the real install phase.
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ zig ] ++ lib.optional isElfTarget patchelf;

  # The whole of the native dependency closure, and it is worth stating exactly
  # what it is rather than what a transfer library is usually assumed to need.
  #
  # No file in the vendored closure calls `dlopen` or `LoadLibrary`; the tree
  # carries `HAVE_DLFCN_H` as a config macro (`lib/curl_config.h.in:231-232`)
  # and nothing that consumes it. Threads are a different matter:
  # `lib/curl_setup.h:219-221` includes `<pthread.h>` under
  # `HAVE_THREADS_POSIX`, `:678-680` turns that macro into `USE_MUTEX`, and
  # `lib/curl_threads.h:43-46` and `lib/easy_lock.h:88-91` make `curl_mutex_t`
  # and `curl_simple_lock` `pthread_mutex_t` -- with `lib/curl_threads.c:132-133`
  # refusing to compile at all when neither `HAVE_THREADS_POSIX` nor `_WIN32` is
  # defined. So a target whose generated config selects POSIX threads links
  # pthreads. Which targets select them is
  # `build_support/curl_config_gen.c`'s decision, and that is the build owner's
  # file, which this owner did not read; on a libc that carries pthreads inside
  # it the single input below covers both cases, and a target that would need a
  # separate `-lpthread` has to have that named by the owner who generates the
  # config, not guessed here.
  #
  # Sockets (`lib/curl_setup.h:879-881`), name resolution and `unistd.h` are all
  # the C library. mbed-TLS is deliberately not a nix input: it is compiled from
  # the sibling tree in `src` by the same `zig build`, through the
  # `b.dependency` the manifest declares, so there is no separate
  # `pkgs.mbedtls` to propagate and no possibility of a system TLS backend
  # taking its place.
  propagatedBuildInputs = [ stdenv.cc.libc ];

  # The driver owns every gate for this SDK, and a Nix build is not a
  # verification receipt. No check phase is declared here rather than a check
  # phase that runs something smaller than the real gates; the commands that do
  # verify this package are in README.md and CHANGELOG.md.
  doCheck = false;
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Both caches go under the Nix-provided TMPDIR, outside the unpacked source
    # tree, so a build cannot write into $src and so two parallel derivations
    # cannot share state. Any caller-supplied cache variables are left alone:
    # they are the caller's scratch, not this file's to clear.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"

    # build.zig owns the 196-unit source list, the C flags, the USE_MBEDTLS
    # selection, the generated curl_config.h, the pkg-config file and every
    # installed path. Declaring any of them here as well would create a second
    # place where they can disagree with the build graph. No `-Dtls` is passed:
    # the default resolves the `.dependencies` entry, and a package that named
    # an override here could silently build against something other than the
    # sibling this derivation ships.
    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      ${lib.optionalString (requestedLinkage != "") "-Dlinkage=${requestedLinkage}"}

    # Zig records the build cache in the rpath of anything that links a dynamic
    # artifact it has just built, so an installed object names a directory that
    # is gone, and Nix rejects an installed file that names its build directory
    # at all. The dynamic variant is exactly that case here: it links the three
    # mbed-TLS artifacts the sibling build graph just produced. Both Zig caches
    # above are under $TMPDIR, so dropping those entries and no other removes
    # it: the $ORIGIN/../lib an install adds, and every store path a real
    # dependency needs, stay. Symlinks are resolved first so a soname link is
    # rewritten through to the object and never replaced by a copy of it.
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

  # The layout this derivation produces is the build graph's, not this file's.
  # build.zig is another owner's file and this owner has not read it, so what
  # follows is the delivery this package is required to make -- the library
  # artifact for the selected linkage, the public headers, the pkg-config file
  # and the licence records -- stated as a requirement and not as an
  # observation. PENDING-VERIFICATION until the driver's `zig build install`
  # receipt says which paths it actually wrote:
  #
  #   $out/lib/libcurl.a          (`-Dlinkage=static`, the default)
  #   $out/lib/libcurl.so*        (`-Dlinkage=dynamic`)
  #   $out/include/curl/*.h       the public headers
  #   $out/lib/pkgconfig/libcurl.pc
  #   $out/share/licenses/libcurl/  COPYING, NOTICE.md, FORK-LICENSE.md,
  #                                 UPSTREAM.md
  #
  # On the header set, one upstream fact is on the record and is the natural
  # reference for what a libcurl install ships: `include/curl/Makefile.am:24-26`
  # lists twelve names in `pkginclude_HEADERS` -- curl.h, curlver.h, easy.h,
  # mprintf.h, stdcheaders.h, multi.h, typecheck-gcc.h, system.h, urlapi.h,
  # options.h, header.h, websockets.h. `include/curl/` also holds that
  # Makefile, a generated `Makefile.in` and a README that upstream does not
  # install, so "every file in include/curl/" is not the answer.
  #
  # The shared object's file name and its SONAME are not stated here on
  # purpose. `lib/Makefile.soname:26` says to keep the SONAME in sync with
  # `CURL_LIBCURL_VERSIONED_SYMBOLS_SONAME`, which lives in `configure.ac` --
  # a file this package does not vendor -- so the value upstream would install
  # was not observed and is not invented. The runtime route's `LoadSource.system`
  # takes a bare name, so whatever `build.zig` installs has to be a name a
  # `dlopen` can be given; that is a requirement on the build graph, and
  # checking it is the driver's job.
  #
  # Both variants keep the layout; only the artifact kind differs. Nothing is
  # copied or generated by hand here, so `zig build install --prefix $out` and
  # `nix build` produce one layout by construction rather than two that have to
  # be kept in agreement.

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

    # SPDX `curl`, the identifier every file in the vendored tree carries
    # (`include/curl/curlver.h:23`, `lib/Makefile.soname:21`,
    # `lib/curl_config-cmake.h.in:21`) and the one this fork's own files use.
    # It is spelled as a string rather than taken from `lib.licenses`, because
    # no attribute for it was read from the pinned nixpkgs and picking one by
    # memory is exactly the kind of guess this workspace does not keep. curl's
    # term is a permissive MIT derivative; the identifier that says so is the
    # one upstream wrote in its own files. `COPYING` is the verbatim grant
    # (1088 bytes, sha256 recorded in UPSTREAM.sha256) and `NOTICE.md` is the
    # per-file inventory.
    license = "curl";
    licenseFile = "COPYING";
    platforms = lib.platforms.unix;
  };
}