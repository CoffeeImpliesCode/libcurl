# Zig facade API

This page documents the typed facade. See `README.md` for package setup and build options.

```zig
const curl = @import("libcurl");

try curl.globalInit(curl.InitFlags.default_flags);
defer curl.globalCleanup();

var easy = try curl.Easy.init();
defer easy.deinit();
try easy.setUrl("https://example.com");
try easy.perform();
```

Close every easy and multi handle before the matching `globalCleanup`. `Easy.init` may initialize libcurl implicitly. Do not copy an open `Easy` or `Multi`: each owns one handle.

## Runtime loading

- `runtime_loaded` is a compile-time boolean. `load`, `loadedSource`, and `unload` apply to runtime-loading builds; linked builds return null from `loadedSource` and panic on `load` or `unload`.
- `LoadSource.path` takes an absolute file path. `LoadSource.system` takes a bare library name or SONAME. Failed loads publish no provider and can be retried; a different provider request returns `ProviderMismatch`.
- `LoadError`: `EmptySource`, `SourceTooLong`, `InvalidSource`, `UnsupportedTarget`, `OpenFailed`, `MissingSymbol`, `ProviderMismatch`, `ReentrantLoad`. `unload` releases the dispatch table; do not call it while libcurl calls may be active.
- Runtime `c` variadic wrappers take their fixed parameters followed by one scalar argument or a tuple of arguments. Use `.{}` for no extra arguments; use C-promoted argument types such as `c_int` and `c_long`.

## Global state and version

- `InitFlags` has `Win32`, `Ssl`, and `AckIntr` fields, plus `default_flags`, `nothing`, and `toBits`. `globalInit` returns `GlobalInitFailed` and is reference-counted; pair each call with `globalCleanup`.
- `version`, `version_num`, `version_parts.{major,minor,patch}`, `copyright`, and `timestamp` come from the build headers. `versionString()` and `versionInfo()` report the loaded library. `VersionInfo` contains `version`, `version_num`, `host`, optional `ssl_version`, and `features`; its strings are borrowed for the process lifetime.
- `strError(code)` returns borrowed text for a `CURLcode`.

## Easy transfers

`Easy` owns one handle. `handle()` exposes its raw `CURL` pointer and panics after `deinit`. `deinit` closes the handle; `reset` restores default options, clears callbacks and contexts, but retains libcurl's caches and cookies. `perform` is synchronous. HTTP error statuses do not fail a transfer by default.

| Method | Contract |
| --- | --- |
| `setUrl([:0]const u8)` | Sets a NUL-terminated URL; returns `OptionError`. |
| `setTimeoutMs(c_long)` | Sets the whole-transfer timeout; zero disables it, negative values return `BadFunctionArgument`. |
| `setFollowLocation(bool)`, `setVerbose(bool)` | Set redirects and diagnostic output. |
| `setWriteFunction(ctx, callback)` | Stores the response-body callback and context. |
| `setHeaderFunction(ctx, callback)` | Stores the header callback and context; a null callback restores libcurl's default. |
| `setHeaders(?*SList)` | Sets request headers; libcurl borrows the list through transfers. |
| `perform()` | Runs synchronously; returns `PerformError`. |
| `responseCode()`, `headerSize()` | Return HTTP status and parsed header byte count as `u64`; no HTTP response yields status zero. Unknown selectors return `InfoError`. |
| `effectiveUrl()` | Returns an optional borrowed string, valid until the URL changes or the handle closes. |

`WriteCallback` and `HeaderCallback` use the C ABI `(buffer, size, nitems, ctx)` and return the consumed byte count. A short count aborts the callback; a callback may also return libcurl's pause/error sentinel. `chunkLength(size, nitems)` returns null on multiplication overflow.

## Multi transfers

`Multi` owns its multi handle, not the `Easy` handles added to it. `handle()` exposes its raw `CURLM` pointer and panics after `deinit`. Remove an easy handle before closing it. `perform` advances transfers; `poll` and `socketAction` support a custom event loop; `drive(timeout_ms)` polls and advances active transfers.

`DriveResult` is `running`, `done`, `failed`, `multi_failed`, or `timed_out`. After `drive`, call `readInfo` to retrieve a retained completion; it returns null when no completion is queued. `Message.easy` is a borrowed view of the caller-owned handle and rotates after four later messages. `Message.isFor` compares handles. `PollEvent` is `none`, `in`, `out`, `inout`, or `remove`; `MessageKind` is `none` or `done`.

## Lists, escaping, and introspection

- `SList.append` copies a NUL-terminated line and can return `OutOfMemory`. `Easy.setHeaders` borrows the list, so detach it from transfers before `freeAll`. `raw()` exposes the borrowed chain until `freeAll`.
- `escape` and `unescape` return libcurl-allocated buffers or `EscapeError.Failed`. Release the unchanged result with `freeEscaped`. Unescaping preserves embedded NULs and leaves malformed escapes literal.
- `optionByName`, `optionById`, and `optionNext` return borrowed static `OptionInfo` records or null. `OptionType` tags are `long`, `values`, `off_t`, `object`, `string`, `slist`, `cb_ptr`, `blob`, and `function`; `option_flag_alias` marks retained aliases.
- `WaitFd`, `SListNode`, and `Header` expose C structs; parsed-header pointers are borrowed until the next libcurl call on that handle. `multiSetopt` calls the raw multi-option interface and maps its result to `MultiError`; `performFrom` and `performErrorFrom` map a `CURLcode` to an optional `PerformError`.
- `c` exposes translated C declarations, including APIs not wrapped by the facade.

## Errors

- `InitError`: `OutOfMemory`. `EscapeError`: `Failed`. `InfoError`: `UnknownInfo`.
- `OptionError`: `UnknownOption`, `OutOfMemory`, `BadFunctionArgument`, `NotBuiltIn`, `OptionNotAllowedInThisBuild`.
- `PerformError` maps recognized transfer codes; tags are `UnsupportedProtocol`, `FailedInit`, `UrlMalformat`, `NotBuiltIn`, `CouldntResolveProxy`, `CouldntResolveHost`, `CouldntConnect`, `WeirdServerReply`, `RemoteAccessDenied`, `PartialFile`, `HttpReturnedError`, `WriteError`, `UploadFailed`, `ReadError`, `OutOfMemory`, `OperationTimedOut`, `RangeError`, `SslConnectError`, `FileCouldntReadFile`, `AbortedByCallback`, `BadFunctionArgument`, `InterfaceFailed`, `TooManyRedirects`, `SslEngineNotFound`, `SendError`, `RecvError`, `SslCertProblem`, `PeerFailedVerification`, `FileSizeExceeded`, `LoginDenied`, `RemoteFileNotFound`, `SslShutdownFailed`, `Again`, `SslCrlBadfile`, `Http2Stream`, `RecursiveApiCall`, `Http3`, `Proxy`, `UnrecoverablePoll`, `TooLarge`, and `Unknown`.
- `MultiError`: `CallAgain`, `BadHandle`, `BadEasyHandle`, `OutOfMemory`, `InternalError`, `BadSocket`, `UnknownOption`, `AddedAlready`, `RecursiveApiCall`, `WakeupFailure`, `BadFunctionArgument`, `AbortedByCallback`, `UnrecoverablePoll`.
