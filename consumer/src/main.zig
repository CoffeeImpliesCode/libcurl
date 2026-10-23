// SPDX-License-Identifier: curl
// See ../FORK-LICENSE.md for what that identifier covers.

//! External-consumer example for the published libcurl package.
//! It transfers from a local loopback server and checks response bytes, headers, and encoding.
//! The same source supports linked and runtime-loaded builds with an explicit provider.

const std = @import("std");
const curl = @import("libcurl");

const Sha256 = std.crypto.hash.sha2.Sha256;

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// Read the provider path from `--provider` or `LIBCURL_TEST_PROVIDER`.
/// Both are explicit; no default lookup or fallback is attempted.
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

/// Explain how to select a provider for a runtime-loaded build.
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

/// IPv4 loopback address used by the fixture server.
const loopback = "127.0.0.1";

/// Body includes a header-like line to detect response-head contamination.
const fixture_body: []const u8 =
    "libcurl consumer fixture\n" ++
    "X-Not-A-Header: this is body text, not a response header\n" ++
    "last line\n";

/// Expected SHA-256 of `fixture_body`.
const fixture_digest_hex = "908a5869982caac4fa0dffb85a2449c22db791fdd153cded06ea90f41a93f6aa";

const body_capacity = 64 * 1024;
const head_capacity = 4096;

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

/// libcurl body callback; the byte count is `size * nitems`.
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

/// libcurl response-header callback, with the same argument shape as `onWrite`.
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

/// Single-process HTTP/1.1 fixture on loopback.
/// Group cancellation interrupts `accept` and joins the serving thread at teardown.
const FixtureServer = struct {
    io: std.Io,
    group: std.Io.Group = .init,
    listener: std.Io.net.Server,
    requests: usize,
    port: u16,
    answered: usize = 0,
    fault: bool = false,

    /// Initialize in place because the serving thread borrows `self`.
    /// Returning by value would leave it with a pointer to expired stack storage.
    fn start(self: *FixtureServer, io: std.Io, requests: usize) !void {
        var address = try std.Io.net.IpAddress.parseIp4(loopback, 0);
        const listener = try address.listen(io, .{ .reuse_address = true });
        self.* = .{
            .io = io,
            .listener = listener,
            .requests = requests,
            // Port 0 requests an ephemeral port; read the bound port from the listener.
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
        // `setUrl` uses `strlen`, and `bufPrint` does not append the NUL required by `[:0]`.
        // Write the terminator explicitly and return the sentinel-terminated slice.
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

        // `respond` writes and flushes the complete response head before returning.
        // Manual writes could remain buffered when the socket closes.
        request.respond(fixture_body, .{ .keep_alive = false }) catch {
            self.fault = true;
            return;
        };
    }
}

/// Whether `head` contains `line` as a complete CRLF-terminated line.
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

    // The linked build comptime-elides this load; runtime mode loads its named provider.
    if (comptime curl.runtime_loaded) {
        try curl.load(.{ .path = try providerRequest(init) });
    }
    const route: []const u8 = if (curl.runtime_loaded)
        "an explicit load() of a named provider"
    else
        "a direct call into the linked library";

    try w.print("libcurl consumer\n", .{});
    try w.print("{s} provider, reached by {s}\n", .{
        curl.versionString(),
        route,
    });
    try w.flush();

    try curl.globalInit(.{});
    // Keep global state initialized while the Easy handle remains open.

    // Serve exactly one request so the response check matches the fixture's work.
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

    // libcurl retains the list pointer, so keep the caller-owned list alive through `perform`.
    // Free it afterward, before the handle's deferred teardown.
    var headers = curl.SList{};
    try headers.append("X-Consumer-Probe: libcurl");
    try easy.setHeaders(&headers);

    try easy.perform();

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

    // Check the status line and content length sent by the fixture.
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

    // Borrowed from the Easy handle; do not free this value.
    const effective = (try easy.effectiveUrl()) orelse return error.NoEffectiveUrl;
    try checkString(w, "CURLINFO_EFFECTIVE_URL", effective, url);

    headers.freeAll();
    try checkBool(w, "the caller's header list is released once", headers.raw() == null);

    // Expected escapes use RFC 3986's unreserved set; hex digits are uppercase.
    const input = "AZaz09-._~ /?#&=[]%+:@!$'(),;\"\\*|<>{}`^\x00\xff";
    var expected_buffer: [512]u8 = undefined;
    const expected = try expectedEscape(input, &expected_buffer);

    // libcurl owns the result; release it with `curl.freeEscaped`, not a Zig allocator.
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
