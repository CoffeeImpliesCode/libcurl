// SPDX-License-Identifier: curl
// See ../FORK-LICENSE.md for what that identifier covers.

//! Consumes the `libcurl` package the way an outside project would.
//!
//! Everything here goes through the published surface only: `dep.module` in
//! `build.zig`, and `@import("libcurl")` here. No path reaches into the
//! library's own tree, so if this builds and produces the answers below, the
//! module contract is real: the typed facade, the translated headers it
//! re-exports as `c`, and the native library behind both arrived through one
//! dependency line.
//!
//! ## What it proves
//!
//! A real fetch, over a real socket, against an HTTP server this process starts
//! itself on `127.0.0.1` on a port the kernel picks. No host is named, no name
//! is resolved, nothing leaves the machine, and the output does not depend on
//! the clock or a random seed.
//!
//! The answers are not values this program computed and printed for comparison.
//! The body is checked against a SHA-256 taken before any library code ran, and
//! the response head is checked against the shape RFC 9110 requires. Any
//! mismatch prints both sides and exits non-zero.
//!
//! ## Both configurations
//!
//! The same source builds against a linked package and against a
//! runtime-loaded one. `libcurl.runtime_loaded` is a comptime constant, so the
//! difference is one branch and no duplicated program: in the runtime-loaded
//! build the provider is named on the command line (`--provider <path>`) or in
//! `LIBCURL_TEST_PROVIDER`, loaded once, and the same answers follow.
//!
//! `build.zig` removes `LIBCURL_TEST_PROVIDER` from this run step's environment,
//! so a `zig build run -Druntime=true -- --provider <path>` demonstrably took
//! the command-line route. The environment route is still reachable by running
//! the installed executable directly with the variable set. The program prints
//! which route it used, so the record says rather than assumes.

const std = @import("std");
const curl = @import("libcurl");

const Sha256 = std.crypto.hash.sha2.Sha256;

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// The provider this run should load, from `--provider <path>` or from
/// `LIBCURL_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location, and a build
/// that was not told which file to load says so rather than loading something
/// else.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get("LIBCURL_TEST_PROVIDER") orelse
        return noProvider();
}

/// Say which variable is missing. An error name on its own would send the next
/// person into the loader instead of to the command line.
fn noProvider() ConfigurationError {
    std.debug.print(
        "consumer: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export LIBCURL_TEST_PROVIDER with a shared object exporting the " ++
            "declarations of zig/translate.h. Nothing is loaded by default and " ++
            "no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}

/// The loopback address the fixture binds to.
const loopback = "127.0.0.1";

/// The recorded body this program serves and then checks.
///
/// Independently constructed for this package, and written out here rather than
/// shared with `../tests.zig` and `../smoke.zig`: a file both of those would
/// import has to appear in `../build.zig.zon`'s `.paths`, which is not this
/// package's file to edit. The digest is what makes the duplication safe -- if
/// the copies drifted, one of the three programs would fail rather than
/// quietly check its own bytes.
///
/// Its one unusual property is a line that looks like a response header
/// (`X-Not-A-Header: ...`). A body contaminated by the response head is then
/// visible rather than merely plausible, so the byte-exact check below is a
/// statement about the body and not about the whole exchange.
const fixture_body: []const u8 =
    "libcurl consumer fixture\n" ++
    "X-Not-A-Header: this is body text, not a response header\n" ++
    "last line\n";

/// SHA-256 of `fixture_body`, OBSERVED from `sha256sum` over its bytes before
/// any libcurl code in this package had been built or run.
const fixture_digest_hex = "908a5869982caac4fa0dffb85a2449c22db791fdd153cded06ea90f41a93f6aa";

const body_capacity = 64 * 1024;
const head_capacity = 4096;

/// What the transfer delivered, assembled by the facade's own callbacks.
const Sink = struct {
    body: [body_capacity]u8 = undefined,
    body_len: usize = 0,
    head: [head_capacity]u8 = undefined,
    head_len: usize = 0,
    write_calls: usize = 0,

    fn bytes(self: *const Sink) []const u8 {
        return self.body[0..self.body_len];
    }

    fn headBytes(self: *const Sink) []const u8 {
        return self.head[0..self.head_len];
    }
};

/// The write sink libcurl calls for response bodies.
///
/// Four parameters, in libcurl's own order: `curl_write_callback` is
/// `size_t (*)(char *buffer, size_t size, size_t nitems, void *outstream)`
/// (`include/curl/curl.h:285-288`), and `lib/url.c:326` casts libc's `fwrite` --
/// also four, userdata last -- into that type to make the default. The byte
/// count is `size * nitems`.
fn onWrite(
    buffer: [*c]u8,
    size: usize,
    nitems: usize,
    outstream: ?*anyopaque,
) callconv(.c) usize {
    const sink: *Sink = @ptrCast(@alignCast(outstream orelse return 0));
    sink.write_calls += 1;
    const total = curl.chunkLength(size, nitems) orelse return 0;
    if (sink.body_len + total > body_capacity) return 0;
    @memcpy(sink.body[sink.body_len..][0..total], buffer[0..total]);
    sink.body_len += total;
    return total;
}

/// The header sink libcurl calls for the response head. Same shape as `onWrite`,
/// same source line.
fn onHeader(
    buffer: [*c]u8,
    size: usize,
    nitems: usize,
    outstream: ?*anyopaque,
) callconv(.c) usize {
    const sink: *Sink = @ptrCast(@alignCast(outstream orelse return nitems * size));
    const total = curl.chunkLength(size, nitems) orelse return 0;
    if (sink.head_len + total > head_capacity) return 0;
    @memcpy(sink.head[sink.head_len..][0..total], buffer[0..total]);
    sink.head_len += total;
    return total;
}

/// A tiny HTTP/1.1 server on the loopback interface, answering `requests`
/// connections and then stopping.
///
/// One `std.Io.Group` member on the instance's own thread pool, which is a real
/// OS thread underneath and is the arrangement `std/Build/WebServer.zig:147-186`
/// uses for the same job. Cancelling the group both interrupts the blocked
/// `accept` and waits for the thread to leave, so this program cannot hang in
/// teardown even if a transfer never arrived.
const FixtureServer = struct {
    io: std.Io,
    group: std.Io.Group = .init,
    listener: std.Io.net.Server,
    requests: usize,
    port: u16,
    answered: usize = 0,
    fault: bool = false,

    /// Takes the destination rather than returning one, because the serving
    /// thread is handed `self`. Returning by value left the thread holding a
    /// pointer to a stack frame that ended when `start` returned, so it read
    /// `self.listener` and `self.io` out of reclaimed stack and faulted inside
    /// `Server.accept` (`std/Io/net.zig:1443`) on the first connection.
    fn start(self: *FixtureServer, io: std.Io, requests: usize) !void {
        var address = try std.Io.net.IpAddress.parseIp4(loopback, 0);
        const listener = try address.listen(io, .{ .reuse_address = true });
        self.* = .{
            .io = io,
            .listener = listener,
            .requests = requests,
            // `Socket.address` carries the resolved port "if requested"
            // (`std/Io/net.zig:1054-1055`), which is what `port 0` is for.
            .port = listener.socket.address.getPort(),
        };
        errdefer self.listener.deinit(io);
        try self.group.concurrent(io, serve, .{self});
    }

    fn deinit(self: *FixtureServer) void {
        self.group.cancel(self.io);
        self.listener.deinit(self.io);
        self.* = undefined;
    }

    fn url(self: *const FixtureServer, target: []const u8, buffer: []u8) ![:0]const u8 {
        // `[:0]` because `Easy.setUrl` measures with `strlen`
        // (`lib/setopt.c:84`). `bufPrint` writes no terminator of its own, so
        // the NUL is written here rather than asserted over untouched bytes.
        const printed = try std.fmt.bufPrint(buffer, "http://{s}:{d}{s}", .{ loopback, self.port, target });
        buffer[printed.len] = 0;
        return buffer[0..printed.len :0];
    }
};

fn serve(self: *FixtureServer) std.Io.Cancelable!void {
    while (self.answered < self.requests) {
        const stream = self.listener.accept(self.io) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            else => {
                self.fault = true;
                return;
            },
        };
        defer stream.close(self.io);

        var in_buffer: [head_capacity]u8 = undefined;
        var out_buffer: [head_capacity]u8 = undefined;
        var reader = stream.reader(self.io, &in_buffer);
        var writer = stream.writer(self.io, &out_buffer);
        var http: std.http.Server = .init(&reader.interface, &writer.interface);

        var request = http.receiveHead() catch {
            self.fault = true;
            return;
        };
        self.answered += 1;

        // `respond` emits the status line, a `Content-Length` that matches the
        // body and the empty line that ends the head
        // (`std/http/Server.zig:352-386`), and it flushes before it returns.
        // Writing the head by hand through an `Io.Writer` would look equivalent
        // and would not be: that writer buffers, and closing the socket with
        // bytes still in its buffer drops them. So the head comes from `std`,
        // and the checks below are statements about the protocol rather than
        // about this program's own spelling of it.
        request.respond(fixture_body, .{ .keep_alive = false }) catch {
            self.fault = true;
            return;
        };
    }
}

/// True when one CRLF-terminated line of `head` is exactly `line`.
fn hasLine(head: []const u8, line: []const u8) bool {
    var lines = std.mem.splitSequence(u8, head, "\r\n");
    while (lines.next()) |candidate| {
        if (std.mem.eql(u8, candidate, line)) return true;
    }
    return false;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // In a runtime-loading build every call below goes through a table that this
    // one call fills. In a linked build the branch is not analyzed at all.
    if (comptime curl.runtime_loaded) {
        try curl.load(.{ .path = try providerRequest(init) });
    }
    const route: []const u8 = if (curl.runtime_loaded)
        "an explicit load() of a named provider"
    else
        "a direct call into the linked library";

    try w.print("libcurl consumer\n", .{});
    try w.print("{s} provider, reached by {s}\n", .{
        // Through the raw escape hatch, so this line names the library this
        // build reached rather than a constant compiled into this program. It
        // is printed, never compared: a version string is provenance, not
        // behaviour.
        curl.versionString(),
        route,
    });
    try w.flush();

    try curl.globalInit(.{});
    // No `globalCleanup`: the handle below is still open when this function
    // returns, and `curl_global_cleanup` decrements a refcount
    // (`lib/easy.c:266-273`) that closing it is what balances.

    // One connection, because this program makes one transfer. The server stops
    // asking after that and blocks in `accept`, which `deinit` cancels -- so a
    // count higher than the transfers would not hang here, but it would make
    // the count below a statement about the wrong number.
    var fixture: FixtureServer = undefined;
    try fixture.start(io, 1);
    defer fixture.deinit();

    var url_buffer: [128]u8 = undefined;
    const url = try fixture.url("/consumer.txt", &url_buffer);

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};

    try easy.setUrl(url);
    try easy.setTimeoutMs(10_000);
    easy.setWriteFunction(&sink, onWrite);
    easy.setHeaderFunction(&sink, onHeader);

    // A header list the caller owns. Upstream copies each line at append time
    // (`curlx_strdup`, `lib/slist.c:87`) and stores only the pointer at setopt
    // time (`s->headers = slist`, `lib/setopt.c:1362`), so the list must
    // outlive the transfer and is still the caller's to release afterwards.
    // It is released explicitly below rather than in a `defer`, because defers
    // run last-in-first-out and the release has to come after the transfer, not
    // before the handle's own teardown.
    var headers = curl.SList{};
    try headers.append("X-Consumer-Probe: libcurl");
    try easy.setHeaders(&headers);

    try easy.perform();

    // The independent known answer.
    var digest: [32]u8 = undefined;
    Sha256.hash(sink.bytes(), &digest, .{});
    var hex: [64]u8 = undefined;
    try checkString(
        w,
        "body of GET /consumer.txt (sha256)",
        try std.fmt.bufPrint(&hex, "{x}", .{digest[0..]}),
        fixture_digest_hex,
    );
    try checkBytes(w, "body, byte for byte", sink.bytes(), fixture_body);

    // What the protocol fixes, cross-checked between the status line and the
    // declared length the fixture wrote.
    try checkInt(w, "CURLINFO_RESPONSE_CODE", try easy.responseCode(), 200);
    try checkBool(w, "status line as RFC 9110 requires", hasLine(sink.headBytes(), "HTTP/1.1 200 OK"));
    try checkBool(
        w,
        "content-length matches the body",
        hasLine(sink.headBytes(), try std.fmt.bufPrint(&hex, "content-length: {d}", .{fixture_body.len})),
    );
    try checkBool(w, "the write callback ran", sink.write_calls >= 1);
    try checkBool(w, "the body was not the head", sink.bytes()[0] == fixture_body[0]);
    try checkBool(w, "the fixture served its one request", !fixture.fault and fixture.answered == 1);

    // `CURLINFO_EFFECTIVE_URL` is a borrow into the handle's own storage
    // (`lib/getinfo.c:83-87`), and upstream says of the neighbouring string info
    // "Callers must never free it themselves" (`lib/getinfo.c:124-130`). So it
    // is read here, not released.
    const effective = (try easy.effectiveUrl()) orelse return error.NoEffectiveUrl;
    try checkString(w, "CURLINFO_EFFECTIVE_URL", effective, url);

    headers.freeAll();
    try checkBool(w, "the caller's header list is released once", headers.raw() == null);

    // Percent-encoding, against a value derived from RFC 3986 section 2.3 rather
    // than from anything libcurl said. The character classes are the RFC's; the
    // upper-case hex digits are libcurl's, read out of `lib/escape.c:226-227`
    // and `lib/mprintf.c:40`.
    const input = "AZaz09-._~ /?#&=[]%+:@!$'(),;\"\\*|<>{}`^\x00\xff";
    var expected_buffer: [512]u8 = undefined;
    const expected = try expectedEscape(input, &expected_buffer);

    // Owned by libcurl, so it is released with the matching free (`curl_free`,
    // `lib/escape.c:190`) rather than with any Zig allocator.
    const escaped = try curl.escape(input);
    defer curl.freeEscaped(escaped);
    try checkString(w, "escape, RFC 3986 unreserved", escaped, expected);

    const decoded = try curl.unescape(escaped);
    defer curl.freeEscaped(decoded);
    try checkBytes(w, "unescape of the escape, NUL and all", decoded, input);

    try w.print("every answer matched the documented value\n", .{});
    try w.flush();
}

/// One byte's escape, derived from the character classes RFC 3986 defines.
fn expectedEscape(input: []const u8, output: []u8) ![]const u8 {
    const unreserved = "0123456789" ++
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ" ++
        "abcdefghijklmnopqrstuvwxyz" ++
        "-._~";
    const digits = "0123456789ABCDEF";
    var length: usize = 0;
    for (input) |byte| {
        if (std.mem.indexOfScalar(u8, unreserved, byte) != null) {
            if (length >= output.len) return error.BufferTooSmall;
            output[length] = byte;
            length += 1;
        } else {
            if (length + 3 > output.len) return error.BufferTooSmall;
            output[length] = '%';
            output[length + 1] = digits[byte >> 4];
            output[length + 2] = digits[byte & 0x0f];
            length += 3;
        }
    }
    return output[0..length];
}

fn checkInt(w: *std.Io.Writer, what: []const u8, got: anytype, expected: anytype) !void {
    try w.print("{s: <44}{d}\n", .{ what, got });
    if (got != expected) {
        std.debug.print("consumer: {s}: expected {d}, computed {d}\n", .{ what, expected, got });
        return error.ConsumerCheckFailed;
    }
}

fn checkBool(w: *std.Io.Writer, what: []const u8, got: bool) !void {
    try w.print("{s: <44}{s}\n", .{ what, if (got) "yes" else "no" });
    if (!got) {
        std.debug.print("consumer: {s}: expected yes, computed no\n", .{what});
        return error.ConsumerCheckFailed;
    }
}

fn checkString(w: *std.Io.Writer, what: []const u8, got: []const u8, expected: []const u8) !void {
    try w.print("{s: <44}{s}\n", .{ what, got });
    if (!std.mem.eql(u8, got, expected)) {
        std.debug.print("consumer: {s}: expected \"{s}\", computed \"{s}\"\n", .{ what, expected, got });
        return error.ConsumerCheckFailed;
    }
}

fn checkBytes(w: *std.Io.Writer, what: []const u8, got: []const u8, expected: []const u8) !void {
    try w.print("{s: <44}{d} bytes\n", .{ what, got.len });
    if (!std.mem.eql(u8, got, expected)) {
        std.debug.print("consumer: {s}: expected {x}, computed {x}\n", .{ what, expected, got });
        return error.ConsumerCheckFailed;
    }
}