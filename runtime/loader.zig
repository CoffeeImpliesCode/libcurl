// SPDX-License-Identifier: curl
//
//! Reusable runtime loader for translated C APIs.
//! It publishes a process-lifetime table only after symbols and provider validation succeed.
//! Failed attempts publish nothing and remain retryable.

const std = @import("std");
const builtin = @import("builtin");

/// Select an absolute file path or a bare name for the platform loader.
pub const LoadSource = union(enum) {
    /// Absolute file path; relative paths return `InvalidSource`.
    path: []const u8,
    /// Basename or SONAME; path separators and embedded NULs return `InvalidSource`.
    system: []const u8,
};

/// Errors returned by `load`.
pub const LoadError = error{
    /// Empty path or system name, rejected before calling the platform loader.
    EmptySource,
    /// Request exceeds `max_source_len`; the loader never truncates it.
    SourceTooLong,
    /// Relative path, system name with path components, or embedded NUL.
    InvalidSource,
    /// Target has no dynamic-library loader.
    UnsupportedTarget,
    /// Platform loader cannot open the request or one of its dependencies.
    OpenFailed,
    /// Opened provider lacks a required symbol; the candidate is closed.
    MissingSymbol,
    /// Provider validation failed; the candidate is closed without publication.
    ValidationFailed,
    /// A different provider already succeeded or is loading; this request changes nothing.
    ProviderMismatch,
    /// Called from the thread already running `load`; returns instead of deadlocking.
    ReentrantLoad,
};

/// Maximum request length stored by the loader, in bytes.
pub const max_source_len = 32768;

/// Fixed-size copy of the request; it preserves idempotence after the caller's buffer expires.
const SourceRecord = struct {
    tag: enum(u8) { none = 0, path, system } = .none,
    len: u32 = 0,
    bytes: [max_source_len]u8 = undefined,

    /// Record a validated request while holding the loader lock.
    fn set(self: *SourceRecord, request: LoadSource) void {
        const text = switch (request) {
            .path => |p| p,
            .system => |s| s,
        };
        @memcpy(self.bytes[0..text.len], text);
        self.len = @intCast(text.len);
        self.tag = switch (request) {
            .path => .path,
            .system => .system,
        };
    }

    /// Return the remembered request, or null before one is recorded.
    pub fn source(self: *const SourceRecord) ?LoadSource {
        const text = self.bytes[0..self.len];
        return switch (self.tag) {
            .none => null,
            .path => .{ .path = text },
            .system => .{ .system = text },
        };
    }
};

/// Compare request kind and bytes without normalizing their contents.
pub fn eqlSource(a: LoadSource, b: LoadSource) bool {
    return switch (a) {
        .path => |pa| switch (b) {
            .path => |pb| std.mem.eql(u8, pa, pb),
            .system => false,
        },
        .system => |sa| switch (b) {
            .system => |sb| std.mem.eql(u8, sa, sb),
            .path => false,
        },
    };
}

fn validateSource(source: LoadSource) LoadError!void {
    const text = switch (source) {
        .path => |p| p,
        .system => |s| s,
    };
    if (text.len == 0) return error.EmptySource;
    if (text.len > max_source_len) return error.SourceTooLong;
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidSource;
    switch (source) {
        .path => {
            const absolute = if (builtin.os.tag == .windows)
                switch (std.fs.path.getWin32PathType(u8, text)) {
                    .drive_absolute, .unc_absolute, .local_device, .root_local_device => true,
                    .relative, .rooted, .drive_relative => false,
                }
            else
                std.fs.path.isAbsolutePosix(text);
            if (!absolute) return error.InvalidSource;
        },
        .system => {
            for (text) |byte| {
                if (std.fs.path.isSep(byte)) return error.InvalidSource;
                if (builtin.os.tag == .windows and byte == ':') return error.InvalidSource;
            }
        },
    }
}

/// The states of a configured module's dispatch table.
pub const Phase = enum(u8) {
    /// No successful load; failed attempts leave the module retryable.
    not_loaded = 0,
    /// A thread is filling the table.
    loading = 1,
    /// The table is published and routed calls may proceed.
    ready = 2,
};

/// Atomic readiness flag for the dispatch table.
/// Release publication pairs with acquire reads before routed calls.
pub const Ready = struct {
    phase: std.atomic.Value(u8) = .init(@intFromEnum(Phase.not_loaded)),

    /// Return true after a successful load, using acquire ordering.
    pub fn isReady(self: *const Ready) bool {
        return self.phase.load(.acquire) == @intFromEnum(Phase.ready);
    }

    /// Return the current state.
    pub fn state(self: *const Ready) Phase {
        return @enumFromInt(self.phase.load(.acquire));
    }

    /// Publish the new state with release ordering.
    pub fn set(self: *Ready, value: Phase) void {
        self.phase.store(@intFromEnum(value), .release);
    }
};

/// Kind of provider export stored in a dispatch table.
pub const SymbolKind = enum {
    /// Function pointer with the translated header's signature.
    function,
    /// Provider-owned object address, not a copied value.
    data,
};

/// A required export and its kind.
pub const Symbol = struct {
    /// Exported name as declared by the C header.
    name: [:0]const u8,
    /// Kind of value stored for this export.
    kind: SymbolKind,
};

/// Panic with the library and symbol when a routed call precedes a successful load.
/// This check remains active in every optimization mode.
pub fn panicNotReady(library: []const u8, comptime symbol: []const u8) noreturn {
    std.debug.panic(
        "{s}: {s} was called before this module was loaded; call " ++
            "load({{ .path = \"...\" }}) or load({{ .system = \"...\" }}) first",
        .{ library, symbol },
    );
}

/// Whether this target is classified as supporting dynamic loading.
/// False for WASI, Emscripten, and freestanding targets.
pub const supported_target: bool = switch (builtin.os.tag) {
    .wasi, .emscripten, .freestanding => false,
    else => true,
};

/// Define load state and operations for one dispatch configuration.
/// The configuration supplies its table, symbols, synchronization, and validation hooks.
pub fn Loader(comptime Config: type) type {
    return struct {
        const LoaderType = @This();

        /// Dispatch table type filled by this loader.
        pub const table_type = Config.table;

        /// Current attempt, retained until all waiters read its result.
        attempt: ?Attempt = null,

        /// Immutable request copy, set under lock before publication.
        request: SourceRecord = .{},

        /// Load a provider and publish the table on success.
        /// Failures return `LoadError`, publish nothing, and can be retried.
        pub fn load(self: *LoaderType, source: LoadSource) LoadError!void {
            try validateSource(source);
            // The ready path accepts identical requests without taking the lock.
            if (Config.ready().isReady()) return self.accept(source);

            Config.sync.lock();
            while (true) {
                switch (Config.ready().state()) {
                    .ready => {
                        Config.sync.unlock();
                        return self.accept(source);
                    },
                    .loading => {
                        const attempt = &self.attempt.?;
                        if (attempt.owner == Config.sync.threadSelf()) {
                            Config.sync.unlock();
                            return error.ReentrantLoad;
                        }
                        if (!eqlSource(self.request.source().?, source)) {
                            Config.sync.unlock();
                            return error.ProviderMismatch;
                        }
                        // Join the active attempt instead of starting a competing load.
                        attempt.waiters += 1;
                        while (Config.ready().state() == .loading) Config.sync.wait();
                        const result = attempt.result;
                        attempt.waiters -= 1;
                        // Keep the attempt until every waiter has read its result.
                        Config.sync.broadcast();
                        Config.sync.unlock();
                        return result;
                    },
                    .not_loaded => {
                        // Do not retry until the previous attempt's waiters drain.
                        if (self.attempt != null) {
                            Config.sync.wait();
                            continue;
                        }
                        break;
                    },
                }
            }

            self.request.set(source);
            self.attempt = .{ .owner = Config.sync.threadSelf() };
            Config.ready().set(.loading);
            Config.sync.unlock();

            // Run provider constructors outside the lock; callers wait on the attempt.
            const outcome = runAttempt(self.request.source().?);
            const succeeded = if (outcome) |_| true else |_| false;

            Config.sync.lock();
            self.attempt.?.result = outcome;
            Config.ready().set(if (succeeded) .ready else .not_loaded);
            // Wake all waiters after publishing this attempt's result.
            Config.sync.broadcast();
            // Retain the attempt until every waiter has consumed its result.
            while (self.attempt.?.waiters > 0) Config.sync.wait();
            self.attempt = null;
            // Wake callers waiting to start a retry.
            Config.sync.broadcast();
            Config.sync.unlock();

            return outcome;
        }

        /// Return the successful request, or null before a load succeeds.
        /// The retained request remains valid for the process lifetime.
        pub fn loadedSource(self: *const LoaderType) ?LoadSource {
            if (!Config.ready().isReady()) return null;
            return self.request.source();
        }

        /// Check a new request against the published provider.
        fn accept(self: *const LoaderType, source: LoadSource) LoadError!void {
            const published = self.request.source() orelse unreachable;
            if (eqlSource(published, source)) return;
            return error.ProviderMismatch;
        }

        /// Open and validate a provider without holding the loader lock.
        /// Close the candidate unless every check succeeds.
        fn runAttempt(source: LoadSource) LoadError!void {
            const handle = platform.open(source) catch |err| return err;

            var retain = false;
            defer if (!retain) platform.close(handle);

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |_, index| {
                    Config.assignMissing(index, Config.tablePtr());
                }
            }

            inline for (Config.symbols, 0..) |symbol, index| {
                const address = platform.lookup(handle, symbol.name) orelse
                    return error.MissingSymbol;
                Config.assign(index, Config.tablePtr(), address);
            }

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |symbol, index| {
                    if (platform.lookup(handle, symbol.name)) |address| {
                        Config.assignOptional(index, Config.tablePtr(), address);
                    }
                }
            }

            if (@hasDecl(Config, "validate")) {
                if (Config.validate(Config.tablePtr())) |refusal| {
                    std.debug.print("{s}: refusing this provider: {s}\n", .{
                        Config.library_name,
                        refusal,
                    });
                    return error.ValidationFailed;
                }
            }

            // Keep the handle because dispatch table pointers refer into it.
            retain = true;
        }
    };
}

/// State shared by one load attempt and its waiters.
const Attempt = struct {
    /// Thread running the attempt, used to detect reentrancy.
    owner: u64,
    /// Result published before readiness changes from `loading`.
    result: LoadError!void = error.OpenFailed,
    /// Waiters that must consume this result before the attempt is cleared.
    waiters: usize = 0,
};

/// UTF-16 buffer capacity for Windows paths; accepted UTF-8 byte lengths fit.
const windows_path_units = 32768;

const platform = if (builtin.os.tag == .windows)
    Windows
else if (supported_target)
    Unix
else
    NoLoader;

/// Platform stub for targets without a dynamic loader.
const NoLoader = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        _ = source;
        return error.UnsupportedTarget;
    }
    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        _ = handle;
        _ = name;
        return null;
    }
    fn close(handle: *anyopaque) void {
        _ = handle;
    }
};

/// Unix `dlopen`/`dlsym`/`dlclose` backend.
const Unix = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        var buffer: [max_source_len + 1]u8 = undefined;
        @memcpy(buffer[0..text.len], text);
        buffer[text.len] = 0;
        // Resolve dependencies now and keep provider symbols out of the global namespace.
        return std.c.dlopen(
            // `dlopen` requires a NUL-terminated path.
            buffer[0..text.len :0].ptr,
            .{ .NOW = true, .GLOBAL = false },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return std.c.dlsym(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = std.c.dlclose(handle);
    }
};

/// Windows dynamic-loader declarations used by this module.
const kernel32 = struct {
    extern "kernel32" fn LoadLibraryExW(
        file_name: [*:0]const u16,
        file: ?*anyopaque,
        flags: u32,
    ) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetProcAddress(module: *anyopaque, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn FreeLibrary(module: *anyopaque) callconv(.winapi) i32;
};

/// Windows `LoadLibraryExW`/`GetProcAddress`/`FreeLibrary` backend.
const Windows = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget, SourceTooLong };

    /// Search standard directories for bare names; do not search the current directory.
    const load_library_search_default_dirs: u32 = 0x0000_1000;
    const load_library_search_dll_load_dir: u32 = 0x0000_0100;

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        if (text.len > windows_path_units) return error.SourceTooLong;
        var buffer: [windows_path_units + 1]u16 = undefined;
        const units = std.unicode.utf8ToUtf16Le(buffer[0..text.len], text) catch
            return error.OpenFailed;
        buffer[units] = 0;
        return kernel32.LoadLibraryExW(
            buffer[0..units :0],
            null,
            load_library_search_default_dirs | switch (source) {
                .path => load_library_search_dll_load_dir,
                .system => @as(u32, 0),
            },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return kernel32.GetProcAddress(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = kernel32.FreeLibrary(handle);
    }
};
