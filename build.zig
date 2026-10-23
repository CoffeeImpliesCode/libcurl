// SPDX-License-Identifier: curl
// See FORK-LICENSE.md for what that identifier covers.
//! Builds libcurl 8.22.0 with Zig 0.17.0 from upstream C sources.
//! A host generator creates target-specific `curl_config.h` for C and translate-c.
//! mbed-TLS is mandatory; unsupported targets are refused at configure time.
const std = @import("std");

const manifest = @import("build.zig.zon");

/// Parse the manifest release version; invalid semantic versions stop configuration.
const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon: .version is not a semantic version");

/// Release version from `include/curl/curlver.h:35`; the manifest and pkg-config version must match.
/// The shared-library ABI version is separate.
const upstream_version: std.SemanticVersion = .{ .major = 8, .minor = 22, .patch = 0 };

/// Upstream release string used in generated headers and pkg-config.
const upstream_version_string = "8.22.0";

/// Shared-library ABI version 4.8.0 from upstream's libtool triplet (`lib/Makefile.soname:26-28`).
/// This differs from the 8.22.0 release version.
const abi_version: std.SemanticVersion = .{ .major = 4, .minor = 8, .patch = 0 };

/// ELF symbol-version prefix selected by upstream for the mbed-TLS backend.
const version_script_prefix = "MBEDTLS_";

/// Name exposed to Zig dependents and C linkers; module and artifact are both `libcurl`.
const lib_name = "libcurl";

/// Static link order required by the mbed-TLS archives.
const tls_dependency_name = "mbed-tls";
const tls_artifacts = [_][]const u8{ "mbedtls", "mbedx509", "mbedcrypto" };

/// mbed-TLS headers are under the sibling package's `src/include`.
const tls_public_include = "src/include";

/// DES support enables libcurl's NTLM core in the mbed-TLS configuration.
const mbedtls_des_crypt_ecb = "yes";

/// Zig facade source.
const facade_source = "zig/root.zig";

const translate_header = "zig/translate.h";

/// Import name expected by `zig/root.zig` for translated headers.
const translate_import_name = "translate";

/// Import name for the runtime loader core. Keep one module instance so its public types remain nominally identical.
const loader_import_name = "rt";

const test_source = "tests.zig";
const example_source = "smoke.zig";

/// Include roots for upstream C sources and public headers; `curl_setup.h` includes `curl_config.h` by name (`lib/curl_setup.h:140`).
const source_dir = "lib";
const public_include_dir = "include";

/// Generated header included by name from `lib/curl_setup.h:140`.
const config_generator_source = "build_support/curl_config_gen.c";
const config_header_name = "curl_config.h";

/// Target-compiled header probe supplies `--header-facts` to the generator.
const header_probe_source = "build_support/curl_headers_probe.c";

/// Host collector compiles function and member probes for the target.
/// Its facts file supplies `--function-facts` and `--member-facts`.
const function_probe_source = "build_support/curl_existence_probe.c";

/// The collector output is a tracked build-graph input to the generator.
const function_facts_name = "curl_function_facts.txt";

/// Explicit upstream `CSOURCES` list (`lib/Makefile.inc:439-441`); avoid compiling unrelated files by glob.
const curlx_sources = [_][]const u8{
    // LIB_CURLX_CFILES, lib/Makefile.inc:26-45, entries at :27-45. 19 units.
    "lib/curlx/base64.c",
    "lib/curlx/basename.c",
    "lib/curlx/dynbuf.c",
    "lib/curlx/fopen.c",
    "lib/curlx/inet_ntop.c",
    "lib/curlx/inet_pton.c",
    "lib/curlx/multibyte.c",
    "lib/curlx/nonblock.c",
    "lib/curlx/snprintf.c",
    "lib/curlx/strcopy.c",
    "lib/curlx/strdup.c",
    "lib/curlx/strerr.c",
    "lib/curlx/strparse.c",
    "lib/curlx/timediff.c",
    "lib/curlx/timeval.c",
    "lib/curlx/version_win32.c",
    "lib/curlx/wait.c",
    "lib/curlx/warnless.c",
    "lib/curlx/winapi.c",
};

const vauth_sources = [_][]const u8{
    // LIB_VAUTH_CFILES, lib/Makefile.inc:68-81, entries at :69-81. 13 units.
    "lib/vauth/cleartext.c",
    "lib/vauth/cram.c",
    "lib/vauth/digest.c",
    "lib/vauth/digest_sspi.c",
    "lib/vauth/gsasl.c",
    "lib/vauth/krb5_gssapi.c",
    "lib/vauth/krb5_sspi.c",
    "lib/vauth/ntlm.c",
    "lib/vauth/ntlm_sspi.c",
    "lib/vauth/oauth2.c",
    "lib/vauth/spnego_gssapi.c",
    "lib/vauth/spnego_sspi.c",
    "lib/vauth/vauth.c",
};

const vdns_sources = [_][]const u8{
    // LIB_VDNS_CFILES, lib/Makefile.inc:87-97, entries at :88-97. 10 units.
    "lib/vdns/asyn-ares.c",
    "lib/vdns/asyn-base.c",
    "lib/vdns/asyn-thrdd.c",
    "lib/vdns/cf-dns.c",
    "lib/vdns/dnscache.c",
    "lib/vdns/doh.c",
    "lib/vdns/hostip.c",
    "lib/vdns/hostip4.c",
    "lib/vdns/hostip6.c",
    "lib/vdns/httpsrr.c",
};

const vtls_sources = [_][]const u8{
    // LIB_VTLS_CFILES, lib/Makefile.inc:107-123, entries at :108-123. 16 units.
    // Only `mbedtls.c` has an active body in this TLS source group.
    "lib/vtls/apple.c",
    "lib/vtls/cipher_suite.c",
    "lib/vtls/gtls.c",
    "lib/vtls/hostcheck.c",
    "lib/vtls/keylog.c",
    "lib/vtls/mbedtls.c",
    "lib/vtls/openssl.c",
    "lib/vtls/rustls.c",
    "lib/vtls/schannel.c",
    "lib/vtls/schannel_verify.c",
    "lib/vtls/vtls.c",
    "lib/vtls/vtls_config.c",
    "lib/vtls/vtls_scache.c",
    "lib/vtls/vtls_spack.c",
    "lib/vtls/wolfssl.c",
    "lib/vtls/x509asn1.c",
};

const vquic_sources = [_][]const u8{
    // LIB_VQUIC_CFILES, lib/Makefile.inc:144-152, entries at :145-152. 8 units.
    "lib/vquic/capsule.c",
    "lib/vquic/cf-capsule.c",
    "lib/vquic/cf-ngtcp2.c",
    "lib/vquic/cf-ngtcp2-cmn.c",
    "lib/vquic/cf-ngtcp2-proxy.c",
    "lib/vquic/cf-quiche.c",
    "lib/vquic/vquic.c",
    "lib/vquic/vquic-tls.c",
};

const vssh_sources = [_][]const u8{
    // LIB_VSSH_CFILES, lib/Makefile.inc:165-168, entries at :166-168. 3 units.
    "lib/vssh/libssh.c",
    "lib/vssh/libssh2.c",
    "lib/vssh/vssh.c",
};

const core_sources = [_][]const u8{
    // LIB_CFILES, lib/Makefile.inc:174-301, entries at :175-301. 127 units.
    "lib/altsvc.c",
    "lib/amigaos.c",
    "lib/api.c",
    "lib/bufq.c",
    "lib/bufref.c",
    "lib/cf-h1-proxy.c",
    "lib/cf-h2-proxy.c",
    "lib/cf-haproxy.c",
    "lib/cf-https-connect.c",
    "lib/cf-ip-happy.c",
    "lib/cf-recvbuf.c",
    "lib/cf-setup.c",
    "lib/cf-socket.c",
    "lib/cfilters.c",
    "lib/conncache.c",
    "lib/connect.c",
    "lib/content_encoding.c",
    "lib/cookie.c",
    "lib/creds.c",
    "lib/cshutdn.c",
    "lib/curl_addrinfo.c",
    "lib/curl_endian.c",
    "lib/curl_fnmatch.c",
    "lib/curl_fopen.c",
    "lib/curl_get_line.c",
    "lib/curl_gethostname.c",
    "lib/curl_gssapi.c",
    "lib/curl_memrchr.c",
    "lib/curl_ntlm_core.c",
    "lib/curl_range.c",
    "lib/curl_sasl.c",
    "lib/curl_sha512_256.c",
    "lib/curl_share.c",
    "lib/curl_sspi.c",
    "lib/curl_threads.c",
    "lib/curl_trc.c",
    "lib/cw-out.c",
    "lib/cw-pause.c",
    "lib/dict.c",
    "lib/dynhds.c",
    "lib/easy.c",
    "lib/easygetopt.c",
    "lib/easyoptions.c",
    "lib/escape.c",
    "lib/fake_addrinfo.c",
    "lib/file.c",
    "lib/fileinfo.c",
    "lib/formdata.c",
    "lib/ftp.c",
    "lib/ftplistparser.c",
    "lib/getenv.c",
    "lib/getinfo.c",
    "lib/gopher.c",
    "lib/hash.c",
    "lib/headers.c",
    "lib/hmac.c",
    "lib/hsts.c",
    "lib/http.c",
    "lib/http1.c",
    "lib/http2.c",
    "lib/http_aws_sigv4.c",
    "lib/http_httpsig.c",
    "lib/curl_ed25519.c",
    "lib/http_chunks.c",
    "lib/http_digest.c",
    "lib/http_negotiate.c",
    "lib/http_ntlm.c",
    "lib/http_proxy.c",
    "lib/idn.c",
    "lib/if2ip.c",
    "lib/imap.c",
    "lib/ldap.c",
    "lib/llist.c",
    "lib/macos.c",
    "lib/md4.c",
    "lib/md5.c",
    "lib/memdebug.c",
    "lib/mime.c",
    "lib/mprintf.c",
    "lib/mqtt.c",
    "lib/multi.c",
    "lib/multi_ev.c",
    "lib/multi_ntfy.c",
    "lib/netrc.c",
    "lib/openldap.c",
    "lib/parsedate.c",
    "lib/peer.c",
    "lib/pingpong.c",
    "lib/pop3.c",
    "lib/progress.c",
    "lib/protocol.c",
    "lib/proxy.c",
    "lib/psl.c",
    "lib/rand.c",
    "lib/ratelimit.c",
    "lib/request.c",
    "lib/rtsp.c",
    "lib/select.c",
    "lib/sendf.c",
    "lib/setopt.c",
    "lib/sha256.c",
    "lib/slist.c",
    "lib/smb.c",
    "lib/smtp.c",
    "lib/socketpair.c",
    "lib/socks.c",
    "lib/socks_gssapi.c",
    "lib/socks_sspi.c",
    "lib/splay.c",
    "lib/strcase.c",
    "lib/strequal.c",
    "lib/strerror.c",
    "lib/system_win32.c",
    "lib/telnet.c",
    "lib/tftp.c",
    "lib/thrdpool.c",
    "lib/thrdqueue.c",
    "lib/transfer.c",
    "lib/uint-bset.c",
    "lib/uint-hash.c",
    "lib/uint-hashset.c",
    "lib/uint-spbset.c",
    "lib/uint-table.c",
    "lib/url.c",
    "lib/urlapi.c",
    "lib/version.c",
    "lib/ws.c",
};

/// Full upstream `CSOURCES` closure, in makefile order (`lib/Makefile.inc:439-441`).
const curl_sources = blk: {
    var all: [core_sources.len + vauth_sources.len + vdns_sources.len +
        vtls_sources.len + vquic_sources.len + vssh_sources.len +
        curlx_sources.len][]const u8 = undefined;
    var n: usize = 0;
    for ([_][]const []const u8{
        core_sources[0..],
        vauth_sources[0..],
        vdns_sources[0..],
        vtls_sources[0..],
        vquic_sources[0..],
        vssh_sources[0..],
        curlx_sources[0..],
    }) |group| {
        for (group) |unit| {
            all[n] = unit;
            n += 1;
        }
    }
    break :blk all;
};

const curl_source_count = curl_sources.len;

/// Public headers installed by upstream (`include/curl/Makefile.am:24-26`).
const public_headers = [_][]const u8{
    "curl.h",
    "curlver.h",
    "easy.h",
    "mprintf.h",
    "stdcheaders.h",
    "multi.h",
    "typecheck-gcc.h",
    "system.h",
    "urlapi.h",
    "options.h",
    "header.h",
    "websockets.h",
};

/// Licence and provenance records installed under `share/licenses/libcurl/`.
const licence_records = [_][]const u8{
    "COPYING",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
    "UPSTREAM.sha256",
    "README",
    "RELEASE-NOTES",
    "CHANGELOG.md",
    "FORK-NOTES.md",
};

/// Compile upstream's C as `gnu99`; strict `c99` hides POSIX/GNU declarations used by the sources.
/// In particular, glibc hides `gethostname`, `strerror_r`, `explicit_bzero`, and `fseeko` in strict mode.
const c_flags = [_][]const u8{"-std=gnu99"};

/// Compile the host collector with C11 and pass one flag string to each target probe.
/// Target probes use the library's `gnu99` dialect so feature-test macros match.
const collector_flags = [_][]const u8{
    "-std=c11",
    "-Wall",
    "-Wextra",
    "-Wpedantic",
};
const probe_flags_arg = "-std=gnu99";

const generator_flags = [_][]const u8{
    "-std=c11",
    "-Wall",
    "-Wextra",
    "-Wpedantic",
};

const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
};

/// WASI is refused because mbed-TLS requires network APIs the target lacks.
/// `checkMatrixPartition` keeps this refusal explicit.
const refused_check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

const Graph = struct {
    /// C library output; this package has no system-library mode.
    c_lib: *std.Build.Step.Compile,
    /// Facade module.
    module: *std.Build.Module,
};

/// Map a target to the libc name expected by the generator; ABI names are not libc names.
/// Reject unknown Linux ABIs instead of guessing.
fn generatorLibc(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.os.tag) {
        // glibc and musl expose different feature-test macros.
        .linux => switch (target.result.abi) {
            .gnu, .gnuabin32, .gnuabi64, .gnux32, .gnueabi, .gnueabihf => "gnu",
            .musl, .musleabi, .musleabihf, .muslabi64 => "musl",
            else => std.debug.panic(
                "libcurl: no --libc value for OS {s} with ABI {s}. " ++
                    "curl_config_gen.c's Linux family has exactly two answers - gnu " ++
                    "and musl - because HAVE_GLIBC_STRERROR_R and " ++
                    "HAVE_POSIX_STRERROR_R are mutually exclusive and " ++
                    "lib/strerror.c reaches them through whichever the platform " ++
                    "has. Add the ABI to generatorLibc.",
                .{ @tagName(target.result.os.tag), @tagName(target.result.abi) },
            ),
        },
        // macOS-family targets, including Mac Catalyst, use libSystem.
        .macos, .ios, .tvos, .watchos, .visionos, .maccatalyst => "darwin",
        // Select mingw or msvcrt from the Windows ABI.
        .windows => switch (target.result.abi) {
            .msvc => "msvcrt",
            else => "mingw",
        },
        // BSD targets use the generator's BSD configuration row.
        .freebsd, .netbsd, .openbsd, .dragonfly => "bsd",
        else => "sysv",
    };
}

/// Map each architecture to the generator's supported pointer width.
/// The exhaustive switch rejects new tags; only 32- and 64-bit widths are supported.
fn pointerWidthBits(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.cpu.arch) {
        .aarch64, .aarch64_be, .alpha, .amdgcn, .bpfeb, .bpfel, .hppa64, .kvx,
        .loongarch64, .mips64, .mips64el, .nvptx, .nvptx64, .powerpc64,
        .powerpc64le, .riscv64, .riscv64be, .s390x, .sparc64, .spirv64, .ve,
        .wasm64, .x86_64,
        => "64",

        // Endianness does not change pointer width.
        .arc, .arceb, .arm, .armeb, .csky, .hexagon, .hppa, .kalimba, .lanai,
        .loongarch32, .m68k, .m88k, .microblaze, .microblazeel, .mips, .mipsel,
        .or1k, .powerpc, .powerpcle, .propeller, .riscv32, .riscv32be, .sh,
        .sheb, .sparc, .spirv32, .thumb, .thumbeb, .wasm32, .x86, .xcore,
        .xtensa, .xtensaeb,
        => "32",

        // Refuse architectures whose pointer width the generator cannot express.
        .avr, .ez80, .msp430, .spork8, .x86_16,
        => std.debug.panic("libcurl: no --pointer-width for architecture {s}. " ++
            "curl_config_gen.c derives SIZEOF_SIZE_T, SIZEOF_LONG, SIZEOF_OFF_T, " ++
            "SIZEOF_CURL_SOCKET_T and SIZEOF_TIME_T from --pointer-width, which " ++
            "accepts 32 and 64 only; this architecture's pointer width is not " ++
            "representable. lib/curl_setup.h:630-632 rejects a configuration where long " ++
            "exceeds size_t, so any other width here would be a guess that fails " ++
            "as a compile error rather than as a refusal.", .{
            @tagName(target.result.cpu.arch),
        }),
    };
}

/// Probe target headers and return the `--header-facts` file.
/// Compile for the target and omit package include paths so only target headers answer.
/// The output is a tracked build-graph input to `curl_config_gen.c`.
fn addHeaderProbe(b: *std.Build, target: std.Build.ResolvedTarget) std.Build.LazyPath {
    const triple = target.result.zigTriple(b.allocator) catch
        @panic("libcurl: the header probe needs a target triple it can spell");

    const probe = b.addSystemCommand(&.{ b.graph.zig_exe, "cc" });
    probe.setName(b.fmt("probe target headers for {s}", .{triple}));
    probe.addArg("-target");
    probe.addArg(triple);
    for (c_flags) |flag| probe.addArg(flag);
    probe.addArg("-E"); // preprocess only: the probe is asked, never run
    probe.addFileArg(b.path(header_probe_source));
    // Use a tracked output file so the generator can consume the probe results.
    probe.addArg("-o");
    return probe.addOutputFileArg("curl_header_facts.txt");
}

/// Run a host collector that compiles function and member probes for the target.
/// It records missing declarations as `no`, because that is a configuration fact.
/// The returned facts file is consumed by `curl_config_gen.c`.
fn addFunctionProbe(b: *std.Build, target: std.Build.ResolvedTarget) std.Build.LazyPath {
    const triple = target.result.zigTriple(b.allocator) catch
        @panic("libcurl: the existence probe needs a target triple it can spell");

    const module = b.createModule(.{
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        // The host collector uses libc for process and file operations.
        .link_libc = true,
    });
    module.addCSourceFiles(.{
        .files = &.{function_probe_source},
        .flags = &collector_flags,
    });
    // Select the collector translation unit before creating its compile step.
    module.addCMacro("CURL_EXISTENCE_COLLECTOR", "1");
    const collector = b.addExecutable(.{
        .name = b.fmt("{s}-existence-probe-host", .{lib_name}),
        .root_module = module,
    });

    const run = b.addRunArtifact(collector);
    run.setName(b.fmt("probe target functions and members for {s}", .{triple}));
    run.addArg(b.graph.zig_exe);
    run.addArg(triple);
    // Match libcurl's `gnu99` feature-test environment in target probes.
    run.addArg(probe_flags_arg);
    // Pass the same libc name as the generator; glibc and musl expose different declarations.
    run.addArg(generatorLibc(target));
    // The facts file is a tracked output; scratch files share its directory.
    return run.addOutputFileArg(function_facts_name);
}

/// Build the host config generator for one target and return its generated `curl_config.h`.
/// It receives target facts and probe outputs as build-graph inputs.
/// The returned LazyPath keeps generation ordered before its consumers.
fn addGeneratedConfig(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    ca_bundle: ?[]const u8,
    ca_path: ?[]const u8,
) std.Build.LazyPath {
    const generator_module = b.createModule(.{
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        // The host generator uses libc for file and string operations.
        .link_libc = true,
    });
    generator_module.addCSourceFiles(.{
        .files = &.{config_generator_source},
        .flags = &generator_flags,
    });
    const generator = b.addExecutable(.{
        .name = b.fmt("{s}-config-gen-host", .{lib_name}),
        .root_module = generator_module,
    });

    const run = b.addRunArtifact(generator);

    run.addArg("--os");
    run.addArg(@tagName(target.result.os.tag));
    run.addArg("--arch");
    run.addArg(@tagName(target.result.cpu.arch));
    run.addArg("--pointer-width");
    run.addArg(pointerWidthBits(target));
    // Spell target byte order as the generator expects: `little` or `big`.
    run.addArg("--endian");
    run.addArg(@tagName(target.result.cpu.arch.endian()));
    run.addArg("--libc");
    run.addArg(generatorLibc(target));
    run.addArg("--mbedtls-des-crypt-ecb");
    run.addArg(mbedtls_des_crypt_ecb);
    // Header facts are a required tracked input, so generation waits for the target probe.
    run.addArg("--header-facts");
    run.addFileArg2(addHeaderProbe(b, target), .{});
    // One tracked collector output supplies both function and member facts.
    const existence_facts = addFunctionProbe(b, target);
    run.addArg("--function-facts");
    run.addFileArg2(existence_facts, .{});
    run.addArg("--member-facts");
    run.addFileArg2(existence_facts, .{});
    run.addArg("--curl-version");
    run.addArg(upstream_version_string);
    // Unset CA options omit the generated rows read by curl (`lib/getinfo.c:161-169`).
    if (ca_bundle) |value| {
        run.addArg("--ca-bundle");
        run.addArg(value);
    }
    if (ca_path) |value| {
        run.addArg("--ca-path");
        run.addArg(value);
    }
    run.addArg("--output");
    return run.addOutputFileArg(config_header_name);
}

/// Build one target's C library and facade.
/// Matrix checks use private modules because module names are unique per build.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    linkage: std.lang.LinkMode,
    runtime_loaded: bool,
    ca_bundle: ?[]const u8,
    ca_path: ?[]const u8,
    public: bool,
) Graph {
    // Refuse unsupported OS targets before creating build steps.
    if (refusalFor(target.result.os.tag) != null) refuseTarget(b, target);

    const config_header = addGeneratedConfig(b, target, ca_bundle, ca_path);
    // Include the generated header's directory; `curl_setup.h` includes it by name (`lib/curl_setup.h:140`).
    const config_dir = config_header.dirname();

    // Resolve TLS once so its headers and archives use the same dependency.
    const tls = resolveTls(b, target, optimize);

    const c_lib = add_c_library(b, target, optimize, linkage, config_dir, tls, artifactName(b, target, public));

    // Translate headers with the same target and config as the C archive to preserve ABI agreement.
    const translate = b.addTranslateC(.{
        .root_source_file = b.path(translate_header),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // Translation needs public, internal, and generated-header include roots.
    translate.addIncludePath(b.path(public_include_dir));
    translate.addIncludePath(b.path(source_dir));
    translate.addIncludePath(config_dir);
    // Match `USE_MBEDTLS` and `BUILDING_LIBCURL` to C compilation; translation must describe the library.
    translate.defineCMacro("USE_MBEDTLS", "1");
    translate.defineCMacro("BUILDING_LIBCURL", "1");
    // Set `CURL_STATICLIB` only for archives; curl.h uses it to control DLL exports (`include/curl/curl.h:124`).
    if (deliveredLinkage(target, linkage) == .static) {
        translate.defineCMacro("CURL_STATICLIB", "1");
    }

    const module = if (public)
        b.addModule(lib_name, .{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            // Both facade modes use libc; runtime loading needs `dlopen`.
            .link_libc = true,
        });

    // Runtime dispatch and the facade share one core module so their public types remain nominally identical.
    // Delivery linkage is independent; runtime mode does not link the provider into the facade.
    if (runtime_loaded) {
        // Runtime-loaded mode must not link libcurl or mbed-TLS archives into the facade.
        module.addImport(translate_import_name, graph.createModule(b, translate, target, optimize));
    } else {
        // Keep translated declarations private; dependents import only the libcurl facade.
        module.addImport(translate_import_name, translate.createModule());
        module.addImport(loader_import_name, graph.createCoreModule(b, target, optimize));
        // Linking through this module propagates libcurl and TLS archives to dependents.
        module.linkLibrary(c_lib);
    }

    // Public modules expose the source headers needed by dependent C compilation.
    module.addIncludePath(b.path(public_include_dir));
    module.addIncludePath(b.path(source_dir));

    return .{ .c_lib = c_lib, .module = module };
}

/// Resolve the required mbed-TLS dependency; a missing package stops configuration.
/// Use its source headers and shipped config, not a build-cache output.
fn resolveTls(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
) *std.Build.Dependency {
    return b.dependency(tls_dependency_name, .{
        .target = target,
        .optimize = optimize,
        // Keep mbed-TLS's delivery options independent from libcurl's options.
    });
}

/// Reuse the dependency resolved by `addGraph` for headers and TLS archives.
/// `config_dir` is the generated header's directory, not an unresolved file path.

/// Compile upstream's 196 `CSOURCES` units for one target.
/// Linkage selects the artifact, not a different source closure.
fn add_c_library(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    requested: std.lang.LinkMode,
    config_dir: std.Build.LazyPath,
    tls: *std.Build.Dependency,
    name: []const u8,
) *std.Build.Step.Compile {
    const linkage = deliveredLinkage(target, requested);
    const c_lib = b.addLibrary(.{
        .name = name,
        .linkage = linkage,
        // Static archives have no soname or versioned filename.
        .version = if (linkage == .dynamic) abi_version else null,
        // Use upstream's explicit COFF export list; keep conditional `curl_easy_option_*` symbols enabled.
        .win32_module_definition = if (linkage == .dynamic and target.result.ofmt == .coff)
            b.path("lib/libcurl.def")
        else
            null,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            // The C library uses libc.
            .link_libc = true,
            // Build PIC for every target: non-PIC MIPS calls into musl's PIC `sigsetjmp` without setting `$t9` (`lib/vdns/hostip.c:890`).
            // This also applies to static archives.
            .pic = true,
        }),
    });
    const c_mod = c_lib.root_module;

    // `lib/` contains internal headers and `curl_config.h`, included by name (`lib/curl_setup.h:140`).
    c_mod.addIncludePath(b.path(source_dir));
    // Public curl headers use the `include/` root.
    c_mod.addIncludePath(b.path(public_include_dir));
    // Add the generator's output directory as the third include root.
    c_mod.addIncludePath(config_dir);

    // Generated config, TLS backend, and library-side declarations must match the C compilation.
    // `BUILDING_LIBCURL` also selects internal allocator wrappers (`lib/curl_setup.h:1488-1500`).
    // `CURL_STATICLIB` is set only for archives and controls DLL exports (`include/curl/curl.h:124`).
    c_mod.addCMacro("HAVE_CONFIG_H", "1");
    c_mod.addCMacro("USE_MBEDTLS", "1");
    c_mod.addCMacro("BUILDING_LIBCURL", "1");
    if (linkage == .static) c_mod.addCMacro("CURL_STATICLIB", "1");

    // Unix targets need `-lm`; Darwin and Windows provide these functions through libc.
    // The runtime loader is Zig code, so C does not link `-ldl`.
    if (separateLibm(target.result.os.tag)) c_mod.linkSystemLibrary("m", .{});

    // Windows sources use Winsock, IP Helper, and BCrypt APIs, so link their import libraries.
    // Attach them to `c_mod` so dependent modules inherit them with the TLS archives.
    if (target.result.os.tag == .windows) {
        c_mod.linkSystemLibrary("ws2_32", .{});
        c_mod.linkSystemLibrary("iphlpapi", .{});
        c_mod.linkSystemLibrary("bcrypt", .{});
    }

    // Resolve mbed-TLS headers from the sibling source root at `src/include`.
    // Compile against its shipped config; its generated cache path is not a dependency here.
    c_mod.addIncludePath(tls.path(tls_public_include));
    // Static link order: `mbedtls`, `mbedx509`, then `mbedcrypto`.
    for (tls_artifacts) |artifact| {
        c_mod.linkLibrary(tls.artifact(artifact));
    }

    for (curl_sources[0..]) |source| {
        c_mod.addCSourceFile(.{
            .file = b.path(source),
            .flags = &c_flags,
        });
    }

    if (linkage == .dynamic) setVersionScript(b, c_lib, target);

    // Install upstream's public headers (`include/curl/Makefile.am:24-26`).
    for (public_headers) |header| {
        c_lib.installHeader(
            b.path(b.fmt("{s}/curl/{s}", .{ public_include_dir, header })),
            b.fmt("curl/{s}", .{header}),
        );
    }

    return c_lib;
}

/// Generate the upstream ELF export map from its mbed-TLS prefix and ABI soname.
/// Mach-O has no equivalent version script and its shared object exports internals.
/// COFF uses upstream's `.def` list, which is not versioned.
fn setVersionScript(
    b: *std.Build,
    c_lib: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
) void {
    if (target.result.ofmt != .elf) return;
    const script = b.addWriteFiles().add("libcurl.map", b.fmt(
        \\# Generated by build.zig from upstream's own lib/libcurl.vers.in.
        \\# Node name: lib/CMakeLists.txt:289-290 chooses the prefix
        \\# CURL_LIBCURL_VERSIONED_SYMBOLS_PREFIX = "{s}" for CURL_USE_MBEDTLS,
        \\# and lib/CMakeLists.txt:303 supplies CURL_LIBCURL_VERSIONED_SYMBOLS_SONAME,
        \\# which lib/CMakeLists.txt:271 computes from lib/Makefile.soname:26-28 as
        \\# VERSIONCHANGE - VERSIONDEL.
        \\CURL_{s}{d}
        \\{{
        \\  global: curl_*;
        \\  local: *;
        \\}};
        \\
    , .{ version_script_prefix, version_script_prefix, abi_version.major }));
    c_lib.setVersionScript(script);
}

/// Name public artifacts `libcurl`; give private matrix artifacts their target triple.
fn artifactName(b: *std.Build, target: std.Build.ResolvedTarget, public: bool) []const u8 {
    if (public) return lib_name;
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    return b.fmt("{s}-{s}", .{ lib_name, triple });
}

/// Install pkg-config metadata with paths relative to its location.
/// Put TLS archives in `Libs.private` so static consumers link them.
/// Upstream's `libcurl.pc.in` is not vendored; this file describes this build's artifacts.
fn addPkgConfig(
    b: *std.Build,
    linkage: std.lang.LinkMode,
    separate_m: bool,
) void {
    const files = b.addWriteFiles();
    // Retain the install step so the generated `.pc` file is part of `install`.
    const install_pc = b.addInstallFileWithDir(
        files.add("libcurl.pc", b.fmt(
            \\# libcurl.pc for the libcurl {s} SDK.
            \\#
            \\# Generated by this package's build.zig, addPkgConfig. Upstream ships
            \\# libcurl.pc.in, which this package does not vendor - the closure is
            \\# lib/, include/, COPYING, README and RELEASE-NOTES - so every field
            \\# here is this fork's and names what this build installs.
            \\prefix=${{pcfiledir}}/../..
            \\exec_prefix=${{prefix}}
            \\libdir=${{prefix}}/lib
            \\includedir=${{prefix}}/include
            \\
            \\Name: libcurl
            \\Description: libcurl {s}, with mbed-TLS as its only TLS backend
            \\Version: {s}
            \\
            \\Requires:
            \\Libs: -L"${{libdir}}" -lcurl
            \\Libs.private: -L"${{libdir}}" -lmbedtls -lmbedx509 -lmbedcrypto{s}
            \\Cflags: -I"${{includedir}}"{s}
            \\
        , .{
            // Keep the pkg-config version as the string from `curlver.h:35`.
            upstream_version_string,
            upstream_version_string,
            upstream_version_string,
            // Shared Windows consumers need `dllimport`; set `CURL_STATICLIB` only for archives.
            if (separate_m) " -lm" else "",
            if (linkage == .static) " -DCURL_STATICLIB" else "",
        })),
        .prefix,
        "lib/pkgconfig/libcurl.pc",
    );
    b.getInstallStep().dependOn(&install_pc.step);
}

/// Install upstream `COPYING` verbatim with the fork's provenance records.
/// Keep upstream `README` and `RELEASE-NOTES` together because the latter points to the former.
fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |record| {
        const install_record = b.addInstallFileWithDir(
            b.path(record),
            .prefix,
            b.fmt("share/licenses/{s}/{s}", .{ lib_name, std.fs.path.basename(record) }),
        );
        b.getInstallStep().dependOn(&install_record.step);
    }
}

/// Unix targets use a separate `libm`; Darwin and Windows do not.
fn separateLibm(os_tag: std.Target.Os.Tag) bool {
    return switch (os_tag) {
        .linux, .freebsd, .netbsd, .openbsd, .dragonfly, .illumos => true,
        else => false,
    };
}

/// Windows uses PE/COFF without an interpreter path; WASI has no dynamic linker.
/// Return whether the target supports dynamic delivery.
fn targetHasDynamicLinker(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows or
        std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// Refuse dynamic delivery without a dynamic linker; never substitute an archive.
/// Resolve one linkage for the library, facade, and pkg-config metadata.
fn deliveredLinkage(
    target: std.Build.ResolvedTarget,
    requested: std.lang.LinkMode,
) std.lang.LinkMode {
    if (requested == .dynamic and !targetHasDynamicLinker(target)) {
        // Use a runtime format string because the target OS tag is not comptime-known.
        std.debug.panic(
            "libcurl: -Dlinkage=dynamic was asked for {s}, which has no dynamic " ++
                "linker: std.Target.DynamicLinker.kind is .none for it, so it cannot " ++
                "carry a shared object at all. This build does not substitute a static " ++
                "archive for a requested shared object. Build that target with the " ++
                "default -Dlinkage=static, which is also what cross-test.profile.sh " ++
                "pins for the published 53-platform matrix.",
            .{@tagName(target.result.os.tag)},
        );
    }
    return requested;
}

/// Details for a target the package cannot build.
const Refusal = struct {
    summary: []const u8,
    detail: []const u8,
};

fn refusalFor(os_tag: std.Target.Os.Tag) ?Refusal {
    if (os_tag == .wasi) {
        return .{
            .summary = "libcurl has no buildable configuration for wasm32-wasi with this TLS backend: mbed-TLS compiles its mbedtls_net_* family out on WASI and lib/vtls/mbedtls.c calls mbedtls_net_connect and mbedtls_net_accept.",
            .detail =
            \\The reason is inside the TLS backend, not in curl and not in this
            \\toolchain's C library.
            \\
            \\MBEDTLS_NET_C is compiled in for every unix-like and Windows target
            \\and compiled out for wasm32-wasi. The mbed-TLS sources stop the
            \\build unless MBEDTLS_PLATFORM_IS_UNIXLIKE or _WIN32 is defined, and
            \\that macro is built from unix / __unix / __unix__ /
            \\(__APPLE__ && __MACH__) / __HAIKU__ / __midipix__ / _WIN32 - none of
            \\which WASI's clang defines. So mbedtls_net_connect and
            \\mbedtls_net_accept exist on Linux, macOS and Windows and do not
            \\exist on WASI.
            \\
            \\lib/vtls/mbedtls.c needs both. It uses mbedtls_net_connect to reach
            \\the peer during the handshake and mbedtls_net_accept for the
            \\listening side, and there is no third spelling in that unit to fall
            \\back to.
            \\
            \\Nothing on this side's compile line changes that. It is a
            \\compile-time #error inside the dependency, not a macro, so there is
            \\no configuration this package can write that gets a mbed-TLS-backed
            \\libcurl onto WASI.
            \\
            \\What WASI could otherwise have had, so that the cost of the refusal
            \\is on the record rather than guessed: lib/curl_setup.h:200-203 would
            \\read NEED_REENTRANT, lib/curlx/nonblock.c:52-70 would take its
            \\HAVE_FCNTL_O_NONBLOCK arm and lib/socketpair.c:52-64 its HAVE_PIPE
            \\arm, and lib/curl_setup.h:470-473 would leave USE_EVENTFD undefined
            \\so eventfd is not reached. build_support/curl_config_gen.c carries
            \\that family and refuses --os wasi with these words. Separately, WASI
            \\has no dynamic linker, so deliveredLinkage refuses
            \\-Dlinkage=dynamic there, and the runtime route's Unix backend calls
            \\dlopen, which WASI does not have. Neither is why this row is refused.
            \\
            \\The target is refused rather than patched past: no source is edited,
            \\no TLS backend is swapped for one that is not in the dependency
            \\surface, and no unit is dropped from the 196. Build for a target
            \\this package names a configuration for: x86_64-linux-gnu,
            \\aarch64-linux-gnu, riscv64-linux-gnu, aarch64-macos-none,
            \\x86_64-windows-gnu.
            \\
            \\This is a statement about this pinned lib/vtls/mbedtls.c against this
            \\mbed-TLS build for this toolchain's WASI target, not a claim that
            \\WASI cannot host curl. The cell comes back when the mbed-TLS package
            \\compiles MBEDTLS_NET_C for WASI, or when lib/vtls/mbedtls.c stops
            \\needing mbedtls_net_*. Either is the dependency's or upstream's to
            \\make, and this package makes neither.
            ,
        };
    }

    return null;
}

/// Emit the target-specific reason and stop configuration.
fn refuseTarget(b: *std.Build, target: std.Build.ResolvedTarget) noreturn {
    const refusal = refusalFor(target.result.os.tag) orelse
        @panic("build.zig internal error: refusalFor returned null for a target addGraph refused");
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    std.log.err("libcurl: {s}: {s}\n{s}", .{ triple, refusal.summary, refusal.detail });
    @panic("libcurl: refusing a target this package has no buildable configuration for");
}

/// Ensure the buildable and refused target lists form an explicit partition.
/// Misclassified targets fail configuration instead of silently disappearing from `check`.
fn checkMatrixPartition(b: *std.Build) void {
    for (check_targets) |query| {
        const resolved = b.resolveTargetQuery(query);
        if (refusalFor(resolved.result.os.tag) != null) {
            @panic(b.fmt(
                "build.zig: {s} is in check_targets but this build refuses its operating system",
                .{resolved.result.zigTriple(b.allocator) catch @panic("unspellable check target")},
            ));
        }
    }
    for (refused_check_targets) |query| {
        const resolved = b.resolveTargetQuery(query);
        if (refusalFor(resolved.result.os.tag) == null) {
            @panic(b.fmt(
                "build.zig: {s} is in refused_check_targets but refusalFor no longer refuses it; move it to check_targets and prove it builds",
                .{resolved.result.zigTriple(b.allocator) catch @panic("unspellable check target")},
            ));
        }
    }
}

/// Compile the library, facade, tests, and example for one matrix target.
/// This step does not run cross-built binaries.
fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.lang.Optimize,
    linkage: std.lang.LinkMode,
    runtime_loaded: bool,
    ca_bundle: ?[]const u8,
    ca_path: ?[]const u8,
) void {
    const cross_target = b.resolveTargetQuery(query);
    // Name each matrix artifact with its target triple.
    const triple = cross_target.result.zigTriple(b.allocator) catch @panic("unspellable target");

    const cross = addGraph(b, cross_target, optimize, linkage, runtime_loaded, ca_bundle, ca_path, false);

    const test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addTest(.{
        .name = b.fmt("{s}-tests-{s}", .{ lib_name, triple }),
        .root_module = test_mod,
    }).step);

    const example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addExecutable(.{
        .name = b.fmt("{s}-smoke-{s}", .{ lib_name, triple }),
        .root_module = example_mod,
    }).step);

    step.dependOn(&cross.c_lib.step);
}

/// Build `consumer/` separately to avoid a manifest dependency cycle.
/// Forward target, CPU, linkage, runtime, and CA options so the nested build matches this one.
/// Run native targets; install foreign ones because Zig cannot execute them here.
fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    linkage: std.lang.LinkMode,
    runtime_loaded: bool,
    ca_bundle: ?[]const u8,
    ca_path: ?[]const u8,
) *std.Build.Step.Run {
    const triple = target.query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    // A target triple omits CPU model and features; serialize them for the nested build.
    const cpu = target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    // Use the same Zig executable for the nested build.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path("consumer"));
    run.addArg(if (hostCanExecute(target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(linkage)}));
    run.addArg(b.fmt("-Druntime={s}", .{if (runtime_loaded) "true" else "false"}));
    if (ca_bundle) |value| run.addArg(b.fmt("-Dca-bundle={s}", .{value}));
    if (ca_path) |value| run.addArg(b.fmt("-Dca-path={s}", .{value}));
    run.addArg("--summary");
    run.addArg("all");
    // Do not forward `--prefix`; the nested install must not overwrite this package's output.
    if (hostCanExecute(target)) {
        run.addArg("--");
        run.addPassthruArgs();
    }

    return run;
}

/// A plain system command cannot execute foreign-target binaries.
/// The caller installs them as compile-only checks.
fn hostCanExecute(target: std.Build.ResolvedTarget) bool {
    return target.query.isNative();
}

const graph = @import("runtime/graph.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage: std.lang.LinkMode = b.option(
        std.lang.LinkMode,
        "linkage",
        "Deliver the C library as a static archive (the default, and what " ++
            "cross-test.profile.sh pins for the published matrix) or as a real " ++
            "shared object with upstream's libtool-derived ABI identity, " ++
            "libcurl.so.4.8.0 with soname libcurl.so.4. The ABI number is " ++
            "lib/Makefile.soname:26-28 read through lib/CMakeLists.txt:271 - " ++
            "current minus age, 12 minus 8 - and it is not the release version. " ++
            "This selects the delivery and never the source list: all 196 units " ++
            "are compiled either way.",
    ) orelse .static;

    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve the native entry points at run time instead of linking them. " ++
            "The facade keeps the same translated headers and the same public " ++
            "types; each selected native function becomes a dispatch through one " ++
            "process-lifetime table that an explicit load(source) fills, and the " ++
            "module links no archive and no mbed-TLS archive. Independent of " ++
            "-Dlinkage, which still decides which artifact this build delivers " ++
            "and installs. Default off, and a linked build is unchanged in every " ++
            "respect.",
    ) orelse false;

    // Dependency roots come from build.zig.zon; there is no per-call root override.
    const tls_override = b.option(
        std.Build.LazyPath,
        "tls",
        "Override the mbed-TLS package location. REFUSED while the mbed-TLS " ++
            "declares no package-root option. The root comes from its " ++
            "build.zig.zon entry; only its own -D options are forwarded. " ++
            "To relocate it, change the .path " ++
            "of the mbed-tls entry in this package's build.zig.zon, or add a " ++
            "package-root option to mbed-tls/build.zig. There is no -Dno-tls and " ++
            "no way to build a libcurl without a TLS backend.",
    );
    if (tls_override) |_| {
        std.debug.panic(
            "libcurl: -Dtls was given a path, and this build cannot honour it. " ++
                "The TLS backend is reached only through the standard dependency " ++
                "mechanism: build.zig.zon carries exactly one .dependencies entry, " ++
                ".@\"mbed-tls\" = .{{ .path = \"../mbed-tls\" }}, and build.zig " ++
                "resolves it with b.dependency(\"mbed-tls\", .{{ .target, .optimize }}). " ++
                "Zig 0.17.0 takes the dependency root from build.zig.zon; this " ++
                "build can pass only mbed-TLS's declared options, and it declares " ++
                "none that relocates the root. " ++
                "Forwarding the flag would therefore reach a map that ignores it, " ++
                "and a silently ignored TLS-backend override is worse than no " ++
                "override at all: it would leave a caller believing the backend " ++
                "came from somewhere it did not. Two changes make it real, and " ++
                "neither is made here: change the .path of the mbed-tls entry in " ++
                "libcurl/build.zig.zon, or add a package-root option to " ++
                "mbed-tls/build.zig and name it here. There is no option on this " ++
                "package that disables TLS, and this build will not silently " ++
                "produce a libcurl without a backend.",
            .{},
        );
    }

    // Compile CA paths into `curl_config.h` because curl reports them as defaults (`lib/getinfo.c:161-169`).
    // Preserve caller values verbatim so they remain valid after installation elsewhere.
    const ca_bundle = b.option(
        []const u8,
        "ca-bundle",
        "PEM file path compiled into CURL_CA_BUNDLE, the default CA bundle " ++
            "libcurl reports through CURLINFO_CAINFO. Passed verbatim to " ++
            "build_support/curl_config_gen.c; unset leaves the row undefined, " ++
            "which is how a build says 'no built-in store'.",
    );
    const ca_path = b.option(
        []const u8,
        "ca-path",
        "PEM directory path compiled into CURL_CA_PATH, the default CA path " ++
            "libcurl reports through CURLINFO_CAPATH. Passed verbatim to " ++
            "build_support/curl_config_gen.c.",
    );

    // Keep the manifest release version equal to upstream's `curlver.h:35`.
    if (manifest_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches LIBCURL_VERSION, read " ++
            "out of include/curl/curlver.h:35; see UPSTREAM.md");
    }

    checkMatrixPartition(b);

    const published = addGraph(
        b,
        target,
        optimize,
        linkage,
        runtime_loaded,
        ca_bundle,
        ca_path,
        true,
    );

    const delivered = deliveredLinkage(target, linkage);

    b.installArtifact(published.c_lib);
    addPkgConfig(b, delivered, separateLibm(target.result.os.tag));
    installLicenceRecords(b);

    const example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport(lib_name, published.module);
    const example = b.addExecutable(.{
        .name = b.fmt("{s}-smoke", .{lib_name}),
        .root_module = example_mod,
    });
    b.getInstallStep().dependOn(&example.step);

    const run_example = b.addRunArtifact(example);
    run_example.has_side_effects = true;
    run_example.addPassthruArgs();
    b.step("smoke", "Run the deterministic example program").dependOn(&run_example.step);

    // Use a test root with test blocks; a re-export-only root discovers none.
    // `addRunArtifact` runs tests through the selected executor.
    const test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, published.module);
    const unit_tests = b.addTest(.{
        .name = b.fmt("{s}-tests", .{lib_name}),
        .root_module = test_mod,
    });
    const run_tests = b.addRunArtifact(unit_tests);
    run_tests.has_side_effects = true;
    b.step("test", "Run the behavioural tests").dependOn(&run_tests.step);

    b.step("consumer", "Build or run the consumer/ package for the selected target")
        .dependOn(&runConsumer(
        b,
        target,
        optimize,
        delivered,
        runtime_loaded,
        ca_bundle,
        ca_path,
    ).step);

    const check_step = b.step(
        "check",
        "Compile the native library, the facade, the tests, the example and " ++
            "the whole 196-unit closure for the five buildable check targets " ++
            "without running any of them",
    );
    if (!target.query.isNative()) {
        addTargetCheck(
            b,
            check_step,
            target.query,
            optimize,
            linkage,
            runtime_loaded,
            ca_bundle,
            ca_path,
        );
    } else {
        // Slice the pointer-to-array before iterating; `.*` unwraps a payload.
        for (check_targets[0..]) |query| {
            addTargetCheck(
                b,
                check_step,
                query,
                optimize,
                linkage,
                runtime_loaded,
                ca_bundle,
                ca_path,
            );
        }
    }

    std.debug.print(
        "libcurl: {d} C units (CSOURCES, lib/Makefile.inc:439-441), USE_MBEDTLS=1, " ++
            "BUILDING_LIBCURL=1, HAVE_CONFIG_H=1\n",
        .{curl_source_count},
    );
    std.debug.print("libcurl: {s}\n", .{switch (delivered) {
        .static => "static archive libcurl.a (the default, and what cross-test.profile.sh pins)",
        .dynamic => b.fmt(
            "shared object libcurl.so.{d}.{d}.{d}, soname libcurl.so.{d} " ++
                "(lib/Makefile.soname:26-28 through lib/CMakeLists.txt:271; the dlopen name is the soname)",
            .{
                abi_version.major,
                abi_version.minor,
                abi_version.patch,
                abi_version.major,
            },
        ),
    }});
    std.debug.print(
        "libcurl: {s} {s}\n",
        .{ @tagName(target.result.os.tag), switch (target.result.abi) {
            .gnu => "gnu",
            .musl => "musl",
            .gnuabin32 => "gnuabin32",
            .musleabi => "musleabi",
            .msvc => "msvcrt",
            .none => "no-abi",
            else => @tagName(target.result.abi),
        } },
    );
    if (ca_bundle) |value| {
        std.debug.print("libcurl: CURL_CA_BUNDLE compiled in as \"{s}\"\n", .{value});
    }
    if (ca_path) |value| {
        std.debug.print("libcurl: CURL_CA_PATH compiled in as \"{s}\"\n", .{value});
    }
    if (runtime_loaded) {
        std.debug.print(
            "libcurl: runtime-loaded dispatch (-Druntime=true); the facade module " ++
                "links no archive and a provider is named by an explicit load(source). " ++
                "Under -Dlinkage=dynamic the name this build installs is the soname " ++
                "above; under -Dlinkage=static a caller must name its own provider.\n",
            .{},
        );
    }
    // Only ELF uses a version script; Mach-O exports internals, and COFF's `.def` list is unversioned.
    if (delivered == .dynamic and target.result.ofmt != .elf) {
        std.debug.print(
            "libcurl: {s} takes no ELF version script here, so the shared object " ++
                "exports curl's Curl_-prefixed internals as well as its curl_* API\n",
            .{@tagName(target.result.ofmt)},
        );
    }
    // This dependency set omits HTTP/2, compression, LDAP, and Public Suffix List support.
    // Without PSL, cookie public-suffix rejection is unavailable.
    std.debug.print(
        "libcurl: no HTTP/2 (lib/http2.c:26 needs USE_NGHTTP2), no content " ++
            "encoding (lib/content_encoding.c:29 needs HAVE_LIBZ), no " ++
            "ldap:// or ldaps:// (lib/ldap.c:59-61 includes <lber.h> and " ++
            "<ldap.h>), and no Public Suffix List (lib/psl.c:26 needs " ++
            "USE_LIBPSL, so lib/cookie.c's public-suffix rejection is " ++
            "compiled out). The dependency surface is one entry: the mbed-TLS " ++
            "package.\n",
        .{},
    );
}
