/* SPDX-License-Identifier: curl
 * See FORK-LICENSE.md for what that identifier covers.
 *
 * curl_existence_probe.c - the existence probe for this fork of libcurl.
 *
 * WHAT THIS IS
 * ------------
 * `build_support/curl_config_gen.c` writes `curl_config.h`, and 57 of its rows
 * are "Define to 1 if you have the `x' function" and one is "Define to 1 if
 * struct sockaddr_in6 has the sin6_scope_id member". Those rows are statements
 * about the target's C library, and - exactly as the 35 `X_HEADER` rows beside
 * them - nothing about the machine running the generator answers them. The
 * family mask that decided the function rows is a guess, and on the Darwin
 * headers Zig ships the guess is wrong twice over: `accept4` and `memrchr` are
 * not declared at all, so `HAVE_ACCEPT4` and `HAVE_MEMRCHR` were asserted about
 * a target nobody had asked, and `lib/cf-socket.c:2298-2299` and
 * `lib/cookie.c:168` then called functions that do not exist.
 *
 * The member row was decided from a *second* guess: a closed list of
 * architectures this fork had been told about, because the answer is a property
 * of the architecture rather than of the pointer width or the byte order. That
 * is true, and it is also not enough, because the answer is written in the
 * target's own `<netinet/in.h>` and the list was narrower than the platform
 * matrix: it refused `armeb`, `powerpc64`, `powerpc64le`, `hexagon`, `mipsel`,
 * `thumb` and `riscv32` over a question the target compiler answers in one
 * compile. So the member row is measured here now, by upstream's own technique,
 * and `arch_has_scope_id()` is gone rather than widened.
 *
 * Upstream answers these rows with `AC_CHECK_FUNCS` and `AC_COMPILE_IFELSE`,
 * which run the *target* compiler once per name and record what it found;
 * `CMakeLists.txt`'s `check_function_exists` is one compile per symbol, and
 * `configure.ac:1812-1831` spells the member question out as one
 * `AC_COMPILE_IFELSE` over `struct sockaddr_in6 s; s.sin6_scope_id = 0;`.
 * This file is that idea for this package, and it is the sibling of
 * `build_support/curl_headers_probe.c`: one facts file in, one `yes|no` line per
 * row out, read by `curl_config_gen.c` as `--function-facts`.
 *
 * WHY A COMPILE AND NOT A PREPROCESSOR RUN
 * ----------------------------------------
 * `__has_include` answers the header rows because a header is a *file*, and
 * finding files is what a preprocessor does. A function is a *declaration* and
 * a struct member is a *field*, and no `__has_*` operator asks about either, so
 * the question belongs to the compiler's semantic phase. That single difference
 * is why this file is compiled and `curl_headers_probe.c` is preprocessed, and
 * it is the whole reason the loop below exists.
 *
 * THE ONE-ANSWER TECHNIQUE
 * ------------------------
 * One translation unit per row, containing either
 *
 *     enum { curl_probe_dummy = 1 / !!NAME };
 *
 * for a function - `NAME` is a function designator, which decays to a pointer
 * that is never null, so `!!NAME` is the integer constant 1 and the enumerator
 * is 1 - or, for a struct member, upstream's own form
 *
 *     static void curl_probe_member(STRUCT *p)
 *     {
 *       p->MEMBER = 0;
 *     }
 *     enum { curl_probe_dummy = 1 / !!curl_probe_member };
 *
 * which is an assignment rather than a read because that is what curl does with
 * the member (`lib/cf-socket.c:492` and `:810` both store into it), and whose
 * address the enumerator takes so that the constant is 1 and the probe function
 * is not an unused-function diagnostic. When the name or the member is absent
 * the compiler stops and the compile FAILS, so the answer is the exit status:
 * zero for yes, non-zero for no. Nothing is linked and nothing is run, which is
 * what makes the technique valid for a target this host cannot execute.
 *
 * Why `1 / !!NAME` and not the more often quoted `char probe[sizeof(&NAME ?
 * 1 : -1)]`: same idea, and this one survives `-Wall -Wextra -Wpedantic`
 * cleanly. An array bound written as a conditional over a pointer is a
 * *variable length array* to a conforming compiler, which `-Wvla` reports and
 * C89 does not allow at file scope - measured on this compiler, not recalled.
 * An enumerator is a genuine integer constant expression in every dialect, and
 * `1 / 0` is a compile-time error, so an absent function stops the compile and
 * nothing else happens.
 *
 * Taking the address through `!!` is what makes a function row a *declaration*
 * check rather than a *macro* check, and that is deliberate for every row except
 * the two whose template comment says "function or macro": `HAVE_SIGSETJMP`
 * accepts glibc's function-like `sigsetjmp` macro, and a plain declaration probe
 * would report `no` on the one family that has it. Those rows render the `#ifdef`
 * form below instead, which asks the question the row's own comment asks.
 *
 * TWO MODES, ONE FILE
 * -------------------
 * Compiled with `-DCURL_EXISTENCE_COLLECTOR`, this file is the **collector**: a
 * host program that runs the target compiler once per row and writes the facts
 * file. Without that macro it is the **table**, which the collector reads.
 *
 * Why the loop lives here rather than in `build.zig`: the loop has to read a
 * *child's exit status* and turn it into a line of text, and the build graph
 * has no step for "run this, tolerate a non-zero exit, and write down what the
 * exit meant". `AC_CHECK_FUNCS` has this loop in `autoconf`; CMake has one per
 * symbol. Keeping it in one host program gives the whole class one build step
 * and one facts file - the shape `addHeaderProbe` gives the header class -
 * rather than 58 build steps whose individual results the caller would have to
 * reassemble.
 *
 * The collector runs the compiler itself rather than trusting the host's: it is
 * handed `zig` and a `-target` triple, exactly as `addHeaderProbe` is. It
 * passes the same `-std=gnu99` and no `-I` for this tree's `lib/` or `include/`,
 * because a header this package ships must not be able to answer a question
 * about the target's C library.
 *
 * WHAT IT PRINTS
 * --------------
 * One line per function and one per member. A function row prints
 * `CURL_FUNCTION "<name>" yes|no`; a member row prints
 * `CURL_MEMBER "<struct>::<member>" yes|no`. Both markers are bare tokens, not
 * macros, so nothing rewrites them, and both kinds of line go into the *same*
 * facts file, because there is one build step and one output. The two readers in
 * `curl_config_gen.c` each skip every line that is not their own marker, so one
 * file carries both classes and neither reader can mistake the other's line for
 * an answer.
 *
 * THE ORDER BELOW IS LOAD-BEARING
 * -------------------------------
 * `curl_function_rows` is the order of `function_rows` in
 * `curl_config_gen.c`, which is the order of `entries`, which is the order of
 * `lib/curl_config-cmake.h.in`. The three diff against each other: the generator
 * refuses an `X_FUNCTION` row it has no fact for and refuses a fact no
 * `X_FUNCTION` row asks about, so a name added in one file and forgotten in the
 * other stops the build instead of quietly widening a configuration nobody
 * measured. `curl_member_rows` and `member_rows` are held to the same
 * three-way check.
 */

/* ========================================================================= */
/* THE TABLE                                                                   */
/* ========================================================================= */

/* `flags` is `F_MACRO_OK` for the two rows whose template comment says
 * "function or macro" and plain 0 for every other row, which is the strong
 * claim: the identifier must be a declaration curl can call. */
#define F_MACRO_OK 1u

/* The collector's own headers. Spelled here rather than inside the collector
 * branch because the tables below use `NULL`, and a table that cannot name its
 * own "spelled the same on both platforms" marker is a table nobody can read.
 * These are *host* headers: this half of the file is the program that runs on
 * the build machine, which is the one thing the probe half is not allowed to
 * be. The probe half includes nothing at all - `curl_probe_source_for` renders
 * the target's headers as text. */
#if defined(CURL_EXISTENCE_COLLECTOR)
#include <errno.h>
#include <fcntl.h> /* open, O_WRONLY: the stderr redirect in run_probe */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

static const struct {
  const char *row;   /* the entry name in curl_config_gen.c's `entries` */
  const char *name;  /* the C identifier curl calls */
  const char *group; /* which declaration group to include; see probe_groups */
  unsigned flags;
} curl_function_rows[] = {
    /* ---- Signals, time, process ---- */
    { "HAVE_ALARM", "alarm", "unistd", 0 },
    { "HAVE_GETEUID", "geteuid", "unistd", 0 },
    { "HAVE_GETPPID", "getppid", "unistd", 0 },
    { "HAVE_GETHOSTNAME", "gethostname", "winsock_pair", 0 },
    { "HAVE_PIPE", "pipe", "unistd", 0 },
    { "HAVE_PIPE2", "pipe2", "unistd", 0 },
    { "HAVE_GETTIMEOFDAY", "gettimeofday", "systime", 0 },
    { "HAVE_LOCALTIME_R", "localtime_r", "time", 0 },
    { "HAVE_GMTIME_R", "gmtime_r", "time", 0 },

    /* ---- Sockets and their options ---- */
    { "HAVE_SOCKET", "socket", "socket_or_winsock", 0 },
    { "HAVE_SOCKETPAIR", "socketpair", "socket_or_winsock", 0 },
    { "HAVE_SEND", "send", "socket_or_winsock", 0 },
    { "HAVE_RECV", "recv", "socket_or_winsock", 0 },
    { "HAVE_SENDMSG", "sendmsg", "socket_or_winsock", 0 },
    { "HAVE_SENDMMSG", "sendmmsg", "socket_or_winsock", 0 },
    { "HAVE_GETPEERNAME", "getpeername", "socket_or_winsock", 0 },
    { "HAVE_GETSOCKNAME", "getsockname", "socket_or_winsock", 0 },
    { "HAVE_ACCEPT4", "accept4", "socket_or_winsock", 0 },

    /* ---- Name resolution ---- */
    { "HAVE_GETADDRINFO", "getaddrinfo", "netdb_or_winsock", 0 },
    { "HAVE_FREEADDRINFO", "freeaddrinfo", "netdb_or_winsock", 0 },
    { "HAVE_GETIFADDRS", "getifaddrs", "ifaddrs", 0 },
    { "HAVE_IF_NAMETOINDEX", "if_nametoindex", "netif", 0 },
    { "HAVE_GETPASS_R", "getpass_r", "stdio", 0 },

    /* ---- Files, directories, passwords ---- */

    { "HAVE_OPENDIR", "opendir", "dirent", 0 },
    { "HAVE_FCNTL", "fcntl", "fcntl", 0 },
    { "HAVE_FSEEKO", "fseeko", "stdio", 0 },
    { "HAVE_REALPATH", "realpath", "stdlib", 0 },
    { "HAVE_BASENAME", "basename", "libgen", 0 },
    { "HAVE_FNMATCH", "fnmatch", "fnmatch", 0 },
    { "HAVE_UTIME", "utime", "utime", 0 },
    { "HAVE_UTIMES", "utimes", "systime", 0 },
    { "HAVE_GETPWUID", "getpwuid", "pwd", 0 },
    { "HAVE_GETPWUID_R", "getpwuid_r", "pwd", 0 },

    /* ---- Strings, memory, locale ---- */
    { "HAVE_STRCASECMP", "strcasecmp", "strings", 0 },
    { "HAVE_MEMRCHR", "memrchr", "string", 0 },
    { "HAVE_STRERROR_R", "strerror_r", "string", 0 },
    { "HAVE_ARC4RANDOM", "arc4random", "stdlib", 0 },
    { "HAVE_SETLOCALE", "setlocale", "locale", 0 },

    /* ---- Resources, polling, events, scheduling ---- */
    { "HAVE_GETRLIMIT", "getrlimit", "sysresource", 0 },
    { "HAVE_SETRLIMIT", "setrlimit", "sysresource", 0 },
    { "HAVE_POLL", "poll", "poll", 0 },
    { "HAVE_EVENTFD", "eventfd", "syseventfd", 0 },
    { "HAVE_SCHED_YIELD", "sched_yield", "sched", 0 },
    { "HAVE_SIGACTION", "sigaction", "signal", 0 },
    { "HAVE_SIGNAL", "signal", "signal", 0 },
    { "HAVE_SIGSETJMP", "sigsetjmp", "setjmp", F_MACRO_OK },

    /* ---- Darwin ---- */
    { "HAVE_MACH_ABSOLUTE_TIME", "mach_absolute_time", "machtime", 0 },
};

#define CURL_FUNCTION_COUNT                                                   \
  ((int)(sizeof curl_function_rows / sizeof curl_function_rows[0]))

/* The struct-member rows. One row today, and it is the row whose architecture
 * table used to be the only reason `armeb-linux`, `powerpc64-linux`,
 * `powerpc64le-linux`, `hexagon-linux`, `mipsel-linux`, `thumb-linux` and
 * `riscv32-linux` refused to configure.
 *
 * `name` is the member as upstream's own probe names it. The probe renders
 *
 *     static void curl_probe_member(struct sockaddr_in6 *p)
 *     {
 *       p->sin6_scope_id = 0;
 *     }
 *     enum { curl_probe_dummy = 1 / !!curl_probe_member };
 *
 * which is `configure.ac:1812-1831`'s `s.sin6_scope_id = 0` turned into a
 * translation unit the exit status can answer for. The assignment rather than a
 * read is upstream's shape and it is what `lib/cf-socket.c:492` and `:810` need:
 * both store into the member.
 *
 * `group` is `sockaddr_in6`, the include set `configure.ac:1815-1824` uses -
 * `<winsock2.h>` then `<ws2tcpip.h>` under `_WIN32`, `<netinet/in.h>` otherwise
 * with the Tandem `__TANDEM` extra include upstream carries. Upstream includes
 * `<sys/types.h>` first on both shapes and so does this group. */
static const struct {
  const char *row;    /* the entry name in curl_config_gen.c's `entries` */
  const char *type;   /* the struct type, spelled `struct <type>` */
  const char *name;   /* the member */
  const char *group;  /* which declaration group to include */
} curl_member_rows[] = {
    { "HAVE_SOCKADDR_IN6_SIN6_SCOPE_ID", "sockaddr_in6", "sin6_scope_id",
      "sockaddr_in6" },
};

#define CURL_MEMBER_COUNT                                                    \
  ((int)(sizeof curl_member_rows / sizeof curl_member_rows[0]))

/* The declaration groups. The probe includes one group per question, because
 * two of them are spelled differently on the two platform shapes this table
 * covers and a fixed header would fail the whole question for one of them:
 *
 *   socket_or_winsock  <sys/socket.h> on the unixes, <winsock2.h> on mingw
 *                      - measured: all ten names it declares are present in
 *                      Zig's mingw-w64 headers, so an `M_ALL` row is answered
 *                      on Windows rather than being left to the family mask.
 *   netdb_or_winsock   <netdb.h> on the unixes, <ws2tcpip.h> on mingw.
 *
 *   sockaddr_in6        upstream's own include set for the member row,
 *                      `configure.ac:1815-1824`: `<sys/types.h>` then
 *                      `<winsock2.h>` + `<ws2tcpip.h>` under `_WIN32`, and
 *                      `<sys/types.h>` + `<netinet/in.h>` otherwise, with the
 *                      Tandem `__TANDEM` case carried across unchanged.
 *
 * The other groups are spelled the same way everywhere, so they are listed with
 * the single include they use.
 *
 * `verbatim`, when it is set, is written out exactly as it stands and the other
 * two fields are ignored. Only `sockaddr_in6` uses it: upstream's member probe
 * chooses between two *include sets* inside one block
 * (`configure.ac:1815-1824`) rather than one include per platform shape, so
 * there is no single `unix_include` and no single `windows_include` to hold.
 * `includes_for_group` checks it first, which is why one group shape can answer
 * for both classes. */
static const struct {
  const char *group;
  const char *unix_include;   /* rendered when !_WIN32 */
  const char *windows_include; /* rendered when _WIN32; NULL for the shared ones */
  const char *verbatim;        /* rendered as-is; wins over the two above */
} probe_groups[] = {
    { "socket_or_winsock", "<sys/socket.h>", "<winsock2.h>", NULL },
    { "netdb_or_winsock", "<netdb.h>", "<ws2tcpip.h>", NULL },
    { "unistd", "<unistd.h>", NULL, NULL },
    { "dirent", "<dirent.h>", NULL, NULL },
    { "fcntl", "<fcntl.h>", NULL, NULL },
    { "sysioctl", "<sys/ioctl.h>", NULL, NULL },
    /* `gethostname` is in `<unistd.h>` on the unixes and in `<winsock2.h>` on
     * mingw - not in `<ws2tcpip.h>`, the other member of that pair. Measured:
     * including only `<ws2tcpip.h>` on `x86_64-windows-gnu` reports `no` for a
     * function the SDK does declare. */
    { "winsock_pair", "<unistd.h>", "<winsock2.h>\n#include <ws2tcpip.h>", NULL },
    { "sysresource", "<sys/resource.h>", NULL, NULL },
    { "syseventfd", "<sys/eventfd.h>", NULL, NULL },
    { "systime", "<sys/time.h>", NULL, NULL },
    { "utime", "<utime.h>", "<sys/utime.h>", NULL },
    { "stdlib", "<stdlib.h>", NULL, NULL },
    { "stdio", "<stdio.h>", NULL, NULL },
    { "string", "<string.h>", NULL, NULL },
    { "strings", "<strings.h>", NULL, NULL },
    { "locale", "<locale.h>", NULL, NULL },
    { "pwd", "<pwd.h>", NULL, NULL },
    { "libgen", "<libgen.h>", NULL, NULL },
    { "fnmatch", "<fnmatch.h>", NULL, NULL },
    { "utime", "<sys/utime.h>", NULL, NULL },
    { "signal", "<signal.h>", NULL, NULL },
    { "setjmp", "<setjmp.h>", NULL, NULL },
    { "sched", "<sched.h>", NULL, NULL },
    { "poll", "<poll.h>", NULL, NULL },
    { "time", "<time.h>", NULL, NULL },
    { "pthread", "<pthread.h>", NULL, NULL },
    { "ifaddrs", "<ifaddrs.h>", NULL, NULL },
    { "netif", "<net/if.h>", NULL, NULL },
    { "arpa", "<arpa/inet.h>", NULL, NULL },
    { "machtime", "<mach/mach_time.h>", NULL, NULL },
    { "sockaddr_in6", NULL, NULL,
      /* Upstream's include set for the member question, verbatim:
       * `configure.ac:1815-1824`. */
      "#include <sys/types.h>\n"
      "#ifdef _WIN32\n"
      "#include <winsock2.h>\n"
      "#include <ws2tcpip.h>\n"
      "#else\n"
      "#include <netinet/in.h>\n"
      "#ifdef __TANDEM\n"
      "#include <netinet/in6.h>\n"
      "#endif\n"
      "#endif\n" },
};

#define PROBE_GROUP_COUNT                                                     \
  ((int)(sizeof probe_groups / sizeof probe_groups[0]))

/* The token the collector emits in front of every answer. Spelled here and in
 * `curl_config_gen.c` (`CURL_FUNCTION_MARKER`); a bare token so nothing
 * rewrites it. */
#define CURL_FUNCTION_MARKER "CURL_FUNCTION"

/* The token the collector emits in front of every *member* answer. Spelled here
 * and in `curl_config_gen.c` (`CURL_MEMBER_MARKER`), bare like the function
 * marker, so nothing rewrites it. Two markers rather than one because both
 * classes share one facts file: `read_member_facts` must not read a
 * `CURL_FUNCTION` line as a member answer, or the other way round. */
#define CURL_MEMBER_MARKER "CURL_MEMBER"

#if defined(CURL_EXISTENCE_COLLECTOR)

/* ========================================================================= */
/* COLLECTOR - the host program that asks the target compiler.               */
/* ========================================================================= */

/* The host headers are included above, before the tables, because the tables
 * use `NULL`. */

/* The preamble every probe carries.
 *
 * The feature-test environment is part of the question and part of the answer,
 * and **the answer has to be the environment the library will actually compile
 * in**, not one that is convenient for the probe.
 *
 * `curl_config_gen.c` emits `#define _GNU_SOURCE 1` from exactly one condition:
 * `f->family == FAM_LINUX && strcmp(f->libc, "gnu") == 0` (see `emit()`).
 * `lib/curl_setup.h:138-140` includes that generated header before the first
 * system header, and glibc's `<features.h>` hides `memrchr`, `accept4` and
 * `fmemopen` without it - measured on Zig 0.16.0's glibc, where all three are
 * absent from a plain `-std=gnu99` compile and present with the macro.
 * (observed with Zig 0.16; not rechecked on 0.17).
 *
 * So the macro is defined here under the *same* condition, and the libc is
 * passed in from `build.zig`'s `generatorLibc` - the one function that already
 * decides that string for both this probe and the generator. Guessing the
 * condition here is what made this wrong the first time: an earlier version
 * keyed on `__linux__` alone, so on a musl target the probe compiled *with*
 * `_GNU_SOURCE` and saw musl's `memrchr`, the generator emitted
 * `HAVE_MEMRCHR 1`, and the closure then used a function musl only declares
 * behind the macro the generator had correctly *not* emitted. That broke six
 * Linux cells, including the native one, and upstream's own fallback at
 * `lib/curl_memrchr.c:28` went unused because the row said the function was
 * there. Two artifacts that decide the same fact have to be given the same
 * fact; deriving it twice is how they come to disagree.
 *
 * The `#ifndef` guard is kept because the compiler command line may define it
 * already, and the two spellings of the same request must not collide. */
static const char probe_preamble_gnu[] =
    "#ifndef _GNU_SOURCE\n"
    "#define _GNU_SOURCE 1\n"
    "#endif\n";

/* The empty preamble: every target that is not glibc-Linux compiles its probe
 * with no feature-test macro at all, which is what the generated header gives
 * it. */
static const char probe_preamble_none[] = "";

/* Render one probe into `buffer`. Returns the length written, or -1 when the
 * row does not fit, which is a refusal rather than a truncated answer: a
 * half-written probe would compile to something that measured nothing and be
 * reported as a confident `no`.
 *
 * `decls` is already the `#include` line, chosen by `includes_for_group`, and
 * `preamble` is the feature-test prologue the target's libc decides, so this
 * function is only about the probe itself. */
static int curl_probe_source_for(const char *preamble, const char *decls,
                                 const char *name, unsigned flags, char *buffer,
                                 size_t capacity) {
  int written;

  if ((flags & F_MACRO_OK) != 0) {
    /* The row's own comment says "function or macro", so both forms answer
     * yes. `#ifdef` is asked rather than `defined()`, and both take the name
     * without arguments, which a function-like macro such as glibc's
     * `sigsetjmp` needs. */
    written = snprintf(buffer, capacity,
                       "%s%s"
                       "#ifdef %s\n"
                       "enum { curl_probe_dummy = 1 };\n"
                       "#else\n"
                       "enum { curl_probe_dummy = 1 / !!%s };\n"
                       "#endif\n",
                       preamble, decls, name, name);
  } else {
    written = snprintf(buffer, capacity,
                       "%s%s\n"
                       "enum { curl_probe_dummy = 1 / !!%s };\n",
                       preamble, decls, name);
  }
  if (written < 0 || (size_t)written >= capacity)
    return -1;
  return written;
}

/* The `#include` line for one row's group, rendered into `buffer`. Returns the
 * length written, or -1 on an unknown group or a full buffer. An unknown group
 * is a refusal rather than an empty answer: a probe with no include would
 * measure nothing and be recorded as a confident `no`, which is the exact defect
 * this whole file exists to remove.
 *
 * A group with a `verbatim` string is rendered as it stands, `#include` and all,
 * because upstream's member probe needs its own `#ifdef _WIN32` branch inside
 * the include block rather than around it. */
static int includes_for_group(const char *group, char *buffer,
                              size_t capacity) {
  for (int i = 0; i < PROBE_GROUP_COUNT; i++) {
    if (strcmp(probe_groups[i].group, group) != 0)
      continue;
    if (probe_groups[i].verbatim != NULL)
      return snprintf(buffer, capacity, "%s", probe_groups[i].verbatim);
    if (probe_groups[i].windows_include == NULL)
      return snprintf(buffer, capacity, "#include %s\n",
                      probe_groups[i].unix_include);
    /* The two platform shapes are asked by the *target's* `_WIN32`, in the
     * rendered source, so the host's own platform decides nothing. */
    return snprintf(buffer, capacity,
                    "#ifdef _WIN32\n#include %s\n#else\n#include %s\n#endif\n",
                    probe_groups[i].windows_include,
                    probe_groups[i].unix_include);
  }
  return -1;
}

/* Render one *member* probe into `buffer`. Same refusal contract as
 * `curl_probe_source_for`: -1 rather than a truncated answer.
 *
 * The body is upstream's `s.sin6_scope_id = 0` from
 * `configure.ac:1827-1829`, and it assigns rather than reads because that is
 * what curl does with the member. The enumerator takes the probe function's
 * address, which is what makes the constant 1 and stops the function from being
 * an unused-function diagnostic; a `static` function is the right linkage here
 * because nothing outside this translation unit can name it. */
static int curl_probe_member_source_for(const char *preamble, const char *decls,
                                        const char *type, const char *name,
                                        char *buffer, size_t capacity) {
  int written = snprintf(buffer, capacity,
                         "%s%s"
                         "static void curl_probe_member(struct %s *p)\n"
                         "{\n"
                         "  p->%s = 0;\n"
                         "}\n"
                         "enum { curl_probe_dummy = 1 / !!curl_probe_member };\n",
                         preamble, decls, type, name);
  if (written < 0 || (size_t)written >= capacity)
    return -1;
  return written;
}

/* One probe. Returns 1 when the target compiler accepted the translation unit,
 * 0 when it rejected it, and 2 when the compiler could not be run at all. The
 * distinction is load-bearing: an absent answer ("no") and an unmeasurable one
 * (a compiler that would not start) are different facts, and only the first is
 * allowed to become a line in the facts file.
 *
 * `stem` names the two files this writes inside the cache directory and `label`
 * is what the refusal messages call the question. They differ for a member row,
 * whose stem carries `struct::member` so a function row and a member row can
 * never overwrite each other's scratch files. */
static int run_probe(const char *zig_exe, const char *triple, const char *flags,
                     const char *scratch_dir, const char *stem,
                     const char *source, const char *label) {
  char source_path[4096];
  char object_path[4096];
  pid_t pid;
  int status;
  int exec_pipe[2];

  /* Two paths, never one. The probe source and the object the compiler makes of
   * it are separate files in the cache directory: the source is written here,
   * the compiler reads it and writes the object, and one path would have the
   * compiler read a file it had been handed as its own output.
   *
   * `-c` rather than `-fsyntax-only`, and that is measured rather than
   * preferred: on this compiler `zig cc -fsyntax-only -o <path>` reports
   * `-Wunused-command-line-argument` and then `FileNotFound`, so the question
   * cannot be asked that way. A real object costs one file inside the cache
   * directory and answers the same question, because what is under test is
   * whether the compiler's semantic phase accepts the declaration. */
  if (snprintf(source_path, sizeof source_path, "%s/curl_fn_probe_%s.c",
               scratch_dir, stem) >= (int)sizeof source_path ||
      snprintf(object_path, sizeof object_path, "%s/curl_fn_probe_%s.o",
               scratch_dir, stem) >= (int)sizeof object_path) {
    fprintf(stderr, "curl_existence_probe: the scratch path for \"%s\" does not "
                    "fit in %d bytes.\n", stem, (int)sizeof source_path);
    return 2;
  }

  /* Written as a file rather than piped on stdin, so the compiler has a stable
   * path to name in its diagnostics and the cache directory holds one file per
   * answer instead of nothing at all. */
  {
    FILE *out = fopen(source_path, "wb");
    if (out == NULL) {
      fprintf(stderr, "curl_existence_probe: cannot open \"%s\" for writing: "
                      "%s\n", source_path, strerror(errno));
      return 2;
    }
    if (fwrite(source, 1, strlen(source), out) != strlen(source) ||
        fclose(out) != 0) {
      fprintf(stderr, "curl_existence_probe: cannot write the probe for \"%s\" "
                      "to \"%s\": %s\n", stem, source_path, strerror(errno));
      return 2;
    }
  }

  /* One pipe, carrying one bit: *did `execv` actually start the compiler*.
   *
   * Without it the two cases are the same event. `execv` returns when it
   * fails, and the child then `_exit(2)`s - so a compiler that is not on disk,
   * is not executable, or is a directory arrives at the parent as an ordinary
   * non-zero exit status, which is indistinguishable from "the target does not
   * declare this function". Every row would then be answered `no`, the facts
   * file would be complete and internally consistent, and `check_function_rows`
   * would have nothing to object to: an unmeasurable toolchain wearing the
   * exact shape of a measured "the target has none of these". Measured on this
   * collector, 48 of 48 `no` and exit 0 for a `zig` path that does not exist.
   *
   * The write end is close-on-exec, so the parent's read is the question
   * itself: end-of-file means `execv` succeeded and the compiler owns the
   * process, and a byte means `execv` returned and the child is still the
   * child. This is the one fact that separates "the compiler said no" from
   * "the compiler never ran", and it costs one descriptor per probe. */
  if (pipe(exec_pipe) != 0) {
    fprintf(stderr, "curl_existence_probe: cannot make the exec-status pipe "
                    "for \"%s\": %s\n", stem, strerror(errno));
    return 2;
  }
  if (fcntl(exec_pipe[1], F_SETFD, FD_CLOEXEC) != 0) {
    fprintf(stderr, "curl_existence_probe: cannot mark the exec-status pipe "
                    "close-on-exec for \"%s\": %s\n", stem, strerror(errno));
    close(exec_pipe[0]);
    close(exec_pipe[1]);
    return 2;
  }

  pid = fork();
  if (pid < 0) {
    fprintf(stderr, "curl_existence_probe: cannot fork for the \"%s\" probe: "
                    "%s\n", stem, strerror(errno));
    close(exec_pipe[0]);
    close(exec_pipe[1]);
    return 2;
  }
  /* The parent holds no copy of the write end, or the read below would never
   * see end-of-file. The child has its own descriptor from `fork` and is
   * unaffected by this close. */
  close(exec_pipe[1]);
  if (pid == 0) {
    /* The child. `zig cc` is spelled as argv[0]=zig with `cc` as argv[1],
     * exactly as `addHeaderProbe` spells it.
     *
     * The child's stderr goes to /dev/null before the compiler starts, and that
     * is not tidiness: a function the target does not declare, or a member its
     * `<netinet/in.h>` does not carry, is *answered* by the compiler's
     * diagnostic, so on any target missing one of these several probes print
     * "use of undeclared identifier". Zig's build runner displays a step's
     * stderr even when the step succeeds and prints its `failed command:`
     * banner for it, so leaving that output attached would make a green build
     * read as a red one. The exit status is the answer this file is after, and
     * a diagnostic that is the answer does not also need to be printed.
     *
     * The failures that are *not* answers still print: a fork failure, a
     * compiler that was killed, and the refusal messages in this file all go to
     * the real stderr, and they are the cases a reader must see. */
    int devnull = open("/dev/null", O_WRONLY);
    if (devnull >= 0) {
      (void)dup2(devnull, STDERR_FILENO);
      if (devnull > STDERR_FILENO)
        close(devnull);
    }
    {
      /* The `argv` array is built after the redirect so the compiler's own
       * `open` calls cannot be disturbed by it; `char *const argv[]` is a local,
       * so its lifetime is this block and `execv` never returns. */
      char *const argv[] = {
        (char *)zig_exe, (char *)"cc", (char *)"-target", (char *)triple,
        (char *)flags, (char *)"-c", (char *)"-o", object_path, source_path, NULL
      };
      execv(zig_exe, argv);
    }
    /* Reached only when `execv` failed. The descriptor is still open - it is
     * closed by a *successful* exec, not by this one - so this write is the
     * parent-visible fact that no compiler ever ran. */
    {
      const char exec_failed = 1;
      ssize_t written = write(exec_pipe[1], &exec_failed, 1);
      (void)written;
    }
    _exit(2);
  }

  if (waitpid(pid, &status, 0) < 0) {
    fprintf(stderr, "curl_existence_probe: cannot wait for the \"%s\" probe: "
                    "%s\n", stem, strerror(errno));
    close(exec_pipe[0]);
    return 2;
  }
  if (WIFSIGNALED(status)) {
    fprintf(stderr, "curl_existence_probe: the compiler was killed by signal %d "
                    "while probing \"%s\". That is not an answer about %s.\n",
            WTERMSIG(status), stem, label);
    close(exec_pipe[0]);
    return 2;
  }
  {
    char exec_byte;
    const ssize_t got = read(exec_pipe[0], &exec_byte, 1);

    close(exec_pipe[0]);
    if (got > 0) {
      fprintf(stderr, "curl_existence_probe: cannot execute \"%s\" to probe "
                      "\"%s\". That is not an answer about %s, and answering "
                      "\"no\" for every row would hand the generator a complete "
                      "facts file that says the target declares none of them.\n",
              zig_exe, stem, label);
      return 2;
    }
    if (got < 0) {
      fprintf(stderr, "curl_existence_probe: cannot read the exec-status pipe "
                      "for \"%s\": %s\n", stem, strerror(errno));
      return 2;
    }
  }
  return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 1 : 0;
}

/* One function row: render, then run. */
static int probe_function(const char *zig_exe, const char *triple,
                          const char *flags, const char *preamble,
                          const char *scratch_dir, const char *name,
                          const char *group, unsigned row_flags) {
  char decls[256];
  char source[4096];

  if (includes_for_group(group, decls, sizeof decls) < 0) {
    fprintf(stderr,
            "curl_existence_probe: \"%s\" names the declaration group \"%s\", "
            "which is not in probe_groups. A probe with no declaration header "
            "would measure nothing and be recorded as a \"no\", so this is "
            "refused.\n", name, group);
    return 2;
  }
  if (curl_probe_source_for(preamble, decls, name, row_flags, source,
                            sizeof source) < 0) {
    fprintf(stderr,
            "curl_existence_probe: the probe for \"%s\" does not fit in %d "
            "bytes. A truncated probe would measure nothing and be recorded as "
            "a \"no\", so this is refused.\n", name, (int)sizeof source);
    return 2;
  }
  return run_probe(zig_exe, triple, flags, scratch_dir, name, source, name);
}

/* One member row: render, then run. The `decls` buffer is four times the
 * function one because the `sockaddr_in6` group is the only group that carries
 * more than one include per shape, and a truncated include block would compile
 * to a struct that does not exist and be recorded as a confident `no`. */
static int probe_member(const char *zig_exe, const char *triple,
                        const char *flags, const char *preamble,
                        const char *scratch_dir, const char *type,
                        const char *name, const char *group) {
  char decls[1024];
  char source[4096];
  char stem[512];

  if (includes_for_group(group, decls, sizeof decls) < 0) {
    fprintf(stderr,
            "curl_existence_probe: the member row struct %s names the "
            "declaration group \"%s\", which is not in probe_groups. A probe "
            "with no declaration header would measure nothing and be recorded "
            "as a \"no\", so this is refused.\n", type, group);
    return 2;
  }
  if (snprintf(stem, sizeof stem, "%s__%s", type, name) >=
      (int)sizeof stem) {
    fprintf(stderr, "curl_existence_probe: the member %s::%s does not fit in "
                    "%d bytes.\n", type, name, (int)sizeof stem);
    return 2;
  }
  if (curl_probe_member_source_for(preamble, decls, type, name, source,
                                   sizeof source) < 0) {
    fprintf(stderr,
            "curl_existence_probe: the probe for struct %s::%s does not fit in "
            "%d bytes. A truncated probe would measure nothing and be recorded "
            "as a \"no\", so this is refused.\n", type, name,
            (int)sizeof source);
    return 2;
  }
  return run_probe(zig_exe, triple, flags, scratch_dir, stem, source, stem);
}
/* The control probe: one compile that must succeed, asked once before any real
 * row.
 *
 * `run_probe`'s exec-status pipe separates "the compiler said no" from "the
 * compiler never started", but it cannot separate "the compiler rejected this
 * *declaration*" from "the compiler rejected its own *command line*". Both are
 * exit 1: a typo in the triple, a flag this `zig cc` does not know, a target
 * with no libc for the compiler to find. Measured on this collector, an
 * unparsable triple and an unknown flag each produced 48 of 48 `no` and exit
 * 0, and the facts file passed `check_function_rows` because every row *had* an
 * answer - the wrong one, arrived at uniformly.
 *
 * So the first compile is a declaration that cannot be absent: a static
 * function of this file's own, with no header, no macro and no target symbol in
 * it. Every target's compiler accepts that. If it does not, then nothing this
 * run could have said about any row would be an answer about the target, and
 * the whole facts file is refused rather than written - one refused run instead
 * of 48 confident `no` lines that a reader has no reason to doubt.
 *
 * It is asked through `run_probe` like every other probe, so it is subject to
 * the same exec-status pipe: a compiler that cannot start fails this too, and
 * the refusal message names the probe. */
static int probe_control(const char *zig_exe, const char *triple,
                         const char *flags, const char *scratch_dir) {
  static const char control_source[] =
      "int curl_probe_control_symbol(void) { return 0; }\n"
      "enum { curl_probe_control = 1 / !!curl_probe_control_symbol };\n";

  return run_probe(zig_exe, triple, flags, scratch_dir, "control",
                   control_source, "the compiler's own command line");
}


/* argv: <zig> <triple> <flags> <libc> <output-path>
 *
 * Five arguments, and the scratch directory is *not* one of them: it is the
 * output file's own directory, which the build has already made by the time this
 * runs. One path for the answers and one place for the probes is one fewer
 * argument that can disagree with itself, and there is no scratch directory to
 * create under a path this program would otherwise have to invent.
 *
 * The flags are a single string, passed through to each `zig cc` verbatim.
 * `-std=gnu99` is the dialect the 196 library units are compiled as, and a probe
 * compiled as a different dialect would answer a different question about which
 * declarations the target has.
 *
 * `libc` is `build.zig`'s `generatorLibc` value - the *same* string the
 * generator is given for `--libc`. It is an argument rather than something
 * derived here on purpose: this program and `curl_config_gen.c` both have to
 * know whether the target is glibc, and if they each decided it separately they
 * would eventually disagree, which is exactly what happened when this probe
 * keyed `_GNU_SOURCE` on `__linux__` alone. One fact, one source, passed to
 * both. */
int main(int argc, char **argv) {
  const char *zig_exe;
  const char *triple;
  const char *flags;
  const char *libc;
  const char *output;
  const char *slash;
  const char *preamble;
  char scratch[4096];
  size_t scratch_len;
  FILE *out;
  int refusals = 0;

  if (argc != 6) {
    fprintf(stderr,
            "curl_existence_probe: expected <zig> <triple> <flags> <libc> "
            "<output-path>, got %d arguments.\n", argc - 1);
    return 2;
  }
  zig_exe = argv[1];
  triple = argv[2];
  flags = argv[3];
  libc = argv[4];
  output = argv[5];

  /* Exactly the generator's condition, and no wider. See `probe_preamble_gnu`
   * for why this is not `__linux__` and why the two artifacts must be handed
   * the same libc rather than each deciding it. */
  if (strcmp(libc, "gnu") == 0) {
    preamble = probe_preamble_gnu;
  } else {
    preamble = probe_preamble_none;
  }

  /* The scratch directory is spelled out of the output path rather than taken as
   * an argument. `strrchr` finds the last slash; a path with none has no
   * directory to speak of, which is a refusal rather than a fall back to the
   * current directory - the probes would then land wherever the build runner
   * happened to be, and that is not a path anyone chose. */
  slash = strrchr(output, '/');
  if (slash == NULL) {
    fprintf(stderr, "curl_existence_probe: the output path \"%s\" has no "
                    "directory, so there is nowhere to keep the %d probes. Give "
                    "a path the build owns.\n", output, CURL_FUNCTION_COUNT);
    return 2;
  }
  scratch_len = (size_t)(slash - output);
  if (scratch_len + 1 > sizeof scratch) {
    fprintf(stderr, "curl_existence_probe: the directory of \"%s\" is longer "
                    "than %d bytes.\n", output, (int)sizeof scratch);
    return 2;
  }
  memcpy(scratch, output, scratch_len);
  scratch[scratch_len] = '\0';
  /* Before the answers, not after: a control that fails means no row below it
   * would have been an answer, so nothing is written at all. */
  if (probe_control(zig_exe, triple, flags, scratch) != 1) {
    fprintf(stderr,
            "curl_existence_probe: the compiler did not accept a translation "
            "unit with no header, no macro and no target symbol in it, for "
            "target \"%s\" with flags \"%s\". That is a refusal, not an answer: "
            "the triple, the flags or the target's C library are not usable, "
            "and running the rows now would record \"no\" for every one of the "
            "%d function rows and the %d member row, and hand the generator a "
            "complete, internally consistent facts file that says the target "
            "declares none of them. No facts file was written.\n",
            triple, flags, CURL_FUNCTION_COUNT, CURL_MEMBER_COUNT);
    return 2;
  }

  out = fopen(output, "wb");
  if (out == NULL) {
    fprintf(stderr, "curl_existence_probe: cannot open \"%s\" for writing: "
                    "%s\n", output, strerror(errno));
    return 2;
  }

  /* Every function row first, then every member row, in table order. Both loops
   * go into the one output file and each line carries its own marker, so the
   * generator's two readers split the file by marker rather than by position.
   * A refusal in either loop is counted, not skipped past: the file is not
   * completed and this program exits non-zero, so a missing answer can never be
   * read as a confident `no`. */
  for (int i = 0; i < CURL_FUNCTION_COUNT; i++) {
    const int answer = probe_function(zig_exe, triple, flags, preamble, scratch,
                                      curl_function_rows[i].name,
                                      curl_function_rows[i].group,
                                      curl_function_rows[i].flags);

    if (answer == 2) {
      refusals++;
      continue;
    }
    /* The line names the *function*, because the function is what the probe
     * measured. The generator's `function_rows` maps it back to the row, and
     * `check_function_rows` refuses a fact no row asks about - so printing the
     * row here as well would only add a second spelling for the two sides to
     * disagree about. */
    fprintf(out, "%s \"%s\" %s\n", CURL_FUNCTION_MARKER,
            curl_function_rows[i].name, answer == 1 ? "yes" : "no");
  }

  for (int i = 0; i < CURL_MEMBER_COUNT; i++) {
    const int answer = probe_member(zig_exe, triple, flags, preamble, scratch,
                                    curl_member_rows[i].type,
                                    curl_member_rows[i].name,
                                    curl_member_rows[i].group);

    if (answer == 2) {
      refusals++;
      continue;
    }
    /* `struct::member`, because a bare member name is not a key: the generator
     * has to be able to tell two structs' same-named members apart, and it looks
     * the answer up by exactly this string in `member_rows`. */
    fprintf(out, "%s \"%s::%s\" %s\n", CURL_MEMBER_MARKER,
            curl_member_rows[i].type, curl_member_rows[i].name,
            answer == 1 ? "yes" : "no");
  }

  if (fclose(out) != 0) {
    fprintf(stderr, "curl_existence_probe: cannot finish writing \"%s\": %s\n",
            output, strerror(errno));
    return 2;
  }
  if (refusals != 0) {
    fprintf(stderr,
            "curl_existence_probe: %d of the %d probes could not be run at all. "
            "That is a refusal, not an answer, so no facts file was completed "
            "for this target.\n", refusals,
            CURL_FUNCTION_COUNT + CURL_MEMBER_COUNT);
    return 2;
  }
  return 0;
}

#else /* !CURL_EXISTENCE_COLLECTOR */

/* ========================================================================= */
/* TABLE HALF                                                                  */
/* ========================================================================= */

/* Without `-DCURL_EXISTENCE_COLLECTOR` this file is the table and nothing else.
 * It is not compiled by the build: `build.zig` compiles it once for the host
 * with that macro, and the probe translation units the collector writes are the
 * ones the *target* compiler sees. The half exists so that a reader who greps
 * this file for one function name finds the row and the reason, whether they
 * came for the loop or for the table.
 */

/* The two renders `curl_probe_source_for` and `curl_probe_member_source_for`
 * produce, spelled out next to the tables they apply to, so neither can drift
 * away unnoticed.
 *
 * This is what a *function* row renders - `accept4` in the `socket_or_winsock`
 * group, on a target that is not glibc, so `preamble` is empty:
 *
 *     #ifdef _WIN32
 *     #include <winsock2.h>
 *     #else
 *     #include <sys/socket.h>
 *     #endif
 *     enum { curl_probe_dummy = 1 / !!accept4 };
 *
 * On the Darwin headers Zig ships `accept4` is not declared, so the compile
 * fails and the facts file carries `CURL_FUNCTION "accept4" no`. That single
 * line is what turns `HAVE_ACCEPT4` off for that target, and it is what
 * `lib/cf-socket.c:2298` needs: without it the unit calls a function that does
 * not exist there.
 *
 * And this is what the one *member* row renders on a Unix target - upstream's
 * `configure.ac:1826-1829` body, in a translation unit:
 *
 *     #include <sys/types.h>
 *     #ifdef _WIN32
 *     #include <winsock2.h>
 *     #include <ws2tcpip.h>
 *     #else
 *     #include <netinet/in.h>
 *     #ifdef __TANDEM
 *     #include <netinet/in6.h>
 *     #endif
 *     #endif
 *     static void curl_probe_member(struct sockaddr_in6 *p)
 *     {
 *       p->sin6_scope_id = 0;
 *     }
 *     enum { curl_probe_dummy = 1 / !!curl_probe_member };
 *
 * The answer to that one is what decides
 * `HAVE_SOCKADDR_IN6_SIN6_SCOPE_ID` on every architecture, which is why this
 * file no longer holds a list of architectures at all.
 */

int curl_existence_probe_table_half_is_not_compiled(void);

#endif /* CURL_EXISTENCE_COLLECTOR */