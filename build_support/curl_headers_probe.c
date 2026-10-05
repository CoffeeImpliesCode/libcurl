/* SPDX-License-Identifier: curl
 * See FORK-LICENSE.md for what that identifier covers.
 *
 * curl_headers_probe.c - the header-existence probe for this fork of libcurl.
 *
 * WHAT THIS IS
 * ------------
 * `build_support/curl_config_gen.c` writes `curl_config.h`, and 35 of its rows
 * are "Define to 1 if you have the <x> header file". Those rows are statements
 * about a directory on the *target*, so nothing about the machine running the
 * generator, or even the machine running the generator's build, answers them.
 * Upstream answers them with `AC_CHECK_HEADERS`, which runs the target compiler
 * once per header and records what it found; `CMakeLists.txt`'s
 * `check_include_file` is the same idea. This file is the same idea for this
 * package: it is compiled *for the target*, and what the target's own
 * preprocessor says about its own include path is the answer.
 *
 * WHY A PREPROCESSOR CHECK AND NOT A COMPILE
 * ------------------------------------------
 * The question each row asks is whether a file is reachable on the include path.
 * `__has_include` is exactly that question, asked by the same preprocessor the
 * translation units will use, and it answers all 35 in one invocation instead of
 * 35 compiles. Compiling `#include <x>` for each header would answer a slightly
 * different question - whether the header parses on its own - which is not what
 * any of the 35 comments claim, and it would cost 35 compiler runs per target.
 *
 * Each header is asked in its own `#if`, not all of them included together,
 * because some of them cannot coexist in one translation unit: on glibc
 * `<linux/tcp.h>` and `<netinet/tcp.h>` both define `struct tcphdr`, and
 * including both is a redefinition error. `__has_include` asks about one file
 * without dragging in the other, so the answer per file is independent.
 *
 * WHAT IT PRINTS
 * --------------
 * One line per header, `<header> yes` or `<header> no`, on the preprocessor's
 * stdout. `build.zig` preprocesses this file for the target with `-E`, takes
 * those lines out of the output, and hands them to `curl_config_gen.c` as
 * `--header-facts`. The generator refuses a file it cannot read exactly, and
 * refuses a header no `X_HEADER` row asks about, so a typo here stops the build
 * rather than widening a configuration nobody measured.
 *
 * The order below is the order of `header_rows` in `curl_config_gen.c`, which is
 * the order of `lib/curl_config-cmake.h.in`. The three diff against each other.
 *
 * The seven header rows that carry no family - `<lber.h>`, `<ldap_ssl.h>`,
 * `<idn2.h>`, `<proto/bsdsocket.h>`, `<termio.h>`, `<uv.h>` and the
 * `NEED_LBER_H` row - are absent from this list on purpose. They are off
 * because the library that needs them is not a dependency of this package, not
 * because a file is missing, so there is nothing to measure and a measurement
 * would be free to contradict the reason the row is off.
 *
 * WHY THE NAMES ARE QUOTED
 * ------------------------
 * Each name is a string literal, not a bare token, and that is not decoration.
 * A bare `linux/tcp.h` comes out of the preprocessor as `1/tcp.h`, because
 * `linux` is a predefined macro expanding to `1` on Linux targets; a bare
 * `unix/foo.h` would lose its prefix the same way. A string literal is passed
 * through `-E` byte for byte, so the answer line names the file the generator
 * is looking for. `read_header_facts` in `curl_config_gen.c` strips the quotes.
 *
 * WHAT IT IS NOT
 * --------------
 * This file never runs. It is preprocessed, never linked, and never executed on
 * the target; a header's presence is a question for the preprocessor and needs
 * no execution. It is compiled by `build.zig` with `-std=gnu99` and the target's
 * triple, and no other flags: the probe deliberately does not get `-I` for this
 * tree's own `lib/` and `include/`, because a header this package ships must not
 * be able to satisfy a question about the target's C library. Nothing under
 * `lib/` or `include/` is named `netinet/`, `net/`, `arpa/`, `sys/`, `linux/` or
 * `proto/`, so the search the probe sees is the target's own.
 */

/* One answer per header. `CURL_HEADER` is not a macro: it is a bare token that
 * survives preprocessing, which is what makes an answer line recognisable among
 * the line markers and blank lines `-E` also emits. The generator reads
 * `CURL_HEADER "<header>" yes` and `CURL_HEADER "<header>" no`; see the header
 * comment above for why the name is quoted and why the answer is emitted rather
 * than the header being included. */

#if __has_include(<arpa/inet.h>)
CURL_HEADER "arpa/inet.h" yes
#else
CURL_HEADER "arpa/inet.h" no
#endif

#if __has_include(<dirent.h>)
CURL_HEADER "dirent.h" yes
#else
CURL_HEADER "dirent.h" no
#endif

#if __has_include(<fcntl.h>)
CURL_HEADER "fcntl.h" yes
#else
CURL_HEADER "fcntl.h" no
#endif

#if __has_include(<ifaddrs.h>)
CURL_HEADER "ifaddrs.h" yes
#else
CURL_HEADER "ifaddrs.h" no
#endif

#if __has_include(<pwd.h>)
CURL_HEADER "pwd.h" yes
#else
CURL_HEADER "pwd.h" no
#endif

#if __has_include(<io.h>)
CURL_HEADER "io.h" yes
#else
CURL_HEADER "io.h" no
#endif

#if __has_include(<libgen.h>)
CURL_HEADER "libgen.h" yes
#else
CURL_HEADER "libgen.h" no
#endif

#if __has_include(<locale.h>)
CURL_HEADER "locale.h" yes
#else
CURL_HEADER "locale.h" no
#endif

#if __has_include(<netdb.h>)
CURL_HEADER "netdb.h" yes
#else
CURL_HEADER "netdb.h" no
#endif

#if __has_include(<netinet/in.h>)
CURL_HEADER "netinet/in.h" yes
#else
CURL_HEADER "netinet/in.h" no
#endif

#if __has_include(<netinet/in6.h>)
CURL_HEADER "netinet/in6.h" yes
#else
CURL_HEADER "netinet/in6.h" no
#endif

#if __has_include(<netinet/tcp.h>)
CURL_HEADER "netinet/tcp.h" yes
#else
CURL_HEADER "netinet/tcp.h" no
#endif

#if __has_include(<netinet/udp.h>)
CURL_HEADER "netinet/udp.h" yes
#else
CURL_HEADER "netinet/udp.h" no
#endif

#if __has_include(<netinet/ip.h>)
CURL_HEADER "netinet/ip.h" yes
#else
CURL_HEADER "netinet/ip.h" no
#endif

#if __has_include(<net/if.h>)
CURL_HEADER "net/if.h" yes
#else
CURL_HEADER "net/if.h" no
#endif

#if __has_include(<linux/tcp.h>)
CURL_HEADER "linux/tcp.h" yes
#else
CURL_HEADER "linux/tcp.h" no
#endif

#if __has_include(<sys/eventfd.h>)
CURL_HEADER "sys/eventfd.h" yes
#else
CURL_HEADER "sys/eventfd.h" no
#endif

#if __has_include(<poll.h>)
CURL_HEADER "poll.h" yes
#else
CURL_HEADER "poll.h" no
#endif

#if __has_include(<sys/poll.h>)
CURL_HEADER "sys/poll.h" yes
#else
CURL_HEADER "sys/poll.h" no
#endif

#if __has_include(<stdatomic.h>)
CURL_HEADER "stdatomic.h" yes
#else
CURL_HEADER "stdatomic.h" no
#endif

#if __has_include(<stdbool.h>)
CURL_HEADER "stdbool.h" yes
#else
CURL_HEADER "stdbool.h" no
#endif

#if __has_include(<strings.h>)
CURL_HEADER "strings.h" yes
#else
CURL_HEADER "strings.h" no
#endif

#if __has_include(<stropts.h>)
CURL_HEADER "stropts.h" yes
#else
CURL_HEADER "stropts.h" no
#endif

#if __has_include(<sys/sockio.h>)
CURL_HEADER "sys/sockio.h" yes
#else
CURL_HEADER "sys/sockio.h" no
#endif

#if __has_include(<sys/filio.h>)
CURL_HEADER "sys/filio.h" yes
#else
CURL_HEADER "sys/filio.h" no
#endif

#if __has_include(<sys/types.h>)
CURL_HEADER "sys/types.h" yes
#else
CURL_HEADER "sys/types.h" no
#endif

#if __has_include(<sys/utime.h>)
CURL_HEADER "sys/utime.h" yes
#else
CURL_HEADER "sys/utime.h" no
#endif

#if __has_include(<sys/ioctl.h>)
CURL_HEADER "sys/ioctl.h" yes
#else
CURL_HEADER "sys/ioctl.h" no
#endif

#if __has_include(<sys/param.h>)
CURL_HEADER "sys/param.h" yes
#else
CURL_HEADER "sys/param.h" no
#endif

#if __has_include(<sys/select.h>)
CURL_HEADER "sys/select.h" yes
#else
CURL_HEADER "sys/select.h" no
#endif

#if __has_include(<sys/un.h>)
CURL_HEADER "sys/un.h" yes
#else
CURL_HEADER "sys/un.h" no
#endif

#if __has_include(<sys/resource.h>)
CURL_HEADER "sys/resource.h" yes
#else
CURL_HEADER "sys/resource.h" no
#endif

#if __has_include(<termios.h>)
CURL_HEADER "termios.h" yes
#else
CURL_HEADER "termios.h" no
#endif

#if __has_include(<unistd.h>)
CURL_HEADER "unistd.h" yes
#else
CURL_HEADER "unistd.h" no
#endif

#if __has_include(<utime.h>)
CURL_HEADER "utime.h" yes
#else
CURL_HEADER "utime.h" no
#endif