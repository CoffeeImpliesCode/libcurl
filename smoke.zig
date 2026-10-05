// SPDX-License-Identifier: curl
// See FORK-LICENSE.md for what that identifier covers.

//! A runnable, deterministic demonstration of the libcurl facade.
//!
//! `zig build smoke` runs this. There is no input to supply, no host it names,
//! no clock and no random seed, so the same lines come out every time.
//!
//! ## No network at all
//!
//! The program starts its own HTTP server on `127.0.0.1` on a port the kernel
//! picks, and points libcurl at that address. The only socket in the process is
//! between it and itself: no name is resolved, no route is chosen, no byte
//! leaves the host. A machine with networking switched off produces identical
//! output.
//!
//! ## Every answer is an expected value
//!
//! Nothing below is a value this program computed and printed for comparison.
//! The body is checked against a SHA-256 taken before any library code ran, the
//! response head is checked against the shape RFC 9110 requires, and the
//! percent-encoding is checked against a string built from the character classes
//! RFC 3986 defines. A mismatch prints both sides and exits non-zero, so this is
//! a check and not a demo.
//!
//! The version line is the one exception AGENTS.md §7 allows: a smoke example
//! may print the pinned version. It is printed, never compared.
//!
//! ## What it exercises, in order
//!
//! A library initialised once, an easy handle that owns itself, the write and
//! header callbacks and what each of them is handed, `CURLINFO_RESPONSE_CODE`,
//! a borrow from `CURLINFO_EFFECTIVE_URL` and the rule about who frees it, a
//! header list the caller still owns after the handle is gone, percent-encoding
//! and percent-decoding as a pair, one refused connection, and the raw
//! translated route for the version string.

const std = @import("std");
const curl = @import("libcurl");

const Sha256 = std.crypto.hash.sha2.Sha256;

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// The provider this run should load, from `--provider <path>` or from
/// `LIBCURL_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location or falls back to
/// a linked copy: a runtime-loading build that was not told which file to load
/// reports that it was not told, rather than loading something else.
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
        "smoke: this is a runtime-loading build. Pass --provider <path>, or " ++
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
/// The same 95 bytes and the same digest as `tests.zig`. They are written out
/// twice on purpose: `tests.zig` is the test root and `smoke.zig` is a separate
/// build root, and a shared file would have to appear in `build.zig.zon`'s
/// `.paths`, which belongs to another owner. The digest is what makes the
/// duplication safe -- if the two copies ever drifted, one of the two programs
/// would fail rather than quietly check its own bytes.
const fixture_body: []const u8 =
    "libcurl loopback fixture v1\n" ++
    "X-Not-A-Header: this is body text, not a response header\n" ++
    "last line\n";

/// SHA-256 of `fixture_body`, OBSERVED from `sha256sum` over its 95 bytes
/// before any libcurl code in this package had been built or run.
const fixture_digest_hex = "c1a7c3eda96b2be6976bb9c3723f1931ca9e9cca16d64fa1f25077ec8c4db210";

const body_capacity = 64 * 1024;
const head_capacity = 4096;

/// What one transfer delivered, assembled by the facade's own callbacks.
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
    sink.header_calls += 1;
    const total = curl.chunkLength(size, nitems) orelse return 0;
    if (sink.head_len + total > head_capacity) return 0;
    @memcpy(sink.head[sink.head_len..][0..total], buffer[0..total]);
    sink.head_len += total;
    return total;
}

/// One HTTP request's worth of answer, as data rather than as behaviour.
///
/// The head itself is written by `std.http.Server`, which is what makes the
/// checks below statements about the protocol rather than about this program's
/// own spelling of it: `respond` emits the status line, a `Content-Length` that
/// matches the body, and the empty line that ends the head
/// (`std/http/Server.zig:352-386`), and it flushes. Nothing here writes an
/// `Io.Writer` by hand, so there is no path on which the last bytes of a body
/// are still sitting in a buffer when the socket closes.
const Response = struct {
    body: []const u8,
    extra_headers: []const std.http.Header = &.{},
};

/// A tiny HTTP/1.1 server on the loopback interface, answering `requests`
/// connections and then stopping.
///
/// One `std.Io.Group` member on the instance's own thread pool, which is the
/// arrangement `std/Build/WebServer.zig:147-186` uses for the same job. This is
/// a real OS thread underneath, and cancelling the group both interrupts the
/// blocked `accept` and waits for the thread to leave, so this program cannot
/// hang in teardown. `std.Thread.spawn` would leave a client that never
/// connected with `join` blocked on `accept` forever.
const FixtureServer = struct {
    io: std.Io,
    group: std.Io.Group = .init,
    listener: std.Io.net.Server,
    requests: usize,
    response: Response,
    port: u16,
    answered: usize = 0,
    fault: bool = false,

    /// Bind, take the port the kernel chose, and start answering.
    ///
    /// Takes the destination rather than returning one, because the serving
    /// thread is handed `self`. This used to be
    /// `fn start(...) !FixtureServer` with `var self: FixtureServer` local and
    /// `group.concurrent(io, serve, .{&self})`, and `return self`. That pointer
    /// was to a stack frame that ended when `start` returned, so the serving
    /// thread then read `self.listener` and `self.io` out of reclaimed stack:
    /// `General protection exception` inside `Server.accept`
    /// (`std/Io/net.zig:1443`, which dereferences `s.socket.handle`) on the
    /// first connection. Filling `self` in place gives the thread a pointer
    /// that outlives the call, which is the only thing it needs.
    fn start(self: *FixtureServer, io: std.Io, requests: usize, response: Response) !void {
        var address = try std.Io.net.IpAddress.parseIp4(loopback, 0);
        const listener = try address.listen(io, .{ .reuse_address = true });
        self.* = .{
            .io = io,
            .listener = listener,
            .requests = requests,
            .response = response,
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

        // `respond` flushes before it returns. One request per connection:
        // `connection: close` goes out (`std/http/Server.zig:359-362`) and the
        // socket closes below.
        request.respond(self.response.body, .{
            .extra_headers = self.response.extra_headers,
            .keep_alive = false,
        }) catch {
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

/// One byte's escape, derived from the character classes RFC 3986 defines.
///
/// RFC 3986 section 2.3 names ALPHA, DIGIT, `-`, `.`, `_` and `~` unreserved and
/// requires every other character to be percent-encoded. libcurl's own test is
/// `ISALNUM(x) || x=='-' || x=='.' || x=='_' || x=='~'`
/// (`lib/curl_ctype.h:45-47`), the same set written as ASCII ranges. The case of
/// the two hex digits is not the RFC's choice: libcurl writes them upper-case
/// from `Curl_udigits` (`lib/escape.c:226-227`; `lib/mprintf.c:40`).
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

    // In a runtime-loading build nothing below can run until a provider is
    // loaded, and the load is the one explicit step the contract asks for. In a
    // linked build this is a no-op at comptime and the module is already usable.
    if (comptime curl.runtime_loaded) {
        try curl.load(.{ .path = try providerRequest(init) });
    }

    try w.print("libcurl smoke\n", .{});
    // Through the raw escape hatch, so this line names the provider this build
    // reached rather than a constant compiled into this program. It is printed,
    // not compared: a version string is provenance, not behaviour, and
    // AGENTS.md §7 allows exactly this one place for it.
    try w.print("{s} provider reports: {s}\n", .{
        if (curl.runtime_loaded) "loaded" else "linked",
        curl.versionString(),
    });
    try w.flush();

    try curl.globalInit(.{});
    // No `globalCleanup` at the end: the handles below are still open when this
    // function returns, and `curl_global_cleanup` decrements a refcount
    // (`lib/easy.c:266-273`) that closing them is what balances.

    // ---- the transfer, against a server this program started ----
    // Three connections: one transfer, the refused one below dials nothing so
    // it is not counted, and the count is what proves the fixture answered
    // rather than the client giving up on a socket that was never accepted.
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

    // A header list the caller owns. Upstream copies the line at append time
    // (`curlx_strdup`, `lib/slist.c:87`) and stores only the pointer at setopt
    // time (`s->headers = slist`, `lib/setopt.c:1362`), so the list must
    // outlive the transfer and is still the caller's to release afterwards.
    // It is released explicitly after the checks below rather than in a
    // `defer`, because `defer`s run last-in-first-out and an earlier `defer`
    // would put the release *before* the handle's own teardown.
    var headers = curl.SList{};
    try headers.append("X-Smoke-Fixture: 1");
    try easy.setHeaders(&headers);

    try easy.perform();

    // The independent known answer: a digest of these bytes, taken before any
    // library code ran.
    var digest: [32]u8 = undefined;
    Sha256.hash(sink.bytes(), &digest, .{});
    var hex: [64]u8 = undefined;
    try checkString(
        w,
        "body of GET /fixture.txt (sha256)",
        try std.fmt.bufPrint(&hex, "{x}", .{digest[0..]}),
        fixture_digest_hex,
    );
    // The fixture and the digest have to cover the same bytes, or one of them
    // is checking something other than what the other says.
    try checkInt(w, "bytes the digest covers", fixture_body.len, 95);
    try checkBytes(w, "body, byte for byte", sink.bytes(), fixture_body);

    // The status line and the length are what RFC 9110 requires of the head,
    // and both are cross-checks between two things the fixture emitted: the
    // status line it wrote, and the body length it declared.
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

    // The response head went to the header callback and not to the write
    // callback, which is what makes the byte-exact body above a statement about
    // the body rather than about the whole exchange.
    try checkBool(w, "head callback ran", sink.header_calls > 0);
    try checkBool(w, "the fixture served its one request", !fixture.fault and fixture.answered == 1);

    // ---- a borrow, and the rule about who frees it ----
    // `CURLINFO_EFFECTIVE_URL` hands back a pointer into the handle's own
    // storage (`lib/getinfo.c:83-87`), and upstream says of the neighbouring
    // string info "Callers must never free it themselves"
    // (`lib/getinfo.c:124-130`). So this is read, not released -- calling
    // `curl_free` on it would be a real bug, not a style point.
    const effective = (try easy.effectiveUrl()) orelse return error.NoEffectiveUrl;
    try checkString(w, "CURLINFO_EFFECTIVE_URL", effective, url);

    // Released here, after the transfer it was set on and before the handle
    // goes away. The handle never took ownership, so this is the caller's one
    // release; a facade that freed the list on the caller's behalf would fault
    // on this line.
    headers.freeAll();
    try checkBool(w, "the caller's list is released once", headers.raw() == null);

    // ---- percent-encoding, against a value built from the RFC ----
    const input = "AZaz09-._~ /?#&[]%+:@!$'(),;\"\\*|<>{}`^\x00\xff";
    var expected_buffer: [512]u8 = undefined;
    const expected = try expectedEscape(input, &expected_buffer);

    // Owned by libcurl, so it is released with the matching free
    // (`curl_free`, `lib/escape.c:190`) rather than with any Zig allocator.
    const escaped = try curl.escape(input);
    defer curl.freeEscaped(escaped);
    try checkString(w, "escape, RFC 3986 unreserved", escaped, expected);

    const decoded = try curl.unescape(escaped);
    defer curl.freeEscaped(decoded);
    try checkBytes(w, "unescape of the escape, NUL and all", decoded, input);

    // ---- one refused connection ----
    // Bound without listening: the kernel keeps the port and answers `connect`
    // with a reset, and nothing can take the number while the socket is open.
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
        // `CURLE_COULDNT_CONNECT` (`include/curl/curl.h:529`). Printed, not
        // compared: the facade's spelling of one CURLcode is not something this
        // example should freeze, and the name is what a reader needs.
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
        // `{x}` on a byte slice is two hex digits per byte written straight to
        // the writer, so this says what the bytes are without a buffer to hold
        // a formatted copy in.
        std.debug.print("smoke: {s}: expected {x}, computed {x}\n", .{ what, expected, got });
        return error.SmokeCheckFailed;
    }
}