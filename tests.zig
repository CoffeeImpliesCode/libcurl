// SPDX-License-Identifier: curl
// See FORK-LICENSE.md for what that identifier covers.

//! Behavioural tests for the libcurl facade.
//!
//! ## Nothing in this file reaches off the machine
//!
//! There is no test here that names `example.com`, `httpbin` or any other
//! host, and there is no test that resolves a name. Every transfer goes to a
//! server this file starts itself, bound to `127.0.0.1` on a port the kernel
//! picks (`port 0`), and answered from a fixture recorded in this file. That
//! means the suite is a statement about libcurl and this facade, not about
//! whether a network exists, and it cannot turn flaky when a name server does.
//!
//! The one place the fixture server is bypassed is the connection-refused test,
//! which deliberately connects to a port where nothing is listening. That is a
//! refusal produced by the local kernel, not a remote answer.
//!
//! ## Where the answers come from
//!
//! Three kinds, and they are not interchangeable:
//!
//! * **The fixture body is a recording, pinned two ways.** `fixture_body` is a
//!   byte string committed here, and `fixture_digest_hex` is the SHA-256 of
//!   those bytes, computed once with `sha256sum` before any library code ran.
//!   Neither is produced by the code under test, so neither can agree with it.
//! * **Protocol expectations are stated, not observed.** The header callback
//!   test asserts the shape RFC 9110 requires of a response head, and the
//!   percent-encoding test derives its expectation from the character classes
//!   RFC 3986 defines, computing it in Zig rather than asking libcurl what it
//!   would have said.
//! * **A same-code round trip appears twice, and only as a supplement.** The
//!   malformed-percent-triplet test and the reset test compare libcurl's output
//!   with input libcurl was given. On their own they would prove only that the
//!   code agrees with itself; each says so in its own comment.
//!
//! curl's own `docs/` tree is not vendored in this package (the compile closure
//! does not reach it), so nothing here is cited to a curl documentation page.
//! Everything about upstream behaviour is cited to a file under `lib/` or
//! `include/`, with a line.
//!
//! ## The allocator
//!
//! libcurl allocates through `Curl_cmalloc`, which defaults to libc `malloc`
//! (`lib/easy.c:109`) and is not `std.testing.allocator`. So this allocator
//! cannot be a leak oracle for anything libcurl allocates, and no test here
//! claims it is. What a test *can* check is the ownership transition this
//! package's facade owns: that `deinit` releases the handle, that an `SList`
//! line the caller destroys after `append` does not change what goes on the
//! wire, and that a getter's borrow is the caller's to read and not to free.
//!
//! Where the facade hands back a pointer libcurl owns, the test frees it with
//! the matching `freeEscaped`, which routes to `curl_free` (`lib/escape.c:190`,
//! "For operating systems/environments that use different malloc/free systems
//! for the app and for this library, we provide a free that uses the library's
//! memory system"). Freeing those bytes with `testing.allocator` would be a
//! real bug, so no test here does it.

const std = @import("std");
const curl = @import("libcurl");
const testing = std.testing;

const Sha256 = std.crypto.hash.sha2.Sha256;

/// A shared object exporting the declarations of `zig/translate.h`, named by the
/// environment in a runtime-loading build. Nothing sets it; the driver runs
/// `zig build -Druntime=true` with it exported.
const provider_variable = "LIBCURL_TEST_PROVIDER";

/// The one address every fixture binds to. Loopback, so no packet leaves the
/// host no matter what the test does with it.
const loopback = "127.0.0.1";

/// Connections one fixture will accept before it stops. Bounded so a test that
/// makes fewer requests than expected still tears down.
const max_connections = 4;

/// Bytes of one recorded request head kept per connection.
const head_capacity = 4096;

/// Bytes of one request head kept. A `GET` with one custom header is well under
/// 200; this is generous, and `head()` reports only the bytes it kept, so a
/// longer head would show up as a shorter record rather than as a wrong one.
const recorded_head_capacity = 2048;

/// Bytes one transfer may deliver before the sink refuses more, which is what
/// makes a too-large body a checkable failure instead of a buffer overwrite.
const body_capacity = 64 * 1024;

// ---------------------------------------------------------------------------
// The fixture, and where it came from
// ---------------------------------------------------------------------------

/// The recorded body of `GET /fixture.txt`.
///
/// **Provenance.** Independently constructed for this package. The HTTP/1.1
/// response shape around it is fixed by RFC 9110; the body is not something
/// RFC 9110 defines and it is not a capture of any real host. It was chosen
/// for three properties a write-callback test can check:
///
/// * it contains a line that *looks* like a response header
///   (`X-Not-A-Header: ...`), so a body that had been contaminated by the
///   response head would be visible rather than plausible;
/// * it ends in a newline and is 95 bytes long, so a dropped or duplicated
///   trailing byte changes the length as well as the content;
/// * it has no byte above 0x7e, so the digest below is over text and the
///   separate `binary_body` fixture can carry the non-text bytes instead.
///
/// `fixture_digest_hex` below is this exact string's SHA-256. A test that
/// compared only the body with itself would prove nothing about the code under
/// test; the digest is the independent value.
const fixture_body: []const u8 =
    "libcurl loopback fixture v1\n" ++
    "X-Not-A-Header: this is body text, not a response header\n" ++
    "last line\n";

/// SHA-256 of `fixture_body`, as 64 lowercase hex characters.
///
/// **Provenance.** OBSERVED: printed by `sha256sum` over the 95 bytes of
/// `fixture_body`, in this workspace, before any libcurl code in this package
/// had been built or run. It is not quoted from a published index and there is
/// no upstream file for it; it exists so that an edit to `fixture_body` cannot
/// silently become the new expected answer.
///
/// The length it covers is `95`, and `fixture_body.len` is asserted against it,
/// so a fixture and its digest cannot drift apart unnoticed.
const fixture_digest_hex = "c1a7c3eda96b2be6976bb9c3723f1931ca9e9cca16d64fa1f25077ec8c4db210";

/// Bytes that are not text, served from `GET /binary`.
///
/// The point is the NUL and the two bytes above 0x7e: a callback that treated
/// the body as a C string would deliver one byte here, and a callback that
/// filtered anything "non-printable" would deliver four. `assert` on the
/// received slice is the whole test.
const binary_body = [_]u8{ 0x00, 0x01, 0xFF, 0xFE, 'a', 0x00, 0x41 };

/// What a route answers with, as data rather than as behaviour.
const Response = struct {
    status: std.http.Status = .ok,
    body: []const u8 = "",
    extra_headers: []const std.http.Header = &.{},
    /// Announce `body.len + truncate_by` in `content-length`, send `body`, and
    /// close the connection without the rest. This is a response that stops
    /// before its own declared length, which is what libcurl reports as
    /// `CURLE_PARTIAL_FILE` (`include/curl/curl.h:547`).
    truncate_by: u64 = 0,
};

/// A request target and the response it gets.
const Route = struct {
    target: []const u8,
    response: Response = .{},
};

// ---------------------------------------------------------------------------
// The fixture server
// ---------------------------------------------------------------------------

/// A tiny HTTP/1.1 server on the loopback interface, answering a fixed routing
/// table and recording the request head of every connection it accepts.
///
/// Concurrency is one `std.Io.Group` member on the instance's own thread pool,
/// which is the arrangement `std/Build/WebServer.zig:147-186` uses for the same
/// job. `deinit` cancels the group, which both interrupts the blocked `accept`
/// (`std/Io/Threaded.zig:12461` turns the interrupted call into
/// `error.Canceled`) and waits for the thread to leave, so a test can never
/// hang in teardown because the client made fewer requests than the fixture
/// expected.
///
/// `std.Thread.spawn` would also work and is not used here for one reason: with
/// it there is no cancellation, so a client that failed before connecting would
/// leave `join` blocked on `accept` forever. That is a gate that hangs instead
/// of a gate that reports.
const FixtureServer = struct {
    io: std.Io,
    group: std.Io.Group = .init,
    listener: std.Io.net.Server,
    routes: []const Route,
    port: u16,

    /// Raw request heads, one slot per accepted connection, in arrival order.
    /// Written only by the serving thread; read by the test only after
    /// `deinit`, which is the join. No lock is needed because there is exactly
    /// one writer and the read happens-after the join.
    recorded: [max_connections][recorded_head_capacity]u8 = undefined,
    recorded_len: [max_connections]usize = @splat(0),
    answered: usize = 0,
    fault: ?Fault = null,

    const Fault = enum {
        AcceptFailed,
        HeadUnreadable,
        ResponseUnsendable,
    };

    /// Bind, take the port the kernel chose, and start answering.
    ///
    /// Takes the destination rather than returning one. The struct carries
    /// `max_connections * recorded_head_capacity` bytes of recording space, and
    /// returning it by value would move all of them once for the return and
    /// once for the assignment at the call site; filling `self` in place moves
    /// them exactly once, and that is the only copy.
    fn init(self: *FixtureServer, io: std.Io, routes: []const Route) !void {
        var address = try std.Io.net.IpAddress.parseIp4(loopback, 0);
        const listener = try address.listen(io, .{ .reuse_address = true });
        // `Socket.address` carries the resolved port "if requested"
        // (`std/Io/net.zig:1054-1055`), and requesting it is what `port 0` is
        // for, so this is the number libcurl has to be pointed at.
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
        // Cancel and join. `group.cancel` is idempotent and returns
        // immediately when the serving thread already stopped
        // (`std/Io/Threaded.zig:2367-2373`), so this is correct whether the
        // test made every request it declared or none of them.
        self.group.cancel(self.io);
        self.listener.deinit(self.io);
        self.* = undefined;
    }

    /// The URL a client should be given for `target` on this fixture.
    fn url(self: *const FixtureServer, target: []const u8, buffer: []u8) ![:0]const u8 {
        // `[:0]` because `Easy.setUrl` measures with `strlen`
        // (`lib/setopt.c:84`). `bufPrint` reports how many bytes it wrote and
        // writes no terminator of its own, so the NUL is written here: asserting
        // one on an untouched buffer would be reading whatever was there.
        const printed = try std.fmt.bufPrint(buffer, "http://{s}:{d}{s}", .{ loopback, self.port, target });
        buffer[printed.len] = 0;
        return buffer[0..printed.len :0];
    }

    /// The recorded head of connection `index`, or `error.NoSuchConnection`.
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

    // Copy the head out before answering anything. `head_buffer` points into
    // `reader`'s buffer and the next read moves it, so a server that recorded
    // the pointer would record garbage.
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
            // One request per connection. `connection: close` goes out
            // (`std/http/Server.zig:359-362`) and the socket closes below, so
            // libcurl never sees a head it has to interpret as a second
            // response.
            .keep_alive = false,
        }) catch {
            self.fault = .ResponseUnsendable;
            return;
        };
        return;
    }

    // A `content-length` the response never reaches. `respondStreaming` writes
    // the real head, `body.writer` carries the bytes that do arrive, and the
    // connection closes with `end` never called -- which is the whole shape of
    // a truncated download.
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
    // `BodyWriter.writer`'s buffer first, then the socket: `BodyWriter.flush`
    // only flushes `http_protocol_output` (`std/http.zig:780-784`), so the
    // inner buffer has to be drained into it by hand or the body never leaves.
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

/// A loopback port nothing will ever answer on, held for the whole test.
///
/// `bind` without `listen` is what makes this deterministic. The kernel keeps
/// the number and answers `connect` with a reset, and while the socket is open
/// nothing else can take the port, so there is no window in which a test's
/// "refused" could accidentally become a real server's "accepted". Closing a
/// listener and reusing its port -- the obvious spelling -- has exactly that
/// race, and this test would be the one that lost it once a week.
///
/// It depends on the kernel refusing a connection to a bound-but-not-listening
/// socket, which is what `ECONNREFUSED` means on every platform this package
/// builds a test binary for.
const ClosedPort = struct {
    socket: std.Io.net.Socket,
    port: u16,

    fn open(io: std.Io) !ClosedPort {
        var address = try std.Io.net.IpAddress.parseIp4(loopback, 0);
        const socket = try address.bind(io, .{ .mode = .stream });
        // `bind` resolves the ephemeral port through `getsockname` before it
        // returns (`std/Io/Threaded.zig:12207`), so `socket.address` is the
        // number the client should be pointed at.
        return .{ .socket = socket, .port = socket.address.getPort() };
    }

    fn close(self: *ClosedPort, io: std.Io) void {
        self.socket.close(io);
    }
};

// ---------------------------------------------------------------------------
// The write and header callbacks
// ---------------------------------------------------------------------------

/// Everything one transfer delivered, assembled by the facade's own callbacks.
const Sink = struct {
    body: [body_capacity]u8 = undefined,
    body_len: usize = 0,
    head: [head_capacity]u8 = undefined,
    head_len: usize = 0,
    write_calls: usize = 0,
    header_calls: usize = 0,
    /// The `size` libcurl passes on a write call. Upstream passes the same
    /// value every time, and it is `sizeof(size_t)`, so a caller that read the
    /// byte count out of the wrong parameter would get a product this records
    /// as different.
    write_size: usize = 0,
    /// Bytes libcurl has offered this callback in total, including the ones it
    /// went on to refuse. Used by the refusal below, because "how many calls
    /// will this transfer make" is not a fact anyone can rely on: the body of
    /// the fixture is small enough to arrive in one chunk, and a rule keyed on
    /// the call count would then never fire.
    offered: usize = 0,
    /// When set, the write callback returns a short count as soon as this many
    /// bytes have been offered. libcurl's signal for "stop the transfer" is a
    /// return value other than `size * nitems`, and the bytes of the call it
    /// refuses are not delivered.
    refuse_at_offered: ?usize = null,
    /// Times the header callback ran with no context pointer. It must stay
    /// zero: the facade is expected to set `CURLOPT_HEADERDATA` alongside
    /// `CURLOPT_HEADERFUNCTION`, and a missing context would otherwise show up
    /// as a panic inside a callback rather than as a readable failure here.
    header_without_context: usize = 0,
    /// Set when the body did not fit, so an over-long response is a checkable
    /// outcome instead of a silently truncated comparison.
    overflowed: bool = false,

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
/// (`include/curl/curl.h:285-288`), and `lib/url.c:326` makes libc's `fwrite`
/// -- also four, userdata last -- the default by casting it to that type. The
/// byte count is therefore `size * nitems`, with `outstream` the caller's
/// context, and a five-parameter spelling would read an argument libcurl never
/// passes.
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

    // Checked before the bytes are accepted, so a refusal means nothing was
    // delivered -- which is what libcurl itself does with them.
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

/// The header sink libcurl calls for the response head. Same four-parameter
/// shape as `onWrite`, same source line.
fn onHeader(
    buffer: [*c]u8,
    size: usize,
    nitems: usize,
    outstream: ?*anyopaque,
) callconv(.c) usize {
    const sink: *Sink = @ptrCast(@alignCast(outstream orelse {
        // Counted rather than dereferenced, so a facade that forgot to set
        // `CURLOPT_HEADERDATA` is reported by the assertion below instead of
        // crashing the process.
        return nitems * size;
    }));
    sink.header_calls += 1;

    const total = curl.chunkLength(size, nitems) orelse return 0;
    if (sink.head_len + total > head_capacity) return 0;
    @memcpy(sink.head[sink.head_len..][0..total], buffer[0..total]);
    sink.head_len += total;
    return total;
}

/// A `Sink` wired to an easy handle with a ten-second cap, which is a ceiling
/// on the test and not an expectation about the network: nothing here should
/// take ten seconds.
fn attached(sink: *Sink, easy: *curl.Easy, url: [:0]const u8) !void {
    try easy.setUrl(url);
    try easy.setTimeoutMs(10_000);
    easy.setWriteFunction(sink, onWrite);
    easy.setHeaderFunction(sink, onHeader);
}

/// True when one CRLF-terminated line of `head` is exactly `line`.
fn hasLine(head: []const u8, line: []const u8) bool {
    var lines = std.mem.splitSequence(u8, head, "\r\n");
    while (lines.next()) |candidate| {
        if (std.mem.eql(u8, candidate, line)) return true;
    }
    return false;
}

/// The `content-length` the recorded response head declares, if it declares one.
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

/// Compare `bytes` with a value that was derived outside this run, and say which
/// side was wrong.
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

// ---------------------------------------------------------------------------
// Making the library usable
// ---------------------------------------------------------------------------

/// Make the native library usable, once, before a test calls the facade.
///
/// In a linked build this is a no-op at comptime. In a runtime-loading build
/// every call goes through a table that `load` fills, so this is where the one
/// explicit load happens. It is safe to call from every test: the contract
/// makes the same request idempotent and the loader keeps the handle for the
/// end of the process.
///
/// A build that was not told which file to load stops here with the variable's
/// name. A suite that quietly stopped testing because a variable was unset
/// would report success for nothing.
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

/// Initialise libcurl once per process.
///
/// `curl_easy_init` would do this itself -- `lib/easy.c:345-353` calls
/// `global_init(CURL_GLOBAL_DEFAULT, TRUE)` under `if(!initialized)` -- but
/// stating it makes the dependency explicit and makes a build that failed to
/// initialise fail here rather than inside the first transfer.
///
/// There is deliberately no matching `globalCleanup`. `curl_global_init` is
/// refcounted (`lib/easy.c:129`) and `curl_global_cleanup` decrements it
/// (`lib/easy.c:266-273`), and this process is full of handles that tests have
/// not finished with; a cleanup here would be a use-after-free. A program
/// written by a dependent calls `globalCleanup` once, at the end, after every
/// handle it opened is closed -- which is the rule the facade's doc comment
/// states, and this suite deliberately does not exercise.
fn libraryReady() !void {
    nativeReady();
    if (global_ready.load(.acquire)) return;
    curl.globalInit(.{}) catch |err| {
        std.debug.print("tests.zig: curl_global_init failed: {t}\n", .{err});
        return error.GlobalInitFailed;
    };
    global_ready.store(true, .release);
}

// ---------------------------------------------------------------------------
// The recorded transfer
// ---------------------------------------------------------------------------

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

    // The independent known answer: a digest of these bytes, taken before any
    // library code ran. Everything else here would still pass if the fixture
    // and the assertion were the same string.
    try expectDigest("body of GET /fixture.txt", sink.bytes());
    // The literal, so a failure names the byte rather than only the digest.
    try testing.expectEqualSlices(u8, fixture_body, sink.bytes());

    // The fixture and its digest must cover the same bytes. Without this a
    // one-character edit to `fixture_body` would still satisfy the digest
    // comparison's *absence* of a mismatch only by also editing the digest,
    // and nobody would notice until both had.
    try testing.expectEqual(@as(usize, 95), fixture_body.len);

    // Two things the protocol fixes and the transfer had to get right to
    // produce that body: the status class and the declared length.
    try testing.expectEqual(@as(u64, 200), try easy.responseCode());
    try testing.expectEqual(@as(u64, fixture_body.len), declaredLength(sink.headBytes()) orelse
        return error.NoDeclaredLength);
    try testing.expect(fixture.fault == null);

    // What it would still not prove: that the fixture is what some real origin
    // sends. It is this package's own recording; the point of the test is that
    // libcurl reproduced it byte for byte over a real socket.
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

    // The first byte the write callback saw is the first byte of the fixture,
    // not the 'H' of "HTTP/1.1". A body delivered with the head attached --
    // which is what `CURLOPT_HEADER` on would do -- fails here immediately and
    // legibly rather than producing a body that merely looks plausible.
    try testing.expect(sink.body_len > 0);
    try testing.expectEqual(fixture_body[0], sink.bytes()[0]);
    try testing.expectEqualSlices(u8, fixture_body, sink.bytes());

    // `CURLOPT_HEADER` was not set, so the head went only to the header
    // callback. Asserting the negative is what makes the positive meaningful.
    try testing.expect(sink.header_calls > 0);
    try testing.expectEqual(@as(usize, 0), sink.header_without_context);

    // Upstream's own call is `nwritten = wcb(buf, 1, blen, wcb_data)`
    // (`lib/cw-out.c:190`): the unit is **one byte** and `nitems` carries the
    // length. A callback that multiplied `nitems` by `len` from the wrong
    // parameter would still have produced the right bytes here, so this is a
    // check on the argument shape, and it is cheap.
    try testing.expectEqual(@as(usize, 1), sink.write_size);
    try testing.expect(sink.write_calls >= 1);
    try testing.expect(!sink.overflowed);

    // The recorded request line: a real socket carried a real request.
    const head = try fixture.head(0);
    try testing.expect(hasLine(head, "GET /fixture.txt HTTP/1.1"));

    // What it would still not prove: how libcurl chunks the body across
    // callbacks. `write_calls` is recorded but not asserted to be any number,
    // because the chunking is a performance decision upstream is free to
    // change and a test that pinned it would break on a correct release.
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

    // Every byte, in order, including the two NULs and the two above 0x7e.
    // A body length derived from a NUL scan would deliver one byte; a
    // "printable only" filter would deliver four.
    try testing.expectEqualSlices(u8, &binary_body, sink.bytes());
    try testing.expectEqual(@as(u64, 200), try easy.responseCode());
    try testing.expectEqual(@as(u64, binary_body.len), declaredLength(sink.headBytes()) orelse
        return error.NoDeclaredLength);
}

// ---------------------------------------------------------------------------
// Ownership
// ---------------------------------------------------------------------------

test "a header line the caller destroys after append is still the line sent" {
    try libraryReady();

    var fixture: FixtureServer = undefined;
    try fixture.init(testing.io, &.{
        .{ .target = "/echo", .response = .{ .body = "echoed\n" } },
    });
    defer fixture.deinit();

    var url_buffer: [128]u8 = undefined;
    const url = try fixture.url("/echo", &url_buffer);

    // Upstream copies at append time -- `curl_slist_append` is
    // `curlx_strdup(data)` (`lib/slist.c:87`) -- and does *not* copy at setopt
    // time -- `CURLOPT_HTTPHEADER` stores `s->headers = slist`
    // (`lib/setopt.c:1362`). Those are two different ownership rules, and this
    // test separates them.
    var list = curl.SList{};
    var scratch: [64]u8 = undefined;
    const line: [:0]const u8 = "X-Fixture-Token: 8f22c0d4";
    @memcpy(scratch[0..line.len], line);
    // `[:0]` needs a real NUL at `line.len`. It sits one past the bytes the
    // list is handed, so the `@memset` below -- which covers only
    // `[0..line.len]` -- cannot reach it, and the copy the list holds is still
    // destroyed underneath it.
    scratch[line.len] = 0;
    try list.append(scratch[0..line.len :0]);

    // Destroy the source. Everything the list holds now has to be its own
    // copy, because the bytes it was handed are about to be rubbish.
    @memset(scratch[0..line.len], 'X');

    // The list must still be alive here: `setopt.c:1362` stored the pointer, so
    // dropping the list before the transfer would be a use-after-free and this
    // would be testing the wrong thing. It is freed after the transfer, below,
    // which is the order the ownership rule asks for.
    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};
    try attached(&sink, &easy, url);
    try easy.setHeaders(&list);
    try easy.perform();

    // The observation is made by the other end of the socket: the fixture
    // recorded what libcurl put on the wire. A weaker version of this test --
    // comparing the list's own contents with the string it was given -- would
    // exercise `curlx_strdup`'s copy and nothing else, and would pass whether
    // or not libcurl ever sent the header at all. This one fails if the header
    // is missing, if it carries the rubbish, or if the list was borrowed.
    const head = try fixture.head(0);
    try testing.expect(hasLine(head, line));

    // And the caller's list is still theirs to release. Freeing it here, after
    // the transfer, is the documented order; the handle never took ownership
    // and must not have freed it itself.
    list.freeAll();
    // The type of the pointer is deliberately not named here: translate-c spells
    // `struct curl_slist` its own way, and a test that named it would break on a
    // translate-c change rather than on anything about ownership.
    try testing.expect(list.raw() == null);
    // The wrapper is reusable, which is what nulling the pointer buys a caller:
    // a fresh `append` starts a new list rather than reusing freed storage.
    try list.append("X-After-Release: 1");
    try testing.expect(list.raw() != null);
    list.freeAll();
    // And a second release of the same list is a no-op rather than a second
    // free.
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

    // `curl_easy_cleanup` releases the handle. It does not reach the caller's
    // list -- `lib/setopt.c:1362` stored a pointer, and nothing in the close
    // path frees `data->set.headers`. So after the handle is gone the list is
    // still a live allocation the caller owns, and freeing it here is correct
    // rather than a double free. A facade that had started freeing the list on
    // the caller's behalf would fault here, which is the point of doing it.
    try testing.expect(list.raw() != null);
    list.freeAll();
    try testing.expect(list.raw() == null);

    // The handle's own transfer still produced the answer, so releasing it
    // released one handle and not the whole library.
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

    // `CURLINFO_EFFECTIVE_URL` hands back a pointer into the handle's own
    // storage -- `lib/getinfo.c:83-87` reads `Curl_bufref_ptr(&data->state.url)`
    // -- and upstream says so about its neighbouring string info at
    // `lib/getinfo.c:124-130`: "Callers must never free it themselves". So
    // there is nothing to free here, and the value is the URL libcurl actually
    // used, which for an un-redirected transfer is the one it was given.
    const borrowed = (try easy.effectiveUrl()) orelse return error.NoEffectiveUrl;
    try testing.expectEqualStrings(first_url, borrowed);

    // Reading it again, with a transfer in between on the same handle, is the
    // borrow's whole validity window: valid while the URL is unchanged.
    try easy.perform();
    const again = (try easy.effectiveUrl()) orelse return error.NoEffectiveUrl;
    try testing.expectEqualStrings(first_url, again);

    // What is deliberately *not* done: the value is not read after `setUrl`
    // replaces it, and not after `deinit`. `lib/setopt.c:2344-2347` is where
    // the buffer's bytes are replaced, so after that call the earlier slice is
    // a pointer into storage that has moved, and reading it would be a
    // use-after-free that a passing test could not make sound. The rule is
    // stated instead of tested, because the honest test for "no longer valid"
    // does not exist in a language with no borrow checker.
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

    // `curl_easy_reset` puts the options back to their defaults, which
    // includes no URL. The observable consequence is that the next transfer
    // has nothing to fetch and says so -- and it says so with the URL error,
    // not a connection error, because nothing was dialled.
    easy.reset();
    var after_reset = Sink{};
    easy.setWriteFunction(&after_reset, onWrite);
    const outcome = easy.perform();
    if (outcome) |_| {
        std.debug.print("tests.zig: perform after reset succeeded with no URL\n", .{});
        return error.ResetDidNotClearTheUrl;
    } else |err| {
        // Reported rather than switched on: the facade's spelling of
        // `CURLE_URL_MALFORMAT` (`include/curl/curl.h:524`) is a name this
        // test does not want to hard-code if it ever changes, and a printed
        // name is a readable failure where a compile error would not be.
        std.debug.print("tests.zig: perform after reset gave {s}\n", .{@errorName(err)});
        try testing.expectEqual(@as(usize, 0), after_reset.write_calls);
    }

    // And the handle is usable again as soon as it is given a URL, which is
    // what makes `reset` a transition and not a teardown.
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

    // A null function pointer is curl's documented way back to the default for
    // `CURLOPT_HEADERFUNCTION`, which is a `CURLOPTTYPE_FUNCTIONPOINT`
    // (`include/curl/curl.h:1426-1428`). This transfer registers no header
    // sink at all, so the counter below has to stay at zero -- and nothing the
    // callback would have allocated is freed, because nothing was allocated.
    try easy.setUrl(url);
    try easy.setTimeoutMs(10_000);
    easy.setWriteFunction(&sink, onWrite);
    easy.setHeaderFunction(&sink, null);

    try easy.perform();
    try testing.expectEqual(@as(usize, 0), sink.header_calls);
    try testing.expectEqual(@as(usize, 0), sink.head_len);
    // The body still arrived, so the transfer ran and the zeros above are about
    // the header sink rather than about a transfer that never happened.
    //
    // What is in this sink is the head **and then** the body. With no header
    // function set, `cw_get_writefunc` picks `fwrite_header` when it is set and
    // otherwise falls back to `fwrite_func` (`lib/cw-out.c:159-160`), and this
    // transfer registered no header function, so the head took the write
    // callback. That is upstream's rule, not a defect in the facade, and the
    // two claims this test makes are checked against it: the head is present
    // and the body that follows it is the fixture, byte for byte, against the
    // digest taken before any library code ran.
    try testing.expect(hasLine(sink.bytes(), "HTTP/1.1 200 OK"));
    const tail = sink.bytes()[sink.bytes().len - fixture_body.len ..];
    try expectDigest("body with no header callback", tail);
    try testing.expectEqualSlices(u8, fixture_body, tail);
    try testing.expect(fixture.fault == null);
}

// ---------------------------------------------------------------------------
// Error paths
// ---------------------------------------------------------------------------

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

    // `CURLE_COULDNT_CONNECT` (`include/curl/curl.h:529`) and nothing else.
    // No fixture is running, so nothing on the machine could have answered,
    // and the taxonomy is cut at this one tag rather than at everything
    // libcurl can fail with.
    try testing.expectError(error.CouldntConnect, easy.perform());

    // A refused connection delivers no body and no head.
    try testing.expectEqual(@as(usize, 0), sink.write_calls);
    try testing.expectEqual(@as(usize, 0), sink.header_calls);
}

test "a URL with no host is refused before a socket is opened" {
    try libraryReady();

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};
    easy.setWriteFunction(&sink, onWrite);

    // `Curl_setstropt` only checks the string's length
    // (`lib/setopt.c:84-89`); the URL is parsed when the transfer starts. So
    // setting this succeeds and the failure arrives from `perform`, which is
    // the honest place to look for it.
    try easy.setUrl("http://");

    const outcome = easy.perform();
    if (outcome) |_| {
        std.debug.print("tests.zig: perform with \"http://\" succeeded\n", .{});
        return error.MalformedUrlWasAccepted;
    } else |err| {
        // Printed rather than switched on: `CURLE_URL_MALFORMAT`
        // (`include/curl/curl.h:524`) is the expected code, and a name the
        // facade does not spell this way is a readable failure rather than a
        // file that will not compile.
        std.debug.print("tests.zig: \"http://\" gave {s}\n", .{@errorName(err)});
    }

    // Nothing was fetched, so nothing was delivered: the URL was refused
    // before any socket existed.
    try testing.expectEqual(@as(usize, 0), sink.write_calls);
}

test "a scheme libcurl has no handler for is refused" {
    try libraryReady();

    var easy = try curl.Easy.init();
    defer easy.deinit();
    var sink = Sink{};
    easy.setWriteFunction(&sink, onWrite);

    // No protocol handler exists for this scheme in any build of libcurl, so
    // the refusal does not depend on which features this configuration has --
    // which is what makes it a better test than a protocol that is merely
    // disabled by default.
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
            // The fixture announces 32 bytes more than it sends.
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
        // `CURLE_PARTIAL_FILE` (`include/curl/curl.h:547`) is the expected
        // code. Printed rather than switched on, for the reason given in the
        // URL test above.
        std.debug.print("tests.zig: truncated response gave {s}\n", .{@errorName(err)});
    }

    // The part that matters more than the error: the bytes that did arrive
    // were delivered, in order, and are the fixture's. A transfer that discarded
    // the partial body and reported only the failure would leave nothing to
    // check here, and a caller relying on partial data would be broken.
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
    // Refuse as soon as any byte is offered. Keyed on bytes rather than on the
    // call count on purpose: the fixture's body is 95 bytes, small enough that
    // libcurl may deliver it in a single call, and a rule of the form "accept
    // the first call, refuse the second" would then never fire and this test
    // would report a clean transfer as a pass. Offered bytes are the one thing
    // a caller can rely on here, because a transfer that delivered a body at
    // all offered at least one.
    var sink = Sink{ .refuse_at_offered = 1 };
    try attached(&sink, &easy, url);

    // A return value other than `size * nitems` is libcurl's documented abort
    // signal, and it arrives as `CURLE_WRITE_ERROR`
    // (`include/curl/curl.h:552`).
    try testing.expectError(error.WriteError, easy.perform());

    // The callback ran, and refused on its first and only call: libcurl stops
    // at a short count, so there is no second call to wait for. Nothing was
    // accepted either -- the bytes of the call the callback refused are not
    // delivered -- so the sink is empty rather than partly filled.
    try testing.expectEqual(@as(usize, 1), sink.write_calls);
    try testing.expectEqual(@as(usize, 0), sink.body_len);
}

// ---------------------------------------------------------------------------
// The message interface
// ---------------------------------------------------------------------------

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

    // `poll` with no caller-supplied descriptors is a pure wait. Upstream's
    // `*ret` is the number of descriptors written into the *caller's*
    // `extra_fds` array (`include/curl/multi.h:185-189`), so with no array it
    // is zero on every pass no matter how busy the transfer is -- not a count
    // of descriptors ready, and not a count of descriptors libcurl watches. A
    // caller that read it as either would see `0` throughout and conclude the
    // transfer was stalled. That is why the wrapper takes no array and reports
    // no count, so the call below is a wait and nothing more.
    try multi.poll(10);

    // Drive it to completion, and read the completion message *inside* the
    // switch. `.done` means "nothing running and a DONE message was consumed"
    // -- the message is gone by the time `drive` returns, so a loop that
    // terminated on `readInfo() != null` would read a queue that `drive` had
    // already drained, and would also exit early on a transfer that is merely
    // partway through. `.running` and `.timed_out` both mean keep going.
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
            // A `CURLMcode`, which is a different enumeration from the
            // `CURLcode` a transfer ends with and is deliberately not folded
            // into `failed`. Nothing about this loop can produce it, and a
            // handle that reports one has stopped being usable.
            .multi_failed => |why| {
                std.debug.print("tests.zig: the multi handle itself failed: {s}\n", .{@errorName(why)});
                return error.MultiHandleFailed;
            },
        }
    }
    if (steps >= 10_000) return error.MultiNeverFinished;

    // The completion message names the handle this test added. This is the
    // part only the multi route can say: with several transfers on one multi
    // handle, a `.done` about a different transfer's handle would be another
    // transfer's result being handed over, and nothing else in this file would
    // notice.
    //
    // Compared with `isFor`, not with `==` on the pointers. `Message.easy` is a
    // view this module made around upstream's `CURLMsg.easy_handle`
    // (`lib/multi.c:3131-3140`), so it is not the caller's `Easy` and address
    // equality would be testing where the view was placed. `isFor` compares the
    // `CURL` both sides name, which is the claim being made.
    const completion = message orelse return error.NoCompletionMessage;
    try testing.expect(completion.isFor(&easy));
    // `CURLMSG_DONE` means the handle has completed and "`result` contains the
    // CURLcode of the transfer" (`include/curl/multi.h:91-92`). A null result
    // is `CURLE_OK` -- the successful completion -- and any other value is the
    // failure, which is why the field is optional rather than a boolean: a
    // `done: bool` would say a transfer finished without saying it worked.
    try testing.expectEqual(@as(?curl.PerformError, null), completion.result);

    try multi.removeEasy(&easy);

    // The observable outcome of the transfer, not just the loop's exit.
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

    // The same fixture the blocking route refused. The multi interface's whole
    // job is that a caller learns the outcome from the message rather than
    // from a return value, so `.failed` must be reachable, it must carry the
    // code the transfer ended with, and the message must name this handle.
    //
    // The message is read inside the switch for the same reason as in the
    // test above: `drive` consumes it.
    var steps: usize = 0;
    var failure: ?curl.PerformError = null;
    var completion: ?curl.Message = null;
    while (steps < 10_000) : (steps += 1) {
        switch (multi.drive(100)) {
            .done => {
                // A truncated response finished, and finished successfully --
                // which is the bug this test exists to catch.
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
            // A `CURLMcode`, which is a different enumeration from the
            // `CURLcode` a transfer ends with and is deliberately not folded
            // into `failed`. Nothing about this loop can produce it, and a
            // handle that reports one has stopped being usable.
            .multi_failed => |why| {
                std.debug.print("tests.zig: the multi handle itself failed: {s}\n", .{@errorName(why)});
                return error.MultiHandleFailed;
            },
        }
    }
    if (steps >= 10_000) return error.MultiNeverFinished;
    try testing.expect(failure != null);

    // The blocking route prints this code rather than switching on it, for the
    // same reason: `CURLE_PARTIAL_FILE` is the expected code and the facade's
    // spelling of it is not something this test should freeze.
    std.debug.print("tests.zig: multi reported {s} for a truncated response\n", .{
        @errorName(failure.?),
    });

    const message = completion orelse return error.NoCompletionMessage;
    // `isFor`, for the reason given in the completion test above: the view in
    // a message is this module's, and the underlying `CURL` is the claim.
    try testing.expect(message.isFor(&easy));
    try testing.expectEqual(curl.MessageKind.done, message.kind);
    // On this route the outcome is in `result`, and it is the failure rather
    // than the null that meant success in the test above.
    try testing.expect(message.result != null);

    try multi.removeEasy(&easy);
    // The partial body arrived on this route too, so the failure is reported
    // *and* the data is delivered -- the same two facts the blocking test
    // checks, on the other route.
    try expectDigest("partial body over the multi route", sink.bytes());
}

// ---------------------------------------------------------------------------
// The format invariant
// ---------------------------------------------------------------------------

/// One byte's escape, derived from the character classes RFC 3986 defines
/// rather than from anything libcurl said.
///
/// RFC 3986 section 2.3 calls ALPHA, DIGIT, `-`, `.`, `_` and `~` unreserved
/// and requires every other character to be percent-encoded; libcurl's own
/// test for "unreserved" is `ISALNUM(x) || x=='-' || x=='.' || x=='_' ||
/// x=='~'` (`lib/curl_ctype.h:45-47`), which is the same set written as ASCII
/// ranges. The one thing the RFC does not fix is the case of the two hex
/// digits, and libcurl writes them upper-case from `Curl_udigits`
/// (`lib/escape.c:226-227`, and `lib/mprintf.c:40`, `"0123456789ABCDEF"`), so
/// the expectation below is built from the RFC for *which* bytes are encoded
/// and from the source for *how* they are written.
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

    // One byte from every class the distinction turns on, plus a NUL and a
    // high byte, which are not text at all and must not be dropped.
    const input = "AZaz09-._~ /?#&=[]%+:@!$'(),;\"\\*|<>{}`^\x00\xff";
    var expected_buffer: [512]u8 = undefined;
    const expected = try expectedEscape(input, &expected_buffer);

    // The known answer, built from the RFC above. Not from libcurl: if this
    // derived its expectation by escaping with libcurl and comparing, it would
    // only prove that libcurl agrees with itself.
    const escaped = try curl.escape(input);
    defer curl.freeEscaped(escaped);

    try testing.expectEqualStrings(expected, escaped);

    // Spot checks that name what is at stake, so a reader does not have to count
    // characters. The five marks RFC 3986 lists as unreserved after ALPHA and
    // DIGIT pass through; a space and a slash do not; a NUL becomes three
    // characters rather than ending the string; and the hex digits are
    // upper-case, which is libcurl's choice from `Curl_udigits`
    // (`lib/escape.c:226-227`) and not the RFC's.
    for ("-._~") |mark| {
        try testing.expect(std.mem.indexOfScalar(u8, expected, mark) != null);
    }
    try testing.expect(std.mem.indexOf(u8, expected, "%20") != null);
    try testing.expect(std.mem.indexOf(u8, expected, "%2F") != null);
    try testing.expect(std.mem.indexOf(u8, expected, "%00") != null);
    try testing.expect(std.mem.indexOf(u8, expected, "%FF") != null);
    try testing.expect(std.mem.indexOf(u8, expected, "%ff") == null);

    // The pair is also a round trip, and the round trip is the *supplement*
    // here, not the proof.
    //
    // It does carry one hard requirement on `unescape`: the input ends in a NUL
    // and the result has to be `input.len` bytes. `curl_easy_unescape` is given
    // an `int *outlength` (`include/curl/curl.h:2747-2750`) for exactly this --
    // the returned buffer is NUL-terminated (`lib/escape.c:147`) *and* its true
    // length is reported separately, so a decoded NUL does not shorten it. A
    // `unescape` that derived its length with `strlen` would hand back two
    // bytes fewer than it should, and this line is where that shows.
    const decoded = try curl.unescape(escaped);
    defer curl.freeEscaped(decoded);
    try testing.expectEqualSlices(u8, input, decoded);

    // What it would still not prove: that libcurl's escaping is right for a URL
    // libcurl will actually fetch. This is the encoding function on its own.
}

test "percent-decoding leaves a triplet it cannot read exactly as it found it" {
    try libraryReady();

    // `Curl_urldecode` consumes a triplet only when a `%` is followed by two
    // hex digits and at least one byte follows them
    // (`lib/escape.c:126-133`), and it rejects nothing else -- `REJECT_NADA`
    // accepts every byte, including a decoded NUL (`lib/escape.c:139-143`).
    // So each of these decodes to itself, one for one.
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
        // Lower-case hex decodes the same as upper-case: `ISXDIGIT`
        // (`lib/curl_ctype.h:37`) accepts both, and `%2f` above is the case
        // that distinguishes an encoder from a decoder.
        if (!std.mem.eql(u8, case.expected, decoded)) {
            std.debug.print("tests.zig: unescape(\"{s}\") gave \"{x}\", expected \"{x}\"\n", .{
                case.input,
                decoded,
                case.expected,
            });
            return error.MalformedTripletWasRewritten;
        }
    }

    // A same-code supplement, and honest about it: these expectations come
    // from reading `lib/escape.c`, and every one of them is also something a
    // decoder could get wrong in the direction of being more permissive -- it
    // would have to invent a byte for `%zz`. The independent answer in this
    // file is the escape test above, which builds its expectation from the RFC
    // instead of from the source.
}