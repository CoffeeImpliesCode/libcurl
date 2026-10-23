// SPDX-License-Identifier: curl
// See FORK-LICENSE.md for what that identifier covers.
//
//! libcurl-specific runtime loader configuration.
//! It binds synchronization symbols and checks provider version age and TLS support.
//! Symbol resolution alone does not prove ABI compatibility.

const std = @import("std");

const rt = @import("rt");

/// Synchronization binding shared by this loader instance.
/// Keep its names aligned with `sync_prefix` in `runtime/graph.zig`.
pub const Sync = struct {
    extern fn curl_rt_lock() void;
    extern fn curl_rt_unlock() void;
    extern fn curl_rt_wait() void;
    extern fn curl_rt_broadcast() void;
    // The C function returns `unsigned long long`, which maps to `u64` here.
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

/// Configure the generic loader with this dispatch's table, symbols, and checks.
/// The dispatch supplies its type, so this file does not import it.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Library name used in pre-load panics.
        pub const library_name = "libcurl";

        /// Translated table and symbol lists supplied by the dispatch.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// Namespaced synchronization binding for this loader.
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

        /// Validate provider version shape and TLS support before table publication.
        /// Return a message to reject the provider with `ValidationFailed`.
        pub fn validate(dst: *const table) ?[]const u8 {
            // Pass the header's `CURLVERSION_NOW` value for the struct age check.
            const info = dst.curl_version_info(dispatch.CURLVERSION_NOW) orelse return
                "curl_version_info returned null. include/curl/curl.h:3240-3248 " ++
                "documents it as returning a pointer to a static copy of the " ++
                "version struct, and lib/version.c:579-681 returns the address " ++
                "of one static struct, so null is not a shape this library " ++
                "produces";

            if (info.age < dispatch.CURLVERSION_NOW) return
                "curl_version_info reports an older curl_version_info_data than " ++
                "the CURLVERSION_NOW include/curl/curl.h:3136 defines, so this " ++
                "provider's version struct is not the one these headers describe";

            // Reject providers without a TLS backend.
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
