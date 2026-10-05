# The Zig interface

How the libcurl 8.22.0 SDK is consumed from Zig: the typed surface published by
`zig/root.zig`, the raw translated C route, the runtime-loading route, the
ownership rules and the ABI a loaded provider has to satisfy.

`zig/root.zig` is the authority on this page. Where the two differ, the file is
right and this document is out of date.

For provenance, licensing and the build matrix see [`README.md`](README.md);
for the source-level evidence behind the ABI statements see
[`FORK-NOTES.md`](FORK-NOTES.md).

**Status: nothing here has been run.** No gate has been observed for this
package. What follows describes `zig/root.zig` as it stands; it is not a
receipt, and there is no test count to quote.

## The routes

```zig
const libcurl = @import("libcurl");   // dep.module("libcurl")
const c = libcurl.c;                  // pub const c = @import("translate")
```

| Route | How you get it | What you get |
|---|---|---|
| Linked (default) | `zig build`, then `dep.module("libcurl")` | the typed facade plus the linked `libcurl`; every call is a direct call |
| Runtime-loaded | `zig build -Druntime=true` | the same types and the same public surface, resolved through the platform loader by an explicit `load(source)`; the facade module links no archive |
| Installed C | `zig build install`, then `-I<prefix>/include -lcurl` | upstream's twelve installed headers and the library, for a C consumer |

There is **no system route**. `build.zig` has no `-Dsystem` option, so there is
nothing that binds to an already-installed `libcurl` and nothing that could be
mistaken for one. Every route above builds this repository's own source.

`c` is re-exported **on the `libcurl` module**, not published as a module of
its own: registering it separately would hand a dependent the declarations
without the library that satisfies them.

### `pub const c` is the escape hatch

**Say it plainly: `pub const c` is the escape hatch for everything this facade
does not name.** It is the translation of `zig/translate.h`, which includes
`<curl/curl.h>` and no macro of its own — and `<curl/curl.h>` opens the rest of
the public surface itself, for the reason upstream states at
`include/curl/curl.h:3339-3340`. Importing the facade is all a dependent needs
to reach it.

That surface is exactly **100 functions**, which is the number a provider has
to satisfy:

* 46 in `include/curl/curl.h` — the mime family (12), the deprecated form family
  (3), escape (5), global init and teardown (5), slist (2), share (4), the
  deprecated getenv (1), getdate (1), the strerror family (3), version (2),
  strequal/strnequal (2), the easy header/pause/ssls entry points (4) and more;
* 10 in `include/curl/easy.h:41-117`;
* 24 in `include/curl/multi.h:126-553`;
* 3 in `include/curl/options.h:59-65`;
* 2 in `include/curl/header.h:58,65`;
* 6 in `include/curl/urlapi.h:114-150`;
* 11 in `include/curl/mprintf.h:56-76`, of which nine are variadic;
* 4 in `include/curl/websockets.h:55-92`.

It also carries everything in the header's *own* closure that is not curl's —
`<stdio.h>`, `<limits.h>`, `<sys/types.h>`, `<time.h>`, `<sys/socket.h>`,
`<sys/time.h>`, and on Windows `<winsock2.h>` and `<ws2tcpip.h>`, which reaches
the entire Win32 SDK. Those are the C library's symbols, not the provider's: a
`libcurl.so` does not export `printf`, and asking a provider for one would either
fail the load outright or resolve it out of the C library the provider depends
on. The runtime dispatch classifies them as noise and keeps the declarations
direct.

In a runtime-loaded build `c` is a **generated dispatch** rather than the
translation step's own output. It publishes the same namespace, so
`c.CURL` is the same nominal type either way and nothing needs a cast.

## The allocator crossing, stated once

**Every pointer this module returns is owned by libcurl's own allocator, not by
Zig.** libcurl allocates through the `Curl_cmalloc` family of function pointers
(`lib/easy.c:109-113` sets exactly `malloc`, `free`, `realloc` and `calloc`;
`lib/easy.c:243-247` is the only place they change, through
`curl_global_init_mem`, which this module does not wrap).

Three consequences, each stated again where it applies:

* **`std.mem.Allocator` is not what these pointers belong to.** `escape` and
  `unescape` return `Curl_cmalloc`-family memory. Handing it to a Zig
  allocator's `free` — including `std.testing.allocator` — is a *mismatched*
  free, not a leak. `freeEscaped` exists because of it.
* **No leak oracle is available, and none is claimed.** A Zig test allocator
  detects a leak of memory *it* handed out, because it holds a record of its own
  outstanding blocks. It cannot detect a leak of memory libcurl owns: the block
  was never its. **Nothing in this package asserts that it leaks nothing,
  because no test in this package can observe that claim.**
* **The allocator can be replaced under you.** A program that reaches
  `curl_global_init_mem` through `pub const c` can point libcurl's allocator
  somewhere else entirely, and `escape`'s bytes would then come from there.
  `freeEscaped` still routes to `curl_free`, which is why it is the only correct
  release.

`Easy.deinit` calls `curl_easy_cleanup`, which closes the handle and releases
everything the handle owns (`lib/easy.c:855-867`). That is the whole answer this
module can give about memory, and it is not the same answer as "the program
leaked nothing".

## Global initialization is not optional

`curl_global_init` is refcounted: `lib/easy.c:129` is `if(initialized++) return
CURLE_OK`, so a second call returns success without doing the work again but
still increments a counter that only `curl_global_cleanup` decrements. Every
successful `globalInit` needs its own `globalCleanup`, and one surplus cleanup
is silently ignored rather than reported.

```zig
try libcurl.globalInit(libcurl.InitFlags.default_flags);
defer libcurl.globalCleanup();
```

* **`globalCleanup` must not run while any `Easy` or `Multi` is still open.** The
  count does not know about handles, so it will happily unwind the library out
  from under one. Close every handle first.
* **A working program is not evidence that this was called.** `curl_easy_init`
  initializes the library itself when a caller has not
  (`lib/easy.c:345-353`), so a program that never calls either performs
  transfers perfectly well. A test that transfers a body and passes has proved
  only that the implicit path works.
* `globalInit` reports exactly one error, `GlobalInitFailed`, because
  `curl_global_init` reports exactly one code: `CURLE_FAILED_INIT`, and nothing
  else (`lib/easy.c:195-197`). That is upstream's condition, not a Zig one, so it
  gets one tag rather than a per-subsystem taxonomy this code cannot distinguish.

`InitFlags` is a `packed struct` of three booleans — `Win32`, `Ssl`,
`AckIntr` — every one defaulting to `false`, so `.{ .{} }` and a partial literal
are both valid. `InitFlags.default_flags` is what `CURL_GLOBAL_ALL` sets, and
`InitFlags.nothing` is `CURL_GLOBAL_NOTHING`. `toBits` builds the mask from
upstream's own `CURL_GLOBAL_*` constants rather than from numbers written here.

## Errors

Every error set is cut at what this code actually checked, and every tag is a
real upstream value.

| Set | Members | Where it comes from |
|---|---|---|
| `InitError` | `OutOfMemory` | the single null both `curl_easy_init` and `curl_multi_init` return. Upstream's comment is "If anything goes wrong, NULL is returned" (`curl.h:335`); the other route to that null is a global-init failure, so this is upstream's catch-all for "the handle could not be created", not a claim that `malloc` failed |
| `OptionError` | `UnknownOption`, `OutOfMemory`, `BadFunctionArgument`, `NotBuiltIn`, `OptionNotAllowedInThisBuild` | exactly the code set of `curl_easy_setopt`, read out of `lib/setopt.c`. There is no tag for `CURLE_INTERFACE_FAILED`, which the connect phase produces and a setopt call never does |
| `InfoError` | `UnknownInfo` | `curl_easy_getinfo` on a live handle answers `CURLE_OK` or `CURLE_UNKNOWN_OPTION`; every non-OK path this facade can reach is a `default:` arm that returns the latter |
| `PerformError` | 39 named `CURLE_*` values plus `Unknown` | a shared vocabulary over the whole `CURLcode` enum rather than a per-call list, which is why it is wider than any single transfer can reach. `Unknown` is the one tag that is not a code: the enum is append-only across releases |
| `MultiError` | `CallAgain`, `BadHandle`, `BadEasyHandle`, `OutOfMemory`, `InternalError`, `BadSocket`, `UnknownOption`, `AddedAlready`, `RecursiveApiCall`, `WakeupFailure`, `BadFunctionArgument`, `AbortedByCallback`, `UnrecoverablePoll` | every `CURLMcode` from `include/curl/multi.h:59-78`. `CallAgain` is not a failure; it is upstream's "keep driving the handle" |
| `EscapeError` | `Failed` | one tag, and the reason is upstream's: `curl_easy_escape` and `curl_easy_unescape` return the same null for a refused length, an input over `SIZE_MAX / 16`, a failed allocation, and a result too long for the `int` out-parameter (`lib/escape.c:57,63-64,74-83,171-182`). The API does not distinguish them and neither does this module |
| `LoadError` | `EmptySource`, `SourceTooLong`, `InvalidSource`, `UnsupportedTarget`, `OpenFailed`, `MissingSymbol`, `ValidationFailed`, `ProviderMismatch`, `ReentrantLoad` | see "Two configurations" below |

Two mappings are public because a caller holding a raw `CURLcode` from `pub const
c` needs them: `performErrorFrom(code) ?PerformError` turns a code into the tag
this module would return, and `strError(code)` is `curl_easy_strerror` as a
borrowed slice.

**`PerformError` and `MultiError` are kept apart on purpose.** One is a
*transfer* outcome and the other is a *multi handle* outcome, and collapsing them
would invent a mapping between `CURLMcode` and `CURLcode` that upstream does not
define — a `CURLM_BAD_SOCKET` has no `CURLcode` spelling at all.

## `Easy`

`Easy` owns one `CURL`. `init()` creates one through `curl_easy_init`, and
`deinit()` closes **that one** through the same route — the same provider in a
runtime-loaded build — and then stores `undefined` into the field, so the
wrapper is unusable afterwards. There is deliberately no third state to test
and no `isOpen` to mislead a caller who asks after the fact; `handle()` stops
the program with a message saying exactly what happened.

Zig cannot make a struct non-copyable, so the remaining rule is the usual one:
copy an `Easy` before `deinit` and you have two owners of one handle.

| Method | Upstream | Note |
|---|---|---|
| `init()` | `curl_easy_init` | one null, one error |
| `deinit()` | `curl_easy_cleanup` | stores `undefined`; a second call is a no-op rather than a second cleanup |
| `handle()` | the raw `*CURL` | panics with a named message after `deinit` |
| `setUrl(url)` | `CURLOPT_URL` | takes `[:0]const u8`. Upstream measures with `strlen` (`lib/setopt.c:84`), so the terminator is required, and the type says so rather than a comment. Build one with `bufPrint(&buf, ...) ` then `buf[0..n :0]` |
| `setWriteFunction(ctx, f)` | `CURLOPT_WRITEFUNCTION` + `CURLOPT_WRITEDATA` | `ctx` is the **context pointer**, first, because that is how a caller reads it; libcurl delivers it **last**, because that is the C signature. Nothing reorders them |
| `setHeaderFunction(ctx, f)` | `CURLOPT_HEADERFUNCTION` | `null` clears the option, which upstream treats as a no-op rather than an error |
| `setTimeoutMs(ms)` | `CURLOPT_TIMEOUT_MS` | the whole transfer, not the connect phase alone |
| `setFollowLocation(on)` | `CURLOPT_FOLLOWLOCATION` | cannot fail: the dispatch table for it has no error arm (`lib/setopt.c:363-763`) |
| `setVerbose(on)` | `CURLOPT_VERBOSE` | same |
| `setHeaders(list)` | `CURLOPT_HTTPHEADER` | takes `?*SList`; null clears the option |
| `perform()` | `curl_easy_perform` | the blocking route |
| `responseCode()` | `CURLINFO_RESPONSE_CODE` | as `u64`; a negative upstream value stops the program rather than being read as an enormous status |
| `headerSize()` | `CURLINFO_HEADER_SIZE` | as `u64`, same guard |
| `effectiveUrl()` | `CURLINFO_EFFECTIVE_URL` | `?[]const u8`. A **borrow** from the handle, valid until the handle changes. It is never null, and nothing here frees it |
| `reset()` | `curl_easy_reset` | returns the handle to the state a fresh one is in |

**`deinit` releases the handle, not the caller's header list.** `SList` is
separate and stays the caller's; that is an ownership transition the test suite
checks rather than a claim.

`effectiveUrl` is the deliberate contrast with `Message.easy`: one is a string
the library owns until the handle changes, the other is a view of a handle the
caller owns. Neither has a `deinit`.

## `Multi`, and why the loop cannot be written wrong

`Multi` owns one `CURLM`. It does **not** own the easy handles added to it:
upstream says `curl_multi_cleanup` "does not free or touch any individual easy
handles in any way" (`include/curl/multi.h:222-223`). Close them yourself.

| Method | Upstream | Note |
|---|---|---|
| `init()` / `deinit()` / `handle()` | `curl_multi_init` / `_cleanup` / the raw `*CURLM` | same lifecycle shape as `Easy` |
| `addEasy(easy)` | `curl_multi_add_handle` | |
| `removeEasy(easy)` | `curl_multi_remove_handle` | has to happen before `readInfo` reaches its end |
| `perform()` | `curl_multi_perform` | returns `running_handles` |
| `poll(timeout_ms)` | `curl_multi_poll` | the descriptor count upstream writes through its out-parameter is read and dropped; the variable is a real destination rather than a null |
| `socketAction(fd, ev)` | `curl_multi_socket_action` | for a caller that owns its own event loop |
| `readInfo()` | `curl_multi_info_read` | the separate route to the message queue. It returns the message the last `drive` pass removed **before** asking libcurl again — `drive` has to remove a message to learn its `CURLcode`, and a caller that could not read it back could never learn *which* handle finished |
| `drive(timeout_ms)` | `curl_multi_poll` + `curl_multi_socket_all` + `_info_read` | one pass of the whole cycle. **`curl_multi_socket_all`, not `curl_multi_socket_action(CURL_SOCKET_BAD, 0)`**: `CURL_SOCKET_TIMEOUT` is `#define`d to `CURL_SOCKET_BAD` (`multi.h:288`) but `multi_socket` branches on the former alone (`lib/multi.c:3279`), so the `BAD` spelling reaches `Curl_multi_ev_dirty_xfers` (`:3288`) and dirties *nothing* (`lib/multi_ev.c:589-591`) — enough to start a transfer, never enough to finish one |

`drive` returns a **union, not a `bool`**, and that is the point:

| Arm | Meaning |
|---|---|
| `running: i32` | transfers are still going; this is how many. Call again |
| `done` | a transfer finished successfully, **or nothing was transferring at all**. `running_handles` counts transfers that are *running*, not transfers that were *added* — upstream keeps the two apart in its own counters (`multi.h:468-472`) — so a handle queued waiting for a connection is not counted here |
| `failed: PerformError` | a transfer finished and failed |
| `multi_failed: MultiError` | the multi handle itself failed. This is a `CURLMcode`, not a `CURLcode` |
| `timed_out` | the wait genuinely expired. Calling `drive` again is the only way forward, and it is how a caller notices a stalled transfer rather than spinning on it |

A loop cannot be written wrong against that: every outcome has its own arm, and
the ones that mean "keep going" cannot be confused with the ones that mean
"stop".

### `Message` — borrowed, deliberately

`readInfo()` returns `?Message` with four members: `easy: *Easy` (borrowed),
`kind: MessageKind`, `result: ?PerformError` and `isFor`.

* **`easy` is a view this call created, not the `*Easy` the caller added.** The
  two pointers are different even when they name the same handle, so pointer
  equality is the wrong test. `message.isFor(yourEasy)` compares what both sides
  mean.
* **Never `deinit` it.** It has no `deinit` and must never be given one;
  closing it would be a second `curl_easy_cleanup` on a handle the caller already
  owns.
* **`result` is optional because `CURLE_OK` is a real value an error set cannot
  hold** — the enumeration's first member is `CURLE_OK = 0`. The optional is
  where success lives, and it must not be "simplified" away. Null means
  `CURLE_OK` and nothing else.

## `SList`

`SList` owns one `curl_slist` chain. `init()` returns an empty one, `append(line)`
takes a `[:0]const u8` for the same reason `setUrl` does — upstream copies
`strlen(line)` bytes (`lib/slist.c:87`), so an interior NUL would truncate the
header silently — and adds a copy of `line` (`lib/setopt.c:1358-1363` is upstream copying it, which is
why the caller may destroy its buffer afterwards), `freeAll()` releases the
chain, and `raw()` hands out the upstream pointer for `setHeaders`.

`append` reports one failure, `error.OutOfMemory`, because `curl_slist_append`
has exactly one failure return. `freeAll` on an empty or already-freed list is a
no-op: it stores null first, so a second call is not a second free.

## Percent-encoding: `escape`, `unescape`, `freeEscaped`

These need one rule each, and **they are not the same rule**.

`escape(s)` is `curl_easy_escape` with a null handle, which is what upstream's
own `curl_escape` passes; the handle has been ignored since 7.82.0. Upstream
copies the bytes it is given, so `s` need not outlive the call. **Its length
comes from the NUL terminator**, which is a right rule for it: the writer stores
a terminator past the last byte (`lib/curlx/dynbuf.c:117`) and an empty input
gets a buffer of its own (`lib/escape.c:60-61`).

`unescape(s)` is `curl_easy_unescape`, and **its length comes from upstream, never
from a NUL scan**. `Curl_urldecode` NUL-terminates its buffer *and* writes the
decoded length separately (`lib/escape.c:147`, `:149-151`), and those two are
genuinely different numbers: the decoder runs with `REJECT_NADA`, so a
percent-encoded `%00` decodes to an embedded NUL and the terminator then sits in
the *middle* of the value. That is why `curl_easy_unescape` has an
`int *outlength` parameter at all, and why this hands it a real out-parameter
rather than null. **Deriving the length by scanning for the NUL would silently
truncate a value that legitimately contains one**, with no error to show for it.

Only `%` followed by two hex digits is decoded (`lib/escape.c:129-136`); a `%`
that is not followed by two hex digits is kept as three literal bytes. Nothing
is rejected, so a NUL or control byte in the *input* passes through.

**Both results are libcurl allocations and both go back with `freeEscaped`**,
which routes to `curl_free` (`include/curl/curl.h:2764`). `unescape`'s slice is
a prefix of the buffer, so pass it to `freeEscaped` **unchanged** — a sub-slice
changes the pointer that frees, and there is no way for that function to notice.

## Version and identity

| Name | What it is |
|---|---|
| `version` | `LIBCURL_VERSION` as the **headers** have it, `include/curl/curlver.h:35` |
| `version_num` | `LIBCURL_VERSION_NUM`, `:60` — major in the top byte, minor in the middle, patch in the low one, so `0x081600` for 8.22.0 |
| `version_parts` | `.major`, `.minor`, `.patch` separately, `:39-41` |
| `copyright` | `LIBCURL_COPYRIGHT`, `:31` |
| `timestamp` | `LIBCURL_TIMESTAMP`, `:71` — the build date string in the release tarball. It is **not** a source date |
| `versionString()` | what the loaded library reports, from `curl_version()` |
| `versionInfo()` | the whole `curl_version_info_data`: `version`, `version_num`, `host`, `ssl_version`, `features` |

The first five are **compile-time facts from the translated header**. The last
two are **runtime facts from the library that was actually reached**, and under
a runtime-loaded build the two may differ — which is the point of asking.

`versionInfo()` allocates nothing and frees nothing. Every field is borrowed from
one static `curl_version_info_data` that upstream documents as "a static copy of
the version info struct" (`curl.h:3245`) and implements as the address of one
file-scope object (`lib/version.c:541`, `:680`), so every field stays valid for
the life of the process.

`ssl_version` is optional and **null is a real answer, not a failure**: the
static initialiser leaves it null (`lib/version.c:547`) and only `USE_SSL` fills
it. `features` is upstream's own `int`, so `c_int` and not a wider type;
`CURL_VERSION_SSL` (`:3205`) says whether TLS options are present at all and
`CURL_VERSION_THREADSAFE` (`:3238`) says whether one `Easy` may be shared across
threads.

The option introspection is here too, and it is the only way to reach the
options this facade does not name: `optionByName(name)`, `optionById(id)` and
`optionNext(prev)` walk `curl_easyoption` records, each answering a **borrowed,
static** pointer or null.

## The C variadics

Three entry points this module calls are real C variadics: `curl_easy_setopt`
and `curl_easy_getinfo` (`include/curl/easy.h:42`, `:59`) and
`curl_multi_setopt` (`include/curl/multi.h:438`). The two the facade uses take
exactly one trailing argument, the third parameter of each.

The linked configuration's translation declares them as C variadics, so they are
called through `@call(.auto, ...)` with the trailing value promoted. The
runtime-loaded dispatch keeps their arity and takes the trailing value as one
final argument of its own. **Every call to one of them is a comptime branch on
`runtime_loaded`**, so a build resolves only the route it has and a reader of one
route is reading the one that will run.

## Threads and callbacks

An `Easy` belongs to one thread at a time unless libcurl's own thread-safety
build option says otherwise, which `versionInfo().features` reports. A `Multi`
belongs to the thread that drives it, except that `curl_multi_wakeup` is the one
multi call upstream documents as callable from another thread (`lib/multi.c:1697`).
Nothing else in this module holds shared state except the loader's own table,
which the loader core synchronises.

`WriteCallback` and `HeaderCallback` are both upstream's `curl_write_callback`
shape — there is no separate header-callback typedef upstream,
`CURLOPT_HEADERFUNCTION` reuses the same one (`curl.h:1428`) — so `HeaderCallback`
is the same function type under a second name rather than a distinct one. libcurl
has one write-callback signature, used for the body and for the headers.

Three things about it that are the ABI rather than a choice here:

* **Four parameters, user data last.** `buffer` is `[ *c]u8` rather than a slice
  and is mutable, because upstream's first parameter is `char *`. Upstream's own
  default is libc's `fwrite` cast into this type (`lib/url.c:326`) — four
  arguments, user data last.
* **`size` is the unit and `nitems` is how many of them**, so the byte count is
  `size * nitems` — not the pair read the other way round. Upstream always passes
  `sizeof(size_t)` as the unit, so in practice `size * nitems == nitems`; the
  product is still the documented contract. `chunkLength(len, nmemb) ?usize` forms
  it with the overflow check, which is why that helper exists.
* **The return value is a control code, not an error.** A count equal to
  `size * nitems` means the bytes were taken; a shorter count is upstream's "abort
  the transfer" signal and the transfer ends with `CURLE_ABORTED_BY_CALLBACK`
  (`curl.h:571`), *not* `CURLE_WRITE_ERROR`; `CURL_WRITEFUNC_PAUSE` (`curl.h:279`)
  pauses and `curl_easy_pause` (`curl.h:3281`) resumes, and it is a sentinel
  rather than a count; `CURL_WRITEFUNC_ERROR` is the full-width `0xFFFFFFFF`.

**A callback is not a Zig error boundary.** Returning a short count is curl's
signal, not a Zig error.

## Two configurations: linked and runtime-loaded

`runtime_loaded` is a **comptime constant**, so a consumer can write two code
paths and have only the one it chose analyzed.

*Linked* is the default: the C library is linked, `c` is the translation of
`zig/translate.h`, and every call is direct with no table and no check.

*Runtime-loaded* is opt-in (`-Druntime`). The library is not linked; `c` is a
dispatch generated from the same translation step's output, and every selected
native function is resolved through the platform loader after:

```zig
try libcurl.load(.{ .path = "/usr/lib/libcurl.so.4" });   // an absolute path
try libcurl.load(.{ .system = "libcurl.so.4" });         // the soname
```

Before that, a call into the module stops the program with a message naming the
function, in every optimization mode. That is a programming error rather than a
recoverable condition: the table does not exist yet and there is no partial state
to fall back on, and `std.debug.assert` would be stripped in `ReleaseFast` and
so is the wrong thing for it.

The provider is reached, never guessed. `.path` names a file, `.system` names a
library for the platform loader, and **neither falls back to the other**. A
relative path is `InvalidSource`, never a search. `unload` exists and is
explicit; there is no implicit teardown at any other point. `loadedSource()`
answers the request that succeeded, or null.

`load` can decline in nine ways, all named in `LoadError`: `EmptySource`,
`SourceTooLong`, `InvalidSource`, `UnsupportedTarget`, `OpenFailed`,
`MissingSymbol`, `ValidationFailed`, `ProviderMismatch`, `ReentrantLoad`. A
failed attempt publishes nothing and can be retried explicitly by calling `load`
again; a second call with the same request succeeds and changes nothing; a
different request after a success is `ProviderMismatch` and the library already
in use stays in use.

In a **linked** build there is no provider and nothing to load, so `load` stops
the program with a message saying exactly that — rather than quietly succeeding
and leaving a caller to think it had selected a provider.

### The ABI boundary a provider must satisfy

Resolving the symbols is the boundary. It is **not** proof that a provider is
compatible, and `runtime/library.zig` does not pretend to add more than it
checks.

`provider_optional` and `provider_excluded` are both **empty**, and that took
checking rather than assuming. curl is the first SDK in this workspace whose
public surface is partly behind `CURL_DISABLE_*` build macros, so the obvious
classification would be "optional" — and that would be wrong. For every family
that *is* feature-gated in the C sources, the `#else` branch still defines the
symbol: the four `curl_ws_*` at `lib/ws.c:2027-2071`, `curl_easy_header` and
`curl_easy_nextheader` at `lib/headers.c:396-425`, the three
`curl_easy_option_*` at `lib/easygetopt.c:78-97`, the twelve `curl_mime_*` at
`lib/mime.c:2179-2282`, `curl_formadd`/`curl_formget`/`curl_formfree` at
`lib/formdata.c:842-864`, and `curl_pushheader_bynum`/`_byname` at
`lib/http2.c:2981-2997`. Upstream's own Windows export list `lib/libcurl.def`
is the same 100 names with nothing on either side the other lacks, in every
configuration. `curl_pushheader_bynum` is the case that makes the point: it
cannot be defined here, because there is no second dependency — and routing it as
required would make this package's own shared object fail this package's own
load.

Below those 100 there are five things the boundary actually turns on:

* **`curl_off_t` is a 64-bit signed type by upstream's own rule**
  (`include/curl/system.h:36-43`), and it appears in `CURLOPT_*` and `CURLINFO_*`
  argument positions through the variadic `curl_easy_setopt` and in
  `curl_multi_waitfds`. A provider built where that typedef resolved differently
  passes a different width through the same symbol name.
* **`curl_socket_t` is `int` off Windows and `SOCKET` on it**
  (`curl.h:142-147`), and `SOCKET` is pointer-sized on 64-bit Windows.
* **`long` is a parameter type in curl's own API** — `curl_multi_timeout` at
  `multi.h:343` and `curl_global_init` at `curl.h:2777` — so those two entry
  points are different ABIs on LP64 and ILP32 and agree only on a 64-bit `long`.
* **`struct curl_version_info_data` grows by appending**, which is what the
  `age` check is about: reading the leading fields is safe against an older
  provider, reading a field the provider does not have is not.
* **Twenty-nine function-pointer types cross the boundary in both directions** —
  `curl_write_callback`, `curl_read_callback`, `curl_progress_callback`,
  `curl_xferinfo_callback`, `curl_debug_callback`, the multi timer and socket
  callbacks and the rest — and a callback built against this translation is
  called by the provider's own C with the provider's own calling convention.

**The one thing that is checked is the one symbol resolution cannot check.** All
100 exported names are present in a libcurl built with *no* TLS backend at all,
so resolving the table proves the file is a libcurl of this API family and says
nothing about how it was configured — and this package has exactly one
configuration it will ship. So before anything is published the provider's own
`curl_version_info` must report an `age` at least this header's
`CURLVERSION_NOW`, a non-null `ssl_version`, and the `CURL_VERSION_SSL` feature
bit. All three are read out of the provider rather than asserted here. A refusal
closes the candidate and publishes nothing, so the caller can choose another
provider or retry.

`curl_global_init` and `curl_easy_init` are deliberately **not** called by the
loader. Upstream says `curl_global_init` "should be invoked exactly once for each
application that uses libcurl", and a loader runs inside whatever application
loaded it — spending that one call would leave the application unable to make
it. `curl_version_info` is safe to call before global init, and the reason is in
the C rather than in a promise: `lib/version.c:604-607` reaches the SSL version
only under `USE_SSL`, `lib/vtls/vtls.c:686-703` selects the backend pointer at
compile time so it is never null before init, and everything else the function
reads is `static` storage.

## Where the tests' answers come from

`tests.zig` is this package's own suite and **nothing in it reaches off the
machine**. No test names a host and no test resolves a name: every transfer goes
to an HTTP server the file starts itself, on `127.0.0.1` on a port the kernel
picks. The suite is a statement about libcurl and this facade, not about whether
a network exists, and it cannot turn flaky when a name server does.

The answers come in three kinds, and they are not interchangeable:

* **The fixture body is a recording, pinned two ways.** `fixture_body` is a byte
  string committed in the file, and `fixture_digest_hex` is its SHA-256, taken
  before any library code ran. Neither is produced by the code under test, so
  neither can agree with it. The body was chosen so that a body contaminated by
  the response head would be visible (`X-Not-A-Header:`), so a dropped trailing
  byte changes the length as well as the content, and so a separate
  non-text fixture can carry the NUL and the high bytes instead.
* **Protocol expectations are stated, not observed.** The header-callback test
  asserts the shape RFC 9110 requires of a response head, and the
  percent-encoding test derives its expectation from the character classes
  RFC 3986 defines, computing it in Zig rather than asking libcurl what it would
  have said.
* **A same-code round trip appears, and only as a supplement.** The
  malformed-percent-triplet and reset tests compare libcurl's output with input
  libcurl was given; on their own they would prove only that the code agrees
  with itself, and each says so in its own comment.

curl's own `docs/` tree is not vendored, so nothing is cited to a documentation
page. Everything about upstream behaviour is cited to a file under `lib/` or
`include/`, with a line.

**No test here claims a leak oracle.** What a test *can* check is the ownership
transition this package's facade owns: that `deinit` releases the handle, that an
`SList` line the caller destroys after `append` does not change what goes on the
wire, that a getter's borrow is the caller's to read and not to free, and that a
handle released with no header list of its own leaves the caller's list alone.

`smoke.zig` is a separate build root with the same 95 fixture bytes and the same
digest, written out twice on purpose; the digest is what makes the duplication
safe, because if the two copies ever drifted one of the two programs would fail
rather than quietly check its own bytes.

## The consumer package

`consumer/` is the proof that the published module resolves from a package that
did not write it. Everything in it goes through `dep.module("libcurl")` and
`@import("libcurl")` — no path reaches into the library's own tree — and the
dependency is a **relative path**, not a registry or archive URL, because
resolving it through the network would make the proof depend on a published
state of the world instead.

It performs a real fetch, over a real socket, against an HTTP server it starts
itself, and checks the body against the same pre-computed digest and the
response head against the same RFC 9110 shape. The same source builds against a
linked package and against a runtime-loaded one: `runtime_loaded` is a comptime
constant, so the difference is one branch and no duplicated program. The program
prints which route it used, so the record says rather than assumes.