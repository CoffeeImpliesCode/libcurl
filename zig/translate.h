/* The one header this package translates.
 *
 * `zig build` runs translate-c over this file, and what that translation
 * becomes is the `translate` module that zig/root.zig imports as its
 * `pub const c`. Its whole job is to name the public headers of the library
 * this build compiles.
 *
 * Which headers those are
 * -----------------------
 * curl installs twelve headers of its own under `include/curl/`
 * (`include/curl/Makefile.am:25-26`: curl.h curlver.h easy.h mprintf.h
 * stdcheaders.h multi.h typecheck-gcc.h system.h urlapi.h options.h header.h
 * websockets.h), and this file opens one of them:
 *
 *   curl/curl.h  the umbrella header, and upstream's own comment at
 *                `include/curl/curl.h:3339-3340` says why it opens the rest
 *                itself: "unfortunately, the easy.h and multi.h include files
 *                need options and info stuff before they can be included".
 *
 * The umbrella header supplies curl's public declarations. The translation
 * disables GNU C typechecking macros, as described below.
 *
 * What reaches the translation through that include
 * -------------------------------------------------
 * Two different things arrive, and telling them apart is what decides what
 * the runtime route has to classify as C-library noise.
 *
 * 1. curl's own headers, reached by `curl.h`'s own `#include`s:
 *
 *      curlver.h      include/curl/curl.h:62   version macros only
 *      system.h       include/curl/curl.h:63   platform detection, no
 *                                                declaration surface
 *      easy.h         include/curl/curl.h:3341 curl_easy_init/setopt/perform/
 *                                                cleanup/getinfo/duphandle/
 *                                                reset/recv/send/upkeep
 *      multi.h        include/curl/curl.h:3342 curl_multi_* and CURLMcode;
 *                                                multi.h:51 opens curl.h back,
 *                                                which its own comment at
 *                                                :42-50 explains is deliberate
 *                                                ABI compatibility
 *      urlapi.h       include/curl/curl.h:3343 curl_url_*; opens curl.h back
 *      options.h      include/curl/curl.h:3344 curl_easyoption and
 *                                                curl_easytype
 *      header.h       include/curl/curl.h:3345 curl_easy_header,
 *                                                curl_easy_nextheader,
 *                                                struct curl_header, CURLHcode
 *      websockets.h   include/curl/curl.h:3346 curl_ws_* and struct
 *                                                curl_ws_frame
 *      mprintf.h      include/curl/curl.h:3347 curl_mprintf and the
 *                                                curlx_ family of allocators
 *      typecheck-gcc.h is excluded with CURL_DISABLE_TYPECHECK; its helpers
 *                      have no exported ABI.
 *
 * 2. The C library's headers, reached the same way, which is why the runtime
 *    dispatch has to know about them:
 *
 *      <stdio.h>       include/curl/curl.h:65 and mprintf.h:28, for FILE *
 *      <limits.h>      include/curl/curl.h:66
 *      <sys/types.h>   include/curl/curl.h:74
 *      <time.h>        include/curl/curl.h:75, for time_t
 *      <stdarg.h>      include/curl/mprintf.h:27, for va_list
 *      <sys/socket.h>  include/curl/curl.h:103 and <sys/time.h> :104, on
 *                      every target that is not Windows
 *      <sys/select.h>  include/curl/curl.h:99, under the platform test at
 *                      :90-100
 *      <sys/param.h>   include/curl/curl.h:70, FreeBSD and MidnightBSD only
 *      <winsock2.h>    include/curl/curl.h:82 and <ws2tcpip.h> :83, Windows
 *                      only, and only when winsock.h has not been included
 *                      already (:77-85)
 *
 *    `zig translate-c` emits a declaration for every function it parses in an
 *    include closure, whether or not this build calls it, so the translation
 *    carries the target C library's whole stdio, time, socket and stdarg
 *    surface alongside curl's own. Those are the C library's symbols and not
 *    the provider's: a `libcurl.so` does not export `printf`, and asking a
 *    provider for one would either fail the load outright or, worse, resolve
 *    it out of the C library that the provider itself depends on. They are
 *    therefore what runtime/graph.zig has to classify as noise and keep
 *    direct, and this header is where that list comes from: nothing in curl's
 *    own headers contributes to it.
 *
 * Why stdcheaders.h is not listed separately
 * ------------------------------------------
 * It is installed (`include/curl/Makefile.am:25`) and nothing in this tree
 * includes it: a grep for `stdcheaders` over `include/` returns only the two
 * Makefiles that install it. It is a self-contained convenience header for
 * C++ consumers, so it reaches nothing here.
 *
 * What is deliberately not here
 * -----------------------------
 * A copy of any declaration, and no macro of this build's own.
 *
 * `USE_MBEDTLS`, `CURL_CA_BUNDLE` and `CURL_CA_PATH` are on the compile line
 * and on this translation, not here, because they describe *this* build's
 * platform and its TLS backend rather than what the interface is - the same
 * reason upstream puts its own platform macros in lib/curl_setup.h and not in
 * the installed headers. They are defined once in build.zig and given to the
 * library's own compilation and to this translation alike, so the
 * declarations below and the code that implements them cannot be built for
 * two different platforms.
 *
 * `CURL_STATICLIB` is likewise not set here. It is what makes `CURL_EXTERN`
 * an empty decoration instead of `__declspec(dllimport)`
 * (`include/curl/curl.h:124-138`), and it is a fact about how the library was
 * built rather than about the interface. Whether this build defines it is
 * build.zig's answer for the linkage it selected, and the same include gives
 * an installed C consumer its own answer through its own compile line.
 *
 * build.zig sets `CURL_DISABLE_TYPECHECK` for translation. The GNU C option
 * checker defines static helpers with inline assembly; translate-c demotes
 * those bodies to extern declarations that no libcurl provider exports.
 * The four underlying variadic API declarations remain available.
 */

#ifndef LIBCURL_TRANSLATE_H
#define LIBCURL_TRANSLATE_H

#include <curl/curl.h>

#endif /* LIBCURL_TRANSLATE_H */
