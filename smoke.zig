// SPDX-License-Identifier: curl
// See FORK-LICENSE.md for what that identifier covers.

const std = @import("std");
const curl = @import("libcurl");

const Sha256 = std.crypto.hash.sha2.Sha256;

const ConfigurationError = error{NoProviderConfigured};

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

fn noProvider() ConfigurationError {
    std.debug.print(
        "smoke: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export LIBCURL_TEST_PROVIDER with a shared object exporting the " ++
            "declarations of zig/translate.h. Nothing is loaded by default and " ++
            "no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}

const loopback = "127.0.0.1";

const fixture_body: []const u8 =
    "libcurl loopback fixture v1\n" ++
    "X-Not-A-Header: this is body text, not a response header\n" ++
    "last line\n";

const fixture_digest_hex = "c1a7c3eda96b2be6976bb9c3723f1931ca9e9cca16d64fa1f25077ec8c4db210";

const body_capacity = 64 * 1024;
const head_capacity = 4096;

const Sink = struct {
    body: [body_capacity]u8 = undefined,
    body_len: usize = 0,
    head: [head_capacity]u8 = undefined,
    head_len: usize = 0,
    write_calls: usize = 0,
    header_calls: usize = 0,

    fn bytes(self: *const Sink) []const u8 {
        return self.body[0..self.body_len];
    }

    fn headBytes(self: *const Sink) []const u8 {
        return self.head[0..self.head_len];
    }
};

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

fn onHeader(
    buffer: [*c]u8,
    size: usize,
    nitems: usize,
    outstream: ?*anyopaque,
) callconv(.c) usize {
    const sink: *Sink = @ptrCast(@alignCast(outstream orelse return nitems * size));
    sink.header_calls += 1;
    const total = curl.chunkLength(size, nitems) orelse return 0;
    if (sink.head_len + total > head_capacity) return 0;
    @memcpy(sink.head[sink.head_len..][0..total], buffer[0..total]);
    sink.head_len += total;
    return total;
}

const Response = struct {
    body: []const u8,
    extra_headers: []const std.http.Header = &.{},
};

const FixtureServer = struct {
    io: std.Io,
    group: std.Io.Group = .init,
    listener: std.Io.net.Server,
    requests: usize,
    response: Response,
    port: u16,
    answered: usize = 0,
    fault: bool = false,

    /// Initialize in place because the serving thread retains `self`.
    fn start(self: *FixtureServer, io: std.Io, requests: usize, response: Response) !void {
        var address = try std.Io.net.IpAddress.parseIp4(loopback, 0);
        const listener = try address.listen(io, .{ .reuse_address = true });
        self.* = .{
            .io = io,
            .listener = listener,
            .requests = requests,
            .response = response,
            // Read the kernel-selected port from the bound socket.
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
        // `setUrl` uses `strlen`; `bufPrint` needs an explicit NUL.
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

        request.respond(self.response.body, .{
            .extra_headers = self.response.extra_headers,
            .keep_alive = false,
        }) catch {
            self.fault = true;
            return;
        };
    }
}

fn hasLine(head: []const u8, line: []const u8) bool {
    var lines = std.mem.splitSequence(u8, head, "\r\n");
    while (lines.next()) |candidate| {
        if (std.mem.eql(u8, candidate, line)) return true;
    }
    return false;
}

/// Builds the expected bytes from RFC 3986's unreserved set.
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

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // Load the configured provider before making facade calls.
    if (comptime curl.runtime_loaded) {
        try curl.load(.{ .path = try providerRequest(init) });
    }

    try w.print("libcurl smoke\n", .{});
    try w.print("{s} provider reports: {s}\n", .{
        if (curl.runtime_loaded) "loaded" else "linked",
        curl.versionString(),
    });
    try w.flush();

    try curl.globalInit(.{});

    var fixture: FixtureServer = undefined;
    try fixture.start(io, 1, .{ .body = fixture_body });
    defer fixture.deinit();

    var url_buffer: [128]u8 = undefined;
    const url = try fixture.url("/fixture.txt", &url_buffer);

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};

    try easy.setUrl(url);
    try easy.setTimeoutMs(10_000);
    easy.setWriteFunction(&sink, onWrite);
    easy.setHeaderFunction(&sink, onHeader);

    // `setHeaders` borrows the caller-owned list during the transfer.
    var headers = curl.SList{};
    try headers.append("X-Smoke-Fixture: 1");
    try easy.setHeaders(&headers);

    try easy.perform();

    var digest: [32]u8 = undefined;
    Sha256.hash(sink.bytes(), &digest, .{});
    var hex: [64]u8 = undefined;
    try checkString(
        w,
        "body of GET /fixture.txt (sha256)",
        try std.fmt.bufPrint(&hex, "{x}", .{digest[0..]}),
        fixture_digest_hex,
    );
    try checkInt(w, "bytes the digest covers", fixture_body.len, 95);
    try checkBytes(w, "body, byte for byte", sink.bytes(), fixture_body);

    try checkInt(w, "CURLINFO_RESPONSE_CODE", try easy.responseCode(), 200);
    try checkBool(w, "status line as RFC 9110 requires it", hasLine(sink.headBytes(), "HTTP/1.1 200 OK"));
    try checkBool(
        w,
        "content-length matches the body",
        hasLine(sink.headBytes(), try std.fmt.bufPrint(&hex, "content-length: {d}", .{fixture_body.len})),
    );
    try checkBool(w, "head ends with the empty line", std.mem.endsWith(u8, sink.headBytes(), "\r\n\r\n"));
    try checkBool(w, "the write callback ran", sink.write_calls >= 1);
    try checkBool(w, "the write callback saw the body, not the head", sink.bytes()[0] == fixture_body[0]);

    try checkBool(w, "head callback ran", sink.header_calls > 0);
    try checkBool(w, "the fixture served its one request", !fixture.fault and fixture.answered == 1);

    // `effectiveUrl` borrows handle storage; do not free it.
    const effective = (try easy.effectiveUrl()) orelse return error.NoEffectiveUrl;
    try checkString(w, "CURLINFO_EFFECTIVE_URL", effective, url);

    headers.freeAll();
    try checkBool(w, "the caller's list is released once", headers.raw() == null);

    const input = "AZaz09-._~ /?#&[]%+:@!$'(),;\"\\*|<>{}`^\x00\xff";
    var expected_buffer: [512]u8 = undefined;
    const expected = try expectedEscape(input, &expected_buffer);

    // `escape` returns a libcurl allocation; release it with `freeEscaped`.
    const escaped = try curl.escape(input);
    defer curl.freeEscaped(escaped);
    try checkString(w, "escape, RFC 3986 unreserved", escaped, expected);

    const decoded = try curl.unescape(escaped);
    defer curl.freeEscaped(decoded);
    try checkBytes(w, "unescape of the escape, NUL and all", decoded, input);

    // Bind without listening to reserve a port that refuses connections.
    var address = try std.Io.net.IpAddress.parseIp4(loopback, 0);
    const closed = try address.bind(io, .{ .mode = .stream });
    defer closed.close(io);
    const refused_url = try std.fmt.bufPrint(&url_buffer, "http://{s}:{d}/nothing", .{
        loopback,
        closed.address.getPort(),
    });
    url_buffer[refused_url.len] = 0;
    const refused_terminated = url_buffer[0..refused_url.len :0];

    var doomed = try curl.Easy.init();
    defer doomed.deinit();
    var unused = Sink{};
    try doomed.setUrl(refused_terminated);
    try doomed.setTimeoutMs(10_000);
    doomed.setWriteFunction(&unused, onWrite);
    const refused = doomed.perform();
    if (refused) |_| {
        std.debug.print("smoke: a connection to a closed port succeeded\n", .{});
        return error.SmokeCheckFailed;
    } else |err| {
        try w.print("{s: <44}{s}\n", .{ "closed loopback port gives", @errorName(err) });
        try checkInt(w, "nothing was delivered", unused.write_calls, 0);
    }

    try w.print("every answer matched the documented value\n", .{});
    try w.flush();
}

fn checkInt(w: *std.Io.Writer, what: []const u8, got: anytype, expected: anytype) !void {
    try w.print("{s: <44}{d}\n", .{ what, got });
    if (got != expected) {
        std.debug.print("smoke: {s}: expected {d}, computed {d}\n", .{ what, expected, got });
        return error.SmokeCheckFailed;
    }
}

fn checkBool(w: *std.Io.Writer, what: []const u8, got: bool) !void {
    try w.print("{s: <44}{s}\n", .{ what, if (got) "yes" else "no" });
    if (!got) {
        std.debug.print("smoke: {s}: expected yes, computed no\n", .{what});
        return error.SmokeCheckFailed;
    }
}

fn checkString(w: *std.Io.Writer, what: []const u8, got: []const u8, expected: []const u8) !void {
    try w.print("{s: <44}{s}\n", .{ what, got });
    if (!std.mem.eql(u8, got, expected)) {
        std.debug.print("smoke: {s}: expected \"{s}\", computed \"{s}\"\n", .{ what, expected, got });
        return error.SmokeCheckFailed;
    }
}

fn checkBytes(w: *std.Io.Writer, what: []const u8, got: []const u8, expected: []const u8) !void {
    try w.print("{s: <44}{d} bytes\n", .{ what, got.len });
    if (!std.mem.eql(u8, got, expected)) {
        std.debug.print("smoke: {s}: expected {x}, computed {x}\n", .{ what, expected, got });
        return error.SmokeCheckFailed;
    }
}
