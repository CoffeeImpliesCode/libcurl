// SPDX-License-Identifier: curl
// See FORK-LICENSE.md for what that identifier covers.
//
//! libcurl's side of the runtime loader: the names its synchronization binding
//! has, what it requires of a provider beyond resolving its symbols, and what
//! the external ABI boundary for this provider actually is.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them
//! libcurl's, and it is the file another SDK replaces.
//!
//! ## What a provider must be
//!
//! Every function the headers declare, and nothing else. The translated header
//! is `zig/translate.h`, which includes `<curl/curl.h>` and no macro of its own;
//! `include/curl/curl.h:62-63,3341-3347` opens the whole curl surface, and that
//! surface declares exactly **100** functions:
//!
//!   * 46 in `include/curl/curl.h` - the mime family (12), the deprecated form
//!     family (3), escape (5), global init and teardown (5), slist (2), share
//!     (4), the deprecated getenv (1), getdate (1), the strerror family (3),
//!     version (2), strequal/strnequal (2), the easy header/pause/ssls
//!     entry points (4) and more;
//!   * 10 in `include/curl/easy.h:41-117`;
//!   * 24 in `include/curl/multi.h:126-553`;
//!   * 3 in `include/curl/options.h:59-65`;
//!   * 2 in `include/curl/header.h:58,65`;
//!   * 6 in `include/curl/urlapi.h:114-150`;
//!   * 11 in `include/curl/mprintf.h:56-76`, of which nine are variadic;
//!   * 4 in `include/curl/websockets.h:55-92`.
//!
//! `provider_optional` and `provider_excluded` in `runtime/graph.zig` are
//! therefore empty, and they are written out rather than omitted so that
//! adding a header with an optional entry point is a change in that file with a
//! name in it.
//!
//! ### Why none of them is optional, which is the part that had to be checked
//!
//! curl is the first SDK in this workspace whose public surface is partly
//! behind `CURL_DISABLE_*` build macros, so the obvious classification would be
//! "optional". That would be wrong, and the reason is in the C sources rather
//! than in the headers.
//!
//! `lib/libcurl.def` is upstream's own export list for the Windows DLL: 100
//! names after the `EXPORTS` line, and they are the same 100 names the headers
//! declare, with nothing on either side that the other does not have. And for
//! every family that *is* feature-gated in the C sources, the `#else` branch
//! still defines the symbol, so the export list is the same whatever the
//! configuration:
//!
//!   * `curl_ws_send`, `curl_ws_recv`, `curl_ws_start_frame`, `curl_ws_meta`
//!     sit inside `lib/ws.c:28` `#ifndef CURL_DISABLE_WEBSOCKETS`, and
//!     `lib/ws.c:2027-2071` defines all four again as stubs returning
//!     `CURLE_NOT_BUILT_IN`;
//!   * `curl_easy_header`, `curl_easy_nextheader` sit inside `lib/headers.c:30`
//!     `!CURL_DISABLE_HTTP && !CURL_DISABLE_HEADERS_API`, with stubs at
//!     `lib/headers.c:396-425`;
//!   * `curl_easy_option_by_name`, `curl_easy_option_by_id`,
//!     `curl_easy_option_next` sit inside `lib/easygetopt.c:28`
//!     `#ifndef CURL_DISABLE_GETOPTIONS`, with stubs that return null at
//!     `lib/easygetopt.c:78-97`;
//!   * the twelve `curl_mime_*` sit inside `lib/mime.c:39-41`, with stubs at
//!     `lib/mime.c:2179-2282`;
//!   * `curl_formadd`, `curl_formget`, `curl_formfree` sit inside
//!     `lib/formdata.c:30`, with stubs at `lib/formdata.c:842-864`;
//!   * `curl_pushheader_bynum`, `curl_pushheader_byname` sit inside
//!     `lib/http2.c:26` `!CURL_DISABLE_HTTP && USE_NGHTTP2`, with stubs at
//!     `lib/http2.c:2981-2997`.
//!
//! That last family is the reason the point is worth making out loud. This
//! package builds its C with `USE_MBEDTLS` and nothing else - there is no
//! `-Dno-tls` option and no second backend - and `build.zig.zon` has exactly one
//! dependency, mbed-TLS, so `USE_NGHTTP2` cannot be defined here and cannot be.
//! Routing `curl_pushheader_bynum` as *required* would make this package's own
//! shared object fail this package's own load. It is routed because upstream
//! exports it unconditionally; if a future provider ever lacks it, the honest
//! fix is a build-time decision recorded in `runtime/graph.zig`, not a guess
//! made here.
//!
//! ### What is *not* in the table
//!
//! The target C library's whole surface. `include/curl/curl.h:65-66,74-75`
//! opens `<stdio.h>`, `<limits.h>`, `<sys/types.h>` and `<time.h>`;
//! `:102-105` adds `<sys/socket.h>` and `<sys/time.h>` off Windows;
//! `include/curl/mprintf.h:27-28` adds `<stdarg.h>` and `<stdio.h>` again; and
//! `:77-85` puts `<winsock2.h>` and `<ws2tcpip.h>` in the Windows closure. A
//! translation step emits a declaration for every function it parses in that
//! closure, whether or not this build calls it, so the translation carries a
//! large slab of the C library alongside curl's own surface. Those are the C
//! library's symbols, not the provider's: a `libcurl.so` does not export
//! `printf`, and asking a provider for one would either fail the load outright
//! or, worse, resolve it out of the C library the provider itself depends on.
//! They are classified as noise in `runtime/graph.zig`, which keeps the
//! declarations direct.
//!
//! curl's share of that is much larger than any other SDK in this workspace,
//! because of one line: `any-windows-any/winsock2.h:23` includes `<windows.h>`
//! unconditionally, so on a Windows target curl's header closure reaches the
//! entire Win32 SDK. That is what `runtime/graph.zig`'s comment on the size of
//! its list is about.
//!
//! ## The ABI boundary, stated honestly
//!
//! The supported external ABI family is the one `include/curl/` describes -
//! libcurl 8.22.0 (`include/curl/curlver.h:35`), `LIBCURL_VERSION_NUM`
//! `0x081600` (`:60`) - built with upstream's defaults and with mbed-TLS as the
//! TLS backend. That is a narrower claim than "a shared object that exports
//! these 100 names", and the difference is real:
//!
//!   * `curl_off_t` is a 64-bit signed type by upstream's own rule
//!     (`include/curl/system.h:36-43`, "curl_off_t MUST be typedef'ed to a
//!     64-bit ... shall not be mapped to off_t"), resolved at
//!     `include/curl/system.h:393-397`. It appears in `CURLOPT_*` and
//!     `CURLINFO_*` argument positions through the variadic
//!     `curl_easy_setopt` and in `curl_multi_waitfds`
//!     (`include/curl/multi.h:531`), so a provider built where that typedef
//!     resolved differently passes a different width through the same symbol
//!     name.
//!   * `curl_socket_t` is `int` off Windows and `SOCKET` on it
//!     (`include/curl/curl.h:142-147`), and `SOCKET` is pointer-sized on
//!     64-bit Windows. `curl_multi_socket_action` and `curl_multi_wait` take it
//!     by value, so the same symbol name carries a different width on the two
//!     platforms.
//!   * `long` is a parameter type in curl's own API, not just in the C library's
//!     - `curl_multi_timeout(CURLM *, long *)` at
//!     `include/curl/multi.h:343` and `curl_global_init(long)` at
//!     `include/curl/curl.h:2777`. On an LP64 target `long` is 64 bits and on
//!     an ILP32 one it is 32, so those two entry points are different ABIs on
//!     the two and agree only on a 64-bit `long`.
//!   * `struct curl_version_info_data` (`include/curl/curl.h:3138-3200`) grows
//!     by appending, and upstream records the growth in the enum comment at
//!     `curl.h:3150,3154,3157,3159,3162,3165,3169,3172,3176`
//!     ("This field was added in CURLVERSION_*"). Reading the leading fields
//!     is therefore safe against an older provider; reading a field a provider
//!     does not have is not, which is what the `age` check below is about.
//!   * The allocator is the provider's. `curl_easy_escape`
//!     (`include/curl/curl.h:2728-2730`) and `curl_easy_unescape`
//!     (`:2747-2750`) return a buffer the caller releases with `curl_free`
//!     (`:2764`), which routes to the callback `curl_global_init_mem`
//!     (`:2792-2797`) installed. No Zig allocator is in that path, and a test
//!     framework cannot supply a leak oracle for memory a third-party allocator
//!     owns.
//!   * Twenty-nine function-pointer types cross the boundary in both directions
//!     - `curl_write_callback`, `curl_read_callback`, `curl_progress_callback`,
//!     `curl_xferinfo_callback`, `curl_debug_callback`, the multi timer and
//!     socket callbacks and the rest. A callback built against this
//!     translation is called by the provider's own C with the provider's own
//!     calling convention.
//!
//! Resolving the symbols and translating the header is the boundary. They are
//! not proof that a provider is compatible, and this file does not pretend to
//! add more than it checks.
//!
//! ## The one thing that is checked, and why it is this
//!
//! All 100 exported names are present in a libcurl built with **no TLS backend
//! at all**, because every disabled family keeps its stub symbols (see above).
//! Resolving the whole table therefore proves that the file is a libcurl of
//! this API family and says nothing at all about how it was configured - and
//! this package has exactly one configuration it will ship: a libcurl with a
//! TLS backend. `build.zig` has no option that produces one without, and a
//! build that cannot resolve mbed-TLS must fail at configure time rather than
//! silently produce a TLS-less libcurl. A runtime-loaded provider is the one
//! place that promise can be broken without anything failing to build, so it is
//! where the check belongs.
//!
//! Before anything is published:
//!
//!   * `curl_version_info` answers with a `curl_version_info_data` whose `age`
//!     is at least the `CURLVERSION_NOW` these headers define. `curl.h:3132-3136`
//!     defines what that number is for: "what kind of struct the caller
//!     expects". A provider reporting an older age has a different struct shape
//!     under the same name.
//!   * that struct's `ssl_version` is not null, and its `features` bitmask has
//!     `CURL_VERSION_SSL` set. `lib/version.c:547` initialises `ssl_version` to
//!     `NULL` and only `lib/version.c:604-607` replaces it, under `USE_SSL`;
//!     `lib/version.c:515-517` sets the `CURL_VERSION_SSL` feature bit under the
//!     same macro. So both facts are exactly "this provider was built with a
//!     TLS backend", read out of the provider itself rather than asserted.
//!
//! ### What is deliberately *not* called
//!
//! `curl_global_init`. `include/curl/curl.h:2771-2775` says it "should be
//! invoked exactly once for each application that uses libcurl and before any
//! call of other libcurl functions". A loader runs inside whatever application
//! loaded it, and spending that one call would leave the application unable to
//! make it. For the same reason `curl_easy_init` is not called: a handle
//! created here would have to be released here, and the facade that owns
//! handles would never learn about it.
//!
//! What *is* safe to call before global init is `curl_version_info`, and the
//! reason is in the C rather than in a promise:
//!
//!   * `lib/version.c:604-607` only reaches `Curl_ssl_version` under
//!     `USE_SSL`, so a build with no TLS backend never touches it at all;
//!   * in a build with a TLS backend, `Curl_ssl` is a pointer with a **static**
//!     initialiser - `lib/vtls/vtls.c:686-703` selects `&Curl_ssl_mbedtls` at
//!     compile time under `USE_MBEDTLS` - so it is never null before
//!     `curl_global_init` runs, and `lib/vtls/vtls.c:286-293` can dereference
//!     it safely;
//!   * everything else the function reads is `static` storage
//!     (`lib/version.c:541-577`) or a version string from another library's
//!     `*_version()` entry point.
//!
//! So the check costs one call into a function that only reads constants and
//! static data, and it leaves the provider in exactly the state it was in.
//! A refusal is reported as a refusal: the candidate handle is closed and
//! nothing is published, and the module stays unloaded so the caller can
//! choose another provider or retry.

const std = @import("std");

const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.c` compiled with
/// `RT_SYNC_PREFIX=curl_rt`, which is what `runtime/graph.zig` passes. Two
/// spellings of that prefix have to agree: this file names the symbols, and
/// graph.zig defines the macro. A build where they disagree does not link, and
/// that is the whole error report: there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
pub const Sync = struct {
    extern fn curl_rt_lock() void;
    extern fn curl_rt_unlock() void;
    extern fn curl_rt_wait() void;
    extern fn curl_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
    extern fn curl_rt_thread_self() u64;

    pub fn lock() void {
        curl_rt_lock();
    }
    pub fn unlock() void {
        curl_rt_unlock();
    }
    pub fn wait() void {
        curl_rt_wait();
    }
    pub fn broadcast() void {
        curl_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return curl_rt_thread_self();
    }
};

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "libcurl";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated headers, not from this
        /// file.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// The library-specific checks, run after every symbol resolved and
        /// before anything is published.
        ///
        /// A non-null answer is `ValidationFailed` and the candidate is closed
        /// without being published. Every check here is one whose failure this
        /// code can observe; see the module comment for what is deliberately
        /// not called and why.
        pub fn validate(dst: *const table) ?[]const u8 {
            // `lib/version.c:602` is `(void)stamp;` - the argument is ignored
            // upstream - but `include/curl/curl.h:3132-3136` defines
            // `CURLVERSION_NOW` as the age of the struct the caller expects, so
            // the header's own value is what is passed and what is compared
            // against below.
            const info = dst.curl_version_info(dispatch.CURLVERSION_NOW) orelse return
                "curl_version_info returned null. include/curl/curl.h:3240-3248 " ++
                "documents it as returning a pointer to a static copy of the " ++
                "version struct, and lib/version.c:579-681 returns the address " ++
                "of one static struct, so null is not a shape this library " ++
                "produces";

            // The struct-shape gate, in the form upstream documents.
            if (info.age < dispatch.CURLVERSION_NOW) return
                "curl_version_info reports an older curl_version_info_data than " ++
                "the CURLVERSION_NOW include/curl/curl.h:3136 defines, so this " ++
                "provider's version struct is not the one these headers describe";

            // The package's own requirement: a TLS backend, asked of the
            // provider itself. See the module comment for why symbol
            // resolution cannot establish this.
            if (info.ssl_version == null) return
                "this provider reports a null ssl_version, so it was built " ++
                "without a TLS backend. This package has no configuration " ++
                "without one and will not load a provider that has none";

            if ((info.features & dispatch.CURL_VERSION_SSL) == 0) return
                "this provider does not set CURL_VERSION_SSL, so it was built " ++
                "without a TLS backend. This package has no configuration " ++
                "without one and will not load a provider that has none";

            return null;
        }
    };
}