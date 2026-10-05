// SPDX-License-Identifier: curl
// See FORK-LICENSE.md for what that identifier covers.

//! Zig facade over the libcurl 8.22.0 C implementation under `lib/`.
//!
//! No part of the protocol is reimplemented here. Every value that comes back
//! out of this module was produced by the C under `libcurl/lib/`, reached
//! through `pub const c`, the module the translation step produces from
//! `zig/translate.h`. What the facade adds is the part a C header cannot
//! express: a handle that owns itself and says what closing it means, named
//! errors for the status codes curl actually returns, borrowed and owned
//! strings told apart, one owning type per list that libcurl keeps in its own
//! allocator, and a `Multi` whose loop cannot be written wrong.
//!
//! ## Import routes
//!
//! One Zig route is published: `dep.module("libcurl")` in the dependent's
//! `build.zig`, which is `@import("libcurl")` in source. The translated
//! headers are `c` on that same module and are not published as a module of
//! their own, so the declarations and the library that satisfies them arrive
//! through one route. A C consumer takes the installed headers and the
//! installed `libcurl.a` instead; `README.zig.md` names that layout.
//!
//! ```zig
//! const curl = @import("libcurl");
//! const std = @import("std");
//!
//! pub fn main() !void {
//!     try curl.globalInit(curl.InitFlags.default_flags);
//!     defer curl.globalCleanup();
//!
//!     var easy = try curl.Easy.init();
//!     defer easy.deinit();
//!     try easy.setUrl("https://example.invalid/");
//!     try easy.perform();
//! }
//! ```
//!
//! ## Global initialization is not optional
//!
//! `curl_global_init` is refcounted: every successful call must be matched by
//! one `curl_global_cleanup` (`lib/easy.c:129` counts up, `:196` undoes the
//! count on failure, `:266-269` refuses a cleanup with nothing to undo). The
//! two free functions here are that pair, and `globalInit` reports a single
//! error because `curl_global_init` reports a single code:
//! `CURLE_FAILED_INIT`, and nothing else (`lib/easy.c:195-197`). Upstream also
//! initializes itself on the first `curl_easy_init` when a caller has not
//! (`lib/easy.c:345-346`), which is why a program that skips the explicit pair
//! works until it needs `globalCleanup` to do anything.
//!
//! ## Allocation: a third-party allocator, honestly
//!
//! Nothing in this module allocates through a Zig allocator, and one part of
//! its memory cannot be accounted for at all. libcurl allocates through the
//! `Curl_cmalloc` family of function pointers, which are plain `malloc`,
//! `free`, `realloc` and `calloc` unless a build replaces them
//! (`lib/easy.c:109-113` sets exactly those; `:243-247` is the only place
//! they change, through `curl_global_init_mem`, which this module does not
//! wrap). Every string curl returns to a caller that owns it comes out of that
//! allocator, and `freeEscaped` exists because of it.
//!
//! Nothing here can bound, intercept or account for those allocations, and a
//! Zig test allocator cannot be given a leak oracle for memory a third-party
//! allocator owns. `Easy.deinit` calls `curl_easy_cleanup`, which closes the
//! handle and releases everything the handle owns (`lib/easy.c:855-867`); that
//! is the whole answer this module can give about memory, and it is not the
//! same answer as "the program leaked nothing".
//!
//! ## Two configurations: linked and runtime-loaded
//!
//! This module is built in one of two shapes, and `runtime_loaded` says which
//! at comptime.
//!
//! *Linked* is the default. The C library is linked, `c` is the translation
//! of `zig/translate.h`, and every call below is a direct call with no table
//! and no check.
//!
//! *Runtime-loaded* is opt-in (`-Druntime`). The library is not linked; `c` is
//! a dispatch generated from the same translation step's output by
//! `runtime/graph.zig`'s `createModule`, and every selected native function is
//! resolved through the platform loader when the caller calls
//!
//! ```zig
//! try curl.load(.{ .path = "/usr/lib/libcurl.so.4" });
//! ```
//!
//! before using anything else. A call into a module that has not loaded stops
//! the program with a message naming the function, in every optimization mode:
//! the table does not exist yet and there is no partial state to fall back on,
//! and `std.debug.assert` would be stripped in `ReleaseFast` and so is the
//! wrong thing for it. The load itself reports a missing file, a provider that
//! does not export what the headers declare, a request that cannot be honoured
//! because a different provider already won, or a reentrant call, as errors
//! rather than as a different library being loaded instead. A failed load
//! publishes nothing and may be retried by calling `load` again.
//!
//! The provider is reached, never guessed. `.path` names a file and `.system`
//! names a library for the platform loader; neither falls back to the other.
//! `unload` exists and is explicit, so a caller that wants the table gone can
//! say so; there is no implicit teardown at any other point.
//!
//! `runtime/library.zig` states what a provider must be, including the libcurl
//! external ABI family this SDK supports.
//!
//! ## The C variadics
//!
//! Three of the entry points this module calls are real C variadics:
//! `curl_easy_setopt` and `curl_easy_getinfo` (`include/curl/easy.h:42`, `:59`)
//! and `curl_multi_setopt` (`include/curl/multi.h:438`). The two this facade
//! uses take exactly one trailing argument, which is the third parameter of
//! each.
//!
//! The linked configuration's translation declares them as C variadics, so they
//! are called through `@call(.auto, ...)` with the trailing value promoted.
//! The runtime-loaded dispatch keeps their arity and takes the trailing value
//! as one final argument of its own. Every call to one of them is a comptime
//! branch on `runtime_loaded` through the private `setopt` and `getinfo`
//! helpers below, so a build resolves only the route it has and a reader of one
//! route is reading the one that will run. `runtime_loaded` says which
//! configuration this build is, at comptime.
//!
//! ## Threads and callbacks
//!
//! An `Easy` belongs to one thread at a time unless libcurl's own
//! thread-safety build option says otherwise, which `features` reports. A
//! `Multi` belongs to the thread that drives it, except that
//! `curl_multi_wakeup` is the one multi call upstream documents as callable
//! from another thread (`lib/multi.c:1697`). Nothing else in this module holds
//! shared state except the loader's own table, which the loader core
//! synchronises.
//!
//! A callback is not a Zig error boundary. Returning a short count from a
//! `WriteCallback` is curl's "stop this transfer" signal, not a Zig error, and
//! `CURL_WRITEFUNC_PAUSE` (`include/curl/curl.h:279`) is how a callback asks to
//! be called again later. See `WriteCallback`.
//!
//! ## Lifetime
//!
//! `Easy` owns one `CURL`. `init` creates one through `curl_easy_init` and
//! `deinit` closes that one through the same route - the same provider in a
//! runtime-loaded build - and then stores `undefined` into the field, so the
//! wrapper is unusable afterwards. That is deliberate: there is no third
//! state to test and no `isOpen` to mislead a caller who asks after the fact.
//! Zig cannot make a struct non-copyable, so the remaining rule is the usual
//! one: copy an `Easy` before `deinit` and you have two owners of one handle.
//!
//! `SList` owns one `curl_slist` chain the same way. `Multi` owns one `CURLM`,
//! but *not* the easy handles added to it: upstream says `curl_multi_cleanup`
//! "does not free or touch any individual easy handles in any way"
//! (`include/curl/multi.h:222-223`), so the easy handles stay the caller's to
//! close, and a `Multi` must be cleaned before or after them, not instead of
//! them.
//!
//! `Message.easy` is the deliberate contrast: a borrowed view of a handle the
//! caller already owns. It has no `deinit` and closing it would be a second
//! `curl_easy_cleanup` on one handle.

const std = @import("std");

/// The translated `include/curl/curl.h` and everything its include closure
/// reaches, i.e. upstream's ABI exactly as published.
///
/// This is the escape hatch for the declarations the facade does not name:
/// `curl_easy_duphandle`, `curl_easy_recv`/`curl_easy_send`,
/// `curl_easy_pause`, the `curl_mime_*` form API, `curl_url_*`, the
/// `curl_ws_*` websocket route, the socket callbacks, `curl_share_*`,
/// `curl_multi_setopt`, `curl_multi_assign`, `curl_multi_waitfds`,
/// `curl_multi_timeout`, `curl_multi_wakeup`, `curl_multi_get_offt`,
/// `curl_multi_notify_enable`, `curl_multi_notify_disable`,
/// `curl_multi_socket_callback`, `curl_multi_timer_callback`,
/// `curl_easy_header`, `curl_easy_nextheader`, `curl_ws_meta`, and every
/// macro the headers define. It is the same module the facade calls, on the
/// same library, so importing the facade is all a dependent needs to reach it;
/// it is not published under a name of its own.
///
/// ## The macros, and what they become
///
/// Upstream's convenience operations are C macros, and the translation step
/// carries a macro it can lower into `pub inline fn NAME(params: anytype) T`
/// whose body is the macro's own expansion. `CURLOPT(name, type, number)` is
/// `na = ((t) + (nu))` (`include/curl/curl.h:1132`), so the option constants
/// arrive with the numeric value upstream gave them. `CURLINFO_STRING`,
/// `CURLINFO_LONG` and friends are plain hex constants (`curl.h:2919-2927`),
/// which is why `CURLINFO_RESPONSE_CODE` is `CURLINFO_LONG + 2`
/// (`curl.h:2932`) and why `getinfo` below can hand upstream a `long *` for it
/// and a `const char **` for `CURLINFO_EFFECTIVE_URL`.
///
/// Which names take the lowered shape is the translation's business rather
/// than a promise this module makes: a macro it cannot lower arrives as a
/// `pub const` whose value is `@compileError`, which is a name that cannot be
/// called. `CURLBUF_*` and the `CURL_SETOPT_*` helpers in `curlx` are
/// internal and not in this header set. No `zig translate-c` of this package's
/// `zig/translate.h` has been run in this workspace, so this comment records
/// what the headers declare and not which shape the translator produced for
/// any one of them.
///
/// In a runtime-loaded build this module is a generated dispatch instead of
/// the translation step's own output. It publishes the same namespace: every
/// type and constant is re-exported from the translation rather than restated,
/// so `c.CURL` in this facade and `c_native.CURL` in the dispatch are one
/// type.
pub const c = @import("translate");

/// The loader core, which is where a linked build's two public types come
/// from.
///
/// It is imported only by the linked configuration. In a runtime-loading build
/// the dispatch carries its own copy of the same declarations and this module
/// is never referenced, so it is never resolved and never compiled - which is
/// what lets `build.zig` register `rt` only in the linked branch. Either way
/// there is exactly one `LoadSource` and one `LoadError` in a build, which is
/// what keeps them one type for a consumer that names them.
const rt = @import("rt");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where the C library is linked and `c` is the
/// translation of `zig/translate.h`. True when the build generated a dispatch
/// that resolves the same symbols through the platform loader, in which case
/// `load` is the call that makes the library usable.
///
/// It is a comptime constant, so a consumer can write two different code paths
/// and have only the one it chose analyzed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open.
///
/// `.path` is an explicit file path and `.system` is an explicit name for the
/// platform loader. There is no path-to-system fallback and no implicit
/// fallback of any kind; a request that cannot be honoured is an error, not a
/// different library.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
///
/// Declared here, in the module a consumer imports, rather than only inside the
/// loader: the caller names the failure it is handling. Defined by
/// `runtime/loader.zig` for a linked build and re-exported from the dispatch
/// for a runtime-loaded one, so it is one type either way.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the native library this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then
/// use this module as if it were linked. Calling it again with the same request
/// succeeds and changes nothing; calling it with a different request after a
/// success is a provider mismatch, and the library already in use stays in
/// use. A failed attempt publishes nothing and can be retried explicitly, by
/// calling this again.
///
/// It keeps the process handle and its own copy of the request to the end of
/// the process. There is no implicit teardown; `unload` is how a caller asks
/// for the table to go away.
///
/// Safe to call from any thread. A thread that arrives while an attempt for
/// the same request is in flight waits for that attempt and gets its result,
/// whatever it was. A call from the thread that is running the attempt is
/// reported as a reentrant load rather than a deadlock.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly
/// succeeding. `runtime_loaded` is false there, so a consumer that supports
/// both configurations can tell the two apart at comptime instead of meeting
/// this at run time.
pub fn load(source: LoadSource) LoadError!void {
    // `c.load` exists only in a runtime-loading build. The condition is known
    // at comptime, so the branch this build does not take is never analyzed
    // and never names it; the same gate `unload` below uses, for the same
    // reason.
    if (runtime_loaded) return c.load(source);
    std.debug.panic(
        "libcurl: load was called on a linked build; this module is not " ++
            "runtime-loaded, so there is no library to load. Build with " ++
            "runtime loading configured, or do not call load.",
        .{},
    );
}

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life of
/// the process. Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    if (runtime_loaded) return c.loadedSource();
    return null;
}

/// Release the dispatch table this module holds, explicitly.
///
/// There is no implicit teardown anywhere else: the table is process-global
/// state that other code may already have called through, and unloading it
/// under those callers is a crash rather than a cleanup. A caller that reaches
/// this has to mean it.
///
/// In a linked build there is nothing to release, so this stops the program with
/// a message saying so, for the same reason `load` does.
pub fn unload() void {
    if (runtime_loaded) return c.unload();
    std.debug.panic(
        "libcurl: unload was called on a linked build; this module is not " ++
            "runtime-loaded, so there is no dispatch table to release. Do not " ++
            "call unload.",
        .{},
    );
}

/// The release string the headers were generated with,
/// `include/curl/curlver.h:35`.
///
/// This is the version curl was *built* from, which is what a dependency needs
/// to know. It says nothing about the provider a runtime-loaded build reached;
/// `version` answers that.
pub const version: [:0]const u8 = c.LIBCURL_VERSION;

/// The numeric form of `version`, `include/curl/curlver.h:60`: major in the top
/// byte, minor in the middle, patch in the low one, so `0x081600` for 8.22.0.
///
/// Upstream's own comment at `:43-57` says what it is for, and `CURL_AT_LEAST_VERSION`
/// (`:74-75`) is the comparison upstream writes against it.
pub const version_num: c_uint = c.LIBCURL_VERSION_NUM;

/// The major, minor and patch numbers separately, `include/curl/curlver.h:39-41`.
///
/// Upstream splits the numeric form into these three so a program can print or
/// compare one component without arithmetic on the whole number.
pub const version_parts = struct {
    pub const major: c_uint = c.LIBCURL_VERSION_MAJOR;
    pub const minor: c_uint = c.LIBCURL_VERSION_MINOR;
    pub const patch: c_uint = c.LIBCURL_VERSION_PATCH;
};

/// The global copyright banner the headers carry, `include/curl/curlver.h:31`.
pub const copyright: [:0]const u8 = c.LIBCURL_COPYRIGHT;

/// The build date string in the release tarball, `include/curl/curlver.h:71`.
///
/// Upstream's own comment at `:62-67` says it is set by the packaging script
/// and is not a source date, so it describes the artifact rather than a commit.
pub const timestamp: [:0]const u8 = c.LIBCURL_TIMESTAMP;

/// The version and feature string the loaded library reports about itself.
///
/// This is `curl_version` (`include/curl/curl.h:2717`), which upstream
/// documents as "a pointer to a static buffer" and implements as one
/// (`lib/version.c:140-142`), with a comment at `:130-136` saying the string is
/// made thread-safe by always producing the same bytes. The slice is borrowed:
/// it points into a static buffer inside the library and stays valid for the
/// life of the process. Nothing is copied and nothing is freed.
///
/// Under a runtime-loaded build this is the *provider's* version, which is not
/// this package's `version` unless the provider is the library this package
/// built. A program that prints it is reporting what it reached.
pub fn versionString() [:0]const u8 {
    return std.mem.span(c.curl_version());
}

/// What the loaded library reports about itself, and what it was built with.
///
/// Every field is borrowed from one static `curl_version_info_data`
/// (`include/curl/curl.h:3138-3199`) that `curl_version_info` returns a
/// pointer to; upstream calls it "a static copy of the version info struct"
/// (`curl.h:3245`) and the implementation returns the address of one file-scope
/// object (`lib/version.c:541`, `:680`). Nothing here is copied and nothing is
/// freed, and every field stays valid for the life of the process.
pub const VersionInfo = struct {
    /// `LIBCURL_VERSION` as the *library* has it, `include/curl/curl.h:3140`,
    /// read out of the static initializer at `lib/version.c:543`.
    ///
    /// This is a runtime fact and may differ from this package's `version`
    /// under a runtime-loaded build.
    version: [:0]const u8,

    /// The same number as `LIBCURL_VERSION_NUM`, `include/curl/curl.h:3141`,
    /// from `lib/version.c:544`.
    version_num: c_uint,

    /// The OS, host, CPU and machine the library was configured for,
    /// `include/curl/curl.h:3142`. Its own comment calls it "as found by
    /// configure or set by hand at build-time", and the static initializer
    /// reads `CURL_OS` (`lib/version.c:545`), a macro from the generated
    /// configuration header. The generator this package builds always defines
    /// it, so the value is not null for a library built this way.
    host: [:0]const u8,

    /// The TLS backend's own version string, `include/curl/curl.h:3144`, or null
    /// when the library has no TLS backend compiled in.
    ///
    /// Null is a real answer and not a failure: the static initializer leaves
    /// the field null (`lib/version.c:547`) and only `USE_SSL` fills it
    /// (`lib/version.c:604-607`). A library built without TLS reports null here,
    /// which is one of the facts a caller needs before choosing to trust it.
    ssl_version: ?[:0]const u8,

    /// The feature bitmask, `include/curl/curl.h:3143`, computed at run time
    /// from the `features_table` (`lib/version.c:665-678`).
    ///
    /// It is upstream's `int`, so `c_int` and not a wider type. The bits are
    /// the `CURL_VERSION_*` constants at `include/curl/curl.h:3202-3238`;
    /// `CURL_VERSION_SSL` (`:3205`) is the one that says whether TLS options
    /// are present at all, and `CURL_VERSION_THREADSAFE` (`:3238`) is the one
    /// that says whether one `Easy` may be shared across threads.
    features: c_int,
};

/// What the loaded library reports about itself.
///
/// This is `curl_version_info(CURLVERSION_NOW)`
/// (`include/curl/curl.h:3248`), and `CURLVERSION_NOW` is upstream's own
/// "built-in version number for what kind of struct the caller expects"
/// (`curl.h:3132-3136`), currently `CURLVERSION_TWELFTH`. Every field is
/// borrowed from the library's static struct; see `VersionInfo` for what each
/// one is and for how long it stays valid.
///
/// Nothing is allocated and nothing is freed.
pub fn versionInfo() VersionInfo {
    const info = c.curl_version_info(c.CURLVERSION_NOW);
    return .{
        .version = std.mem.span(info.version),
        .version_num = info.version_num,
        .host = std.mem.span(info.host),
        .ssl_version = if (info.ssl_version) |v| std.mem.span(v) else null,
        .features = info.features,
    };
}

/// The human-readable text for one `CURLcode`, borrowed.
///
/// This is `curl_easy_strerror` (`include/curl/curl.h:3259`), which returns a
/// pointer to a string literal in a verbose build and to one of two literals
/// otherwise (`lib/strerror.c:318-323`). It never returns null and never
/// allocates, so the slice is borrowed and valid for the life of the process.
///
/// A code with no arm of its own still gets text: upstream's own fallback
/// answers "No error" for zero and "Error" for everything else, so this is the
/// string for that code rather than a claim that the code is known.
pub fn strError(code: c.CURLcode) [:0]const u8 {
    return std.mem.span(c.curl_easy_strerror(code));
}

/// The global-init flags `curl_global_init` takes, as a struct of booleans.
///
/// `curl_global_init` takes a `long` bitmask (`include/curl/curl.h:2777`) and
/// the bits are `CURL_GLOBAL_SSL` (1 << 0), `CURL_GLOBAL_WIN32` (1 << 1) and
/// `CURL_GLOBAL_ACK_EINTR` (1 << 2), at `curl.h:3044-3045` and `:3049`. This
/// names those three bits rather than asking a caller to remember them, and
/// every field defaults to `false` so `.{ .{} }` and a partial literal are both
/// valid.
///
/// The three bits and what they mean:
///
///   * `Ssl` is `CURL_GLOBAL_SSL`, and upstream's own comment at
///     `curl.h:3044` is "no purpose since 7.57.0". It is here because upstream
///     still defines it and `CURL_GLOBAL_ALL` (`:3046`) still sets it; the TLS
///     backend initializes itself regardless.
///   * `Win32` is `CURL_GLOBAL_WIN32` and is the only bit with a real effect on
///     a non-Windows build, where `lib/easy.c:183-185` casts it away.
///   * `AckIntr` is `CURL_GLOBAL_ACK_EINTR`, added for interrupted-system-call
///     handling on platforms that have it.
pub const InitFlags = packed struct {
    Win32: bool = false,
    Ssl: bool = false,
    AckIntr: bool = false,
    /// Every bit `CURL_GLOBAL_ALL` sets, which is also `CURL_GLOBAL_DEFAULT`
    /// (`include/curl/curl.h:3046`, `:3048`).
    ///
    /// This is what upstream initializes itself with when a caller has not
    /// called `curl_global_init` (`lib/easy.c:346`).
    pub const default_flags: InitFlags = .{ .Win32 = true, .Ssl = true };

    /// No bits at all, which is `CURL_GLOBAL_NOTHING`
    /// (`include/curl/curl.h:3047`): upstream accepts 0 and does no
    /// subsystem-specific work.
    pub const nothing: InitFlags = .{};

    /// The bitmask upstream's `curl_global_init` will read.
    ///
    /// The three contributions are upstream's own constants, not numbers
    /// written here, so this cannot disagree with the header if a bit moves.
    pub fn toBits(self: InitFlags) c_long {
        var bits: c_long = 0;
        if (self.Win32) bits |= c.CURL_GLOBAL_WIN32;
        if (self.Ssl) bits |= c.CURL_GLOBAL_SSL;
        if (self.AckIntr) bits |= c.CURL_GLOBAL_ACK_EINTR;
        return bits;
    }
};

/// Initialize libcurl's global state, once per matching `globalCleanup`.
///
/// This is `curl_global_init` (`include/curl/curl.h:2777`), and it is
/// refcounted: `lib/easy.c:129` returns `CURLE_OK` immediately once anything
/// has been initialized, counting the call up so that each one still needs its
/// own cleanup. Upstream also calls the same initializer itself from the first
/// `curl_easy_init` when a caller has not (`lib/easy.c:345-346`), so a program
/// that never calls this works; what it does not get is the matching
/// `globalCleanup` doing anything.
///
/// ## The refcount, and why a passing transfer proves nothing about it
///
/// `curl_global_init` is refcounted, and the count is what makes the pairing
/// mandatory rather than conventional. `lib/easy.c:129` is
/// `if(initialized++) return CURLE_OK;`: a second and later calls return
/// success without doing the work again, but each one has still incremented a
/// counter that only `curl_global_cleanup` decrements
/// (`lib/easy.c:266-269`). So one `globalInit` and two `globalCleanup` calls
/// leaves the library initialized when the program believed it had shut down,
/// and the surplus cleanup is silently ignored rather than reported.
///
/// **`globalCleanup` must not run while any `Easy` or `Multi` is still open.**
/// The count does not know about handles, so it will happily unwind the
/// library out from under one. Close every handle first.
///
/// ## Why a working program is not evidence that this was called
///
/// `curl_easy_init` initializes the library itself when a caller has not
/// (`lib/easy.c:345-353` calls `global_init(CURL_GLOBAL_DEFAULT, TRUE)`, and
/// returns null if that failed). A program that never calls `globalInit` and
/// never calls `globalCleanup` therefore performs transfers perfectly well.
///
/// That matters to a test: **a successful transfer is not evidence that the
/// explicit lifecycle was exercised.** A test that transfers a body and passes
/// has proved only that the implicit path works. The only thing that exercises
/// this call is a program or a test that calls it and pairs it with
/// `globalCleanup` after every handle is closed.
///
/// The one failure is upstream's: `curl_global_init` answers `CURLE_OK` or
/// `CURLE_FAILED_INIT` and nothing else, because the internal initializer has
/// exactly one failure exit (`lib/easy.c:195-197`) reached when the SSL, QUIC,
/// SSH, async-DNS or platform subsystem refuses to start
/// (`lib/easy.c:151-179`). That is upstream's condition, not a Zig one, so it
/// gets one tag rather than a per-subsystem taxonomy this code cannot
/// distinguish.
pub fn globalInit(flags: InitFlags) error{GlobalInitFailed}!void {
    switch (c.curl_global_init(flags.toBits())) {
        c.CURLE_OK => {},
        else => return error.GlobalInitFailed,
    }
}

/// Release one level of libcurl's global state, matching one `globalInit`.
///
/// This is `curl_global_cleanup` (`include/curl/curl.h:2807`), which undoes one
/// level of the count `globalInit` raised and does nothing at all when the
/// count is already zero (`lib/easy.c:266-269`). Calling it more often than
/// `globalInit` was called is therefore harmless and does not report an error,
/// because upstream does not.
///
/// It cannot fail and it frees nothing this module allocated. Every `Easy` and
/// `Multi` must already be closed: upstream tears down shared subsystems here,
/// and a handle still open across it is a handle whose backend is gone.
pub fn globalCleanup() void {
    c.curl_global_cleanup();
}

/// Every way `escape` or `unescape` can fail.
///
/// One tag, and the reason is upstream's rather than a choice here: a null
/// return from `curl_easy_escape` is the same null for every cause. Upstream
/// returns null for a refused length argument (`lib/escape.c:57`), for an
/// input larger than `SIZE_MAX / 16` (`:63-64`) and for a buffer its own
/// allocator could not produce (`:74-76`, `:81-83`); `curl_easy_unescape`
/// returns the same null for a failed decode allocation
/// (`lib/escape.c:171-174`, and `:116-119` inside it) and for a result too long
/// to report through its `int` out-parameter (`:177-182`). The API does not
/// distinguish them and neither does this module; a caller that needs to know
/// which happened cannot, from this or from the C.
pub const EscapeError = error{
    /// The library returned no buffer. See the note on the set.
    Failed,
};

/// Percent-encode one string, returning bytes that the caller owns.
///
/// This is `curl_easy_escape` (`include/curl/curl.h:2728`) with a null handle,
/// which is what upstream's own `curl_escape` passes
/// (`lib/escape.c:36-39`); the handle has been ignored since 7.82.0
/// (`lib/escape.c:48-49`). Upstream copies the bytes it is given rather than
/// keeping them, so `s` need not outlive the call.
///
/// ## The length comes from the NUL terminator here, and only here
///
/// `escape` may measure its own result, because a span is the right rule for it:
/// the buffer's writer stores a terminator past the last byte
/// (`lib/curlx/dynbuf.c:117`), and an empty input has a buffer of its own
/// (`lib/escape.c:60-61`). **The same rule does not hold for `unescape`, whose
/// output may contain an embedded NUL** - see that method for why, and for the
/// out-parameter that carries the real length there. Stating one rule without the
/// other is how a reader ends up truncating a value that legitimately holds a
/// zero byte.
///
/// ## What owns the result, and how to release it
///
/// The buffer comes out of libcurl's own allocator, not a Zig one:
/// `curl_easy_escape` returns either `curlx_strdup("")` for an empty input
/// (`lib/escape.c:61`) or the pointer out of a `dynbuf` (`:86`), and both are
/// `Curl_cmalloc`-family allocations. Inside libcurl's own compilation
/// `curlx_malloc` **is** `Curl_cmalloc` (`lib/curl_setup.h:1488-1493`), and that
/// is an `extern` function pointer (`lib/curl_setup.h:1320`) that a program can
/// replace through `curl_global_init_mem` (`lib/easy.c:243-247`) - so the bytes
/// need not have come from the C runtime the caller linked. Upstream's own
/// header says as much: "returns a new allocated string or NULL if an error
/// occurred" (`include/curl/curl.h:2725-2726`), with no mention of which
/// allocator.
///
/// Release it with `freeEscaped`, which routes to `curl_free`
/// (`include/curl/curl.h:2764`). An allocator's `free` is the wrong call here
/// even when both allocators happen to be the C library's, for the reason in the
/// paragraph above. This module does not wrap `curl_global_init_mem`, but a
/// program that reaches it through `pub const c` can, and then the two are not
/// the same allocator at all.
pub fn escape(s: []const u8) EscapeError![]u8 {
    return escapeRaw(s);
}

/// Percent-decode one string, returning bytes that the caller owns.
///
/// This is `curl_easy_unescape` (`include/curl/curl.h:2747-2750`) with a null
/// handle, which is what upstream's own `curl_unescape` passes
/// (`lib/escape.c:42-45`); the handle has been ignored since 7.82.0
/// (`lib/escape.c:161`). Upstream decodes into a buffer of its own
/// (`lib/escape.c:116`), so `s` need not outlive the call.
///
/// ## The length comes from upstream, never from a NUL scan
///
/// This is the one rule that `unescape` and `escape` do **not** share, and it is
/// the reason this method is not written like `escape`.
///
/// `Curl_urldecode` NUL-terminates its buffer *and* writes the decoded length
/// separately: `*ns = 0;` at `lib/escape.c:147` and `*olen = ns - *ostring;` at
/// `:149-151`. Those two are genuinely different numbers, because the decoder is
/// called with `REJECT_NADA` (`lib/escape.c:172`) and so rejects nothing: a
/// percent-encoded `%00` decodes to an embedded NUL and the terminator then sits
/// in the *middle* of the value.
///
/// That is why `curl_easy_unescape` has an `int *outlength` parameter at all,
/// and why this hands it a real out-parameter rather than null
/// (`lib/escape.c:176-182` forwards the number only when the caller supplies the
/// pointer). **Deriving the length by scanning for the NUL would silently
/// truncate a value that legitimately contains one:** the tail is still in the
/// buffer, outside the length reported, and the caller sees a shorter value with
/// no error. So the slice here is exactly `outlength` bytes long.
///
/// ## Decoding rules, which are upstream's and not adjustable here
///
/// Only `%` followed by two hex digits is decoded (`lib/escape.c:129-136`); a
/// `%` that is not followed by two hex digits is kept as three literal bytes.
/// Nothing is rejected, so a NUL byte or a control byte in the *input* passes
/// through rather than being refused - see the note above for what that means
/// for the returned length.
///
/// ## What owns the result
///
/// Identical to `escape`: the bytes are a libcurl allocation and must be
/// released with `freeEscaped`. The slice is a prefix of the buffer, so pass it
/// to `freeEscaped` **unchanged** - a sub-slice changes the pointer that frees.
pub fn unescape(s: []const u8) EscapeError![]u8 {
    return unescapeRaw(s);
}

/// Release a buffer that `escape` or `unescape` returned.
///
/// This is `curl_free` (`include/curl/curl.h:2764`), which upstream implements
/// by calling into its own allocator (`lib/escape.c:190-193`). Upstream's own
/// comment above that function is the reason this exists at all: "For
/// operating systems/environments that use different malloc/free systems for
/// the app and for this library, we provide a free that uses the library's
/// memory system".
///
/// `bytes` must be the slice `escape` or `unescape` returned, unchanged from
/// its start. Slicing it, reallocating it or passing a sub-slice changes the
/// pointer this frees, and there is no way for this function to notice.
///
/// Under a runtime-loaded build `curl_free` dispatches through the same table
/// as everything else, and needs the same `load` first; there is no second free
/// path.
pub fn freeEscaped(bytes: []u8) void {
    c.curl_free(bytes.ptr);
}

/// The one route to `curl_easy_escape`, with the wrapper's own length bound.
///
/// Upstream's length parameter is an `int` (`include/curl/curl.h:2729`) and a
/// negative one is refused (`lib/escape.c:57`), so a slice longer than
/// `INT_MAX` cannot be handed over as it stands. That bound is this wrapper's,
/// and it is reported as `Failed` because upstream's own answer for the same
/// class of input is the same null.
///
/// Upstream reads `length == 0` as "measure the string with `strlen`"
/// (`lib/escape.c:59`). An empty Zig slice does not promise a NUL at its `ptr`,
/// so an empty input is handed a pointer to a real empty C string instead;
/// upstream then measures zero and returns a fresh empty string
/// (`lib/escape.c:61`), which is the answer it would give for a NUL-terminated
/// empty slice too. For a non-empty input upstream reads exactly `length` bytes
/// and never calls `strlen`, so no terminator is promised on the way in - the
/// `@ptrCast` below is that decision written down rather than a scan's
/// requirement.
///
/// The result's length comes from the terminator, which is correct here and only
/// here; `unescapeRaw` is the case where it is not.
fn escapeRaw(s: []const u8) EscapeError![]u8 {
    if (s.len > std.math.maxInt(c_int)) return error.Failed;
    const bytes: []const u8 = if (s.len == 0) "" else s;
    const owned = c.curl_easy_escape(null, @ptrCast(bytes.ptr), @intCast(bytes.len)) orelse
        return error.Failed;
    // `lib/curlx/dynbuf.c:117` stores the terminator past the last byte, so this
    // is the real length. Release it with `freeEscaped`, never with an
    // allocator's `free`.
    return std.mem.span(owned);
}

/// The one route to `curl_easy_unescape`, with the same length bound as
/// `escapeRaw`.
///
/// The result's length is **upstream's `outlength`**, not a scan. See `unescape`
/// for why the two are different numbers and what truncating to the terminator
/// would lose. Upstream fills that out-parameter only when the decoded length
/// fits an `int` (`lib/escape.c:176-182`); when it does not, upstream frees the
/// buffer and returns the same null every other failure produces, so a negative
/// answer here would be a provider contradicting `lib/escape.c:177-178` and is
/// reported rather than turned into a huge slice.
fn unescapeRaw(s: []const u8) EscapeError![]u8 {
    if (s.len > std.math.maxInt(c_int)) return error.Failed;
    // Upstream also measures a zero length with `strlen` (`lib/escape.c:115`), so
    // an empty input gets the same real empty C string `escapeRaw` hands over.
    const bytes: []const u8 = if (s.len == 0) "" else s;
    var decoded: c_int = 0;
    const owned = c.curl_easy_unescape(
        null,
        @ptrCast(bytes.ptr),
        @intCast(bytes.len),
        &decoded,
    ) orelse return error.Failed;
    if (decoded < 0) return error.Failed;
    return owned[0..@intCast(decoded)];
}

/// The one `curl_easy_setopt` route, whichever configuration this build is.
///
/// `curl_easy_setopt` is a real C variadic (`include/curl/easy.h:42`) and the
/// two routes spell the third argument differently: the translation's own
/// declaration takes it as a promoted variadic argument, and the runtime-loaded
/// dispatch takes it as one final argument of a fixed arity.
/// `runtime_loaded` is comptime, so this build resolves the branch it has and
/// never names the other one.
///
/// `value` is the trailing argument already in the shape the option wants - a
/// `c_long`, a pointer, a callback pointer, a `?*struct_curl_slist` or a
/// `?*const struct_curl_blob` - and nothing is reinterpreted between the
/// routes; the same value reaches the same argument register.
fn setopt(handle: *c.CURL, option: c.CURLoption, value: anytype) c.CURLcode {
    if (comptime runtime_loaded) {
        return c.curl_easy_setopt(handle, option, value);
    }
    return @call(.auto, c.curl_easy_setopt, .{ handle, option, value });
}

/// The one `curl_easy_getinfo` route, whichever configuration this build is.
///
/// A real C variadic (`include/curl/easy.h:59`) with exactly one trailing
/// out-parameter, spelled as `setopt` above spells its one. Upstream reads it
/// as `void *` and switches on the type bits of the selector
/// (`lib/getinfo.c:615-672`), so the pointer's type is chosen by the selector
/// and not by the caller's declaration: a `CURLINFO_LONG` selector reads a
/// `long *`, a `CURLINFO_STRING` selector reads a `const char **`
/// (`lib/getinfo.c:634-658`).
fn getinfo(handle: *c.CURL, info: c.CURLINFO, out: anytype) c.CURLcode {
    if (comptime runtime_loaded) {
        return c.curl_easy_getinfo(handle, info, out);
    }
    return @call(.auto, c.curl_easy_getinfo, .{ handle, info, out });
}

/// The one `curl_multi_setopt` route, for the same reason as `setopt`.
///
/// A real C variadic (`include/curl/multi.h:438`). Nothing in this module calls
/// it - every `Multi` option a caller needs is a typed method - but the raw
/// route is reachable through `pub const c`, and naming it here keeps the
/// reason the variadics are spelled differently in one place.
pub fn multiSetopt(handle: *c.CURLM, option: c.CURLMoption, value: anytype) MultiError!void {
    const code = if (comptime runtime_loaded)
        c.curl_multi_setopt(handle, option, value)
    else
        @call(.auto, c.curl_multi_setopt, .{ handle, option, value });
    return codeToMultiError(code);
}

/// One `CURLcode` as one error tag, or null for `CURLE_OK`.
///
/// This is the single funnel from a raw transfer result to a Zig error. It maps
/// the codes `Easy.perform` and `Message.result` name, and answers null for
/// `CURLE_OK` rather than an error: a `CURLcode` has an OK member
/// (`include/curl/curl.h:521`) and a transfer that succeeded is an answer, not
/// a failure.
///
/// A code outside the named set becomes `Unknown`. Upstream's own comment on the
/// enum says "Future versions may return other values, stay prepared"
/// (`curl.h:513-517`), so this arm is a real possibility rather than a
/// formality; it reports that this module did not recognise the code instead of
/// guessing what it meant.
pub fn performFrom(code: c.CURLcode) ?PerformError {
    return switch (code) {
        c.CURLE_OK => null,
        c.CURLE_UNSUPPORTED_PROTOCOL => error.UnsupportedProtocol,
        c.CURLE_FAILED_INIT => error.FailedInit,
        c.CURLE_URL_MALFORMAT => error.UrlMalformat,
        c.CURLE_NOT_BUILT_IN => error.NotBuiltIn,
        c.CURLE_COULDNT_RESOLVE_PROXY => error.CouldntResolveProxy,
        c.CURLE_COULDNT_RESOLVE_HOST => error.CouldntResolveHost,
        c.CURLE_COULDNT_CONNECT => error.CouldntConnect,
        c.CURLE_WEIRD_SERVER_REPLY => error.WeirdServerReply,
        c.CURLE_REMOTE_ACCESS_DENIED => error.RemoteAccessDenied,
        c.CURLE_PARTIAL_FILE => error.PartialFile,
        c.CURLE_HTTP_RETURNED_ERROR => error.HttpReturnedError,
        c.CURLE_WRITE_ERROR => error.WriteError,
        c.CURLE_UPLOAD_FAILED => error.UploadFailed,
        c.CURLE_READ_ERROR => error.ReadError,
        c.CURLE_OUT_OF_MEMORY => error.OutOfMemory,
        c.CURLE_OPERATION_TIMEDOUT => error.OperationTimedOut,
        c.CURLE_RANGE_ERROR => error.RangeError,
        c.CURLE_SSL_CONNECT_ERROR => error.SslConnectError,
        c.CURLE_FILE_COULDNT_READ_FILE => error.FileCouldntReadFile,
        c.CURLE_ABORTED_BY_CALLBACK => error.AbortedByCallback,
        c.CURLE_BAD_FUNCTION_ARGUMENT => error.BadFunctionArgument,
        c.CURLE_INTERFACE_FAILED => error.InterfaceFailed,
        c.CURLE_TOO_MANY_REDIRECTS => error.TooManyRedirects,
        c.CURLE_SSL_ENGINE_NOTFOUND => error.SslEngineNotFound,
        c.CURLE_SEND_ERROR => error.SendError,
        c.CURLE_RECV_ERROR => error.RecvError,
        c.CURLE_SSL_CERTPROBLEM => error.SslCertProblem,
        c.CURLE_PEER_FAILED_VERIFICATION => error.PeerFailedVerification,
        c.CURLE_FILESIZE_EXCEEDED => error.FileSizeExceeded,
        c.CURLE_LOGIN_DENIED => error.LoginDenied,
        c.CURLE_REMOTE_FILE_NOT_FOUND => error.RemoteFileNotFound,
        c.CURLE_SSL_SHUTDOWN_FAILED => error.SslShutdownFailed,
        c.CURLE_AGAIN => error.Again,
        c.CURLE_SSL_CRL_BADFILE => error.SslCrlBadfile,
        c.CURLE_HTTP2_STREAM => error.Http2Stream,
        c.CURLE_RECURSIVE_API_CALL => error.RecursiveApiCall,
        c.CURLE_HTTP3 => error.Http3,
        c.CURLE_PROXY => error.Proxy,
        c.CURLE_UNRECOVERABLE_POLL => error.UnrecoverablePoll,
        c.CURLE_TOO_LARGE => error.TooLarge,
        else => error.Unknown,
    };
}

/// `CURLE_OK` as a success, every other named code as its tag.
///
/// The whole-set version of `performFrom`, for the calls that cannot report
/// success as a value: a transfer that failed has no `void` to return.
fn performOk(code: c.CURLcode) PerformError!void {
    if (performFrom(code)) |failure| return failure;
}

/// One `CURLcode` from `curl_easy_setopt` as one option error, or null for
/// `CURLE_OK`.
///
/// The set is exactly the codes `curl_easy_setopt` can return, read out of
/// `lib/setopt.c`: `CURLE_BAD_FUNCTION_ARGUMENT`, `CURLE_NOT_BUILT_IN`,
/// `CURLE_OUT_OF_MEMORY`, `CURLE_UNKNOWN_OPTION` and
/// `CURLE_UNSUPPORTED_PROTOCOL` are the only non-`OK` values in the file's
/// returns, and `curl_easy_setopt` is the sum of those dispatch tables
/// (`lib/setopt.c:2936-2955`).
fn optionFrom(code: c.CURLcode) ?OptionError {
    return switch (code) {
        c.CURLE_OK => null,
        c.CURLE_UNKNOWN_OPTION => error.UnknownOption,
        c.CURLE_OUT_OF_MEMORY => error.OutOfMemory,
        c.CURLE_BAD_FUNCTION_ARGUMENT => error.BadFunctionArgument,
        c.CURLE_NOT_BUILT_IN => error.NotBuiltIn,
        c.CURLE_UNSUPPORTED_PROTOCOL => error.OptionNotAllowedInThisBuild,
        // Unreachable for a conforming provider: `curl_easy_setopt` returns one
        // of the five codes above and nothing else (`lib/setopt.c:2936-2955`).
        // This reports a code outside that set as an argument problem rather
        // than inventing a sixth tag for an arm nothing reaches, and the choice
        // is "we were given something the function does not accept" because
        // that is the nearest thing upstream says about a setopt refusal.
        else => error.BadFunctionArgument,
    };
}

/// `CURLE_OK` as a success, every other named code as its tag.
fn optionOk(code: c.CURLcode) OptionError!void {
    if (optionFrom(code)) |failure| return failure;
}

/// One `CURLMcode` as one error tag, or null for `CURLM_OK`.
///
/// Every value of the enum gets an arm because it is nineteen lines long
/// (`include/curl/multi.h:59-78`) and upstream says "Always add new return
/// codes last. Never *EVER* remove any" for the transfer enum
/// (`include/curl/curl.h:516-517`), which is the same policy here.
///
/// `CURLM_CALL_MULTI_PERFORM` becomes `CallAgain` and not an error union
/// member: it is an instruction - "please call curl_multi_perform() or
/// curl_multi_socket*() soon" (`multi.h:60-61`) - rather than a failure, and
/// upstream aliases `CURLM_CALL_MULTI_SOCKET` onto it (`multi.h:82`).
fn multiFrom(code: c.CURLMcode) ?MultiError {
    return switch (code) {
        c.CURLM_OK => null,
        c.CURLM_CALL_MULTI_PERFORM => error.CallAgain,
        c.CURLM_BAD_HANDLE => error.BadHandle,
        c.CURLM_BAD_EASY_HANDLE => error.BadEasyHandle,
        c.CURLM_OUT_OF_MEMORY => error.OutOfMemory,
        c.CURLM_INTERNAL_ERROR => error.InternalError,
        c.CURLM_BAD_SOCKET => error.BadSocket,
        c.CURLM_UNKNOWN_OPTION => error.UnknownOption,
        c.CURLM_ADDED_ALREADY => error.AddedAlready,
        c.CURLM_RECURSIVE_API_CALL => error.RecursiveApiCall,
        c.CURLM_WAKEUP_FAILURE => error.WakeupFailure,
        c.CURLM_BAD_FUNCTION_ARGUMENT => error.BadFunctionArgument,
        c.CURLM_ABORTED_BY_CALLBACK => error.AbortedByCallback,
        c.CURLM_UNRECOVERABLE_POLL => error.UnrecoverablePoll,
        // Unreachable for a conforming provider: every value of the enum is
        // named above, including the `CURLM_LAST` marker upstream says "never
        // use" (`multi.h:77`). A code outside the set is a provider that
        // disagrees with the header, and `CURLM_INTERNAL_ERROR` is upstream's
        // own name for "this is a libcurl bug" (`multi.h:66`) - which is what a
        // value outside the published enum is.
        else => error.InternalError,
    };
}

/// `CURLM_OK` as a success, every other named code as its tag.
fn codeToMultiError(code: c.CURLMcode) MultiError!void {
    if (multiFrom(code)) |failure| return failure;
}

/// The one failure `Easy.init` and `Multi.init` can report.
///
/// Both are upstream's "could not allocate the handle", and both are a single
/// null: `curl_easy_init` returns null when its own initializer or `Curl_open`
/// fails (`lib/easy.c:345-361`) and `curl_multi_init` returns whatever
/// `Curl_multi_handle` does (`lib/multi.c:374-381`). Upstream's comment on
/// `curl_easy_init` is "If anything goes wrong, NULL is returned"
/// (`lib/easy.c:335`), and the other route to that null is a global init
/// failure rather than an exhausted allocator - so this tag is upstream's own
/// catch-all for "the handle could not be created", not a claim that `malloc`
/// failed.
pub const InitError = error{
    /// The handle could not be created. See the note on the set.
    OutOfMemory,
};

/// Every way a typed `curl_easy_setopt` can fail.
///
/// This is exactly the code set of `curl_easy_setopt`, read out of
/// `lib/setopt.c`: `CURLE_UNKNOWN_OPTION`, `CURLE_BAD_FUNCTION_ARGUMENT`,
/// `CURLE_NOT_BUILT_IN`, `CURLE_OUT_OF_MEMORY` and `CURLE_UNSUPPORTED_PROTOCOL`.
/// There is no tag for a code the function cannot return; in particular there
/// is no tag for `CURLE_INTERFACE_FAILED`, which the connect phase produces
/// (`lib/cf-socket.c:732`, `:836`, `:889`) and a setopt call never does.
pub const OptionError = error{
    /// `CURLE_UNKNOWN_OPTION`: this build does not know the option. Produced by
    /// the `default:` arm of each dispatch table, e.g. `lib/setopt.c:756`.
    UnknownOption,
    /// `CURLE_OUT_OF_MEMORY`: the option's storage could not be allocated, e.g.
    /// `lib/setopt.c:108` for a string option.
    OutOfMemory,
    /// `CURLE_BAD_FUNCTION_ARGUMENT`: the option or the value is not one the
    /// option accepts. Produced all over `lib/setopt.c`, e.g. `:56` for a null
    /// handle and `:86-87` for a string longer than `CURL_MAX_INPUT_LENGTH`.
    BadFunctionArgument,
    /// `CURLE_NOT_BUILT_IN`: the option names a capability this build does not
    /// have, e.g. an auth method with nothing supported left
    /// (`lib/setopt.c:257`) or a TLS string option behind a backend that does
    /// not offer it (`lib/setopt.c:1997`).
    NotBuiltIn,
    /// `CURLE_UNSUPPORTED_PROTOCOL`: the option's value names something this
    /// build cannot use - a protocol with no handler (`lib/setopt.c:216`) or an
    /// HTTP version this build does not speak (`lib/setopt.c:299`).
    OptionNotAllowedInThisBuild,
};

/// Every way `Easy.responseCode`, `Easy.headerSize` and `Easy.effectiveUrl` can
/// fail.
///
/// One tag, and it is upstream's: `curl_easy_getinfo` on a live handle answers
/// `CURLE_OK` or `CURLE_UNKNOWN_OPTION`. `Curl_getinfo` initializes its result
/// to `CURLE_BAD_FUNCTION_ARGUMENT` (`lib/getinfo.c:625`) but only reaches that
/// for a null handle (`lib/getinfo.c:627-628`), which this facade cannot pass;
/// every other non-OK path is the `default:` arm of one of the typed getters,
/// and they all return `CURLE_UNKNOWN_OPTION` (`lib/getinfo.c:175`, `:472`,
/// `:550`, `:612`).
pub const InfoError = error{
    /// `CURLE_UNKNOWN_OPTION`: the selector is not one this library knows.
    UnknownInfo,
};

/// Every way a `CURLcode` from a transfer becomes an error here.
///
/// Each tag is a real `CURLE_*` value from `include/curl/curl.h:520-650`, with
/// upstream's own one-line description for it in the enum. `Unknown` is the
/// one tag that is not a code: it stands for a value this module does not name,
/// which upstream's comment at `curl.h:513-517` makes a real possibility
/// because the enum is append-only across releases.
///
/// This is a shared vocabulary over the whole enum rather than a per-call list,
/// which is why it is wider than any single transfer can reach. `performOk` is
/// the funnel, and every arm of it is one line of the `CURLEcode` switch above.
pub const PerformError = error{
    /// `CURLE_UNSUPPORTED_PROTOCOL` (1), `curl.h:522`.
    UnsupportedProtocol,
    /// `CURLE_FAILED_INIT` (2), `curl.h:523`.
    FailedInit,
    /// `CURLE_URL_MALFORMAT` (3), `curl.h:524`.
    UrlMalformat,
    /// `CURLE_NOT_BUILT_IN` (4), `curl.h:525`.
    NotBuiltIn,
    /// `CURLE_COULDNT_RESOLVE_PROXY` (5), `curl.h:527`.
    CouldntResolveProxy,
    /// `CURLE_COULDNT_RESOLVE_HOST` (6), `curl.h:528`.
    CouldntResolveHost,
    /// `CURLE_COULDNT_CONNECT` (7), `curl.h:529`.
    CouldntConnect,
    /// `CURLE_WEIRD_SERVER_REPLY` (8), `curl.h:530`.
    WeirdServerReply,
    /// `CURLE_REMOTE_ACCESS_DENIED` (9), `curl.h:531`.
    RemoteAccessDenied,
    /// `CURLE_PARTIAL_FILE` (18), `curl.h:542`.
    PartialFile,
    /// `CURLE_HTTP_RETURNED_ERROR` (22), `curl.h:551`.
    HttpReturnedError,
    /// `CURLE_WRITE_ERROR` (23), `curl.h:552`.
    WriteError,
    /// `CURLE_UPLOAD_FAILED` (25), `curl.h:554`.
    UploadFailed,
    /// `CURLE_READ_ERROR` (26), `curl.h:555`.
    ReadError,
    /// `CURLE_OUT_OF_MEMORY` (27), `curl.h:556`.
    OutOfMemory,
    /// `CURLE_OPERATION_TIMEDOUT` (28), `curl.h:557`.
    OperationTimedOut,
    /// `CURLE_RANGE_ERROR` (33), `curl.h:562`.
    RangeError,
    /// `CURLE_SSL_CONNECT_ERROR` (35), `curl.h:564`.
    SslConnectError,
    /// `CURLE_FILE_COULDNT_READ_FILE` (37), `curl.h:566`.
    FileCouldntReadFile,
    /// `CURLE_ABORTED_BY_CALLBACK` (42), `curl.h:571`.
    AbortedByCallback,
    /// `CURLE_BAD_FUNCTION_ARGUMENT` (43), `curl.h:572`.
    BadFunctionArgument,
    /// `CURLE_INTERFACE_FAILED` (45), `curl.h:574`.
    InterfaceFailed,
    /// `CURLE_TOO_MANY_REDIRECTS` (47), `curl.h:576`.
    TooManyRedirects,
    /// `CURLE_SSL_ENGINE_NOTFOUND` (53), `curl.h:582`.
    SslEngineNotFound,
    /// `CURLE_SEND_ERROR` (55), `curl.h:585`.
    SendError,
    /// `CURLE_RECV_ERROR` (56), `curl.h:586`.
    RecvError,
    /// `CURLE_SSL_CERTPROBLEM` (58), `curl.h:588`.
    SslCertProblem,
    /// `CURLE_PEER_FAILED_VERIFICATION` (60), `curl.h:590`.
    PeerFailedVerification,
    /// `CURLE_FILESIZE_EXCEEDED` (63), `curl.h:594`.
    FileSizeExceeded,
    /// `CURLE_LOGIN_DENIED` (67), `curl.h:599`.
    LoginDenied,
    /// `CURLE_REMOTE_FILE_NOT_FOUND` (78), `curl.h:612`.
    RemoteFileNotFound,
    /// `CURLE_SSL_SHUTDOWN_FAILED` (80), `curl.h:617`.
    SslShutdownFailed,
    /// `CURLE_AGAIN` (81), `curl.h:619`.
    Again,
    /// `CURLE_SSL_CRL_BADFILE` (82), `curl.h:622`.
    SslCrlBadfile,
    /// `CURLE_HTTP2_STREAM` (92), `curl.h:636`.
    Http2Stream,
    /// `CURLE_RECURSIVE_API_CALL` (93), `curl.h:638`.
    RecursiveApiCall,
    /// `CURLE_HTTP3` (95), `curl.h:642`.
    Http3,
    /// `CURLE_PROXY` (97), `curl.h:644`.
    Proxy,
    /// `CURLE_UNRECOVERABLE_POLL` (99), `curl.h:646`.
    UnrecoverablePoll,
    /// `CURLE_TOO_LARGE` (100), `curl.h:647`.
    TooLarge,
    /// A `CURLcode` outside the set named above. See the note on the set.
    Unknown,
};

/// Every way a `Multi` call can fail.
///
/// Each tag is a real `CURLMcode` from `include/curl/multi.h:59-78`. `CallAgain`
/// is the one that is not a failure: it is upstream's way of saying the
/// application should call `curl_multi_perform` or `curl_multi_socket*` again
/// soon (`multi.h:60-61`).
pub const MultiError = error{
    /// `CURLM_CALL_MULTI_PERFORM` (-1), `multi.h:60`. Not a failure; an
    /// instruction to keep driving the handle.
    CallAgain,
    /// `CURLM_BAD_HANDLE` (2), `multi.h:63`.
    BadHandle,
    /// `CURLM_BAD_EASY_HANDLE` (3), `multi.h:64`.
    BadEasyHandle,
    /// `CURLM_OUT_OF_MEMORY` (5), `multi.h:65`.
    OutOfMemory,
    /// `CURLM_INTERNAL_ERROR` (6), `multi.h:66`.
    InternalError,
    /// `CURLM_BAD_SOCKET` (7), `multi.h:67`.
    BadSocket,
    /// `CURLM_UNKNOWN_OPTION` (8), `multi.h:68`.
    UnknownOption,
    /// `CURLM_ADDED_ALREADY` (9), `multi.h:69`.
    AddedAlready,
    /// `CURLM_RECURSIVE_API_CALL` (10), `multi.h:71`.
    RecursiveApiCall,
    /// `CURLM_WAKEUP_FAILURE` (11), `multi.h:73`.
    WakeupFailure,
    /// `CURLM_BAD_FUNCTION_ARGUMENT` (12), `multi.h:74`.
    BadFunctionArgument,
    /// `CURLM_ABORTED_BY_CALLBACK` (13), `multi.h:75`.
    AbortedByCallback,
    /// `CURLM_UNRECOVERABLE_POLL` (14), `multi.h:76`.
    UnrecoverablePoll,
};

/// A callback libcurl calls with the body of a response.
///
/// This is upstream's `curl_write_callback`
/// (`include/curl/curl.h:285-288`), spelled out:
///
/// ```c
/// typedef size_t (*curl_write_callback)(char *buffer,
///                                      size_t size,
///                                      size_t nitems,
///                                      void *outstream);
/// ```
///
/// Four parameters, and the user data is **last**. The order is the ABI and is
/// not negotiable: libcurl stores this pointer in `data->set.fwrite_func`
/// (declared `curl_write_callback`, `lib/urldata.h:840`) and calls it with four
/// arguments, and upstream's own default is libc's `fwrite` cast into this
/// type (`lib/url.c:326`) - `fwrite(char *, size_t, size_t, FILE *)`, four
/// arguments, user data last. A five-parameter function would be called with
/// four and read whatever the fifth slot happened to hold.
///
/// `buffer` is `[ *c]u8` rather than a slice and is mutable because upstream's
/// first parameter is `char *`: a callback type that did not match the C
/// declaration would not compile against `data->set.fwrite_func`.
///
/// There is no separate header-callback typedef upstream. `CURLOPT_HEADERFUNCTION`
/// reuses this exact shape (`include/curl/curl.h:1428`), which is why
/// `HeaderCallback` below is the same function type under a second name rather
/// than a distinct one: libcurl has one write-callback signature, used for the
/// body and for the headers.
///
/// ## The parameter names are load-bearing
///
/// `size` is the unit libcurl passes and `nitems` is how many of them there
/// are, so the byte count is `size * nitems` - not the pair read the other way
/// round, and not either of them alone. Upstream always passes
/// `sizeof(size_t)` as the unit, so `size * nitems == nitems` in practice; the
/// product is still the documented contract, and both option comments say the
/// parameters use `fwrite` syntax (`curl.h:1186`, `:1427`). `chunkLength` below
/// forms the product with the overflow check this module offers in place of
/// trusting the multiplication.
///
/// ## The return value is a control code, not an error
///
///   * A count equal to `size * nitems` means the bytes were taken.
///   * A shorter count is upstream's "abort the transfer" signal; the transfer
///     ends with `CURLE_ABORTED_BY_CALLBACK` (`curl.h:571`). `CURLE_WRITE_ERROR`
///     (`curl.h:552`) is the neighbouring code, not this one.
///   * `CURL_WRITEFUNC_PAUSE` (`curl.h:279`) pauses receiving, and
///     `curl_easy_pause` (`curl.h:3281`) resumes it. Its value is a sentinel,
///     not a count.
///   * `CURL_WRITEFUNC_ERROR` (`curl.h:283`) is the full-width `0xFFFFFFFF`.
///
/// `outstream` is whatever the option's companion data option was set to. The
/// asymmetry with the facade's own method signature is deliberate and is worth
/// stating: `Easy.setWriteFunction` takes `ctx` **first** because that is how a
/// caller wants to read it, and libcurl delivers it **last** because that is the
/// C signature. The method passes `ctx` through to `CURLOPT_WRITEDATA` and
/// libcurl hands it back in this fourth parameter; nothing reorders them.
pub const WriteCallback = *const fn (
    buffer: [*c]u8,
    size: usize,
    nitems: usize,
    outstream: ?*anyopaque,
) callconv(.c) usize;

/// A callback libcurl calls with one header line.
///
/// This is the same function type as `WriteCallback` under a second name, and
/// it is the same C type too: `CURLOPT_HEADERFUNCTION` takes a
/// `curl_write_callback` (`include/curl/curl.h:1428`), and libcurl has only one
/// write-callback signature. Two names, one type, so a caller can pass one
/// function where either option wants it.
///
/// A header callback sees each header line as it arrives, including the blank
/// line that ends a header block, and it sees them whether or not a body
/// follows. A callback returning a short count aborts the transfer exactly as
/// for `WriteCallback`; see that type for the full contract.
///
/// Upstream also offers a typed route over parsed headers:
/// `curl_easy_header` and `curl_easy_nextheader`
/// (`include/curl/header.h:58-68`) hand back a `struct curl_header`, re-exported
/// here as `Header`. Those pointers are borrowed and valid until the next
/// libcurl call on that handle, which is why this module re-exports the struct
/// rather than wrapping it in an owning type it cannot honour.
pub const HeaderCallback = *const fn (
    buffer: [*c]u8,
    size: usize,
    nitems: usize,
    outstream: ?*anyopaque,
) callconv(.c) usize;

/// The bytes one `WriteCallback` or `HeaderCallback` invocation carries, or null
/// if the product does not fit in a `usize`.
///
/// The callback is handed `size` and `nitems` and is entitled to treat
/// `size * nitems` bytes as readable at `buffer` (`include/curl/curl.h:285-288`).
/// Forming that product is the caller's arithmetic, and an ordinary checked
/// multiplication is what this module offers in place of trusting it: null
/// means the product is not representable, and a caller that sees null must not
/// form the slice.
///
/// A result of 0 means the callback was invoked with no bytes, which upstream
/// treats as a no-op; it is not an error.
pub fn chunkLength(len: usize, nmemb: usize) ?usize {
    return std.math.mul(usize, len, nmemb) catch null;
}

/// One descriptor for the multi interface's own poll, upstream's struct.
///
/// This is `struct curl_waitfd` (`include/curl/multi.h:113-117`) and it is
/// upstream's type, re-exported rather than restated: `fd` is a
/// `curl_socket_t`, which is an `int` everywhere except Windows
/// (`include/curl/curl.h:140-150`), and restating it as a fixed-width integer
/// would be wrong on one of the six cross targets this package builds for.
///
/// `events` and `revents` are the same `short`-based vocabulary upstream uses
/// when it fills the array: `CURL_WAIT_POLLIN`, `CURL_WAIT_POLLPRI` and
/// `CURL_WAIT_POLLOUT` (`multi.h:109-111`) are the values to read `revents`
/// against. The array `Multi.poll` writes is the caller's, and upstream says so
/// at `multi.h:167`: "Poll on all fds within a CURLM set as well as any
/// additional fds passed to the function".
pub const WaitFd = c.struct_curl_waitfd;

/// One entry of the `curl_slist` chain, upstream's struct.
///
/// This is `struct curl_slist` (`include/curl/curl.h:2823-2826`) with its two
/// members exactly as upstream declares them, `char *data` and
/// `struct curl_slist *next`. A caller that walks it reads `data` as a NUL
/// terminated string and `next` until it is null; `SList` below is the owning
/// wrapper and the reason a caller usually wants that instead.
pub const SListNode = c.struct_curl_slist;

/// One header libcurl parsed, upstream's struct.
///
/// This is `struct curl_header` (`include/curl/header.h:31-38`) and it is
/// upstream's type. `curl_easy_header` and `curl_easy_nextheader`
/// (`header.h:58-68`) hand back a borrowed pointer to one of these and the
/// pointer stays valid until the next libcurl call on that handle, which is
/// upstream's own contract and the reason this module does not wrap the header
/// route with an owning type.
pub const Header = c.struct_curl_header;

/// What kind of option a `CURLoption` takes, from upstream's own enum.
///
/// This is `curl_easytype` (`include/curl/options.h:31-41`) and the comments
/// in it are upstream's: `long` for a range of values, a defined set or bitmask,
/// `curl_off_t`, a plain `void *`, a NUL terminated string, a `curl_slist *`, a
/// pointer handed to a callback unchanged, a `curl_blob`, or a function pointer.
/// `optionByName` and `optionById` answer this for a selector, and the answer
/// decides what the trailing argument of `curl_easy_setopt` has to be.
pub const OptionType = enum(c_int) {
    /// `CURLOT_LONG` (`options.h:32`), a `long` in `curl_easy_setopt`.
    long = c.CURLOT_LONG,
    /// `CURLOT_VALUES` (`options.h:33`), a `long` carrying one of a defined
    /// set or a bitmask.
    values = c.CURLOT_VALUES,
    /// `CURLOT_OFF_T` (`options.h:34`), a `curl_off_t`.
    off_t = c.CURLOT_OFF_T,
    /// `CURLOT_OBJECT` (`options.h:35`), a `void *`.
    object = c.CURLOT_OBJECT,
    /// `CURLOT_STRING` (`options.h:36`), a NUL terminated `char *`.
    string = c.CURLOT_STRING,
    /// `CURLOT_SLIST` (`options.h:37`), a `struct curl_slist *`.
    slist = c.CURLOT_SLIST,
    /// `CURLOT_CBPTR` (`options.h:38`), a `void *` passed to a callback
    /// unchanged.
    cb_ptr = c.CURLOT_CBPTR,
    /// `CURLOT_BLOB` (`options.h:39`), a `struct curl_blob *`.
    blob = c.CURLOT_BLOB,
    /// `CURLOT_FUNCTION` (`options.h:40`), a function pointer.
    function = c.CURLOT_FUNCTION,
};

/// The `CURLOT_FLAG_ALIAS` bit (`options.h:47`), meaning the name is kept for
/// old programs and a different one is preferred.
///
/// Upstream's comment at `options.h:45-46` says exactly that: "alias" means it
/// is provided for old programs to remain functional, we prefer another name.
pub const option_flag_alias: c_uint = c.CURLOT_FLAG_ALIAS;

/// The `curl_easyoption` record `optionByName` and `optionById` answer.
///
/// This is `struct curl_easyoption` (`include/curl/options.h:51-56`) and it is
/// upstream's type, re-exported rather than restated. Its four members are the
/// name, the selector, the `OptionType` and the flags.
pub const OptionInfo = c.struct_curl_easyoption;

/// The selector for one option name, borrowed, or null when no such option
/// exists.
///
/// This is `curl_easy_option_by_name` (`include/curl/options.h:58-59`), which
/// searches the table upstream generates from the `CURLOPT` list. The record it
/// returns is a `const struct curl_easyoption *` into that table
/// (`options.h:52-55`), so it is borrowed, static and valid for the life of the
/// process; nothing is copied and nothing is freed.
///
/// `name` is matched against the NUL terminated names upstream generates from
/// the `CURLOPT(...)` list (`include/curl/curl.h:1132`), which is why the
/// spelling is upstream's rather than one invented here. Upstream compares it as
/// a C string, so **`name` has to be NUL terminated**, and the signature says so:
/// `[:0]const u8` is a compile-time requirement rather than a comment.
///
/// This was a `[]const u8` parameter scanned with `std.mem.span` before. A
/// scan reads memory the caller never promised was readable, so a slice that
/// was not terminated handed upstream a name with whatever bytes followed it.
/// The compiler now says it instead, which is the one honest thing this
/// function's signature gives up.
///
/// `optionById` is the same table keyed the other way
/// (`include/curl/options.h:61-62`) and has no such requirement.
pub fn optionByName(name: [:0]const u8) ?*const OptionInfo {
    return c.curl_easy_option_by_name(name.ptr);
}

/// The record for one selector, borrowed, or null when the selector is not one
/// upstream knows.
///
/// This is `curl_easy_option_by_id` (`include/curl/options.h:61-62`). The
/// answer is borrowed and static, like `optionByName`'s.
pub fn optionById(id: c.CURLoption) ?*const OptionInfo {
    return c.curl_easy_option_by_id(id);
}

/// The record after `prev` in upstream's option table, or null at the end.
///
/// This is `curl_easy_option_next` (`include/curl/options.h:64-65`), which
/// takes a null to start. Walking the whole table with `optionById` +
/// `optionNext` is how a caller enumerates what this build supports, and it is
/// the only way to learn the options that are not the ones this module names.
pub fn optionNext(prev: ?*const OptionInfo) ?*const OptionInfo {
    return c.curl_easy_option_next(prev);
}

/// `CURLE_*` as one error tag: the whole funnel, for the caller that wants it.
///
/// The same mapping `performFrom` uses, and for the same reason: `Multi` reports
/// a finished transfer's outcome as a `CURLcode` in its message
/// (`include/curl/multi.h:99-102`), and this is how that value becomes a Zig
/// error without the caller reaching for the raw route. A `CURLE_OK` answer is
/// null, because success is not a failure.
pub fn performErrorFrom(code: c.CURLcode) ?PerformError {
    return performFrom(code);
}

/// One transfer handle: the "easy" interface, and the synchronous route.
///
/// An `Easy` owns exactly one `CURL`. `init` creates one through
/// `curl_easy_init` (`include/curl/easy.h:41`) and `deinit` closes that same one
/// through the same `c` route that created it, so a handle created by one
/// provider is always closed by that provider.
///
/// ## What `deinit` means, and why there is no `isOpen`
///
/// `deinit` stores `undefined` into the handle field. That is a real state
/// transition with no third value to represent: the wrapper is unusable
/// afterwards, and there is nothing for a predicate to test. Copying an `Easy`
/// before `deinit` gives two owners of one handle and only one of them should
/// close it - Zig cannot make a struct non-copyable.
///
/// The observable fact after `deinit` is an ownership fact, not a readable
/// field: the pointer the wrapper held is the one `curl_easy_cleanup` consumed
/// and released (`lib/easy.c:855-867`), and the wrapper no longer refers to it.
/// Reading the field to confirm that is not something this module supports.
///
/// ## The one transfer route, and the loop route
///
/// `perform` is the synchronous route: it runs the whole transfer and returns
/// when the transfer is over. A program that needs to interleave several
/// transfers, or to do other work while one runs, drives the same handle through
/// a `Multi` instead; `Multi.addEasy` takes an `Easy` and nothing about the
/// handle changes. The two are alternatives, not stages.
pub const Easy = struct {
    /// The owned handle, or `undefined` once `deinit` has run.
    ///
    /// Optional rather than a raw pointer only so the type can express the
    /// pre-`init` state of a `var easy: Easy = .{}`; `init` is the only way to
    /// get a real one.
    raw: ?*c.CURL = null,

    /// Create a handle with every option at its default.
    ///
    /// This is `curl_easy_init` (`include/curl/easy.h:41`). Upstream's own
    /// comment is "If anything goes wrong, NULL is returned"
    /// (`lib/easy.c:335`), and there are exactly two ways to get there: its
    /// implicit global initializer fails (`lib/easy.c:345-352`) or `Curl_open`
    /// fails (`lib/easy.c:357-361`). The second is an exhausted allocator; the
    /// first is not, which is why `InitError.OutOfMemory` is upstream's own
    /// catch-all name for "no handle" rather than a claim about `malloc`.
    ///
    /// Upstream initializes the library itself here when a caller has not, so
    /// this works without `globalInit` - see `globalInit` for why that makes a
    /// passing transfer no evidence at all about the explicit lifecycle.
    pub fn init() InitError!Easy {
        const raw = c.curl_easy_init() orelse return error.OutOfMemory;
        return .{ .raw = raw };
    }

    /// Close the handle and everything it owns.
    ///
    /// This is `curl_easy_cleanup` (`include/curl/easy.h:44`), which closes the
    /// handle (`lib/easy.c:855-867`) and with it the connection, DNS and session
    /// state the handle held. It cannot fail and upstream reports no code for
    /// it, so there is nothing here to report either.
    ///
    /// ## What this does not account for
    ///
    /// Every byte libcurl allocated for this handle is released with it, but the
    /// module cannot *prove* that and a Zig test allocator cannot be given an
    /// oracle for it: the memory came out of libcurl's own allocator
    /// (`Curl_cmalloc`, `lib/easy.c:109-113`), not out of a Zig one. "The handle
    /// was closed" is the whole claim. See the module note on allocation.
    ///
    /// ## State transition
    ///
    /// The field becomes `undefined`, so the wrapper cannot be used again. See
    /// the note on `Easy` itself.
    pub fn deinit(self: *Easy) void {
        const raw = self.raw orelse return;
        self.raw = undefined;
        c.curl_easy_cleanup(raw);
    }

    /// The raw handle, for anything the facade does not wrap.
    ///
    /// Stopping the program on a closed handle is deliberate, and it is an
    /// ordinary comparison rather than a `std.debug.assert`: `deinit` stores
    /// `undefined`, a call into a closed `CURL` is not a condition to recover
    /// from, and `std.debug.assert` is stripped in `ReleaseFast`, so it would not
    /// be this check at all in the mode that would run.
    pub fn handle(self: *const Easy) *c.CURL {
        return self.raw orelse @panic(
            "libcurl: this Easy was closed. deinit() stores undefined into " ++
                "the handle, so there is no state to call into. Check your own " ++
                "flag if the lifetime is not obvious.",
        );
    }

    /// The URL to transfer.
    ///
    /// This is `CURLOPT_URL` (`include/curl/curl.h:1159`), reached through
    /// `curl_easy_setopt`. Upstream **copies** the bytes: the option goes to
    /// `Curl_setstropt` (`lib/setopt.c:2345`), which stores through
    /// `CURL_EASY_STR_SET` (`lib/urldata.h:1229-1230`) into
    /// `Curl_u8_strset_setx`, whose first act is `val = curlx_memdup0(str, slen)`
    /// (`lib/uint-hashset.c:251`). So `url` need not outlive the call.
    ///
    /// ## `url` must be a NUL terminated string
    ///
    /// Copying is not the same as measuring: upstream computes
    /// `size_t slen = s ? strlen(s) : 0;` (`lib/setopt.c:84`) before copying, so
    /// it reads to the first NUL rather than to `url.len`. **`url` therefore has
    /// to be NUL terminated**, and the signature says so: `[:0]const u8` makes
    /// the compiler enforce it.
    ///
    /// This was a `[]const u8` parameter scanned with `std.mem.span` before.
    /// `mem.span` reads forward from `url.ptr` looking for a NUL, so a caller
    /// that built the URL in a stack buffer and passed `buf[0..n]` -- the shape
    /// `std.fmt.bufPrint` returns, and it does **not** terminate -- had every
    /// byte after the URL appended to it. Those bytes went onto the wire inside
    /// the request target, which is how a fixture asked for `/fixture.txt`
    /// answered this route 404 and the body digest mismatched. That is the whole
    /// class: a scan over memory whose extent the caller never promised.
    ///
    /// To build one, terminate the buffer yourself:
    /// `bufPrint(&buf, ...)` then `buf[0..n :0]`.
    ///
    /// That is the opposite of `setHeaders`, which borrows. Both rules are
    /// stated because a reader who sees only one of them will get it backwards:
    /// **string options copy, slist options borrow.**
    ///
    /// A URL longer than `CURL_MAX_INPUT_LENGTH` is refused by upstream
    /// (`lib/setopt.c:86-87`); an empty one clears the option, because
    /// `Curl_setstropt` measures a null as a zero length (`lib/setopt.c:84`) and
    /// stores nothing.
    pub fn setUrl(self: *Easy, url: [:0]const u8) OptionError!void {
        try optionOk(setopt(self.handle(), c.CURLOPT_URL, url.ptr));
    }

    /// Send the response body to `f`, delivering `ctx` as the callback's
    /// `outstream`.
    ///
    /// Two options, because libcurl has two: `CURLOPT_WRITEFUNCTION`
    /// (`include/curl/curl.h:1187`) takes the function and `CURLOPT_WRITEDATA`
    /// (`curl.h:1156`) takes the pointer. Upstream stores the function in
    /// `data->set.fwrite_func` and the pointer in `data->set.out`, and both of
    /// those cases are a plain assignment followed by `break`
    /// (`lib/setopt.c:2575-2587` and `:2311-2313`), so both calls answer
    /// `CURLE_OK` on every path and there is no code to report. That is why this
    /// returns `void` and discards what cannot fail.
    ///
    /// `ctx` is stored, not copied, and libcurl hands it back unchanged as the
    /// callback's fourth argument. See `WriteCallback` for the parameter order
    /// that comes with it and for the return values that mean something other
    /// than "taken".
    ///
    /// The function is not optional. Upstream does accept a null body callback,
    /// by substituting libc's `fwrite` (`lib/setopt.c:2578-2586`), which writes
    /// to a `FILE *` this module has no way to hand it; a caller that wants the
    /// default back should say so deliberately through `c.curl_easy_setopt`
    /// rather than reach it by accident through a null.
    pub fn setWriteFunction(self: *Easy, ctx: ?*anyopaque, f: WriteCallback) void {
        const raw = self.handle();
        _ = setopt(raw, c.CURLOPT_WRITEFUNCTION, @as(?*const anyopaque, @ptrCast(f)));
        _ = setopt(raw, c.CURLOPT_WRITEDATA, ctx);
    }

    /// Send each response header line to `f`, delivering `ctx` as the callback's
    /// `outstream`; a null function restores libcurl's default.
    ///
    /// `CURLOPT_HEADERFUNCTION` (`include/curl/curl.h:1428`) and
    /// `CURLOPT_HEADERDATA` (`curl.h:1265`). Upstream stores them in
    /// `data->set.fwrite_header` and `data->set.writeheader`, again as plain
    /// assignments with no error path (`lib/setopt.c:2569-2573`, `:2305-2307`),
    /// so the discarded codes cannot fail.
    ///
    /// Null is meaningful here, unlike for the body callback: upstream's case
    /// simply stores the pointer (`lib/setopt.c:2569-2573`), so null removes the
    /// callback and headers go back to libcurl's own handling. `CURLOPT_HEADER`
    /// (`curl.h:1304`) is the separate option that makes headers part of the
    /// *body* instead.
    pub fn setHeaderFunction(self: *Easy, ctx: ?*anyopaque, f: ?HeaderCallback) void {
        const raw = self.handle();
        const function: ?*const anyopaque = if (f) |callback| @ptrCast(callback) else null;
        _ = setopt(raw, c.CURLOPT_HEADERFUNCTION, function);
        _ = setopt(raw, c.CURLOPT_HEADERDATA, ctx);
    }

    /// The whole-transfer timeout, in milliseconds.
    ///
    /// This is `CURLOPT_TIMEOUT_MS` (`include/curl/curl.h:1715`), which upstream
    /// routes to `setopt_set_timeout_ms` (`lib/setopt.c:816-817`). That function
    /// refuses a negative value with `CURLE_BAD_FUNCTION_ARGUMENT`
    /// (`lib/setopt.c:69-70`) and clamps an over-large one to the internal
    /// maximum while still answering `CURLE_OK` (`lib/setopt.c:72-75`), so the
    /// one failure a caller can reach is the negative one.
    ///
    /// Zero means no timeout. This is the *whole* transfer, connect included;
    /// `CURLOPT_CONNECTTIMEOUT_MS` (`curl.h:1716`) is the connect phase alone.
    pub fn setTimeoutMs(self: *Easy, ms: c_long) OptionError!void {
        try optionOk(setopt(self.handle(), c.CURLOPT_TIMEOUT_MS, ms));
    }

    /// Whether to follow `Location` headers.
    ///
    /// This is `CURLOPT_FOLLOWLOCATION` (`include/curl/curl.h:1332`). Upstream
    /// validates the value - anything above 3 is `CURLE_BAD_FUNCTION_ARGUMENT`
    /// (`lib/setopt.c:1023-1024`) - which is why this takes a `bool` rather than
    /// the `long` upstream reads: a boolean cannot produce a value upstream
    /// refuses, so there is no code left to report and the return is `void`.
    ///
    /// Following is off by default and it has a ceiling: without
    /// `CURLOPT_MAXREDIRS` (`curl.h:1388`) upstream's own default applies, and
    /// exceeding it ends the transfer with `CURLE_TOO_MANY_REDIRECTS`
    /// (`curl.h:576`).
    pub fn setFollowLocation(self: *Easy, on: bool) void {
        _ = setopt(self.handle(), c.CURLOPT_FOLLOWLOCATION, boolToLong(on));
    }

    /// Whether libcurl narrates what it is doing on stderr.
    ///
    /// This is `CURLOPT_VERBOSE` (`include/curl/curl.h:1301`). Upstream's case is
    /// reached through `setopt_long_bool`, whose every arm is a plain assignment
    /// and whose function ends with an unconditional `return CURLE_OK`
    /// (`lib/setopt.c:363-763`), so nothing here can fail. Off by default.
    pub fn setVerbose(self: *Easy, on: bool) void {
        _ = setopt(self.handle(), c.CURLOPT_VERBOSE, boolToLong(on));
    }

    /// Replace the request's header lines with `list`, or clear them with a
    /// null.
    ///
    /// This is `CURLOPT_HTTPHEADER` (`include/curl/curl.h:1245`), which upstream
    /// routes to `setopt_slist` (`lib/setopt.c:2895-2905`).
    ///
    /// ## This borrows; `SList.append` copies. Both rules, because they are
    /// opposite and a reader who has only one of them gets it backwards.
    ///
    /// Upstream stores **the caller's pointer** and nothing else: the option's
    /// whole case is `s->headers = slist; break;` (`lib/setopt.c:1358-1363`).
    /// There is no copy and no refcount, so:
    ///
    ///   * the list must outlive every transfer made with this handle, including
    ///     one already in progress;
    ///   * the caller still owns the list afterwards, and closing the easy handle
    ///     does not free it. `SList.freeAll` is the caller's to call, and calling
    ///     it while a transfer is using the list is a use-after-free libcurl
    ///     cannot detect.
    ///
    /// `curl_slist_append` is the opposite operation and **does** copy: its first
    /// statement is `char *dupdata = curlx_strdup(data);` (`lib/slist.c:87`), and
    /// the chain node it links is then owned by the list. So a *line* passed to
    /// `append` need not outlive the call, while the *list* passed to this method
    /// must.
    ///
    /// Null clears the option: the case stores whatever it is given
    /// (`lib/setopt.c:1358-1363`), and a null store is how the built-in headers
    /// come back.
    pub fn setHeaders(self: *Easy, list: ?*SList) OptionError!void {
        const chain: ?*c.struct_curl_slist = if (list) |owned| owned.raw() else null;
        try optionOk(setopt(self.handle(), c.CURLOPT_HTTPHEADER, chain));
    }

    /// Run the transfer to completion.
    ///
    /// This is `curl_easy_perform` (`include/curl/easy.h:43`), and it is
    /// synchronous: it returns when the transfer has finished, so a program that
    /// needs to do other work meanwhile drives the same handle through a `Multi`
    /// instead.
    ///
    /// Every outcome other than `CURLE_OK` becomes a `PerformError`; success has
    /// no value to return. `CURLE_OK` is not proof that the transfer did what the
    /// caller wanted: upstream returns `CURLE_HTTP_RETURNED_ERROR`
    /// (`curl.h:551`) for an HTTP error status *unless* `CURLOPT_FAILONERROR`
    /// (`curl.h:1313`) is set, so `responseCode` is what says whether the server
    /// was happy.
    pub fn perform(self: *Easy) PerformError!void {
        try performOk(c.curl_easy_perform(self.handle()));
    }

    /// The HTTP status code the server answered with.
    ///
    /// This is `CURLINFO_RESPONSE_CODE` (`include/curl/curl.h:2932`), a
    /// `CURLINFO_LONG` selector (`curl.h:2920`), so upstream writes a `long`
    /// through the out-parameter and the value is `data->info.httpcode`
    /// (`lib/getinfo.c:221-223`): the server's status code, or 0 when no HTTP
    /// response was received.
    ///
    /// The value is widened to `u64`, and upstream's is never negative - it is a
    /// status code or 0 - so the widening is checked rather than assumed. A
    /// provider that answered a negative number is stopped here, with a message,
    /// instead of being read as an enormous status code.
    pub fn responseCode(self: *const Easy) InfoError!u64 {
        const status: c_long = try readLongInfo(self, c.CURLINFO_RESPONSE_CODE);
        if (status < 0) @panic(
            "libcurl: CURLINFO_RESPONSE_CODE answered a negative value. Upstream " ++
                "stores a status code or zero (lib/getinfo.c:221-223), so this " ++
                "is a provider that disagrees with the header.",
        );
        return @intCast(status);
    }

    /// How many bytes of headers the transfer produced.
    ///
    /// This is `CURLINFO_HEADER_SIZE` (`include/curl/curl.h:2952`), also a
    /// `CURLINFO_LONG`, read from `data->info.header_size`
    /// (`lib/getinfo.c:237-239`). The unit is bytes and it counts what libcurl
    /// parsed, not what a caller's header callback was handed.
    ///
    /// Widened to `u64` for the same reason and under the same check as
    /// `responseCode`.
    pub fn headerSize(self: *const Easy) InfoError!u64 {
        const bytes: c_long = try readLongInfo(self, c.CURLINFO_HEADER_SIZE);
        if (bytes < 0) @panic(
            "libcurl: CURLINFO_HEADER_SIZE answered a negative value. Upstream " ++
                "stores a byte count (lib/getinfo.c:237-239), so this is a " ++
                "provider that disagrees with the header.",
        );
        return @intCast(bytes);
    }

    /// The URL libcurl actually used, **borrowed**.
    ///
    /// This is `CURLINFO_EFFECTIVE_URL` (`include/curl/curl.h:2931`), a
    /// `CURLINFO_STRING` selector, so upstream writes a `const char *` through
    /// the out-parameter (`lib/getinfo.c:634-637`).
    ///
    /// ## Where the bytes live, and why there is no free function
    ///
    /// The string is **not** allocated for the caller and must not be freed. The
    /// whole of upstream's case is:
    ///
    /// ```c
    /// case CURLINFO_EFFECTIVE_URL: {
    ///   const char *s = Curl_bufref_ptr(&data->state.url);
    ///   *param_charp = s ? s : "";
    /// }
    /// ```
    ///
    /// (`lib/getinfo.c:83-87`). That is a pointer into the handle's own URL
    /// buffer, `data->state.url`, which got its bytes when the option was set:
    /// `case CURLOPT_URL:` stores into `STRING_SET_URL` and then points
    /// `state.url` at it (`lib/setopt.c:2344-2347`). Upstream says the same shape
    /// out loud for its neighbouring string selector - "Callers must never free it
    /// themselves" (`lib/getinfo.c:124-130`) - and it applies here for the same
    /// reason.
    ///
    /// So there is no `freeEffectiveUrl`, and adding one would be a bug. The
    /// consequences a caller has to live with:
    ///
    ///   * the slice is valid until the URL changes or the handle is closed, and
    ///     not one moment longer. A later `setUrl` or transfer may reallocate
    ///     that buffer, and the old slice then points into freed memory;
    ///   * copy it if it has to outlive the next thing done to this handle.
    ///
    /// The return is optional because the C contract is: upstream writes through
    /// a plain `const char *` out-parameter and a provider may leave it null
    /// (`lib/getinfo.c:635-637`). With the library this package builds the answer
    /// is never null on success - upstream substitutes `""` for the null at
    /// `lib/getinfo.c:85` - so the optional is the C boundary being kept rather
    /// than a claim that libcurl sometimes has no URL to report.
    ///
    /// `include/curl/curl.h:2931` is only the bare enumerator and says nothing
    /// about ownership; the lines above are where the ownership is.
    pub fn effectiveUrl(self: *const Easy) InfoError!?[]const u8 {
        var text: ?[*:0]const u8 = null;
        switch (getinfo(self.handle(), c.CURLINFO_EFFECTIVE_URL, &text)) {
            c.CURLE_OK => {},
            else => return error.UnknownInfo,
        }
        const borrowed = text orelse return null;
        return std.mem.span(borrowed);
    }

    /// Put every option back to its default.
    ///
    /// This is `curl_easy_reset` (`include/curl/easy.h:86`), which
    /// re-initializes the handle "to the same state as it was in when it was
    /// created" (`easy.h:81-82`).
    ///
    /// What it deliberately keeps, per upstream's own list at `easy.h:84-85`, is
    /// the live connections, the session ID cache, the DNS cache and the
    /// cookies. It cannot fail and upstream reports no code for it.
    ///
    /// A callback set through `setWriteFunction` or `setHeaderFunction` is
    /// cleared by this, because it is an option like any other; the `ctx` pointer
    /// it captured stops being referenced at the same moment.
    pub fn reset(self: *Easy) void {
        c.curl_easy_reset(self.handle());
    }
};

/// One `CURLINFO_LONG` selector, read into a `c_long`.
///
/// Upstream reads the out-parameter as a `long *` for every selector whose type
/// bits are `CURLINFO_LONG` (`lib/getinfo.c:639-643`), so the caller's
/// declaration has to match the selector and not the caller's convenience.
/// `responseCode` and `headerSize` are both such selectors.
fn readLongInfo(easy: *const Easy, info: c.CURLINFO) InfoError!c_long {
    var value: c_long = 0;
    switch (getinfo(easy.handle(), info, &value)) {
        c.CURLE_OK => return value,
        else => return error.UnknownInfo,
    }
}

/// A `bool` as the `long` upstream's `CURLOPT_LONG` options read.
///
/// Upstream takes `long` (`lib/setopt.c:2889-2890`) and derives enablement with
/// `!!arg` (`lib/setopt.c:361`), so 1 and 0 are the two values this module ever
/// produces. The bound that keeps `setFollowLocation` from being able to produce
/// a value upstream refuses (`lib/setopt.c:1023-1024`) is the `bool` in the
/// signature, not this conversion.
fn boolToLong(value: bool) c_long {
    return if (value) 1 else 0;
}

/// What a socket wants next, from upstream's own five values.
///
/// These are the `CURL_POLL_*` constants (`include/curl/multi.h:282-286`):
/// `CURL_POLL_NONE` 0, `CURL_POLL_IN` 1, `CURL_POLL_OUT` 2, `CURL_POLL_INOUT`
/// 3 and `CURL_POLL_REMOVE` 4. Upstream defines them for the `what` parameter
/// of a socket callback (`curl_socket_callback`, `multi.h:294-300`), and
/// `Multi.socketAction` is the only place this module uses them, mapping them
/// onto what `curl_multi_socket_action` expects; see that method for why the
/// mapping is not the identity.
///
/// The values are explicit rather than implicit so that a value upstream adds
/// later cannot be silently read as one of these.
pub const PollEvent = enum(c_int) {
    /// `CURL_POLL_NONE` (`multi.h:282`).
    none = c.CURL_POLL_NONE,
    /// `CURL_POLL_IN` (`multi.h:283`).
    in = c.CURL_POLL_IN,
    /// `CURL_POLL_OUT` (`multi.h:284`).
    out = c.CURL_POLL_OUT,
    /// `CURL_POLL_INOUT` (`multi.h:285`).
    inout = c.CURL_POLL_INOUT,
    /// `CURL_POLL_REMOVE` (`multi.h:286`).
    remove = c.CURL_POLL_REMOVE,
};

/// Which kind of multi message this is, from upstream's two values.
///
/// `CURLMSG_NONE` 0 and `CURLMSG_DONE` 1 (`include/curl/multi.h:89-94`), with
/// `CURLMSG_LAST` marking the end rather than being a value (`multi.h:93`). Only
/// `done` is ever queued: upstream fills the message list itself and
/// `curl_multi_info_read` hands back its head (`lib/multi.c:3117-3133`), and
/// upstream's own comment on `done` is "'result' contains the CURLcode of the
/// transfer" (`multi.h:91-92`).
pub const MessageKind = enum(c_int) {
    /// `CURLMSG_NONE` (`multi.h:90`), "first, not used".
    none = c.CURLMSG_NONE,
    /// `CURLMSG_DONE` (`multi.h:91`): this easy handle has completed.
    done = c.CURLMSG_DONE,
};

/// One finished transfer, as the multi interface reports it.
///
/// ## `easy` is borrowed, and this module does not own it
///
/// The handle is the one the caller added with `Multi.addEasy` and still owns;
/// upstream's own comment is that the caller should use "the particular
/// 'transfer handle' in that struct ... in subsequent curl_easy_getinfo() calls"
/// (`include/curl/multi.h:246-248`). It arrives as a borrowed pointer, and this
/// hands it back in a borrowed view over that same `CURL`.
///
/// ## Two things a caller must not do with it
///
/// **Do not `deinit` it.** Closing it would be a second `curl_easy_cleanup` on a
/// handle the caller already owns and closes itself; this type has no `deinit`
/// and must never be given one.
///
/// **Do not compare its address with your own `Easy`'s address.** The `*Easy` in
/// a message is a view this call created, not the `*Easy` the caller added, so
/// the two pointers are different even when they name the same handle. Use
/// `isFor`, which compares what both sides actually mean.
///
/// It is usable for `removeEasy`, `responseCode`, `headerSize` and
/// `effectiveUrl`, because all of those reach the same underlying `CURL` and this
/// type has no `deinit` to get wrong.
///
/// Its lifetime is the caller's: it is a view of a handle the caller owns, so
/// it is valid exactly as long as that handle is open and no longer.
pub const Message = struct {
    /// The handle this message concerns, borrowed. See the note above.
    easy: *Easy,

    /// Which message this is. Upstream queues only `done`
    /// (`include/curl/multi.h:89-94`); see `MessageKind`.
    kind: MessageKind,

    /// The transfer's outcome, or null when it succeeded.
    ///
    /// This is optional **because `CURLE_OK` is a real value that an error set
    /// cannot hold**. Upstream puts a `CURLcode` in the message
    /// (`include/curl/multi.h:99-102`), and that enumeration's first member is
    /// `CURLE_OK = 0` (`curl.h:521`). A non-optional `PerformError` would have no
    /// way to say "the transfer succeeded", and every success would have to come
    /// back as an error - so the optional is where success lives, and it must not
    /// be "simplified" away.
    ///
    /// Null means `CURLE_OK` and nothing else. Any other code is the tag
    /// `performFrom` gives it; a code outside that set is `error.Unknown`.
    result: ?PerformError,

    /// Whether this message is about `easy`, compared by the underlying handle.
    ///
    /// Pointer equality on `Message.easy` against the caller's own `Easy` would
    /// be wrong, for the reason the note on `Message` gives: the two are views
    /// that may sit at different addresses. This compares what both name.
    pub fn isFor(message: Message, easy: *const Easy) bool {
        return message.easy.handle() == easy.handle();
    }
};

/// What one pass of `Multi.drive` found.
///
/// The union is the point: a loop cannot be written wrong against a bare
/// `bool`, because every outcome has its own arm and the ones that mean "keep
/// going" cannot be confused with the ones that mean "stop".
pub const DriveResult = union(enum) {
    /// Transfers are still going; this is how many are still transferring.
    ///
    /// That is `curl_multi_perform`'s `running_handles`
    /// (`include/curl/multi.h:216-217`), which upstream documents as "the number
    /// of handles that still transfer data" (`multi.h:208-209`). Call again.
    running: i32,

    /// A transfer finished successfully, or nothing was transferring at all.
    ///
    /// Both are answers rather than failures and both stop the loop. The second
    /// is worth knowing about: `running_handles` counts transfers that are
    /// *running*, not transfers that have been *added* - upstream keeps the two
    /// apart in its own counters (`CURLMINFO_XFERS_CURRENT` against
    /// `CURLMINFO_XFERS_RUNNING`, `multi.h:468-472`) - so a handle that is
    /// queued waiting for a connection is not counted here. A caller that queues
    /// work after this point has to add it again, which it has to do anyway.
    done,

    /// A transfer finished and failed; this is its outcome.
    failed: PerformError,

    /// The multi handle itself failed. This is a `CURLMcode`, not a `CURLcode`.
    ///
    /// The two enumerations are kept apart on purpose. `failed` above is a
    /// *transfer* outcome and this is a *multi handle* outcome, and collapsing
    /// one into the other would invent a mapping between `CURLMcode` and
    /// `CURLcode` that upstream does not define - a `CURLM_BAD_SOCKET` has no
    /// `CURLcode` spelling at all.
    multi_failed: MultiError,

    /// Nothing became ready and nothing finished inside the timeout.
    ///
    /// The wait genuinely expired: libcurl's own descriptors had no activity and
    /// no transfer reported an outcome. Calling `drive` again is the only way
    /// forward, and it is how a caller notices a stalled transfer rather than
    /// spinning on it.
    timed_out,
};

/// Many transfers on one thread, driven by a message loop.
///
/// A `Multi` owns exactly one `CURLM`. It does **not** own the easy handles added
/// to it: upstream says `curl_multi_cleanup` "does not free or touch any
/// individual easy handles in any way" (`include/curl/multi.h:222-223`). The
/// easy handles are the caller's, and `Multi.deinit` is not a substitute for
/// closing them.
///
/// ## The loop
///
/// `drive` is one pass of the whole cycle - wait for activity, let libcurl act
/// on it, and report what a finished transfer said - and it returns a
/// `DriveResult` rather than a `bool`, so a caller cannot forget to loop or
/// mistake "still running" for "finished". `readInfo` is the separate route to
/// the message queue, for a caller that wants to drain messages itself rather
/// than let `drive` consume one per pass.
///
/// `socketAction` and `poll` are the two halves of the same machinery and are
/// exposed for a caller that owns its own event loop instead of calling `drive`.
/// How many `Message.easy` views one `Multi` keeps alive at once.
///
/// A `Message` borrows an `Easy` view, and a view cannot be a local in
/// `readInfo` - the caller would be left holding a frame that has already
/// returned. So the views live in the `Multi` and this many are rotated; a
/// message stays valid until this handle has produced that many further ones.
/// Four covers the drain-then-report shape the multi interface is built around
/// without making the struct grow for no reason.
const message_view_slots = 4;

pub const Multi = struct {
    /// The owned multi handle, or `undefined` once `deinit` has run.
    raw: ?*c.CURLM = null,
    /// Storage backing the `*Easy` in each `Message`, rotated by `view_next`.
    views: [message_view_slots]Easy = undefined,
    view_next: usize = 0,
    /// The message the last `drive` pass removed to learn its outcome, kept so
    /// `readInfo` can still hand it to the caller. See `readInfo`.
    held: ?Message = null,

    /// Create a multi handle.
    ///
    /// This is `curl_multi_init` (`include/curl/multi.h:126`), whose body is one
    /// call into `Curl_multi_handle` with the four fixed table sizes
    /// (`lib/multi.c:374-381`). That function's only failure is not being able to
    /// allocate the handle, which is what `InitError.OutOfMemory` names.
    ///
    /// A new multi handle has no handles in it; `addEasy` is how transfers join.
    pub fn init() InitError!Multi {
        const raw = c.curl_multi_init() orelse return error.OutOfMemory;
        return .{ .raw = raw };
    }

    /// Close the multi handle, leaving the easy handles alone.
    ///
    /// This is `curl_multi_cleanup` (`include/curl/multi.h:229`). Upstream's own
    /// contract is that it "does not free or touch any individual easy handles in
    /// any way" (`multi.h:222-223`), so every `Easy` added to this handle is
    /// still open afterwards and still the caller's to close.
    ///
    /// It does report a code - `CURLMcode` - but the one non-`OK` value it can
    /// return is `CURLM_BAD_HANDLE` for a transfer in the set it cannot
    /// recognise (`lib/multi.c:3011-3013`), and every transfer here was added
    /// through `addEasy` from an `Easy` this module created. Upstream also
    /// removes every remaining handle as part of the cleanup
    /// (`lib/multi.c:3006-3008`), so a handle left added is detached rather than
    /// closed, and that is upstream's behaviour rather than a leak here.
    pub fn deinit(self: *Multi) void {
        const raw = self.raw orelse return;
        self.raw = undefined;
        _ = c.curl_multi_cleanup(raw);
    }

    /// The raw multi handle, for anything the facade does not wrap.
    ///
    /// Stopping the program on a closed handle is deliberate and is an ordinary
    /// comparison, for the reasons `Easy.handle` gives.
    pub fn handle(self: *const Multi) *c.CURLM {
        return self.raw orelse @panic(
            "libcurl: this Multi was closed. deinit() stores undefined into " ++
                "the handle, so there is no state to call into. Check your own " ++
                "flag if the lifetime is not obvious.",
        );
    }

    /// Put `easy`'s transfer into this multi handle's set.
    ///
    /// This is `curl_multi_add_handle` (`include/curl/multi.h:135-136`). The
    /// handle is not consumed: `easy` stays the caller's and stays usable, and
    /// `removeEasy` takes the same value back out. Adding it twice is
    /// `CURLM_ADDED_ALREADY` (`multi.h:69-70`), reported as `error.AddedAlready`
    /// rather than silently ignored.
    ///
    /// The transfer does not start by being added; it starts when the handle is
    /// driven.
    pub fn addEasy(self: *Multi, easy: *Easy) MultiError!void {
        try codeToMultiError(c.curl_multi_add_handle(self.handle(), easy.handle()));
    }

    /// Take `easy`'s transfer back out of this multi handle.
    ///
    /// This is `curl_multi_remove_handle` (`include/curl/multi.h:145-146`).
    ///
    /// Remove an easy handle that is still transferring and the transfer stops
    /// where it is; upstream reads that as "we are asked to remove a handle that
    /// is still doing something", so a caller that wants the transfer finished
    /// has to drain `readInfo` to its end first.
    pub fn removeEasy(self: *Multi, easy: *Easy) MultiError!void {
        try codeToMultiError(c.curl_multi_remove_handle(self.handle(), easy.handle()));
    }

    /// Let libcurl make progress and report how many transfers are still going.
    ///
    /// This is `curl_multi_perform` (`include/curl/multi.h:216-217`) with
    /// nothing else, and it is the whole-transfer `Easy.perform` split into steps
    /// a caller interleaves with its own work.
    ///
    /// The answer is upstream's `running_handles`: "the number of handles that
    /// still transfer data" (`multi.h:208-209`). It is not a count of handles
    /// that have been added, and not a count of transfers that finished; see
    /// `DriveResult.running` for why that distinction matters.
    pub fn perform(self: *Multi) MultiError!i32 {
        var running: c_int = 0;
        try codeToMultiError(c.curl_multi_perform(self.handle(), &running));
        return running;
    }

    /// Wait up to `timeout_ms` for socket activity, without passing any extra
    /// descriptors.
    ///
    /// This is `curl_multi_poll` (`include/curl/multi.h:185-189`) with no
    /// `extra_fds` and no `extra_nfds`. Upstream's own description is "Poll on
    /// all fds within a CURLM set as well as any additional fds passed to the
    /// function" (`multi.h:167-168`), so with none passed it polls the multi
    /// handle's own descriptors and nothing else.
    ///
    /// `timeout_ms` is milliseconds and it is **not** optional-wait: upstream
    /// refuses a negative one outright with `CURLM_BAD_FUNCTION_ARGUMENT`
    /// (`lib/multi.c:1562-1563`), so there is no "block forever" and no error
    /// beyond that. Upstream also shortens the wait when libcurl has an earlier
    /// internal timer pending (`lib/multi.c:1627-1629`), which is correct and
    /// not something a caller has to compensate for.
    ///
    /// ## The descriptor count is deliberately not returned
    ///
    /// Upstream writes a count through its last argument, and this discards it.
    /// The reason is that the count is not a statement about this handle's
    /// activity in a form a caller can act on here: it describes the descriptors
    /// the underlying poll woke on, which with no `extra_fds` array are
    /// exclusively libcurl's own, and libcurl subtracts its internal wakeup
    /// socket from it (`lib/multi.c:1645-1652`). A caller that wanted to select
    /// on those descriptors itself needs its own array, and the array route is
    /// `WaitFd` plus `curl_multi_poll` through `pub const c`.
    ///
    /// What this call *is* good for is the wait itself: it returns when there is
    /// something to do or when the timeout expires, and either way the next step
    /// is `socketAction` or `perform`. `drive` does both for you.
    pub fn poll(self: *Multi, timeout_ms: i32) MultiError!void {
        // Upstream writes a descriptor count through this out-parameter. It is
        // read and then dropped, which is the decision the note above explains,
        // so the variable is a real destination rather than a null: passing null
        // would skip `*ret = nevents` (`lib/multi.c:1658-1659`) and change which
        // code path upstream takes.
        var ready: c_int = 0;
        try codeToMultiError(c.curl_multi_poll(self.handle(), null, 0, timeout_ms, &ready));
    }

    /// Tell libcurl what happened to one of its descriptors, and report how many
    /// transfers are still going.
    ///
    /// This is `curl_multi_socket_action` (`include/curl/multi.h:319-322`).
    ///
    /// ## Why `PollEvent` is not the bitmask upstream wants
    ///
    /// The third parameter upstream reads is an `ev_bitmask` built from
    /// `CURL_CSELECT_IN`, `CURL_CSELECT_OUT` and `CURL_CSELECT_ERR`
    /// (`multi.h:290-292`) - the values 0x01, 0x02 and 0x04 - while `PollEvent`
    /// carries the five `CURL_POLL_*` values 0 through 4 (`multi.h:282-286`).
    /// They are different enumerations, so this method maps between them rather
    /// than passing a `PollEvent` through as if it were a mask:
    ///
    ///   * `none` -> a zero mask, which is the no-event case;
    ///   * `in` -> `CURL_CSELECT_IN` (1);
    ///   * `out` -> `CURL_CSELECT_OUT` (2);
    ///   * `inout` -> `CURL_CSELECT_IN | CURL_CSELECT_OUT` (3);
    ///   * `remove` -> **not a mask at all**. Upstream removes a descriptor by
    ///     being handed the bad-socket sentinel with a zero mask:
    ///     `CURL_SOCKET_TIMEOUT` is defined as `CURL_SOCKET_BAD` (`multi.h:288`)
    ///     and `CURL_SOCKET_BAD` is `(-1)` (`curl.h:147`), which is exactly what
    ///     upstream's own all-descriptors call passes
    ///     (`lib/multi.c:3500`). So `remove` is performed by that call and `fd`
    ///     is ignored.
    ///
    /// A caller that needs the error bit - `CURL_CSELECT_ERR`, which has no
    /// `CURL_POLL_*` counterpart - reaches `c.curl_multi_socket_action` and
    /// builds the mask itself. That is the raw route, and it is honest: this
    /// module will not invent a sixth `PollEvent` value that upstream's
    /// `CURL_POLL_*` list does not contain.
    ///
    /// The answer is the same `running_handles` as `perform`.
    pub fn socketAction(self: *Multi, fd: c.curl_socket_t, ev: PollEvent) MultiError!i32 {
        var running: c_int = 0;
        const removal = ev == .remove;
        const descriptor: c.curl_socket_t = if (removal) c.CURL_SOCKET_BAD else fd;
        const bits: c_int = switch (ev) {
            .none => 0,
            .in => c.CURL_CSELECT_IN,
            .out => c.CURL_CSELECT_OUT,
            .inout => c.CURL_CSELECT_IN | c.CURL_CSELECT_OUT,
            // The removal call above already carries the zero mask upstream's own
            // all-descriptors pass uses (`lib/multi.c:3500`).
            .remove => 0,
        };
        try codeToMultiError(
            c.curl_multi_socket_action(self.handle(), descriptor, bits, &running),
        );
        return running;
    }

    /// Take the next finished transfer's message out of the queue, or null when
    /// the queue is empty.
    ///
    /// This is `curl_multi_info_read` (`include/curl/multi.h:259-260`). Each call
    /// removes one message from libcurl's own queue and hands it over
    /// (`lib/multi.c:3117-3133`), so a loop drains the queue by calling this
    /// until it answers null. Upstream says the same at `multi.h:239-241`.
    ///
    /// The message the last `drive` pass consumed is handed back **before** the
    /// queue is asked again. `drive` has to remove a message to learn its
    /// outcome - `curl_multi_info_read` is the only upstream call that carries
    /// the `CURLcode` - and a caller that cannot then read the message back
    /// cannot learn *which* handle finished, which is the only thing this
    /// interface exists to say. So `drive` keeps the one it removed and this
    /// returns it first.
    ///
    /// `Message.easy` is **borrowed**, not owned: see `Message`. The view is
    /// backed by storage inside this `Multi`, so it outlives this call; that
    /// used to be a local here, which handed out a pointer to a frame that had
    /// already returned.
    ///
    /// A message whose tag is not `done` is reported as an empty queue rather
    /// than as a result. That is not a guess: upstream fills this queue itself
    /// and its own enum has only `none`, `done` and a trailing `last` marker
    /// (`multi.h:89-94`), so a tag this module does not recognise would be a
    /// provider disagreeing with the header, and there is no honest outcome to
    /// report for it beyond "nothing here".
    pub fn readInfo(self: *Multi) ?Message {
        if (self.held) |kept| {
            self.held = null;
            return kept;
        }
        return self.popInfo();
    }

    /// Remove one message from libcurl's own queue.
    ///
    /// Separate from `readInfo` because `drive` must not re-offer the message
    /// `drive` itself is holding: it would report the same completion on every
    /// later pass and the caller's loop would never see the transfer end.
    fn popInfo(self: *Multi) ?Message {
        var still_queued: c_int = 0;
        const raw = c.curl_multi_info_read(self.handle(), &still_queued) orelse return null;
        const msg: *c.CURLMsg = @alignCast(@ptrCast(raw));
        const kind: MessageKind = switch (msg.msg) {
            c.CURLMSG_DONE => .done,
            else => return null,
        };
        const owned = msg.easy_handle orelse return null;
        // The view has to outlive this function: `Message.easy` is a `*Easy`,
        // and pointing it at a local would leave the caller holding a dead
        // frame. The window rotates, so draining several messages in a row
        // keeps each of them valid.
        const slot = &self.views[self.view_next];
        slot.* = .{ .raw = owned };
        self.view_next = (self.view_next + 1) % message_view_slots;
        return .{
            .easy = slot,
            .kind = kind,
            .result = performFrom(msg.data.result),
        };
    }

    /// One pass of the whole loop: wait, let libcurl act, and report.
    ///
    /// This is `curl_multi_poll` followed by `curl_multi_socket_all`, then one
    /// `readInfo`. Nothing is hidden and nothing is replaced: a caller that
    /// wants the steps separately has `poll`, `socketAction` and `readInfo`.
    ///
    /// ## Why the second step is `curl_multi_socket_all`
    ///
    /// This was `curl_multi_socket_action` on `CURL_SOCKET_BAD` with a zero
    /// mask, described here as upstream's own "no descriptor, just run the
    /// timers" call. That description does not hold. `CURL_SOCKET_TIMEOUT` is
    /// `#define`d to `CURL_SOCKET_BAD` (`multi.h:288`) but `multi_socket`
    /// tests the two *separately*: it takes the timeout branch only for
    /// `CURL_SOCKET_TIMEOUT` (`lib/multi.c:3279`), and any other value -
    /// including `CURL_SOCKET_BAD` - goes to
    /// `Curl_multi_ev_dirty_xfers(multi, s)` (`lib/multi.c:3288`), which looks
    /// the descriptor up in the socket hash and **marks no transfer dirty when
    /// there is no entry** (`lib/multi_ev.c:589-591`). So the call ran only the
    /// transfers that were already dirty.
    ///
    /// That is enough to start a transfer and not enough to finish one: once
    /// the connect completed and the transfer was waiting to read, the only
    /// thing that would re-dirty it is the readiness event for *that
    /// descriptor*, and the descriptor is never named. The transfer therefore
    /// stopped between states and the caller's loop never saw it complete.
    ///
    /// `curl_multi_socket_all` (`multi.h:325`) is upstream's replacement for
    /// the deprecated `curl_multi_perform`; it passes `checkall = TRUE`
    /// (`lib/multi.c:3497-3501`), which runs `multi_perform` and then reassesses
    /// every active transfer's socket events. That is the "act on everything"
    /// this method's contract promises, and it is what a caller of `poll` +
    /// `socketAction` is building by hand.
    ///
    /// ## How the outcome is decided, and in what order
    ///
    /// A finished transfer is authoritative and is read first, so a transfer
    /// that completed during a *timed-out* wait still reports its outcome rather
    /// than being hidden behind `timed_out`:
    ///
    ///   1. a message with a failure -> `failed`;
    ///   1. a message with success -> `done`;
    ///   1. otherwise, transfers still transferring -> `running`, with the count;
    ///   1. otherwise, nothing became ready inside the timeout -> `timed_out`;
    ///   1. otherwise, nothing was transferring -> `done`.
    ///
    /// The last two are told apart by libcurl's own readiness count, which is
    /// the count the underlying poll produced (`lib/multi.c:1658-1659`) over
    /// libcurl's own descriptors minus its internal wakeup socket
    /// (`lib/multi.c:1645-1652`). It is not a count of the caller's descriptors -
    /// this call passes none - and it is not a promise that anything finished.
    ///
    /// A `multi_failed` result is a failure of the multi handle rather than of a
    /// transfer, and the two are kept apart in the union for the reason
    /// `DriveResult.multi_failed` gives.
    pub fn drive(self: *Multi, timeout_ms: i32) DriveResult {
        var ready: c_int = 0;
        if (multiFrom(c.curl_multi_poll(self.handle(), null, 0, timeout_ms, &ready))) |why|
            return .{ .multi_failed = why };

        var running: c_int = 0;
        if (multiFrom(c.curl_multi_socket_all(
            self.handle(),
            &running,
        ))) |why|
            return .{ .multi_failed = why };

        // `popInfo`, not `readInfo`: re-offering the message `drive` itself is
        // holding would report the same completion on every later pass. The
        // message is kept rather than discarded so the caller can still read
        // it back and learn *which* handle finished.
        if (self.popInfo()) |msg| {
            self.held = msg;
            if (msg.result) |failure| return .{ .failed = failure };
            return .done;
        }

        if (running > 0) return .{ .running = running };
        if (ready == 0) return .timed_out;
        return .done;
    }
};

/// A list of header lines or other strings, owned.
///
/// An `SList` owns one `curl_slist` chain. `append` copies each line into
/// libcurl's own storage, and `freeAll` releases the whole chain.
///
/// ## The two ownership rules, which are opposite
///
/// `append` **copies** the line: `curl_slist_append`'s first statement is
/// `char *dupdata = curlx_strdup(data);` (`lib/slist.c:87`), and the chain node
/// it links is then owned by the list (`lib/slist.c:92`). So the caller's slice
/// need not outlive the call.
///
/// /// `Easy.setHeaders` **borrows** the list: upstream stores the caller's
/// pointer and nothing else (`lib/setopt.c:1358-1363`). So the *list* must
/// outlive every transfer it is set on, and closing the easy handle does not
/// free it - `freeAll` is the caller's to call.
///
/// Copy and borrow are stated together because a reader who has only one of them
/// gets the other one backwards, and the mistake is a use-after-free rather than
/// a wrong answer.
pub const SList = struct {
    /// The owned chain, or null before the first `append` and after `freeAll`.
    head: ?*c.struct_curl_slist = null,

    /// The one failure `append` can report.
    ///
    /// `curl_slist_append` returns null for exactly two reasons and both are
    /// allocations: `curlx_strdup` of the line (`lib/slist.c:87-90`) and
    /// `curlx_malloc` of the chain node (`lib/slist.c:62-64`). Upstream reports
    /// neither as a `CURLcode`; the function's only signal is the null.
    pub const AppendError = error{
        /// The line or the chain node could not be allocated.
        OutOfMemory,
    };

    /// An empty list.
    ///
    /// It has no chain yet, and passing it to `Easy.setHeaders` stores a null,
    /// which is how a caller clears an option.
    pub fn init() SList {
        return .{};
    }

    /// Copy `line` onto the end of the list.
    ///
    /// This is `curl_slist_append` (`include/curl/curl.h:2878-2879`). Upstream
    /// documents that it "always returns the address of the first record, so
    /// that you can use this function as an initialization function as well as
    /// an append function" (`lib/slist.c:79-83`), which is why the head can
    /// change: the first append onto an empty list *becomes* the head. This
    /// method takes that return value and stores it, so the caller never has to.
    ///
    /// `line` is copied, so it need not outlive the call; see the note on
    /// `SList` for the rule that does have a lifetime, and for the contrast with
    /// `Easy.setHeaders`.
    ///
    /// ## `line` must be a NUL terminated string
    ///
    /// Upstream copies `strlen(line)` bytes, not `line.len`
    /// (`lib/slist.c:87`), so an interior NUL **truncates the line silently** -
    /// no error, no signal, just a shorter header than the caller wrote. The
    /// signature says the rest: `[:0]const u8` makes the compiler enforce the
    /// terminator. This was a `[]const u8` parameter scanned with
    /// `std.mem.span`, which read past a caller-supplied buffer exactly as
    /// `Easy.setUrl` did.
    ///
    /// An empty line is accepted: upstream copies zero bytes, and that is how
    /// libcurl is told to send a header with no value.
    pub fn append(self: *SList, line: [:0]const u8) AppendError!void {
        const owned = c.curl_slist_append(self.head, line.ptr) orelse
            return error.OutOfMemory;
        self.head = owned;
    }

    /// Release the whole chain and leave this list empty.
    ///
    /// This is `curl_slist_free_all` (`include/curl/curl.h:2888-2889`), which
    /// walks the chain and frees every node's string and the node itself
    /// (`lib/slist.c:124-133`).
    ///
    /// The head is cleared afterwards, so a second `freeAll` on the same value
    /// is a no-op rather than a double free. That matters here because upstream's
    /// own function tolerates a null (`lib/slist.c:129-130`) and this makes the
    /// *wrapper* idempotent rather than relying on that.
    ///
    /// Every `Easy` this list was handed to must be closed or have the option
    /// cleared first: `Easy.setHeaders` stored the pointer, and upstream never
    /// copied it (`lib/setopt.c:1358-1363`).
    pub fn freeAll(self: *SList) void {
        const chain = self.head orelse return;
        self.head = null;
        c.curl_slist_free_all(chain);
    }

    /// The chain, borrowed, for `Easy.setHeaders` and for the raw route.
    ///
    /// Null before the first `append` and after `freeAll`. The pointer is the
    /// list's own, so it stays valid until `freeAll`; upstream's re-exported
    /// `SListNode` is how a caller walks it.
    pub fn raw(self: *const SList) ?*c.struct_curl_slist {
        return self.head;
    }
};
