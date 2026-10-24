// SPDX-License-Identifier: curl
// See FORK-LICENSE.md for what that identifier covers.

//! Zig facade for libcurl.

const std = @import("std");

/// Translated libcurl declarations and raw access to APIs not wrapped here.
pub const c = @import("translate");

const rt = @import("rt");

/// True when this build resolves native symbols at runtime rather than linking them.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Selects an explicit library path or system name for `load`; neither falls back to the other.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Errors returned when the requested provider cannot be loaded.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Loads the explicit provider in runtime builds; linked-build calls panic.
/// Failed loads retry; same-request callers share results, conflicts and reentrancy error.
pub fn load(source: LoadSource) LoadError!void {
    if (runtime_loaded) return c.load(source);
    std.debug.panic(
        "libcurl: load was called on a linked build; this module is not " ++
            "runtime-loaded, so there is no library to load. Build with " ++
            "runtime loading configured, or do not call load.",
        .{},
    );
}

/// Returns the successful request; its path is borrowed for the process lifetime.
/// Null when no provider is published, including linked builds.
pub fn loadedSource() ?LoadSource {
    if (runtime_loaded) return c.loadedSource();
    return null;
}

/// Releases the runtime dispatch table; linked builds panic.
/// Call only when no code can still use the table.
pub fn unload() void {
    if (runtime_loaded) return c.unload();
    std.debug.panic(
        "libcurl: unload was called on a linked build; this module is not " ++
            "runtime-loaded, so there is no dispatch table to release. Do not " ++
            "call unload.",
        .{},
    );
}

/// Compile-time version; a runtime-loaded provider may have a different version.
pub const version: [:0]const u8 = c.LIBCURL_VERSION;

/// Numeric compile-time version: major, minor and patch occupy the high, middle and low bytes.
pub const version_num: c_uint = c.LIBCURL_VERSION_NUM;

/// Compile-time major, minor and patch version components.
pub const version_parts = struct {
    pub const major: c_uint = c.LIBCURL_VERSION_MAJOR;
    pub const minor: c_uint = c.LIBCURL_VERSION_MINOR;
    pub const patch: c_uint = c.LIBCURL_VERSION_PATCH;
};

/// The global copyright banner the headers carry, `include/curl/curlver.h:31`.
pub const copyright: [:0]const u8 = c.LIBCURL_COPYRIGHT;

/// Build timestamp embedded in the release artifact, not a source date.
pub const timestamp: [:0]const u8 = c.LIBCURL_TIMESTAMP;

/// Returns the loaded library's version string, borrowed for the process lifetime.
/// In runtime-loading builds this describes the provider, not this package.
pub fn versionString() [:0]const u8 {
    return std.mem.span(c.curl_version());
}

/// Runtime version and feature data reported by the loaded library.
/// All fields are borrowed and remain valid for the process lifetime.
pub const VersionInfo = struct {
    /// Runtime library version string; it may differ from the package version.
    version: [:0]const u8,

    /// Runtime library version number.
    version_num: c_uint,

    /// Borrowed host and target string reported by the library.
    host: [:0]const u8,

    /// Borrowed TLS backend version, or null when TLS support is absent.
    ssl_version: ?[:0]const u8,

    /// `CURL_VERSION_*` feature bitmask, including SSL and thread-safety flags.
    features: c_int,
};

/// Runtime version and feature data, borrowed from libcurl's static version record.
/// Fields remain valid for the process lifetime.
pub fn versionInfo() VersionInfo {
    const info = c.curl_version_info(c.CURLVERSION_NOW);
    return .{
        .version = std.mem.span(info[0].version),
        .version_num = info[0].version_num,
        .host = std.mem.span(info[0].host),
        .ssl_version = if (info[0].ssl_version) |v| std.mem.span(v) else null,
        .features = info[0].features,
    };
}

/// Returns borrowed error text for a `CURLcode`; unknown codes still have fallback text.
pub fn strError(code: c.CURLcode) [:0]const u8 {
    return std.mem.span(c.curl_easy_strerror(code));
}

/// Boolean flags passed to `globalInit`.
pub const InitFlags = packed struct {
    Win32: bool = false,
    Ssl: bool = false,
    AckIntr: bool = false,
    /// Flags used by `CURL_GLOBAL_DEFAULT`.
    pub const default_flags: InitFlags = .{ .Win32 = true, .Ssl = true };

    /// No global-init flags.
    pub const nothing: InitFlags = .{};

    /// Converts these flags to libcurl's bitmask.
    pub fn toBits(self: InitFlags) c_long {
        var bits: c_long = 0;
        if (self.Win32) bits |= c.CURL_GLOBAL_WIN32;
        if (self.Ssl) bits |= c.CURL_GLOBAL_SSL;
        if (self.AckIntr) bits |= c.CURL_GLOBAL_ACK_EINTR;
        return bits;
    }
};

/// Initializes global state; pair every call with `globalCleanup` after closing all handles.
/// `Easy.init` may initialize implicitly; failure returns `GlobalInitFailed`.
pub fn globalInit(flags: InitFlags) error{GlobalInitFailed}!void {
    switch (c.curl_global_init(flags.toBits())) {
        c.CURLE_OK => {},
        else => return error.GlobalInitFailed,
    }
}

/// Releases one global-init reference; close every `Easy` and `Multi` first.
pub fn globalCleanup() void {
    c.curl_global_cleanup();
}

/// Error returned when libcurl cannot produce an escape or unescape buffer.
pub const EscapeError = error{
    /// The library returned no buffer. See the note on the set.
    Failed,
};

/// Percent-encodes bytes into a libcurl-owned buffer; release it with `freeEscaped`.
/// The input is copied, so it need not outlive the call.
pub fn escape(s: []const u8) EscapeError![]u8 {
    return escapeRaw(s);
}

/// Percent-decodes bytes into a libcurl-owned buffer; release it unchanged with `freeEscaped`.
/// Embedded NULs are preserved, and malformed escapes remain literal.
pub fn unescape(s: []const u8) EscapeError![]u8 {
    return unescapeRaw(s);
}

/// Frees the unchanged buffer returned by `escape` or `unescape` with libcurl's allocator.
pub fn freeEscaped(bytes: []u8) void {
    c.curl_free(bytes.ptr);
}

fn escapeRaw(s: []const u8) EscapeError![]u8 {
    if (s.len > std.math.maxInt(c_int)) return error.Failed;
    const bytes: []const u8 = if (s.len == 0) "" else s;
    const owned = c.curl_easy_escape(null, @ptrCast(bytes.ptr), @intCast(bytes.len)) orelse
        return error.Failed;
    return std.mem.span(owned);
}

fn unescapeRaw(s: []const u8) EscapeError![]u8 {
    if (s.len > std.math.maxInt(c_int)) return error.Failed;
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

fn setopt(handle: *c.CURL, option: c.CURLoption, value: anytype) c.CURLcode {
    if (comptime runtime_loaded) {
        return c.curl_easy_setopt(handle, option, value);
    }
    return @call(.auto, c.curl_easy_setopt, .{ handle, option, value });
}

fn getinfo(handle: *c.CURL, info: c.CURLINFO, out: anytype) c.CURLcode {
    if (comptime runtime_loaded) {
        return c.curl_easy_getinfo(handle, info, out);
    }
    return @call(.auto, c.curl_easy_getinfo, .{ handle, info, out });
}

/// Calls the raw `curl_multi_setopt` route and maps its `CURLMcode`.
pub fn multiSetopt(handle: *c.CURLM, option: c.CURLMoption, value: anytype) MultiError!void {
    const code = if (comptime runtime_loaded)
        c.curl_multi_setopt(handle, option, value)
    else
        @call(.auto, c.curl_multi_setopt, .{ handle, option, value });
    return codeToMultiError(code);
}

/// Maps `CURLcode` to `PerformError`, or null for success.
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

fn performOk(code: c.CURLcode) PerformError!void {
    if (performFrom(code)) |failure| return failure;
}

fn optionFrom(code: c.CURLcode) ?OptionError {
    return switch (code) {
        c.CURLE_OK => null,
        c.CURLE_UNKNOWN_OPTION => error.UnknownOption,
        c.CURLE_OUT_OF_MEMORY => error.OutOfMemory,
        c.CURLE_BAD_FUNCTION_ARGUMENT => error.BadFunctionArgument,
        c.CURLE_NOT_BUILT_IN => error.NotBuiltIn,
        c.CURLE_UNSUPPORTED_PROTOCOL => error.OptionNotAllowedInThisBuild,
        else => error.BadFunctionArgument,
    };
}

/// `CURLE_OK` as a success, every other named code as its tag.
fn optionOk(code: c.CURLcode) OptionError!void {
    if (optionFrom(code)) |failure| return failure;
}

/// Maps `CURLMcode` to a multi error, or null for success.
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
        else => error.InternalError,
    };
}

/// `CURLM_OK` as a success, every other named code as its tag.
fn codeToMultiError(code: c.CURLMcode) MultiError!void {
    if (multiFrom(code)) |failure| return failure;
}

/// Error returned when `Easy.init` or `Multi.init` cannot create a handle.
pub const InitError = error{
    /// The handle could not be created. See the note on the set.
    OutOfMemory,
};

/// Errors returned by typed `curl_easy_setopt` calls.
pub const OptionError = error{
    /// This build does not know the option.
    UnknownOption,
    /// libcurl could not allocate option storage.
    OutOfMemory,
    /// The option or value is invalid.
    BadFunctionArgument,
    /// The requested option is unavailable in this build.
    NotBuiltIn,
    /// The protocol or option value is unsupported in this build.
    OptionNotAllowedInThisBuild,
};

/// Error returned when a typed info selector is unknown.
pub const InfoError = error{
    /// `CURLE_UNKNOWN_OPTION`: the selector is not one this library knows.
    UnknownInfo,
};

/// Transfer failures mapped from `CURLcode`; `Unknown` covers future values.
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

/// Errors returned by multi-handle calls.
pub const MultiError = error{
    /// Ask the caller to drive the multi handle again.
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

/// C callback ABI for response bodies: `(buffer, size, nitems, ctx)`, with `ctx` last.
/// Return all bytes, a short count to abort, `CURL_WRITEFUNC_PAUSE`, or `CURL_WRITEFUNC_ERROR`.
pub const WriteCallback = *const fn (
    buffer: [*c]u8,
    size: usize,
    nitems: usize,
    outstream: ?*anyopaque,
) callconv(.c) usize;

/// Same C callback ABI as `WriteCallback`, invoked for each response header line.
/// Returning a short count aborts the transfer.
pub const HeaderCallback = *const fn (
    buffer: [*c]u8,
    size: usize,
    nitems: usize,
    outstream: ?*anyopaque,
) callconv(.c) usize;

/// Computes `size * nitems`; null means the product overflows `usize`.
/// A null result must not be used to form a callback slice.
pub fn chunkLength(len: usize, nmemb: usize) ?usize {
    return std.math.mul(usize, len, nmemb) catch null;
}

/// Upstream `curl_waitfd`; `fd` uses the platform's native socket type.
pub const WaitFd = c.struct_curl_waitfd;

/// Upstream `curl_slist` node type.
pub const SListNode = c.struct_curl_slist;

/// Parsed header returned by libcurl; borrowed until the next call on that handle.
pub const Header = c.struct_curl_header;

/// Upstream option type; it determines the type of `curl_easy_setopt`'s value.
pub const OptionType = enum(c_int) {
    /// `CURLOT_LONG` (`options.h:32`), a `long` in `curl_easy_setopt`.
    long = c.CURLOT_LONG,
    /// A `long` value from a defined set or bitmask.
    values = c.CURLOT_VALUES,
    /// `CURLOT_OFF_T` (`options.h:34`), a `curl_off_t`.
    off_t = c.CURLOT_OFF_T,
    /// `CURLOT_OBJECT` (`options.h:35`), a `void *`.
    object = c.CURLOT_OBJECT,
    /// `CURLOT_STRING` (`options.h:36`), a NUL terminated `char *`.
    string = c.CURLOT_STRING,
    /// `CURLOT_SLIST` (`options.h:37`), a `struct curl_slist *`.
    slist = c.CURLOT_SLIST,
    /// A callback context pointer.
    cb_ptr = c.CURLOT_CBPTR,
    /// `CURLOT_BLOB` (`options.h:39`), a `struct curl_blob *`.
    blob = c.CURLOT_BLOB,
    /// `CURLOT_FUNCTION` (`options.h:40`), a function pointer.
    function = c.CURLOT_FUNCTION,
};

/// The bit indicating an option name is retained as an alias.
pub const option_flag_alias: c_uint = c.CURLOT_FLAG_ALIAS;

/// Upstream option metadata returned by the lookup functions.
pub const OptionInfo = c.struct_curl_easyoption;

/// Looks up a borrowed static option record by NUL-terminated name.
/// Returns null when the name is unknown.
pub fn optionByName(name: [:0]const u8) ?*const OptionInfo {
    return c.curl_easy_option_by_name(name.ptr);
}

/// Looks up a borrowed static option record by selector, or returns null.
pub fn optionById(id: c.CURLoption) ?*const OptionInfo {
    return c.curl_easy_option_by_id(id);
}

/// Returns the next borrowed option record, or null at the end.
pub fn optionNext(prev: ?*const OptionInfo) ?*const OptionInfo {
    return c.curl_easy_option_next(prev);
}

/// Maps a transfer `CURLcode` to `PerformError`, or null for success.
pub fn performErrorFrom(code: c.CURLcode) ?PerformError {
    return performFrom(code);
}

/// Owns one easy handle; do not copy it while open.
/// Share it across threads only when runtime `features` include `CURL_VERSION_THREADSAFE`.
pub const Easy = struct {
    /// Owned handle, undefined after `deinit`.
    raw: ?*c.CURL = null,

    /// Creates a default handle; failure returns `OutOfMemory`.
    pub fn init() InitError!Easy {
        const raw = c.curl_easy_init() orelse return error.OutOfMemory;
        return .{ .raw = raw };
    }

    /// Closes the handle and its resources; the wrapper is unusable afterwards.
    pub fn deinit(self: *Easy) void {
        const raw = self.raw orelse return;
        self.raw = undefined;
        c.curl_easy_cleanup(raw);
    }

    /// Returns the raw handle; panics after `deinit`.
    pub fn handle(self: *const Easy) *c.CURL {
        return self.raw orelse @panic(
            "libcurl: this Easy was closed. deinit() stores undefined into " ++
                "the handle, so there is no state to call into. Check your own " ++
                "flag if the lifetime is not obvious.",
        );
    }

    /// Sets a NUL-terminated URL, which libcurl copies; the source may expire after the call.
    /// Invalid or unsupported values return an `OptionError`.
    pub fn setUrl(self: *Easy, url: [:0]const u8) OptionError!void {
        try optionOk(setopt(self.handle(), c.CURLOPT_URL, url.ptr));
    }

    /// Sets the response-body callback and stores `ctx` unchanged for callback use.
    /// Keep `ctx` valid while callbacks may run; setting options cannot fail.
    pub fn setWriteFunction(self: *Easy, ctx: ?*anyopaque, f: WriteCallback) void {
        const raw = self.handle();
        _ = setopt(raw, c.CURLOPT_WRITEFUNCTION, @as(?*const anyopaque, @ptrCast(f)));
        _ = setopt(raw, c.CURLOPT_WRITEDATA, ctx);
    }

    /// Sets the header callback and stores `ctx`; null restores libcurl's default.
    /// Keep `ctx` valid while callbacks may run; setting options cannot fail.
    pub fn setHeaderFunction(self: *Easy, ctx: ?*anyopaque, f: ?HeaderCallback) void {
        const raw = self.handle();
        const function: ?*const anyopaque = if (f) |callback| @ptrCast(callback) else null;
        _ = setopt(raw, c.CURLOPT_HEADERFUNCTION, function);
        _ = setopt(raw, c.CURLOPT_HEADERDATA, ctx);
    }

    /// Sets the whole-transfer timeout in milliseconds; zero disables it.
    /// Negative values return `BadFunctionArgument`.
    pub fn setTimeoutMs(self: *Easy, ms: c_long) OptionError!void {
        try optionOk(setopt(self.handle(), c.CURLOPT_TIMEOUT_MS, ms));
    }

    /// Enables or disables redirects; disabled by default.
    pub fn setFollowLocation(self: *Easy, on: bool) void {
        _ = setopt(self.handle(), c.CURLOPT_FOLLOWLOCATION, boolToLong(on));
    }

    /// Enables or disables libcurl's diagnostic output on stderr.
    pub fn setVerbose(self: *Easy, on: bool) void {
        _ = setopt(self.handle(), c.CURLOPT_VERBOSE, boolToLong(on));
    }

    /// Sets request headers; libcurl borrows the list until its transfers finish.
    /// `SList.append` copies lines; the caller releases the list. Returns `OptionError`.
    pub fn setHeaders(self: *Easy, list: ?*SList) OptionError!void {
        const chain: ?*c.struct_curl_slist = if (list) |owned| owned.raw() else null;
        try optionOk(setopt(self.handle(), c.CURLOPT_HTTPHEADER, chain));
    }

    /// Runs a transfer synchronously and returns `PerformError` on transfer failure.
    /// Inspect `responseCode` separately; HTTP error statuses are not failures by default.
    pub fn perform(self: *Easy) PerformError!void {
        try performOk(c.curl_easy_perform(self.handle()));
    }

    /// Returns the HTTP status code, or zero if no HTTP response arrived.
    /// HTTP error statuses are not transfer failures by default; unknown selectors return `InfoError`.
    pub fn responseCode(self: *const Easy) InfoError!u64 {
        const status: c_long = try readLongInfo(self, c.CURLINFO_RESPONSE_CODE);
        if (status < 0) @panic(
            "libcurl: CURLINFO_RESPONSE_CODE answered a negative value. Upstream " ++
                "stores a status code or zero (lib/getinfo.c:221-223), so this " ++
                "is a provider that disagrees with the header.",
        );
        return @intCast(status);
    }

    /// Returns parsed header-byte count, not callback bytes; unknown selectors return `InfoError`.
    pub fn headerSize(self: *const Easy) InfoError!u64 {
        const bytes: c_long = try readLongInfo(self, c.CURLINFO_HEADER_SIZE);
        if (bytes < 0) @panic(
            "libcurl: CURLINFO_HEADER_SIZE answered a negative value. Upstream " ++
                "stores a byte count (lib/getinfo.c:237-239), so this is a " ++
                "provider that disagrees with the header.",
        );
        return @intCast(bytes);
    }

    /// Returns the effective URL as a borrowed string, valid until the URL changes or the handle closes.
    /// The result is optional; an unknown selector returns `InfoError`.
    pub fn effectiveUrl(self: *const Easy) InfoError!?[]const u8 {
        var text: ?[*:0]const u8 = null;
        switch (getinfo(self.handle(), c.CURLINFO_EFFECTIVE_URL, &text)) {
            c.CURLE_OK => {},
            else => return error.UnknownInfo,
        }
        const borrowed = text orelse return null;
        return std.mem.span(borrowed);
    }

    /// Restores default options but retains connections, DNS/session caches, and cookies.
    /// This clears callbacks and their stored contexts.
    pub fn reset(self: *Easy) void {
        c.curl_easy_reset(self.handle());
    }
};

fn readLongInfo(easy: *const Easy, info: c.CURLINFO) InfoError!c_long {
    var value: c_long = 0;
    switch (getinfo(easy.handle(), info, &value)) {
        c.CURLE_OK => return value,
        else => return error.UnknownInfo,
    }
}

fn boolToLong(value: bool) c_long {
    return if (value) 1 else 0;
}

/// `CURL_POLL_*` event requested for a socket.
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

/// Message kind reported by libcurl's multi interface.
pub const MessageKind = enum(c_int) {
    /// `CURLMSG_NONE` (`multi.h:90`), "first, not used".
    none = c.CURLMSG_NONE,
    /// `CURLMSG_DONE` (`multi.h:91`): this easy handle has completed.
    done = c.CURLMSG_DONE,
};

/// A completed transfer. `easy` borrows the caller's handle; do not close it here.
/// Its view remains stored by `Multi` until four later messages rotate it out.
pub const Message = struct {
    /// Borrowed view of the caller-owned handle.
    easy: *Easy,

    /// libcurl message kind.
    kind: MessageKind,

    /// Transfer error, or null when the transfer succeeded.
    /// Unknown CURLcode values map to `PerformError.Unknown`.
    result: ?PerformError,

    /// Compares the underlying handle, not the view's address.
    pub fn isFor(message: Message, easy: *const Easy) bool {
        return message.easy.handle() == easy.handle();
    }
};

/// Outcome of one pass through `Multi.drive`.
pub const DriveResult = union(enum) {
    /// Transfers remain active; this is libcurl's running-handle count.
    running: i32,

    /// A transfer completed successfully, or no transfer is active.
    done,

    /// A transfer finished and failed; this is its outcome.
    failed: PerformError,

    /// The multi handle failed; distinct from a transfer failure.
    multi_failed: MultiError,

    /// No activity completed before the timeout.
    timed_out,
};

const message_view_slots = 4;

/// Owns one multi handle, not the easy handles added to it.
/// Keep calls on its driving thread; raw `curl_multi_wakeup` is the cross-thread exception.
pub const Multi = struct {
    /// Owned handle, undefined after `deinit`.
    raw: ?*c.CURLM = null,
    /// Backing storage for borrowed `Message.easy` views.
    views: [message_view_slots]Easy = undefined,
    view_next: usize = 0,
    /// Completion retained by `drive` for the next `readInfo` call.
    held: ?Message = null,

    /// Creates an empty multi handle. Returns `OutOfMemory` on failure.
    pub fn init() InitError!Multi {
        const raw = c.curl_multi_init() orelse return error.OutOfMemory;
        return .{ .raw = raw };
    }

    /// Closes this multi handle without closing its easy handles.
    pub fn deinit(self: *Multi) void {
        const raw = self.raw orelse return;
        self.raw = undefined;
        _ = c.curl_multi_cleanup(raw);
    }

    /// Returns the raw multi handle; panics after `deinit`.
    pub fn handle(self: *const Multi) *c.CURLM {
        return self.raw orelse @panic(
            "libcurl: this Multi was closed. deinit() stores undefined into " ++
                "the handle, so there is no state to call into. Check your own " ++
                "flag if the lifetime is not obvious.",
        );
    }

    /// Adds a caller-owned easy handle; it starts only when the multi handle is driven.
    /// Returns `AddedAlready` if the handle is already in this set.
    pub fn addEasy(self: *Multi, easy: *Easy) MultiError!void {
        try codeToMultiError(c.curl_multi_add_handle(self.handle(), easy.handle()));
    }

    /// Removes an easy handle; removing it while active stops its transfer.
    pub fn removeEasy(self: *Multi, easy: *Easy) MultiError!void {
        try codeToMultiError(c.curl_multi_remove_handle(self.handle(), easy.handle()));
    }

    /// Advances transfers and returns the number still running.
    pub fn perform(self: *Multi) MultiError!i32 {
        var running: c_int = 0;
        try codeToMultiError(c.curl_multi_perform(self.handle(), &running));
        return running;
    }

    /// Waits up to `timeout_ms` milliseconds on libcurl's descriptors only.
    /// Negative timeouts return `BadFunctionArgument`; use the raw API for extra descriptors.
    pub fn poll(self: *Multi, timeout_ms: i32) MultiError!void {
        // libcurl requires a count output; this wrapper discards the count.
        var ready: c_int = 0;
        try codeToMultiError(c.curl_multi_poll(self.handle(), null, 0, timeout_ms, &ready));
    }

    /// Maps `PollEvent` to libcurl's event mask.
    /// `.remove` ignores `fd`; use the raw API for error flags or custom masks.
    pub fn socketAction(self: *Multi, fd: c.curl_socket_t, ev: PollEvent) MultiError!i32 {
        var running: c_int = 0;
        const removal = ev == .remove;
        const descriptor: c.curl_socket_t = if (removal) c.CURL_SOCKET_BAD else fd;
        const bits: c_int = switch (ev) {
            .none => 0,
            .in => c.CURL_CSELECT_IN,
            .out => c.CURL_CSELECT_OUT,
            .inout => c.CURL_CSELECT_IN | c.CURL_CSELECT_OUT,
            // A removal uses a zero event mask.
            .remove => 0,
        };
        try codeToMultiError(
            c.curl_multi_socket_action(self.handle(), descriptor, bits, &running),
        );
        return running;
    }

    /// Returns the next completion, or null when the queue is empty; returns `drive`'s held message first.
    /// `Message.easy` is borrowed; its stored view rotates after four further messages.
    pub fn readInfo(self: *Multi) ?Message {
        if (self.held) |kept| {
            self.held = null;
            return kept;
        }
        return self.popInfo();
    }

    fn popInfo(self: *Multi) ?Message {
        var still_queued: c_int = 0;
        const raw = c.curl_multi_info_read(self.handle(), &still_queued) orelse return null;
        const msg: *c.CURLMsg = @ptrCast(@alignCast(raw));
        const kind: MessageKind = switch (msg.msg) {
            c.CURLMSG_DONE => .done,
            else => return null,
        };
        const owned = msg.easy_handle orelse return null;
        // Store the view in `Multi`; a local would not outlive this function.
        const slot = &self.views[self.view_next];
        slot.* = .{ .raw = owned };
        self.view_next = (self.view_next + 1) % message_view_slots;
        return .{
            .easy = slot,
            .kind = kind,
            .result = performFrom(msg.data.result),
        };
    }

    /// Polls, runs libcurl across active sockets, and returns one `DriveResult`.
    /// Completion outcomes take priority over a timed-out wait.
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

        // Keep this message so `readInfo` can return the completion to the caller.
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

/// Owns a libcurl `curl_slist` chain; `append` copies lines.
/// `Easy.setHeaders` borrows the list.
pub const SList = struct {
    /// Owned chain, null before append and after `freeAll`.
    head: ?*c.struct_curl_slist = null,

    /// Error returned when libcurl cannot allocate the line or node.
    pub const AppendError = error{
        /// Allocation failed.
        OutOfMemory,
    };

    /// Returns an empty list.
    pub fn init() SList {
        return .{};
    }

    /// Appends a copied NUL-terminated line; returns `OutOfMemory` on allocation failure.
    /// The line need not outlive the call; an interior NUL truncates it.
    pub fn append(self: *SList, line: [:0]const u8) AppendError!void {
        const owned = c.curl_slist_append(self.head, line.ptr) orelse
            return error.OutOfMemory;
        self.head = owned;
    }

    /// Frees and clears the chain; repeated calls are safe.
    /// Finish transfers and clear the option before reusing a handle.
    pub fn freeAll(self: *SList) void {
        const chain = self.head orelse return;
        self.head = null;
        c.curl_slist_free_all(chain);
    }

    /// Returns the caller-owned chain, borrowed until `freeAll`.
    pub fn raw(self: *const SList) ?*c.struct_curl_slist {
        return self.head;
    }
};
