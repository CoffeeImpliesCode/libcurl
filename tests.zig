// SPDX-License-Identifier: curl
// See FORK-LICENSE.md for what that identifier covers.

const std = @import("std");
const curl = @import("libcurl");
const testing = std.testing;

test {
    _ = @import("runtime/generate.zig");
}

const Sha256 = std.crypto.hash.sha2.Sha256;

const provider_variable = "LIBCURL_TEST_PROVIDER";

const loopback = "127.0.0.1";

const max_connections = 4;

const head_capacity = 4096;

const recorded_head_capacity = 2048;

const body_capacity = 64 * 1024;

const fixture_body: []const u8 =
    "libcurl loopback fixture v1\n" ++
    "X-Not-A-Header: this is body text, not a response header\n" ++
    "last line\n";

const fixture_digest_hex = "c1a7c3eda96b2be6976bb9c3723f1931ca9e9cca16d64fa1f25077ec8c4db210";

const binary_body = [_]u8{ 0x00, 0x01, 0xFF, 0xFE, 'a', 0x00, 0x41 };

const Response = struct {
    status: std.http.Status = .ok,
    body: []const u8 = "",
    extra_headers: []const std.http.Header = &.{},
    /// Bytes declared but omitted before closing, for the partial-transfer test.
    truncate_by: u64 = 0,
};

const Route = struct {
    target: []const u8,
    response: Response = .{},
};

const FixtureServer = struct {
    io: std.Io,
    group: std.Io.Group = .init,
    listener: std.Io.net.Server,
    routes: []const Route,
    port: u16,

    /// Written by the server thread; read only after `deinit` joins it.
    recorded: [max_connections][recorded_head_capacity]u8 = undefined,
    recorded_len: [max_connections]usize = @splat(0),
    answered: usize = 0,
    fault: ?Fault = null,

    const Fault = enum {
        AcceptFailed,
        HeadUnreadable,
        ResponseUnsendable,
    };

    fn init(self: *FixtureServer, io: std.Io, routes: []const Route) !void {
        var address = try std.Io.net.IpAddress.parseIp4(loopback, 0);
        const listener = try address.listen(io, .{ .reuse_address = true });
        // Read the resolved ephemeral port from the bound socket.
        self.* = .{
            .io = io,
            .listener = listener,
            .routes = routes,
            .port = listener.socket.address.getPort(),
        };
        errdefer self.listener.deinit(io);
        try self.group.concurrent(io, serve, .{self});
    }

    fn deinit(self: *FixtureServer) void {
        // Cancel and join before reading the server thread's recordings.
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

    fn head(self: *const FixtureServer, index: usize) ![]const u8 {
        if (index >= self.answered) return error.NoSuchConnection;
        return self.recorded[index][0..self.recorded_len[index]];
    }

    fn responseFor(self: *const FixtureServer, target: []const u8) Response {
        for (self.routes) |route| {
            if (std.mem.eql(u8, route.target, target)) return route.response;
        }
        return .{ .status = .not_found, .body = "no such fixture route\n" };
    }
};

fn serve(self: *FixtureServer) std.Io.Cancelable!void {
    while (self.answered < max_connections) {
        const stream = self.listener.accept(self.io) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            else => {
                self.fault = .AcceptFailed;
                return;
            },
        };
        defer stream.close(self.io);
        serveOne(self, stream) catch {
            self.fault = .HeadUnreadable;
        };
    }
}

fn serveOne(self: *FixtureServer, stream: std.Io.net.Stream) !void {
    var in_buffer: [head_capacity]u8 = undefined;
    var out_buffer: [head_capacity]u8 = undefined;
    var reader = stream.reader(self.io, &in_buffer);
    var writer = stream.writer(self.io, &out_buffer);
    var http: std.http.Server = .init(&reader.interface, &writer.interface);

    var request = try http.receiveHead();

    // Copy before the next read invalidates `request.head_buffer`.
    const index = self.answered;
    const kept = @min(request.head_buffer.len, recorded_head_capacity);
    @memcpy(self.recorded[index][0..kept], request.head_buffer[0..kept]);
    self.recorded_len[index] = kept;
    self.answered += 1;

    const response = self.responseFor(request.head.target);

    if (response.truncate_by == 0) {
        request.respond(response.body, .{
            .status = response.status,
            .extra_headers = response.extra_headers,
            .keep_alive = false,
        }) catch {
            self.fault = .ResponseUnsendable;
            return;
        };
        return;
    }

    // Declared length exceeds the sent body; closing early tests a partial transfer.
    var body_buffer: [head_capacity]u8 = undefined;
    var body = request.respondStreaming(&body_buffer, .{
        .content_length = response.body.len + response.truncate_by,
        .respond_options = .{
            .status = response.status,
            .extra_headers = response.extra_headers,
            .keep_alive = false,
        },
    }) catch {
        self.fault = .ResponseUnsendable;
        return;
    };
    // Drain the body buffer into the protocol writer before it flushes to the socket.
    body.writer.writeAll(response.body) catch {
        self.fault = .ResponseUnsendable;
        return;
    };
    body.writer.flush() catch {
        self.fault = .ResponseUnsendable;
        return;
    };
    body.flush() catch {
        self.fault = .ResponseUnsendable;
        return;
    };
}

/// A bound, non-listening socket reserves a port that refuses connections.
const ClosedPort = struct {
    socket: std.Io.net.Socket,
    port: u16,

    fn open(io: std.Io) !ClosedPort {
        var address = try std.Io.net.IpAddress.parseIp4(loopback, 0);
        const socket = try address.bind(io, .{ .mode = .stream });
        // `bind` resolves the ephemeral port before returning.
        return .{ .socket = socket, .port = socket.address.getPort() };
    }

    fn close(self: *ClosedPort, io: std.Io) void {
        self.socket.close(io);
    }
};

const Sink = struct {
    body: [body_capacity]u8 = undefined,
    body_len: usize = 0,
    head: [head_capacity]u8 = undefined,
    head_len: usize = 0,
    write_calls: usize = 0,
    header_calls: usize = 0,
    write_size: usize = 0,
    offered: usize = 0,
    refuse_at_offered: ?usize = null,
    header_without_context: usize = 0,
    overflowed: bool = false,

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
    if (sink.write_size == 0) sink.write_size = size;

    const total = curl.chunkLength(size, nitems) orelse return 0;
    sink.offered += total;

    if (sink.refuse_at_offered) |limit| {
        if (sink.offered >= limit) return 0;
    }

    if (sink.body_len + total > body_capacity) {
        sink.overflowed = true;
        return 0;
    }
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
    const sink: *Sink = @ptrCast(@alignCast(outstream orelse {
        // Return without dereferencing; the assertion reports missing callback data.
        return nitems * size;
    }));
    sink.header_calls += 1;

    const total = curl.chunkLength(size, nitems) orelse return 0;
    if (sink.head_len + total > head_capacity) return 0;
    @memcpy(sink.head[sink.head_len..][0..total], buffer[0..total]);
    sink.head_len += total;
    return total;
}

fn attached(sink: *Sink, easy: *curl.Easy, url: [:0]const u8) !void {
    try easy.setUrl(url);
    try easy.setTimeoutMs(10_000);
    easy.setWriteFunction(sink, onWrite);
    easy.setHeaderFunction(sink, onHeader);
}

fn hasLine(head: []const u8, line: []const u8) bool {
    var lines = std.mem.splitSequence(u8, head, "\r\n");
    while (lines.next()) |candidate| {
        if (std.mem.eql(u8, candidate, line)) return true;
    }
    return false;
}

fn declaredLength(head: []const u8) ?u64 {
    var lines = std.mem.splitSequence(u8, head, "\r\n");
    while (lines.next()) |line| {
        var parts = std.mem.splitScalar(u8, line, ':');
        const name = parts.next() orelse continue;
        if (!std.ascii.eqlIgnoreCase(name, "content-length")) continue;
        return std.fmt.parseInt(u64, std.mem.trim(u8, parts.rest(), " \t"), 10) catch null;
    }
    return null;
}

fn expectDigest(what: []const u8, bytes: []const u8) !void {
    var digest: [32]u8 = undefined;
    Sha256.hash(bytes, &digest, .{});
    var hex: [64]u8 = undefined;
    const rendered = try std.fmt.bufPrint(&hex, "{x}", .{digest[0..]});
    if (!std.mem.eql(u8, fixture_digest_hex, rendered)) {
        std.debug.print(
            "tests.zig: {s}: sha256 is {s}, expected {s}\n",
            .{ what, rendered, fixture_digest_hex },
        );
        return error.DigestMismatch;
    }
}

fn nativeReady() void {
    if (comptime !curl.runtime_loaded) return;
    if (curl.loadedSource() != null) return;

    var buffer: [4096]u8 = undefined;
    const value = testing.environ.getAlloc(testing.allocator, provider_variable) catch
        missingProvider();
    defer testing.allocator.free(value);
    if (value.len == 0 or value.len > buffer.len) missingProvider();
    @memcpy(buffer[0..value.len], value);
    curl.load(.{ .path = buffer[0..value.len] }) catch |err| {
        std.debug.print(
            "tests.zig: loading " ++ provider_variable ++ " = \"{s}\" failed: {t}\n",
            .{ buffer[0..value.len], err },
        );
        @panic("tests.zig: the provider named by " ++ provider_variable ++
            " did not load; nothing below this line ran");
    };
}

fn missingProvider() noreturn {
    @panic(
        "tests.zig: this is a runtime-loading build and " ++ provider_variable ++
            " is not set. Point it at a shared object exporting the declarations " ++
            "of zig/translate.h, for example the one `zig build -Dlinkage=dynamic` " ++
            "installs, and export it for the whole `zig build` invocation: the " ++
            "build cannot inject a path into a run step's environment.",
    );
}

var global_ready = std.atomic.Value(bool).init(false);

fn libraryReady() !void {
    nativeReady();
    if (global_ready.load(.acquire)) return;
    curl.globalInit(.{}) catch |err| {
        std.debug.print("tests.zig: curl_global_init failed: {t}\n", .{err});
        return error.GlobalInitFailed;
    };
    global_ready.store(true, .release);
}

test "version information reads the provider's C record" {
    try libraryReady();
    const info = curl.versionInfo();
    try testing.expect(info.version.len != 0);
    try testing.expect(info.version_num != 0);
    try testing.expect(info.host.len != 0);
    try testing.expect(info.ssl_version != null);
    try testing.expect((info.features & curl.c.CURL_VERSION_SSL) != 0);
}

test "variadic options preserve scalar integer and pointer arguments" {
    try libraryReady();
    var easy = try curl.Easy.init();
    defer easy.deinit();
    try easy.setTimeoutMs(1234);
    try testing.expectError(error.BadFunctionArgument, easy.setTimeoutMs(-1));

    var context: u8 = 42;
    const pointer: ?*anyopaque = &context;
    const set_result = if (comptime curl.runtime_loaded)
        curl.c.curl_easy_setopt(easy.handle(), curl.c.CURLOPT_PRIVATE, pointer)
    else
        @call(.auto, curl.c.curl_easy_setopt, .{ easy.handle(), curl.c.CURLOPT_PRIVATE, pointer });
    try testing.expectEqual(@as(@TypeOf(set_result), @intCast(curl.c.CURLE_OK)), set_result);

    var returned: ?*anyopaque = null;
    const get_result = if (comptime curl.runtime_loaded)
        curl.c.curl_easy_getinfo(easy.handle(), curl.c.CURLINFO_PRIVATE, &returned)
    else
        @call(.auto, curl.c.curl_easy_getinfo, .{ easy.handle(), curl.c.CURLINFO_PRIVATE, &returned });
    try testing.expectEqual(@as(@TypeOf(get_result), @intCast(curl.c.CURLE_OK)), get_result);
    try testing.expectEqual(pointer, returned);
}

test "runtime provider contract contains only libcurl exports" {
    if (comptime !curl.runtime_loaded) return;
    try testing.expect(curl.c.symbols.len != 0);
    var unexpected = false;
    inline for (.{ curl.c.symbols, curl.c.optional_symbols }) |symbols| {
        for (symbols) |symbol| {
            if (!std.mem.startsWith(u8, symbol.name, "curl_")) {
                std.debug.print("tests.zig: unexpected runtime provider export: {s}\n", .{symbol.name});
                unexpected = true;
            }
        }
    }
    try testing.expect(!unexpected);
}

test "runtime variadic dispatch preserves multiple and empty argument tuples" {
    if (comptime !curl.runtime_loaded) return;
    try libraryReady();
    var buffer: [64]u8 = undefined;
    const text: [*:0]const u8 = "value";
    const count = curl.c.curl_msnprintf(&buffer, buffer.len, "%s:%d", .{ text, @as(c_int, 42) });
    try testing.expectEqual(@as(c_int, 8), count);
    try testing.expectEqualStrings("value:42", std.mem.span(@as([*:0]const u8, @ptrCast(&buffer))));

    const empty_count = curl.c.curl_msnprintf(&buffer, buffer.len, "literal", .{});
    try testing.expectEqual(@as(c_int, 7), empty_count);
    try testing.expectEqualStrings("literal", std.mem.span(@as([*:0]const u8, @ptrCast(&buffer))));
}

test "a loopback transfer delivers the recorded fixture, byte for byte" {
    try libraryReady();

    var fixture: FixtureServer = undefined;
    try fixture.init(testing.io, &.{
        .{ .target = "/fixture.txt", .response = .{ .body = fixture_body } },
    });
    defer fixture.deinit();

    var url_buffer: [128]u8 = undefined;
    const url = try fixture.url("/fixture.txt", &url_buffer);

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};
    try attached(&sink, &easy, url);
    try easy.perform();

    try expectDigest("body of GET /fixture.txt", sink.bytes());
    try testing.expectEqualSlices(u8, fixture_body, sink.bytes());

    try testing.expectEqual(@as(usize, 95), fixture_body.len);

    try testing.expectEqual(@as(u64, 200), try easy.responseCode());
    try testing.expectEqual(@as(u64, fixture_body.len), declaredLength(sink.headBytes()) orelse
        return error.NoDeclaredLength);
    try testing.expect(fixture.fault == null);
}

test "the write callback receives the fixture's bytes and no response head" {
    try libraryReady();

    var fixture: FixtureServer = undefined;
    try fixture.init(testing.io, &.{
        .{ .target = "/fixture.txt", .response = .{ .body = fixture_body } },
    });
    defer fixture.deinit();

    var url_buffer: [128]u8 = undefined;
    const url = try fixture.url("/fixture.txt", &url_buffer);

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};
    try attached(&sink, &easy, url);
    try easy.perform();

    try testing.expect(sink.body_len > 0);
    try testing.expectEqual(fixture_body[0], sink.bytes()[0]);
    try testing.expectEqualSlices(u8, fixture_body, sink.bytes());

    try testing.expect(sink.header_calls > 0);
    try testing.expectEqual(@as(usize, 0), sink.header_without_context);

    try testing.expectEqual(@as(usize, 1), sink.write_size);
    try testing.expect(sink.write_calls >= 1);
    try testing.expect(!sink.overflowed);

    const head = try fixture.head(0);
    try testing.expect(hasLine(head, "GET /fixture.txt HTTP/1.1"));
}

test "a body byte that is not text reaches the callback intact" {
    try libraryReady();

    var fixture: FixtureServer = undefined;
    try fixture.init(testing.io, &.{
        .{ .target = "/binary", .response = .{ .body = &binary_body } },
    });
    defer fixture.deinit();

    var url_buffer: [128]u8 = undefined;
    const url = try fixture.url("/binary", &url_buffer);

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};
    try attached(&sink, &easy, url);
    try easy.perform();

    try testing.expectEqualSlices(u8, &binary_body, sink.bytes());
    try testing.expectEqual(@as(u64, 200), try easy.responseCode());
    try testing.expectEqual(@as(u64, binary_body.len), declaredLength(sink.headBytes()) orelse
        return error.NoDeclaredLength);
}

test "a header line the caller destroys after append is still the line sent" {
    try libraryReady();

    var fixture: FixtureServer = undefined;
    try fixture.init(testing.io, &.{
        .{ .target = "/echo", .response = .{ .body = "echoed\n" } },
    });
    defer fixture.deinit();

    var url_buffer: [128]u8 = undefined;
    const url = try fixture.url("/echo", &url_buffer);

    var list = curl.SList{};
    var scratch: [64]u8 = undefined;
    const line: [:0]const u8 = "X-Fixture-Token: 8f22c0d4";
    @memcpy(scratch[0..line.len], line);
    scratch[line.len] = 0;
    try list.append(scratch[0..line.len :0]);

    @memset(scratch[0..line.len], 'X');

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};
    try attached(&sink, &easy, url);
    try easy.setHeaders(&list);
    try easy.perform();

    const head = try fixture.head(0);
    try testing.expect(hasLine(head, line));

    list.freeAll();
    try testing.expect(list.raw() == null);
    try list.append("X-After-Release: 1");
    try testing.expect(list.raw() != null);
    list.freeAll();
    list.freeAll();
    try testing.expect(list.raw() == null);

    try testing.expect(fixture.fault == null);
}

test "releasing a handle leaves the caller's header list alone" {
    try libraryReady();

    var fixture: FixtureServer = undefined;
    try fixture.init(testing.io, &.{
        .{ .target = "/echo", .response = .{ .body = "echoed\n" } },
    });
    defer fixture.deinit();

    var url_buffer: [128]u8 = undefined;
    const url = try fixture.url("/echo", &url_buffer);

    var list = curl.SList{};
    try list.append("X-Fixture-Token: 8f22c0d4");

    {
        var easy = try curl.Easy.init();
        defer easy.deinit();
        var sink = Sink{};
        try attached(&sink, &easy, url);
        try easy.setHeaders(&list);
        try easy.perform();
    }

    try testing.expect(list.raw() != null);
    list.freeAll();
    try testing.expect(list.raw() == null);

    try testing.expect(fixture.fault == null);
}

test "a getter's borrow reads back while the handle is unchanged and is the caller's not to free" {
    try libraryReady();

    var fixture: FixtureServer = undefined;
    try fixture.init(testing.io, &.{
        .{ .target = "/fixture.txt", .response = .{ .body = fixture_body } },
    });
    defer fixture.deinit();

    var first_buffer: [128]u8 = undefined;
    const first_url = try fixture.url("/fixture.txt", &first_buffer);

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};
    try attached(&sink, &easy, first_url);
    try easy.perform();

    const borrowed = (try easy.effectiveUrl()) orelse return error.NoEffectiveUrl;
    try testing.expectEqualStrings(first_url, borrowed);

    try easy.perform();
    const again = (try easy.effectiveUrl()) orelse return error.NoEffectiveUrl;
    try testing.expectEqualStrings(first_url, again);
}

test "reset returns a handle to the state a fresh one is in" {
    try libraryReady();

    var fixture: FixtureServer = undefined;
    try fixture.init(testing.io, &.{
        .{ .target = "/fixture.txt", .response = .{ .body = fixture_body } },
    });
    defer fixture.deinit();

    var url_buffer: [128]u8 = undefined;
    const url = try fixture.url("/fixture.txt", &url_buffer);

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};
    try attached(&sink, &easy, url);
    try easy.perform();
    try testing.expectEqual(@as(u64, 200), try easy.responseCode());

    easy.reset();
    var after_reset = Sink{};
    easy.setWriteFunction(&after_reset, onWrite);
    const outcome = easy.perform();
    if (outcome) |_| {
        std.debug.print("tests.zig: perform after reset succeeded with no URL\n", .{});
        return error.ResetDidNotClearTheUrl;
    } else |err| {
        std.debug.print("tests.zig: perform after reset gave {s}\n", .{@errorName(err)});
        try testing.expectEqual(@as(usize, 0), after_reset.write_calls);
    }

    try attached(&after_reset, &easy, url);
    try easy.perform();
    try testing.expectEqual(@as(u64, 200), try easy.responseCode());
    try expectDigest("body after reset", after_reset.bytes());

    try testing.expect(fixture.fault == null);
}

test "a header callback that was never set is not called" {
    try libraryReady();

    var fixture: FixtureServer = undefined;
    try fixture.init(testing.io, &.{
        .{ .target = "/fixture.txt", .response = .{ .body = fixture_body } },
    });
    defer fixture.deinit();

    var url_buffer: [128]u8 = undefined;
    const url = try fixture.url("/fixture.txt", &url_buffer);

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};

    try easy.setUrl(url);
    try easy.setTimeoutMs(10_000);
    easy.setWriteFunction(&sink, onWrite);
    easy.setHeaderFunction(&sink, null);

    try easy.perform();
    try testing.expectEqual(@as(usize, 0), sink.header_calls);
    try testing.expectEqual(@as(usize, 0), sink.head_len);
    try testing.expect(hasLine(sink.bytes(), "HTTP/1.1 200 OK"));
    const tail = sink.bytes()[sink.bytes().len - fixture_body.len ..];
    try expectDigest("body with no header callback", tail);
    try testing.expectEqualSlices(u8, fixture_body, tail);
    try testing.expect(fixture.fault == null);
}

test "a port nothing is listening on is refused, and only that" {
    try libraryReady();

    var closed = try ClosedPort.open(testing.io);
    defer closed.close(testing.io);

    var url_buffer: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buffer, "http://{s}:{d}/nothing", .{ loopback, closed.port });
    url_buffer[url.len] = 0;
    const terminated = url_buffer[0..url.len :0];

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};
    try attached(&sink, &easy, terminated);

    try testing.expectError(error.CouldntConnect, easy.perform());

    try testing.expectEqual(@as(usize, 0), sink.write_calls);
    try testing.expectEqual(@as(usize, 0), sink.header_calls);
}

test "a URL with no host is refused before a socket is opened" {
    try libraryReady();

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};
    easy.setWriteFunction(&sink, onWrite);

    try easy.setUrl("http://");

    const outcome = easy.perform();
    if (outcome) |_| {
        std.debug.print("tests.zig: perform with \"http://\" succeeded\n", .{});
        return error.MalformedUrlWasAccepted;
    } else |err| {
        std.debug.print("tests.zig: \"http://\" gave {s}\n", .{@errorName(err)});
    }

    try testing.expectEqual(@as(usize, 0), sink.write_calls);
}

test "a scheme libcurl has no handler for is refused" {
    try libraryReady();

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};
    easy.setWriteFunction(&sink, onWrite);

    try easy.setUrl("nosuchscheme://127.0.0.1/fixture");

    try testing.expectError(error.UnsupportedProtocol, easy.perform());
    try testing.expectEqual(@as(usize, 0), sink.write_calls);
}

test "a response that stops before its declared length is a partial file, and the bytes that arrived are still delivered" {
    try libraryReady();

    var fixture: FixtureServer = undefined;
    try fixture.init(testing.io, &.{
        .{
            .target = "/truncated",
            .response = .{ .body = fixture_body, .truncate_by = 32 },
        },
    });
    defer fixture.deinit();

    var url_buffer: [128]u8 = undefined;
    const url = try fixture.url("/truncated", &url_buffer);

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};
    try attached(&sink, &easy, url);

    const outcome = easy.perform();
    if (outcome) |_| {
        std.debug.print("tests.zig: a truncated response was reported as a success\n", .{});
        return error.TruncationWasNotReported;
    } else |err| {
        std.debug.print("tests.zig: truncated response gave {s}\n", .{@errorName(err)});
    }

    try expectDigest("partial body of GET /truncated", sink.bytes());
    try testing.expectEqual(@as(u64, fixture_body.len + 32), declaredLength(sink.headBytes()) orelse
        return error.NoDeclaredLength);
}

test "a write callback that returns a short count stops the transfer" {
    try libraryReady();

    var fixture: FixtureServer = undefined;
    try fixture.init(testing.io, &.{
        .{ .target = "/fixture.txt", .response = .{ .body = fixture_body } },
    });
    defer fixture.deinit();

    var url_buffer: [128]u8 = undefined;
    const url = try fixture.url("/fixture.txt", &url_buffer);

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{ .refuse_at_offered = 1 };
    try attached(&sink, &easy, url);

    try testing.expectError(error.WriteError, easy.perform());

    try testing.expectEqual(@as(usize, 1), sink.write_calls);
    try testing.expectEqual(@as(usize, 0), sink.body_len);
}

test "the message interface carries the same transfer to completion" {
    try libraryReady();

    var fixture: FixtureServer = undefined;
    try fixture.init(testing.io, &.{
        .{ .target = "/fixture.txt", .response = .{ .body = fixture_body } },
    });
    defer fixture.deinit();

    var url_buffer: [128]u8 = undefined;
    const url = try fixture.url("/fixture.txt", &url_buffer);

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};
    try attached(&sink, &easy, url);

    var multi = try curl.Multi.init();
    defer multi.deinit();
    try multi.addEasy(&easy);

    try multi.poll(10);

    var steps: usize = 0;
    var message: ?curl.Message = null;
    while (steps < 10_000) : (steps += 1) {
        switch (multi.drive(100)) {
            .done => {
                message = multi.readInfo();
                break;
            },
            .failed => |err| {
                std.debug.print("tests.zig: multi transfer failed with {s}\n", .{@errorName(err)});
                return error.MultiTransferFailed;
            },
            .running => {},
            .timed_out => {},
            .multi_failed => |why| {
                std.debug.print("tests.zig: the multi handle itself failed: {s}\n", .{@errorName(why)});
                return error.MultiHandleFailed;
            },
        }
    }
    if (steps >= 10_000) return error.MultiNeverFinished;

    const completion = message orelse return error.NoCompletionMessage;
    try testing.expect(completion.isFor(&easy));
    try testing.expectEqual(@as(?curl.PerformError, null), completion.result);

    try multi.removeEasy(&easy);

    try testing.expectEqual(@as(u64, 200), try easy.responseCode());
    try expectDigest("body of GET /fixture.txt over the multi route", sink.bytes());
    try testing.expect(fixture.fault == null);
}

test "the message interface reports a failure the way the blocking route does" {
    try libraryReady();

    var fixture: FixtureServer = undefined;
    try fixture.init(testing.io, &.{
        .{
            .target = "/truncated",
            .response = .{ .body = fixture_body, .truncate_by = 32 },
        },
    });
    defer fixture.deinit();

    var url_buffer: [128]u8 = undefined;
    const url = try fixture.url("/truncated", &url_buffer);

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};
    try attached(&sink, &easy, url);

    var multi = try curl.Multi.init();
    defer multi.deinit();
    try multi.addEasy(&easy);

    var steps: usize = 0;
    var failure: ?curl.PerformError = null;
    var completion: ?curl.Message = null;
    while (steps < 10_000) : (steps += 1) {
        switch (multi.drive(100)) {
            .done => {
                completion = multi.readInfo();
                std.debug.print(
                    "tests.zig: multi reported a truncated response as a completion (result {?})\n",
                    .{if (completion) |m| m.result else null},
                );
                return error.TruncationWasNotReported;
            },
            .failed => |err| {
                failure = err;
                completion = multi.readInfo();
                break;
            },
            .running => {},
            .timed_out => {},
            .multi_failed => |why| {
                std.debug.print("tests.zig: the multi handle itself failed: {s}\n", .{@errorName(why)});
                return error.MultiHandleFailed;
            },
        }
    }
    if (steps >= 10_000) return error.MultiNeverFinished;
    try testing.expect(failure != null);

    std.debug.print("tests.zig: multi reported {s} for a truncated response\n", .{
        @errorName(failure.?),
    });

    const message = completion orelse return error.NoCompletionMessage;
    try testing.expect(message.isFor(&easy));
    try testing.expectEqual(curl.MessageKind.done, message.kind);
    try testing.expect(message.result != null);

    try multi.removeEasy(&easy);
    try expectDigest("partial body over the multi route", sink.bytes());
}

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

test "percent-encoding follows the unreserved set the specification defines" {
    try libraryReady();

    const input = "AZaz09-._~ /?#&=[]%+:@!$'(),;\"\\*|<>{}`^\x00\xff";
    var expected_buffer: [512]u8 = undefined;
    const expected = try expectedEscape(input, &expected_buffer);

    const escaped = try curl.escape(input);
    defer curl.freeEscaped(escaped);

    try testing.expectEqualStrings(expected, escaped);

    for ("-._~") |mark| {
        try testing.expect(std.mem.indexOfScalar(u8, expected, mark) != null);
    }
    try testing.expect(std.mem.indexOf(u8, expected, "%20") != null);
    try testing.expect(std.mem.indexOf(u8, expected, "%2F") != null);
    try testing.expect(std.mem.indexOf(u8, expected, "%00") != null);
    try testing.expect(std.mem.indexOf(u8, expected, "%FF") != null);
    try testing.expect(std.mem.indexOf(u8, expected, "%ff") == null);

    const decoded = try curl.unescape(escaped);
    defer curl.freeEscaped(decoded);
    try testing.expectEqualSlices(u8, input, decoded);
}

test "percent-decoding leaves a triplet it cannot read exactly as it found it" {
    try libraryReady();

    const cases = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = "%", .expected = "%" },
        .{ .input = "%2", .expected = "%2" },
        .{ .input = "%zz", .expected = "%zz" },
        .{ .input = "%2z", .expected = "%2z" },
        .{ .input = "a%2", .expected = "a%2" },
        .{ .input = "%41", .expected = "A" },
        .{ .input = "%2f%41%73", .expected = "/As" },
        .{ .input = "%ff", .expected = "\xff" },
    };

    for (cases) |case| {
        const decoded = try curl.unescape(case.input);
        defer curl.freeEscaped(decoded);
        if (!std.mem.eql(u8, case.expected, decoded)) {
            std.debug.print("tests.zig: unescape(\"{s}\") gave \"{x}\", expected \"{x}\"\n", .{
                case.input,
                decoded,
                case.expected,
            });
            return error.MalformedTripletWasRewritten;
        }
    }
}
