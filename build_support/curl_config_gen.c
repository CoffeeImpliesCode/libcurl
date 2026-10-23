/* SPDX-License-Identifier: curl
 * See FORK-LICENSE.md for what that identifier covers.
 *
 * curl_config_gen.c - the generated input for this fork of libcurl, as code.
 *
 * WHY THIS FILE EXISTS
 * --------------------
 * `lib/curl_setup.h:140` does `#include \"curl_config.h\"`, and that header is
 * the one thing upstream generates at configure time. Upstream generates it
 * with autoconf (`lib/curl_config.h.in`) or CMake
 * (`lib/curl_config-cmake.h.in`). This package executes neither, and AGENTS.md
 * section 5 forbids the alternative - a hand-written stand-in. So the generated
 * input is this program: a deterministic step that runs on the *build host* and
 * emits a `curl_config.h` for the *target being built*.
 *
 * WHAT IT READS AND WHAT IT DELIBERATELY DOES NOT
 * ------------------------------------------------
 * The target's OS tag, architecture, pointer width, byte order and libc name
 * arrive as command-line arguments, and nothing else. There is no `#ifdef` on
 * any host macro anywhere in this file, no `__linux__`, no `sizeof` of a host
 * type, no `#include <unistd.h>`, and no probe of its own. Running this program
 * on an x86_64 Linux host to configure `aarch64-macos-none` is the correct use,
 * not a bug: copying the host's platform macros onto a cross target is
 * precisely the failure AGENTS.md section 5 forbids.
 *
 * HEADER EXISTENCE IS A PROBE, NOT A FAMILY
 * -----------------------------------------
 * A row whose template comment says "if you have the <x> header file" is a
 * claim about a directory on the target, and no OS family, architecture,
 * pointer width, byte order or libc name determines it. Deciding such a row
 * from the family mask alone - which is what an earlier revision of this file
 * did for all 35 of them - asserts a fact about the target's headers that
 * nobody checked. On the glibc Zig ships, `<netinet/in6.h>` and `<sys/utime.h>`
 * are absent, so `HAVE_NETINET_IN6_H 1` turned on five `#include
 * <netinet/in6.h>` sites and 100 C units failed to compile with "file not
 * found".
 *
 * So those rows carry the `X_HEADER` flag and their value comes from
 * `--header-facts`: a file of `yes|no` answers that the caller measured for
 * the *target* by compiling `build_support/curl_headers_probe.c` with the
 * target's own compiler and the target's own include path. That is the shape
 * of upstream's `AC_CHECK_HEADERS`, which runs the target compiler once per
 * header and records what it found. `build.zig` runs that probe as a build
 * step; this program compiles nothing and looks at no header itself, so
 * running it on the host to configure a cross target stays correct.
 *
 * `--header-facts` is required and has no default, and this program refuses
 * rather than guessing in both directions: a header-existence row with no
 * answer, and an answer for a header no such row names, both stop the run.
 * Seven header rows carry no family at all - `<lber.h>`, `<ldap_ssl.h>`,
 * `<idn2.h>`, `<proto/bsdsocket.h>`, `<termio.h>`, `<uv.h>` and `NEED_LBER_H`
 * - because they are off for a different and already-stated reason, that the
 * library needing them is not a dependency of this package. They ask for no
 * fact, and the probe does not answer for them.
 *
 * FUNCTION EXISTENCE IS A PROBE, NOT A FAMILY
 * ------------------------------------------
 * The same argument one step further out. A row whose template comment says "if
 * you have the `x' function" is a claim about a *declaration* in the target's
 * headers, and no OS family, architecture, pointer width, byte order or libc
 * name determines it. 47 of those rows decided from the family mask alone
 * asserted facts nobody checked, and two of them were wrong on the very target
 * this package is built for: the Darwin headers Zig ships declare neither
 * `accept4` nor `memrchr`, so `HAVE_ACCEPT4` and `HAVE_MEMRCHR` came out
 * defined and `lib/cf-socket.c:2298` and `lib/cookie.c:168` called functions
 * the target does not have.
 *
 * So those rows carry the `X_FUNCTION` flag and their value comes from
 * `--function-facts`: a file of `yes|no` answers the caller measured for the
 * *target* by compiling one probe per function with
 * `build_support/curl_existence_probe.c` and the target's own compiler. That is
 * the shape of upstream's `AC_CHECK_FUNCS`, and `CMakeLists.txt`'s
 * `check_function_exists` is the same idea one symbol at a time. `build.zig`
 * runs that probe as a build step; this program compiles nothing and looks at
 * no header itself, so running it on the host to configure a cross target
 * stays correct.
 *
 * `--function-facts` is required and has no default, and this program refuses
 * rather than guessing in both directions: a function-existence row with no
 * answer, and an answer for a function no such row names, both stop the run.
 * `function_row` below is the name-to-function map the flag indexes, and
 * `check_function_rows` fails the run if the flag, the map and the fact file
 * ever disagree.
 *
 * What this class cannot measure is named at its rows and in the probe's own
 * header comment rather than left to be discovered later: a row asserting that
 * a *macro* works, or that a function is *thread-safe*, is a different question,
 * and pretending otherwise would be the exact defect `X_HEADER`, `X_FUNCTION`
 * and `X_MEMBER` exist to remove.
 *
 * STRUCT-MEMBER EXISTENCE IS A PROBE, NOT AN ARCHITECTURE
 * -------------------------------------------------------
 * The same argument one step further out again, and the one that cost this
 * repository seven cells of its published 53-platform matrix before it was
 * applied. `HAVE_SOCKADDR_IN6_SIN6_SCOPE_ID` asks whether the target's
 * `<netinet/in.h>` lets curl assign `s.sin6_scope_id`. That answer really is a
 * property of the target rather than of the family mask - which is why this file
 * used to carry a closed list of architectures that have it and a closed list
 * of architectures that do not, and refused by name anything in neither.
 *
 * Both lists were narrower than the platform matrix this package claims to
 * support, and refused `armeb`, `powerpc64`, `powerpc64le`, `hexagon`, `mipsel`,
 * `thumb` and `riscv32` - seven cells - over a question upstream answers with
 * one compile at `configure.ac:1812-1831`.
 *
 * So the row carries `X_MEMBER` now and its value comes from `--member-facts`: a
 * `yes|no` answer the caller measured for the *target* by compiling one probe
 * per member with `build_support/curl_existence_probe.c`, upstream's own
 * technique. The architecture tables are deleted rather than widened, so no
 * architecture can be missing from a list that no longer exists, and the row is
 * measured on every family instead of asserted on four of them.
 *
 * `--member-facts` is required and has no default, and this program refuses
 * rather than guessing in both directions, exactly as the other two classes do.
 * `member_row` is the name-to-member map the flag indexes and `check_member_rows`
 * fails the run if the flag, the map and the fact file ever disagree.
 *
 * DETERMINISM
 * -----------
 * Same arguments, same bytes, every time. The output is a fixed table walked in
 * one order, with no clock, no locale-dependent formatting, no randomness and no
 * environment read. Two of the arguments (`--ca-bundle`, `--ca-path`) are copied
 * through verbatim, so the build's own options are the only thing that can move
 * a byte.
 *
 * THE TABLE IS THE ANSWER, NOT BRANCHING
 * ---------------------------------------
 * Every entry below is one row of `struct entry`, and whether it is defined is
 * decided by that row's family mask and flag mask against the parsed arguments.
 * The alternative - an `if` per entry - would be the same information spread
 * across the file with the reasons detached from the rows. Two places compute
 * a value rather than look one up: the `SIZEOF_*` block, because those are
 * arithmetic on the pointer width and the family, and the `X_HEADER` rows,
 * because those are the ones the caller measured. `header_row` below is the
 * name-to-header map those flags index, and `check_header_rows` fails the run
 * if the flag, the map and the fact file ever disagree.
 *
 * ORDERING
 * --------
 * Rows appear in the order of `lib/curl_config-cmake.h.in`, and each row carries
 * that template's own comment, verbatim. An entry this configuration does not
 * set is written the way CMake's own `configure_file` writes an unset
 * `#cmakedefine`: as a C comment whose body is `#undef NAME`. That is a
 * deliberate choice - a reader diffing this header against the template must see
 * which entries were decided rather than guess from an absence. The literal is
 * spelled in prose rather than written out, because a slash-star sequence here
 * would close this comment and turn the rest of the header into C.
 *
 * REFUSING INSTEAD OF GUESSING
 * ----------------------------
 * Where a value is genuinely target-dependent and the arguments do not determine
 * it, this program stops with a message naming the argument it needed. It does
 * not emit a default. Four things in this build are refused this way and all
 * four are load-bearing:
 *
 *   - `--header-facts` carries the whole of the header-existence answer, as the
 *     section above sets out. All 35 rows that ask a question about a directory
 *     on the target read their value from that one file, and a missing,
 *     unreadable, malformed, incomplete or over-complete file stops the run
 *     before a byte is written.
 *
 *   - `--function-facts` and `--member-facts` carry the function-existence and
 *     member-existence answers, as their sections set out. All 47 function rows
 *     and the one member row read their value from those two reads of the same
 *     file, and a missing, unreadable, malformed, incomplete or over-complete
 *     file stops the run before a byte is written.
 *
 *   - `HAVE_MBEDTLS_DES_CRYPT_ECB` is a property of the mbed-TLS *headers*, not
 *     of the operating system, architecture, pointer width, byte order or libc.
 *     No argument above determines it, so `--mbedtls-des-crypt-ecb yes|no` is
 *     required and there is no default. `build.zig` supplies it for the resolved
 *     mbed-TLS release; see `build.zig` for why that value is a named fact and
 *     not a guess.
 *
 * `--arch` is still required, and is still the architecture's own spelling,
 * because `CURL_HOST` is built from it. What changed is that no row *decides*
 * anything from it any more: the one row that used to consult an architecture
 * table for `HAVE_SOCKADDR_IN6_SIN6_SCOPE_ID` is measured now, and the width the
 * `SIZEOF_*` arithmetic uses arrives as `--pointer-width` from `build.zig`,
 * which resolves it from Zig's own target rather than from a table here.
 *
 * Compile: for the host, with `-Wall -Wextra -Wpedantic`. Nothing in this file
 * writes to a file other than the path given by `--output`, it creates no
 * directories, and the only files it reads are the ones given by
 * `--header-facts`, `--function-facts` and `--member-facts`: `build.zig` hands
 * each of them a path inside a directory the cache already made.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------------- */
/* The target's facts, and nothing else.                                      */
/* ------------------------------------------------------------------------- */

/* The families this generator can describe. An OS tag outside this set is
 * refused, not approximated: the per-family answers below are statements about
 * a C library, and "roughly POSIX" is not one of them. */
enum family {
  FAM_LINUX,
  FAM_BSD,
  FAM_SOLARIS,
  FAM_MACOS,
  FAM_WINDOWS,
  FAM_COUNT
};

/* One measured answer: does the *target* have this header? `header` is the
 * `<...>` spelling the template's own comment uses, so the fact file, the map
 * below and the emitted comment all name a file the same way.
 *
 * Declared before `struct facts` because a struct tag first used inside
 * another struct's member list is scoped to that struct, which would give the
 * pointer below and this definition two different incompatible types. */
struct header_fact {
  const char *header; /* e.g. "netinet/in6.h" */
  int present;        /* 1 the target's compiler found it, 0 it did not */
};

/* One measured answer: does the *target* declare the function `name`? Spelled
 * the same shape as `struct header_fact` and for the same reason: the fact
 * file, the map below and the probe all name the same identifier, so a
 * disagreement is about a function rather than about a spelling.
 *
 * Declared before `struct facts` for the reason the header one is. */
struct function_fact {
  const char *name; /* e.g. "accept4" */
  int present;      /* 1 the target's compiler accepts it, 0 it does not */
};

/* One measured answer: can the *target*'s headers be asked to assign
 * `member`? Spelled the same shape as `struct function_fact` and for the same
 * reason. `member` is the `"<struct>::<member>"` key
 * `build_support/curl_existence_probe.c` prints and `member_rows` maps back
 * from, so the probe, the map and the fact file all name the member the same
 * way.
 *
 * Declared before `struct facts` for the reason the other two are. */
struct member_fact {
  const char *member; /* e.g. "sockaddr_in6::sin6_scope_id" */
  int present;        /* 1 the target's compiler accepted the assignment, 0 not */
};

struct facts {
  const char *os;           /* the --os argument, verbatim */
  const char *arch;         /* the --arch argument, verbatim */
  const char *libc;         /* the --libc argument, verbatim */
  const char *endian;       /* "little" or "big" */
  int pointer_width;        /* 32 or 64, from --pointer-width */
  enum family family;       /* which family --os selected */
  int des_crypt_ecb;        /* --mbedtls-des-crypt-ecb: 1 yes, 0 no */
  const char *ca_bundle;    /* --ca-bundle, or NULL when the option was absent */
  const char *ca_path;      /* --ca-path, or NULL when the option was absent */
  const struct header_fact *header_facts; /* --header-facts, parsed */
  size_t header_fact_count;
  const struct function_fact *function_facts; /* --function-facts, parsed */
  size_t function_fact_count;
  const struct member_fact *member_facts; /* --member-facts, parsed */
  size_t member_fact_count;
};

/* Family masks. A row's `families` field is a mask of these. */
#define M_LINUX (1u << FAM_LINUX)
#define M_BSD (1u << FAM_BSD)
#define M_SOLARIS (1u << FAM_SOLARIS)
#define M_MACOS (1u << FAM_MACOS)
#define M_WINDOWS (1u << FAM_WINDOWS)
#define M_UNIX (M_LINUX | M_BSD | M_SOLARIS | M_MACOS)
#define M_ALL (M_UNIX | M_WINDOWS)

/* Conditions that are not the family. A row's `flags` field is a mask of these
 * and every one of them must hold for the row to be defined. */
#define X_DES_ECB (1u << 0)  /* and --mbedtls-des-crypt-ecb was "yes" */
#define X_GNU (1u << 1)      /* and --libc is gnu */
#define X_NOT_GNU (1u << 2)  /* and --libc is not gnu */
#define X_64 (1u << 3)       /* and --pointer-width is 64 */
#define X_32 (1u << 4)       /* and --pointer-width is 32 */
/* There is deliberately no endian flag here. `--endian` is still required and
 * still validated, but no row of the table is gated on it: curl's own byte-order
 * handling reads the compiler's `__BYTE_ORDER__`, not this configuration. See
 * the byte-order note in the table and this file's own header comment. */
/* A struct-member-existence row: neither the family's mask nor the
 * architecture decides it, the measured answer in `--member-facts` does. The
 * same argument as `X_FUNCTION` below, and the proof that a table could not
 * stand in for it is this repository's own 53-platform matrix: the answer was
 * taken from a closed list of architectures, and that list refused
 * `armeb-linux`, `powerpc64-linux`, `powerpc64le-linux`, `hexagon-linux`,
 * `mipsel-linux`, `thumb-linux` and `riscv32-linux` over a question the target
 * compiler answers in one compile. It was bit 5 while `HAVE_SOCKADDR_IN6_SIN6_
 * SCOPE_ID` was the only row carrying it; the number is kept so no other flag
 * silently moves. */
#define X_MEMBER (1u << 5) /* and --member-facts says the member is assignable */
/* A header-existence row: the family's directories do not decide it, the
 * measured answer in `--header-facts` does. See "HEADER EXISTENCE IS A PROBE,
 * NOT A FAMILY" above for why a family mask cannot stand in for the check. */
#define X_HEADER (1u << 6)

/* A function-existence row: the family's mask does not decide it, the measured
 * answer in `--function-facts` does. Same argument as `X_HEADER` above, one
 * step further out: a header is a file the target may or may not ship, and a
 * function is a *declaration* the target's headers may or may not contain.
 * `HAVE_ACCEPT4` was the proof that the family mask cannot stand in for the
 * check: Darwin headers do not declare `accept4`, and the row claimed it. */
#define X_FUNCTION (1u << 7)

/* How a row's value is spelled on the way out. */
enum shape {
  SH_FLAG,   /* #define NAME 1 */
  SH_STRING, /* #define NAME "value" */
  SH_SIZE    /* #define NAME <computed by size_of()> */
};

struct entry {
  unsigned families;  /* defined for these families */
  unsigned flags;     /* and only when all of these hold */
  const char *name;
  const char *comment; /* the template's own comment, verbatim */
  const char *value;   /* literal text for SH_STRING; NULL for SH_FLAG */
  enum shape shape;
};

/* Which `<...>` file an `X_HEADER` row is asking about.
 *
 * This map is what makes the class of header-existence rows a class rather than
 * 35 coincidences. Every row whose template comment says "if you have the <x>
 * header file" carries `X_HEADER` in `entries` and has an entry here; every
 * entry here names a row in `entries` that carries `X_HEADER`. Nothing in this
 * file knows which header a row implies - the map says so, in one place, and
 * `check_header_rows` refuses the run if the map, the flags and the fact file
 * ever disagree. Adding a header row therefore means adding a row here too, and
 * forgetting is a refusal rather than a silent wrong answer.
 *
 * The `<...>` spelling is the template's own, so the map, the probe file and
 * the emitted comment all name a file the same way and a reader can match them
 * against `lib/curl_config-cmake.h.in` without a translation. */
struct header_row {
  const char *name;   /* the entry name in `entries`, e.g. HAVE_NETINET_IN6_H */
  const char *header; /* the file, without angle brackets */
};

/* Which function an `X_FUNCTION` row is asking about.
 *
 * The same argument as `header_row`, one step out: every row whose template
 * comment says "if you have the `x' function" carries `X_FUNCTION` and has an
 * entry here, and every entry here names a row that carries it. This file
 * knows nothing about which header declares the function - the map says, in one
 * place - so `check_function_rows` can refuse the run when the flags, the map
 * and `--function-facts` disagree in any of the three directions. */
struct function_row {
  const char *name;      /* the entry name in `entries`, e.g. HAVE_ACCEPT4 */
  const char *function;  /* the C identifier, e.g. accept4 */
};

/* Which struct member an `X_MEMBER` row is asking about.
 *
 * The same argument as `header_row` and `function_row`, one step further out:
 * every row whose template comment says "if struct X has the M member" carries
 * `X_MEMBER` and has an entry here, and every entry here names a row that
 * carries it. The `member` spelling is `"<struct>::<member>"`, which is what
 * `build_support/curl_existence_probe.c` prints, so the probe, the map and the
 * fact file name the member identically. */
struct member_row {
  const char *name;   /* the entry name in `entries`, e.g.
                       * HAVE_SOCKADDR_IN6_SIN6_SCOPE_ID */
  const char *member; /* the member, e.g. "sockaddr_in6::sin6_scope_id" */
};

/* The token `build_support/curl_existence_probe.c` emits in front of every
 * *member* answer, spelled once here and once there. It is a second token
 * rather than a third spelling of the function one because both kinds of line
 * share one facts file: each reader skips anything that does not start with its
 * own marker, so neither can read the other's line as an answer. */
#define CURL_MEMBER_MARKER "CURL_MEMBER"

/* The token `build_support/curl_existence_probe.c` emits in front of every
 * function answer, spelled once here and once there. A bare identifier, like the
 * header marker's, so nothing rewrites it and a fact file's lines are
 * recognisable. `read_function_facts` skips anything that does not start with
 * it, which is also what keeps it from reading a `CURL_MEMBER` line. */
#define CURL_FUNCTION_MARKER "CURL_FUNCTION"

/* The token `build_support/curl_headers_probe.c` emits in front of every answer,
 * spelled once here and once there. It is a bare identifier rather than a macro
 * so the preprocessor passes it through verbatim, and it is what tells an
 * answer line apart from the line markers and blank lines around it in `-E`
 * output. `read_header_facts` skips anything that does not start with it. */
#define CURL_HEADER_MARKER "CURL_HEADER"

/* --ca-bundle and --ca-path are the two rows whose value is not a constant: it
 * is whatever the build's own options said. `value` selects which argument. */
#define FROM_CA_BUNDLE "\001ca-bundle"
#define FROM_CA_PATH "\001ca-path"

/* ------------------------------------------------------------------------- */
/* SIZEOF_*                                                                   */
/* ------------------------------------------------------------------------- */

/* `lib/curl_config-cmake.h.in:616-642` fills these seven rows from CMake's
 * CheckTypeSize, i.e. from a compile probe of the *target*. This generator has
 * no probe, so it computes them, and it computes them from the two facts that
 * determine them:
 *
 *   int            4, always. Every platform this generator accepts has a
 *                  32-bit int; `lib/curl_setup.h:630-632` uses exactly this
 *                  relation to reject a configuration where long exceeds
 *                  size_t, which cannot happen for these answers.
 *   size_t         the pointer width.
 *   long           the pointer width on every LP64 and ILP32 target, and 4 on
 *                  Windows, which is LLP64. Upstream's own hand-written Windows
 *                  configuration says so: `lib/config-win32.h:77-85` pins
 *                  SIZEOF_LONG 4 and only widens SIZEOF_SIZE_T under _WIN64.
 *   curl_socket_t  4 on everything except 64-bit Windows. Same two places:
 *                  `lib/config-win32.h:79-85` splits on _WIN64, and
 *                  `lib/curl_setup.h:535-543` keys its own default on
 *                  `USE_WINSOCK && _WIN64`. A POSIX socket is an `int`, so a
 *                  winsock SOCKET is the only one that is not.
 *   curl_off_t     8, always. `lib/curl_setup.h:584-585` is `#error "too small
 *                  curl_off_t"` below 8, so 8 is the only answer that compiles,
 *                  and `lib/config-win32.h:86` agrees.
 *   off_t          8 where this build asks for large files, and 4 on Windows,
 *                  where `lib/curl_setup.h:515` redirects lseek to _lseeki64
 *                  and `lib/config-win32.h:93` pins SIZEOF_OFF_T 4.
 *   time_t         the pointer width on every 64-bit target here. This is the
 *                  one value whose history this table records: a 32-bit time_t
 *                  is the reason `lib/curl_setup.h:530-533` defaults to 4 and
 *                  `lib/curl_ntlm_core.c:448` branches on `SIZEOF_TIME_T > 4`.
 *                  Every family in this table is 64-bit-time_t on a 64-bit
 *                  target, and `lib/config-win32.h:87-92` states the same for
 *                  Windows explicitly.
 */
static int size_of(const struct facts *f, const char *what) {
  const int pw = f->pointer_width;
  const int winsock64 = (f->family == FAM_WINDOWS && pw == 64);

  if (strcmp(what, "int") == 0)
    return 4;
  if (strcmp(what, "size_t") == 0)
    return pw;
  if (strcmp(what, "long") == 0)
    return winsock64 ? 4 : pw;
  if (strcmp(what, "curl_socket_t") == 0)
    return winsock64 ? 8 : 4;
  if (strcmp(what, "curl_off_t") == 0)
    return 8;
  if (strcmp(what, "off_t") == 0)
    return f->family == FAM_WINDOWS ? 4 : 8;
  if (strcmp(what, "time_t") == 0)
    return pw;
  return 0;
}

/* ------------------------------------------------------------------------- */
/* CURL_OS                                                                    */
/* ------------------------------------------------------------------------- */

/* `lib/curl_config-cmake.h.in:613` names this entry `cpu-machine-OS`, and the
 * two hand-written configurations upstream keeps in `lib/` spell it that way:
 * `lib/config-win32.h:113-121` produces `i386-pc-win32` and
 * `x86_64-pc-win32`, `lib/config-mac.h:33-35` produces the third spelling `mac`.
 *
 * What those two do not tell us is what `configure` produces on Linux, because
 * `configure.ac` is not part of the vendored closure - this package carries
 * `lib/`, `include/`, `COPYING`, `README` and `RELEASE-NOTES`, nothing else. So
 * the strings below are this build's own, built to the shape the template's
 * comment names. They land in `curl_version_info_data.host`, which
 * `lib/version.c:545` reports and nothing in this package acts on, and the
 * choice is recorded here rather than left to look like an upstream fact.
 */
static const char *curl_os(const struct facts *f) {
  static char buffer[256];

  if (f->family == FAM_WINDOWS) {
    /* Verbatim from lib/config-win32.h:113-121, including its "pc" vendor. */
    snprintf(buffer, sizeof buffer, "%s-pc-win32", f->arch);
    return buffer;
  }

  if (f->family == FAM_LINUX) {
    /* The canonical autotools triple, which is also the shape
     * lib/config-win32.h uses for the vendor field. */
    snprintf(buffer, sizeof buffer, "%s-pc-linux-%s", f->arch, f->libc);
    return buffer;
  }

  if (f->family == FAM_MACOS) {
    snprintf(buffer, sizeof buffer, "%s-apple-macos", f->arch);
    return buffer;
  }

  if (f->family == FAM_SOLARIS) {
    snprintf(buffer, sizeof buffer, "%s-sun-%s", f->arch, f->os);
    return buffer;
  }

  /* The BSDs. The autotools convention for these is a "unknown" vendor. */
  snprintf(buffer, sizeof buffer, "%s-unknown-%s", f->arch, f->os);
  return buffer;
}

/* ------------------------------------------------------------------------- */
/* The table                                                                  */
/* ------------------------------------------------------------------------- */

/* Order and comments follow `lib/curl_config-cmake.h.in`. The `lib/...:NN`
 * marker after each comment is the template line the row corresponds to, so a
 * reader can walk both files side by side.
 */
static const struct entry entries[] = {
    /* ---- CA bundle, CA path, and the SSL backend ---- */

    { M_ALL, 0, "CURL_CA_BUNDLE",
      "/* Location of default CA bundle */",
      FROM_CA_BUNDLE, SH_STRING },

    /* The template's own comment here says "built-in CA store of TLS backend".
     * That is an OpenSSL 1.0.2+ feature and nothing else implements it: the
     * only reader is `lib/url.c`, which uses it to fall back to the backend's
     * own store, and mbed-TLS has no such store - `lib/vtls/mbedtls.c` is
     * handed a trust list by CURLOPT_CAINFO or CURLOPT_CAPATH and has no
     * alternative. Undefined here for every target. */
    { 0, 0, "CURL_CA_FALLBACK",
      "/* define \"1\" to use built-in CA store of TLS backend */",
      NULL, SH_FLAG },

    { M_ALL, 0, "CURL_CA_PATH",
      "/* Location of default CA path */",
      FROM_CA_PATH, SH_STRING },

    /* Required, not optional: `lib/url.c` reads CURL_DEFAULT_SSL_BACKEND for
     * CURLOPT_SSLVERSION, CURLOPT_SSLVERSION_MAX, CURLOPT_SSL_CTX_FUNCTION and
     * CURLOPT_PINNEDPUBLICKEY, so a configuration with no value for it loses
     * four options that the public API still declares. "mbedtls" is the string
     * upstream's own `lib/vtls/vtls.c` and `lib/curl_setup.h:727` branch on. */
    { M_ALL, 0, "CURL_DEFAULT_SSL_BACKEND",
      "/* Default SSL backend */",
      "mbedtls", SH_STRING },

    /* mbed-TLS reaches the store only through a CA bundle or CA path, so there
     * is no native CA store to prefer. */
    { 0, 0, "CURL_CA_NATIVE",
      "/* Use native CA store */",
      NULL, SH_FLAG },

    /* ---- Everything this build does not disable ----
     *
     * All thirty of the CURL_DISABLE_* rows below are unset, and that is a
     * decision rather than an omission: `build.zig.zon .dependencies` carries
     * exactly one entry, the mbed-TLS package, so there is no zlib, no
     * brotli, no zstd, no nghttp2, no libpsl, no libidn2, no GSS-API and no
     * LDAP to disable. Each is written out with its own template comment so the
     * header says which protocol survived and why the others did not need a
     * switch thrown.
     *
     * Two of the protocols DO need one, and the table says so at its own row:
     * CURL_DISABLE_LDAP and CURL_DISABLE_LDAPS below.
     */

    { 0, 0, "CURL_DISABLE_ALTSVC", "/* disables alt-svc */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_COOKIES", "/* disables cookies support */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_BASIC_AUTH", "/* disables Basic authentication */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_BEARER_AUTH", "/* disables Bearer authentication */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_DIGEST_AUTH", "/* disables Digest authentication */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_KERBEROS_AUTH", "/* disables Kerberos authentication */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_NEGOTIATE_AUTH", "/* disables negotiate authentication */", NULL, SH_FLAG },

    /* AWS SigV4 needs nothing beyond <time.h> and the SHA-256 this build has
     * from mbed-TLS, so it stays. */
    { 0, 0, "CURL_DISABLE_AWS", "/* disables aws-sigv4 */", NULL, SH_FLAG },

    /* RFC 9421 HTTP Message Signatures need nothing beyond <time.h>
     * (`lib/http_httpsig.c:43`). Stays. */
    { 0, 0, "CURL_DISABLE_HTTPSIG", "/* disables HTTP Message Signatures (RFC 9421) */", NULL, SH_FLAG },

    /* DICT needs no external library: `lib/dict.c:28` gates on this macro and
     * every system header it uses (`<netdb.h>`, `<net/if.h>`) is behind its own
     * HAVE_ row. Stays. */
    { 0, 0, "CURL_DISABLE_DICT", "/* disables DICT */", NULL, SH_FLAG },

    /* DoH needs a resolver that can be handed a query -c-ares or DoH-internal -
     * and there is neither. `lib/vdns/doh.c` compiles away without
     * USE_RESOLV_ARES. Disabled, and recorded rather than silent. */
    { 0, 0, "CURL_DISABLE_DOH", "/* disables DNS-over-HTTPS */", NULL, SH_FLAG },

    { 0, 0, "CURL_DISABLE_FILE", "/* disables FILE */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_FORM_API", "/* disables form api */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_FTP", "/* disables FTP */", NULL, SH_FLAG },

    /* Must stay enabled: the published facade exposes `optionByName` and
     * `optionById`, which read `struct curl_easy_option` out of
     * `lib/easygetopt.c` - `:53`, `:59` and `:65` are their definitions and
     * `:28` is the `#ifndef CURL_DISABLE_GETOPTIONS` that gates them. */
    { 0, 0, "CURL_DISABLE_GETOPTIONS",
      "/* disables curl_easy_options API for existing options to curl_easy_setopt */",
      NULL, SH_FLAG },

    { 0, 0, "CURL_DISABLE_GOPHER", "/* disables GOPHER */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_HEADERS_API", "/* disables headers-api support */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_HSTS", "/* disables HSTS support */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_HTTP", "/* disables HTTP */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_HTTP_AUTH", "/* disabled all HTTP authentication methods */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_IMAP", "/* disables IMAP */", NULL, SH_FLAG },

    /* The one feature this build does have to switch off, and the reason is
     * forced rather than chosen. `lib/ldap.c:28` is
     * `#if !defined(CURL_DISABLE_LDAP) && !defined(USE_OPENLDAP)` and the unit
     * then includes `<lber.h>` and `<ldap.h>` unguarded
     * (`lib/ldap.c:59`, `:61`). There is no LDAP library in a dependency set
     * with exactly one entry, so leaving this unset does not build - it fails on
     * a missing header. Disabling LDAP is what keeps `lib/ldap.c` and
     * `lib/openldap.c` as empty translation units, which is upstream's own
     * design (the contract for the compile closure reads the first `#if` of each
     * unit for exactly this reason).
     *
     * The cost is real and is not hidden: this libcurl speaks no ldap:// and no
     * ldaps://. `lib/protocol.c:192` and `:205` turn both scheme entries into
     * ZERO_NULL, and CURLOPT_SCHEME reports them unsupported. */
    { M_ALL, 0, "CURL_DISABLE_LDAP", "/* disables LDAP */", NULL, SH_FLAG },
    { M_ALL, 0, "CURL_DISABLE_LDAPS", "/* disables LDAPS */", NULL, SH_FLAG },

    /* The curl command-line tool's --libcurl option. This package builds no
     * program (the `curl` tool is upstream's `src/`, deliberately not vendored),
     * so the row is dead weight either way; leaving it unset keeps the header
     * identical in shape to a default upstream configure run. */
    { 0, 0, "CURL_DISABLE_LIBCURL_OPTION",
      "/* disables --libcurl option from the curl tool */",
      NULL, SH_FLAG },

    { 0, 0, "CURL_DISABLE_MIME", "/* disables MIME support */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_BINDLOCAL", "/* disables local binding support */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_MQTT", "/* disables MQTT */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_NETRC", "/* disables netrc parser */", NULL, SH_FLAG },

    /* NTLM stays enabled, and this build is what makes that true rather than
     * nominal. `lib/curl_setup.h:756-767` defines USE_CURL_NTLM_CORE only when
     * CURL_ENABLE_NTLM is set and one of five DES providers is; for mbed-TLS the
     * test at `:759` is `defined(USE_MBEDTLS) && defined(HAVE_MBEDTLS_DES_CRYPT_ECB)`,
     * and USE_NTLM then follows at `:764-766`. With both rows below set,
     * `lib/http_ntlm.c:26` is live and `lib/curl_ntlm_core.c:26` is live, the
     * latter reaching `<mbedtls/des.h>` at `:81`. */
    { M_ALL, 0, "CURL_ENABLE_NTLM", "/* enables NTLM support */", NULL, SH_FLAG },

    { 0, 0, "CURL_DISABLE_PARSEDATE", "/* disables date parsing */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_POP3", "/* disables POP3 */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_PROGRESS_METER", "/* disables built-in progress meter */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_PROXY", "/* disables proxies */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_IPFS", "/* disables IPFS from the curl tool */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_RTSP", "/* disables RTSP */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_SHA512_256", "/* disables SHA-512/256 hash algorithm */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_SHUFFLE_DNS", "/* disabled shuffle DNS feature */", NULL, SH_FLAG },

    /* SMB stays. Its only extra is `lib/smb.c:298`, which reads the compiler's
     * own `__BYTE_ORDER__` - not a config macro - and `USE_WIN32_CRYPTO` below,
     * which the Windows row sets. */
    { M_ALL, 0, "CURL_ENABLE_SMB", "/* disables SMB */", NULL, SH_FLAG },

    { 0, 0, "CURL_DISABLE_SMTP", "/* disables SMTP */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_WEBSOCKETS", "/* disabled WebSocket */", NULL, SH_FLAG },

    /* Must stay enabled. `lib/socketpair.c:29` is `#ifndef CURL_DISABLE_SOCKETPAIR`
     * and its body then has to choose one wake-up implementation; with this row
     * unset the unit picks eventfd on Linux, pipe on the other unixes and the
     * loopback-socket path on Windows, and `lib/socketpair.c:90`'s `#error` is
     * reachable only from the `HAVE_SOCKETPAIR`-without-`USE_UNIX_SOCKETS` arm,
     * which this table never enters. */
    { 0, 0, "CURL_DISABLE_SOCKETPAIR",
      "/* disables use of socketpair for curl_multi_poll() */",
      NULL, SH_FLAG },

    { 0, 0, "CURL_DISABLE_TELNET", "/* disables TELNET */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_TFTP", "/* disables TFTP */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_VERBOSE_STRINGS", "/* disables verbose strings */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_CA_SEARCH",
      "/* disables unsafe CA bundle search on Windows from the curl tool */",
      NULL, SH_FLAG },
    { 0, 0, "CURL_CA_SEARCH_SAFE",
      "/* safe CA bundle search (within the curl tool directory) on Windows */",
      NULL, SH_FLAG },

    /* ---- Export decoration ----
     *
     * `include/curl/curl.h:124-138` only reaches CURL_EXTERN_SYMBOL through the
     * `BUILDING_LIBCURL && CURL_HIDDEN_SYMBOLS` arm, and CURL_HIDDEN_SYMBOLS is
     * a debug-build macro this package does not define. The value is therefore
     * empty here, and the template's own fallback block is reproduced verbatim
     * immediately after the row so a consumer that reaches the symbol still gets
     * a definition. */
    { 0, 0, "CURL_EXTERN_SYMBOL", "/* to make a symbol visible */", NULL, SH_FLAG },

    /* ---- Windows extras ---- */

    /* "Allow SMB to work on Windows": `lib/smb.c` needs the Windows crypto
     * primitives for its NTLM digest. Upstream's own hand-written Windows
     * configuration sets it (`lib/config-win32.h:110`) and this row follows
     * that. See build.zig for why it is the one Windows feature this table
     * follows that configuration for and is itself restricted to MSVC
     * (`lib/config-win32.h:29-31`). */
    { M_WINDOWS, 0, "USE_WIN32_CRYPTO", "/* Allow SMB to work on Windows */", NULL, SH_FLAG },

    /* Windows' own LDAP implementation. Deliberately NOT set, unlike
     * `lib/config-win32.h:108-109`: that header enables it because MSVC ships
     * <winber.h> with the SDK. The `lib/ldap.c:59` include is inside
     * `#ifdef _WIN32`, so leaving both USE_WIN32_LDAP and CURL_DISABLE_LDAP off
     * it is that, and this build takes CURL_DISABLE_LDAP. */
    { 0, 0, "USE_WIN32_LDAP", "/* Use Windows LDAP implementation */", NULL, SH_FLAG },

    /* ---- IPv6 ----
     *
     * `lib/curl_setup.h:695-702` reads this together with HAVE_GETADDRINFO and
     * selects CURLRES_IPV6, and its `:697-699` arm is an `#error` on Windows if
     * IPv6 is on without getaddrinfo. Every family here has getaddrinfo (the
     * Windows answer is `lib/config-win32.h:49`, the unixes have it in POSIX),
     * so the question is not whether the resolver exists but whether asking for
     * IPv6 costs something else, and on macOS it does.
     *
     * NOT CLAIMED FOR MACOS, and the reason is a header rather than a
     * capability. `lib/curl_setup.h:397-402` is
     *
     *     #if defined(__APPLE__) && !defined(USE_ARES)
     *     #  define USE_RESOLVE_ON_IPS 1
     *     #  if TARGET_OS_MAC && ... && defined(USE_IPV6)
     *     #    define CURL_MACOS_CALL_COPYPROXIES 1
     *     #  endif
     *     #endif
     *
     * and `lib/macos.c:30` then includes
     * `<SystemConfiguration/SCDynamicStoreCopySpecific.h>` unconditionally
     * inside that macro. Zig 0.16.0 ships no SystemConfiguration framework for
     * any Darwin target - measured, not assumed: no `SCDynamicStore*` and no
     * `*SystemConfiguration*` file exists anywhere under the compiler's
     * `lib/` - so `USE_IPV6` on macOS makes `lib/macos.c` uncompilable for want
     * of a header no build configuration can conjure. There is no third lever:
     * `USE_ARES` would need c-ares, which is not a dependency of this package,
     * and `TARGET_OS_IPHONE` is the target's own platform macro, so defining it
     * to steer this test would be telling the sources a lie about the platform.
     * (observed with Zig 0.16; not rechecked on 0.17).
     *
     * This is upstream's own answer rather than an invention: `lib/config-mac.h`
     * - the hand-written macOS configuration this package also does not use -
     * does not define `USE_IPV6` either, so upstream's own macOS answer is the
     * IPv4 resolver.
     *
     * The cost is real and is not hidden: on macOS `CURLRES_IPV4` is selected at
     * `lib/curl_setup.h:701`, so this libcurl resolves A records and not AAAA
     * ones. `USE_RESOLVE_ON_IPS` is still defined at `:398`, so the NAT64/DNS64
     * synthesis an IPv4 literal needs on a Darwin network interface is
     * unaffected; what is lost is resolving a host that publishes only AAAA.
     * Every other family keeps IPv6. */
    { M_ALL & ~M_MACOS, 0, "USE_IPV6",
      "/* Define if you want to enable IPv6 support */", NULL, SH_FLAG },

    /* ---- Headers: UNIX ---- */

    /* signal(3) and SIGALRM are POSIX. `lib/vdns/hostip.c:63-70` needs all of
     * HAVE_ALARM, SIGALRM, HAVE_SIGSETJMP and GLOBAL_INIT_IS_THREADSAFE before
     * it will use alarm-based resolve timeouts at all, so this row is one of
     * four, not a switch on its own. */
    { M_UNIX, X_FUNCTION, "HAVE_ALARM", "/* Define to 1 if you have the alarm function. */", NULL, SH_FLAG },

    /* arc4random(3) is a BSD and libc interface. macOS and the BSDs have it; a
     * glibc only has it from 2.36 and musl's appeared later still, and --libc
     * carries no version, so claiming it for Linux would be the guess this file
     * exists to avoid. `lib/rand.c:57` is its one reader, inside the `#ifdef HAVE_ARC4RANDOM` arm of
     * that unit's entropy block, and `lib/rand.c` also carries a
     * `/dev/urandom` reader for the targets that have one, so leaving the row off
     * costs a syscall and not a random number. */
    { M_BSD | M_MACOS, X_FUNCTION, "HAVE_ARC4RANDOM",
      "/* Define to 1 if you have the arc4random function. */", NULL, SH_FLAG },

    { M_UNIX, X_HEADER, "HAVE_ARPA_INET_H",
      "/* Define to 1 if you have the <arpa/inet.h> header file. */", NULL, SH_FLAG },

    /* C11 _Atomic. Every C11 compiler on these families provides it; Windows is
     * excluded because `lib/config-win32.h` does not claim it and
     * `lib/easy_lock.h` has a non-atomic arm. */
    { M_UNIX, 0, "HAVE_ATOMIC",
      "/* Define to 1 if you have _Atomic support. */", NULL, SH_FLAG },

    /* Linux and the BSDs added accept4; macOS has it from 10.14; Solaris has
     * `accept4st`, not `accept4`. */
    { M_LINUX | M_BSD | M_MACOS, X_FUNCTION, "HAVE_ACCEPT4",
      "/* Define to 1 if you have the `accept4' function. */", NULL, SH_FLAG },

    { M_UNIX, X_FUNCTION, "HAVE_FNMATCH",
      "/* Define to 1 if you have the `fnmatch' function. */", NULL, SH_FLAG },

    /* POSIX.1-2008 basename(const char *) over the GNU basename(char *).
     * `lib/curlx/basename.c` has its own reader behind this row. */
    { M_UNIX, X_FUNCTION, "HAVE_BASENAME",
      "/* Define to 1 if you have the `basename' function. */", NULL, SH_FLAG },

    /* C99. Claimed on every family: `lib/config-win32.h:40-43` claims it for
     * Windows too, guarded on the compiler having <stdbool.h>. */
    { M_ALL, 0, "HAVE_BOOL_T",
      "/* Define to 1 if bool is an available type. */", NULL, SH_FLAG },

    /* `__builtin_available` is an Apple clang feature, and the only reader is
     * `lib/curl_setup.h:41-60`, which uses it to ask for TARGET_OS_* at compile
     * time for the availability attributes. Apple clang has it; the other
     * toolchains in these families do not, and it is not a libc question at all.
     */
    { M_MACOS, 0, "HAVE_BUILTIN_AVAILABLE",
      "/* Define to 1 if you have the __builtin_available function. */", NULL, SH_FLAG },

    { M_UNIX, 0, "HAVE_CLOCK_GETTIME_MONOTONIC",
      "/* Define to 1 if you have the clock_gettime function and monotonic timer. */",
      NULL, SH_FLAG },

    /* CLOCK_MONOTONIC_RAW is a Linux kernel clock with no counterpart elsewhere
     * that this table can name. */
    { M_LINUX, 0, "HAVE_CLOCK_GETTIME_MONOTONIC_RAW",
      "/* Define to 1 if you have the clock_gettime function and raw monotonic timer.\n   */",
      NULL, SH_FLAG },

    /* ---- Windows socket spellings ----
     *
     * `lib/config-win32.h:47-55` is the source for all four: closesocket,
     * getpeername, getsockname and ioctlsocket. ioctlsocket's FIONBIO form is
     * load-bearing, not decorative: `lib/curlx/nonblock.c:84-86` is the Windows
     * arm and `lib/curlx/nonblock.c:90`'s `#error "no non-blocking method was
     * found/used/set"` is reached when none of its four arms is defined. */
    { M_WINDOWS, 0, "HAVE_CLOSESOCKET",
      "/* Define to 1 if you have the `closesocket' function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_CLOSESOCKET_CAMEL",
      "/* Define to 1 if you have the `CloseSocket' function. */", NULL, SH_FLAG },
    { M_WINDOWS, 0, "HAVE_IOCTLSOCKET",
      "/* Define to 1 if you have the ioctlsocket function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_IOCTLSOCKET_CAMEL",
      "/* Define to 1 if you have the IoctlSocket camel case function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_IOCTLSOCKET_CAMEL_FIONBIO",
      "/* Define to 1 if you have a working IoctlSocket camel case FIONBIO function.\n   */",
      NULL, SH_FLAG },
    { M_WINDOWS, 0, "HAVE_IOCTLSOCKET_FIONBIO",
      "/* Define to 1 if you have a working ioctlsocket FIONBIO function. */", NULL, SH_FLAG },

    /* ---- UNIX headers ---- */

    { M_UNIX, X_HEADER, "HAVE_DIRENT_H",
      "/* Define to 1 if you have the <dirent.h> header file. */", NULL, SH_FLAG },
    { M_UNIX, X_FUNCTION, "HAVE_OPENDIR",
      "/* Define to 1 if you have the `opendir' function. */", NULL, SH_FLAG },

    /* C23 and C11 Annex K. Neither is reachable from a C11 build of this
     * release, and `lib/curl_setup.h` never asks for either on its own. */
    { 0, 0, "HAVE_MEMSET_EXPLICIT",
      "/* Define to 1 if you have the memset_explicit (C23) function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_MEMSET_S",
      "/* Define to 1 if you have the memset_s (C11) function. */", NULL, SH_FLAG },

    { M_UNIX, X_FUNCTION, "HAVE_FCNTL",
      "/* Define to 1 if you have the fcntl function. */", NULL, SH_FLAG },

    /* Windows too, from `lib/config-win32.h:37`. `M_ALL` says which families
     * reach for `<fcntl.h>`; whether they have it is the probe's answer, and on
     * mingw-w64 the answer is yes. */
    { M_ALL, X_HEADER, "HAVE_FCNTL_H",
      "/* Define to 1 if you have the <fcntl.h> header file. */", NULL, SH_FLAG },

    /* Load-bearing on every unixes row. `lib/curlx/nonblock.c:52-70` is the
     * first of its four arms, and `:90`'s `#error` is the alternative. */
    { M_UNIX, 0, "HAVE_FCNTL_O_NONBLOCK",
      "/* Define to 1 if you have a working fcntl O_NONBLOCK function. */", NULL, SH_FLAG },

    { M_ALL, X_FUNCTION, "HAVE_FREEADDRINFO",
      "/* Define to 1 if you have the freeaddrinfo function. */", NULL, SH_FLAG },

    /* fseeko/off_t spellings. Windows has _fseeki64 and `lib/curl_setup.h:515`
     * routes lseek through it, so there is no fseeko there. */
    { M_UNIX, X_FUNCTION, "HAVE_FSEEKO",
      "/* Define to 1 if you have the fseeko function. */", NULL, SH_FLAG },
    { M_UNIX, 0, "HAVE_DECL_FSEEKO",
      "/* Define to 1 if you have the fseeko declaration. */", NULL, SH_FLAG },

    /* ---- Name resolution ----
     *
     * These five are all five families. `lib/config-win32.h:49-50` gives the
     * Windows two from winsock, and POSIX gives the other three. With them,
     * `lib/curl_setup.h:695-696` selects CURLRES_IPV6 on every target, which is
     * the resolver this build delivers rather than the IPv4-only fallback at
     * `:701`. */
    { M_ALL, X_FUNCTION, "HAVE_GETADDRINFO",
      "/* Define to 1 if you have a working getaddrinfo function. */", NULL, SH_FLAG },
    { M_ALL, 0, "HAVE_GETADDRINFO_THREADSAFE",
      "/* Define to 1 if the getaddrinfo function is thread-safe. */", NULL, SH_FLAG },

    /* Not claimed anywhere: the gethostbyname_r family has no reader in the 196
     * compiled units. `lib/vdns/hostip.c` resolves through getaddrinfo once
     * CURLRES_IPV6 is selected, and the only definitions of these macros in the
     * tree are `lib/amigaos.c:69` (an __AMIGA__-gated bitmask) and
     * `lib/setup-win32.h:48-49` (a Windows header this package does not
     * include, because HAVE_CONFIG_H sends `lib/curl_setup.h:138-140` to the
     * generated header instead). Defining them would describe an interface
     * nothing calls. */
    { 0, 0, "HAVE_GETHOSTBYNAME_R",
      "/* Define to 1 if you have the gethostbyname_r function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_GETHOSTBYNAME_R_3",
      "/* gethostbyname_r() takes 3 args */", NULL, SH_FLAG },
    { 0, 0, "HAVE_GETHOSTBYNAME_R_5",
      "/* gethostbyname_r() takes 5 args */", NULL, SH_FLAG },
    { 0, 0, "HAVE_GETHOSTBYNAME_R_6",
      "/* gethostbyname_r() takes 6 args */", NULL, SH_FLAG },

    { M_ALL, X_FUNCTION, "HAVE_GETHOSTNAME",
      "/* Define to 1 if you have the gethostname function. */", NULL, SH_FLAG },

    /* geteuid and getppid are POSIX. Not claimed for Windows: nothing in the
     * Windows path calls either, and upstream's own `lib/config-win32.h` does
     * not list them.
     */
    { M_UNIX, X_FUNCTION, "HAVE_GETEUID",
      "/* Define to 1 if you have the `geteuid' function. */", NULL, SH_FLAG },
    { M_UNIX, X_FUNCTION, "HAVE_GETPPID",
      "/* Define to 1 if you have the `getppid' function. */", NULL, SH_FLAG },

    /* getifaddrs and <ifaddrs.h>: every unixes family here, and not Windows. */
    { M_UNIX, X_FUNCTION, "HAVE_GETIFADDRS",
      "/* Define to 1 if you have a working getifaddrs function. */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_IFADDRS_H",
      "/* Define to 1 if you have the <ifaddrs.h> header file. */", NULL, SH_FLAG },

    /* getpass_r is a GNU/POSIX.1-2001 addition that `lib/netrc.c` reaches; both
     * libc names this build accepts for Linux (gnu, musl) provide it. */
    { M_LINUX, X_FUNCTION, "HAVE_GETPASS_R",
      "/* Define to 1 if you have the `getpass_r' function. */", NULL, SH_FLAG },

    /* Windows' two come from `lib/config-win32.h:51-52`. */
    { M_ALL, X_FUNCTION, "HAVE_GETPEERNAME",
      "/* Define to 1 if you have the `getpeername' function. */", NULL, SH_FLAG },
    { M_ALL, X_FUNCTION, "HAVE_GETSOCKNAME",
      "/* Define to 1 if you have the `getsockname' function. */", NULL, SH_FLAG },

    /* if_nametoindex: POSIX, all four unixes families. Left off for Windows
     * because `lib/curl_setup.h:163-167` defines it there itself, under
     * `_MSC_VER || __MINGW32__`, so a config value would be redundant. */
    { M_UNIX, X_FUNCTION, "HAVE_IF_NAMETOINDEX",
      "/* Define to 1 if you have the `if_nametoindex' function. */", NULL, SH_FLAG },

    /* The password database. `lib/netrc.c:32` is the reader and it is behind
     * HAVE_PWD_H, so the two rows travel together. */
    { M_UNIX, X_FUNCTION, "HAVE_GETPWUID",
      "/* Define to 1 if you have the `getpwuid' function. */", NULL, SH_FLAG },
    { M_UNIX, X_FUNCTION, "HAVE_GETPWUID_R",
      "/* Define to 1 if you have the `getpwuid_r' function. */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_PWD_H",
      "/* Define to 1 if you have the <pwd.h> header file. */", NULL, SH_FLAG },

    { M_UNIX, X_FUNCTION, "HAVE_GETRLIMIT",
      "/* Define to 1 if you have the `getrlimit' function. */", NULL, SH_FLAG },
    { M_UNIX, X_FUNCTION, "HAVE_GETTIMEOFDAY",
      "/* Define to 1 if you have the `gettimeofday' function. */", NULL, SH_FLAG },

    /* ---- strerror_r: exactly one of the two, never both ----
     *
     * glibc's returns `char *` and completes the string; the XSI/POSIX one
     * returns `int` and may not. `lib/curl_setup.h` reaches both only through
     * whichever the platform gives, so claiming both would be a claim about an
     * interface that does not exist on the target. musl, the BSDs, Solaris and
     * macOS are all POSIX-conforming here; glibc is the GNU-conforming one. */
    { M_LINUX, X_GNU, "HAVE_GLIBC_STRERROR_R",
      "/* Define to 1 if you have a working glibc-style strerror_r function. */",
      NULL, SH_FLAG },
    { M_UNIX, X_NOT_GNU, "HAVE_POSIX_STRERROR_R",
      "/* Define to 1 if you have a working POSIX-style strerror_r function. */",
      NULL, SH_FLAG },
    { M_UNIX, X_FUNCTION, "HAVE_STRERROR_R",
      "/* Define to 1 if you have the strerror_r function. */", NULL, SH_FLAG },

    /* ---- GSS-API and Kerberos ----
     *
     * All off. `build.zig.zon .dependencies` carries exactly one entry - the
     * mbed-TLS package - and curl's own note on this set is that it is what a
     * minimal build looks like. With HAVE_GSSAPI off, `lib/curl_setup.h:744-747`
     * leaves USE_SPNEGO undefined, so `lib/http_negotiate.c:26` is an empty
     * translation unit, and `:750-753` leaves USE_KERBEROS5 undefined.
     * `lib/vauth/spnego_gssapi.c` and `lib/vauth/krb5_gssapi.c` are empty for
     * the same reason. */
    { 0, 0, "HAVE_GSSAPI", "/* if you have the gssapi libraries */", NULL, SH_FLAG },
    { 0, 0, "HAVE_GSSAPPLE", "/* if you have Apple GSS */", NULL, SH_FLAG },
    { 0, 0, "HAVE_GSSGNU", "/* if you have the GNU gssapi libraries */", NULL, SH_FLAG },
    { 0, 0, "HAVE_GSS_SET_NEG_MECHS",
      "/* if you have gss_set_neg_mechs */", NULL, SH_FLAG },
    { 0, 0, "CURL_KRB5_VERSION", "/* MIT Kerberos version */", NULL, SH_STRING },
    { 0, 0, "CURL_BORINGSSL_VERSION", "/* BoringSSL version */", NULL, SH_STRING },
    { 0, 0, "CURL_PATCHSTAMP", "/* Patch stamp */", NULL, SH_STRING },

    /* sa_family_t is POSIX in `struct sockaddr` and winsock2 provides the
     * member under the same name, so this row is every family. */
    { M_ALL, 0, "HAVE_SA_FAMILY_T",
      "/* Define to 1 if symbol `sa_family_t' exists */", NULL, SH_FLAG },

    /* `lib/config-win32.h:53-55` and `:38`: the three ioctl/io.h rows Windows
     * gets from its own headers rather than from POSIX. Not claimed here
     * because `lib/curl_setup.h:511` already includes <io.h> under `HAVE_IO_H`
     * on `_WIN32` alone and `:659` includes <sys/ioctl.h> from the same
     * macro. */
    { M_UNIX, 0, "HAVE_IOCTL_FIONBIO",
      "/* Define to 1 if you have a working ioctl FIONBIO function. */", NULL, SH_FLAG },
    { M_UNIX, 0, "HAVE_IOCTL_SIOCGIFADDR",
      "/* Define to 1 if you have a working ioctl SIOCGIFADDR function. */", NULL, SH_FLAG },
    { M_WINDOWS, X_HEADER, "HAVE_IO_H",
      "/* Define to 1 if you have the <io.h> header file. */", NULL, SH_FLAG },

    /* ---- LDAP ----
     *
     * All off, and see the CURL_DISABLE_LDAP row above for why: with the legacy
     * LDAP implementation disabled there is nothing for these to enable.
     * `lib/protocol.c:205` gates the ldaps:// scheme entry on
     * `CURL_DISABLE_LDAP || !HAVE_LDAP_SSL`, so it is already ZERO_NULL. */
    { 0, 0, "HAVE_LBER_H",
      "/* Define to 1 if you have the lber.h header file. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_LDAP_SSL", "/* Use LDAPS implementation */", NULL, SH_FLAG },
    { 0, 0, "HAVE_LDAP_SSL_H",
      "/* Define to 1 if you have the ldap_ssl.h header file. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_LDAP_URL_PARSE",
      "/* Define to 1 if you have the `ldap_url_parse' function. */", NULL, SH_FLAG },

    /* libgen.h is POSIX, which is why the family mask says `M_UNIX`. Whether a
     * given target ships it is the probe's answer. */
    { M_UNIX, X_HEADER, "HAVE_LIBGEN_H",
      "/* Define to 1 if you have the <libgen.h> header file. */", NULL, SH_FLAG },

    /* ---- Optional third-party libraries: none of them ----
     *
     * Every row in this block is off because `build.zig.zon .dependencies` has
     * exactly one entry. These are the rows that would each add a second
     * dependency, and the cost of each if it were wrong is a link error rather
     * than a fallback, so each is named here rather than left implied:
     *
     *   idn2       `lib/idn.c:33` would include <idn2.h>; without it curl still
     *              handles punycode through its own `lib/idn.c` decoder, so no
     *              capability is lost beyond Unicode normalisation.
     *   zlib       `lib/content_encoding.c:29` is `#ifdef HAVE_LIBZ`, so the
     *              whole unit - gzip and deflate - is compiled out.
     *   brotli     same unit, same macro family; no Brotli content encoding.
     *   zstd       `lib/content_encoding.c` and `lib/version.c` read HAVE_ZSTD;
     *              no zstd content encoding and no zstd version string.
     *   libpsl     `lib/psl.c:26` is `#ifdef USE_LIBPSL`, so the unit is empty
     *              and `lib/cookie.c:804`'s public-suffix rejection is compiled
     *              out. This is the one omission with a security reading, so it
     *              is named: cookie rejection is coarser without PSL. `build.zig`
     *              records the same.
     *   nghttp2    `lib/http2.c:26` is `#if !defined(CURL_DISABLE_HTTP) &&
     *              defined(USE_NGHTTP2)`, so the whole HTTP/2 unit is compiled
     *              out and this libcurl speaks HTTP/1.1 only.
     */
    { 0, 0, "HAVE_LIBIDN2", "/* Define to 1 if you have the `idn2' library (-lidn2). */", NULL, SH_FLAG },
    { 0, 0, "HAVE_IDN2_H", "/* Define to 1 if you have the idn2.h header file. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_LIBZ", "/* if zlib is available */", NULL, SH_FLAG },
    { 0, 0, "HAVE_BROTLI", "/* if brotli is available */", NULL, SH_FLAG },
    { 0, 0, "HAVE_ZSTD", "/* if zstd is available */", NULL, SH_FLAG },
    { 0, 0, "USE_LIBPSL", "/* if libpsl is in use */", NULL, SH_FLAG },
    { 0, 0, "USE_NGHTTP2", "/* to enable NGHTTP2 */", NULL, SH_FLAG },

    { M_ALL, X_HEADER, "HAVE_LOCALE_H",
      "/* Define to 1 if you have the <locale.h> header file. */", NULL, SH_FLAG },

    { M_UNIX, X_FUNCTION, "HAVE_LOCALTIME_R",
      "/* Define to 1 if you have a working localtime_r function. */", NULL, SH_FLAG },
    { M_UNIX, X_FUNCTION, "HAVE_GMTIME_R",
      "/* Define to 1 if you have a working gmtime_r function. */", NULL, SH_FLAG },
    { M_UNIX, 0, "HAVE_SUSECONDS_T",
      "/* Define to 1 if you have the 'suseconds_t' data type. */", NULL, SH_FLAG },

    /* ---- Socket headers ----
     *
     * The four netinet rows plus <netdb.h> are POSIX and are all four unixes
     * families. They are what `lib/vdns/hostip.c:26-38`, `lib/easy.c:26-38` and
     * `lib/curl_addrinfo.h:27-36` each include behind, and with them
     * HAVE_GETADDRINFO above, they are what makes the IPv6 resolver compile.
     *
     * "POSIX" is why the family mask says `M_UNIX` and not why the row is
     * defined: POSIX describes which systems are expected to ship the file, and
     * the file's presence is what each of these seven rows is asked about. That
     * distinction is not academic here. `<netinet/in6.h>` is the header the five
     * `#include <netinet/in6.h>` sites behind `HAVE_NETINET_IN6_H` - `lib/urldata.h:50-52`,
     * `lib/curl_addrinfo.c:29-31`, `lib/vdns/hostip.c:29-31`, `lib/vdns/dnscache.c:29-31`
     * and `lib/vtls/hostcheck.c:32-34` - reach for, and the glibc Zig ships has
     * no such file: `__has_include(<netinet/in6.h>)` is false for every unixes
     * target here, so `netinet6/in6.h` and `netinet/in.h` are the only in6
     * spellings available. So the row is now answered by the probe and comes
     * out undefined, and `lib/urldata.h` does not include a header the target
     * does not have. */
    { M_UNIX, X_HEADER, "HAVE_NETDB_H",
      "/* Define to 1 if you have the <netdb.h> header file. */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_NETINET_IN_H",
      "/* Define to 1 if you have the <netinet/in.h> header file. */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_NETINET_IN6_H",
      "/* Define to 1 if you have the <netinet/in6.h> header file. */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_NETINET_TCP_H",
      "/* Define to 1 if you have the <netinet/tcp.h> header file. */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_NETINET_UDP_H",
      "/* Define to 1 if you have the <netinet/udp.h> header file. */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_NETINET_IP_H",
      "/* Define to 1 if you have the <netinet/ip.h> header file. */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_NET_IF_H",
      "/* Define to 1 if you have the <net/if.h> header file. */", NULL, SH_FLAG },

    /* Linux's TCP_MD5SIG spelling. `lib/curl_tcp_md5sig` does not exist in this
     * release, but `lib/tcp.h`-shaped code paths do consult the header. Note
     * that `<linux/tcp.h>` and `<netinet/tcp.h>` cannot both be included in one
     * translation unit on glibc - their `struct tcphdr` collide - which is why
     * the probe reports each header on its own rather than including them all. */
    { M_LINUX, X_HEADER, "HAVE_LINUX_TCP_H",
      "/* Define to 1 if you have the <linux/tcp.h> header file. */", NULL, SH_FLAG },

    /* ---- Pipes, poll, realpath ---- */

    { M_UNIX, X_FUNCTION, "HAVE_PIPE", "/* Define to 1 if you have the `pipe' function. */", NULL, SH_FLAG },

    /* pipe2 and eventfd are the two wake-up mechanisms `lib/socketpair.c:34`
     * and `:52` choose between before it falls back to `socket(2)`. eventfd also
     * needs `lib/curl_setup.h:470-473` to see HAVE_EVENTFD *and*
     * HAVE_SYS_EVENTFD_H together before it defines USE_EVENTFD, so the two rows
     * are written as a pair on purpose. */
    { M_LINUX, X_FUNCTION, "HAVE_PIPE2", "/* Define to 1 if you have the `pipe2' function. */", NULL, SH_FLAG },
    { M_LINUX, X_FUNCTION, "HAVE_EVENTFD", "/* Define to 1 if you have the `eventfd' function. */", NULL, SH_FLAG },
    { M_LINUX, X_HEADER, "HAVE_SYS_EVENTFD_H",
      "/* Define to 1 if you have the <sys/eventfd.h> header file. */", NULL, SH_FLAG },

    { M_UNIX, X_FUNCTION, "HAVE_POLL", "/* If you have poll */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_POLL_H",
      "/* Define to 1 if you have the <poll.h> header file. */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_SYS_POLL_H",
      "/* Define to 1 if you have the <sys/poll.h> header file. */", NULL, SH_FLAG },

    { M_UNIX, X_FUNCTION, "HAVE_REALPATH", "/* If you have realpath */", NULL, SH_FLAG },

    /* ---- sendmsg / sendmmsg ----
     *
     * sendmsg is POSIX. sendmmsg is not: it is Linux, and macOS from 10.14, and
     * nothing this table can source-verify about the other families, so it is
     * claimed for exactly the two. The cost of not claiming it is a loop of
     * sendmsg calls in `lib/cf-socket.c`, not a missing feature. */

    /* send and recv are POSIX, and Windows too: `lib/config-win32.h:58` and
     * `:65` claim both, with `:60-64` and `:66-70` supplying the RECV_TYPE_*
     * and SEND_TYPE_* argument shapes that `lib/curl_setup.h` reads under
     * `USE_WINSOCK`. That is upstream's own Windows answer and this build
     * follows it; the argument shapes themselves are derived from `_WIN32`
     * rather than from a config macro, so nothing has to be spelled here.
     */
    { M_ALL, X_FUNCTION, "HAVE_RECV",
      "/* Define to 1 if you have the recv function. */", NULL, SH_FLAG },
    { M_ALL, X_FUNCTION, "HAVE_SEND",
      "/* Define to 1 if you have the send function. */", NULL, SH_FLAG },

    /* The one reader is `lib/easy_lock.h:40` and `:76-77`, the back-off arm of
     * curl's own spinlock helper, so this row is not decoration: without it a
     * contended `Curl_mutex` or `Curl_cond` spins the core. POSIX on all four
     * unixes families; not claimed for Windows, where `lib/easy_lock.h` reaches
     * `SwitchToThread` on its `_WIN32` arm.
     */
    { M_UNIX, X_FUNCTION, "HAVE_SCHED_YIELD",
      "/* Define to 1 if you have the sched_yield function. */", NULL, SH_FLAG },
    { M_UNIX, X_FUNCTION, "HAVE_SENDMSG",
      "/* Define to 1 if you have the sendmsg function. */", NULL, SH_FLAG },
    { M_LINUX | M_MACOS, X_FUNCTION, "HAVE_SENDMMSG",
      "/* Define to 1 if you have the sendmmsg function. */", NULL, SH_FLAG },

    /* ---- Extended attributes ----
     *
     * Not claimed. fsetxattr is Linux and Solaris; macOS has setxattr but no
     * fsetxattr; the BSDs gained it recently. Since --libc carries no version
     * and the BSD row cannot be pinned from these arguments, leaving the whole
     * fsetxattr block off is the honest answer, and no compiled unit reads it. */
    { 0, 0, "HAVE_FSETXATTR", "/* Define to 1 if you have the 'fsetxattr' function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_FSETXATTR_5", "/* fsetxattr() takes 5 args */", NULL, SH_FLAG },
    { 0, 0, "HAVE_FSETXATTR_6", "/* fsetxattr() takes 6 args */", NULL, SH_FLAG },

    { M_ALL, X_FUNCTION, "HAVE_SETLOCALE",
      "/* Define to 1 if you have the `setlocale' function. */", NULL, SH_FLAG },

    { M_UNIX, X_FUNCTION, "HAVE_SETRLIMIT",
      "/* Define to 1 if you have the `setrlimit' function. */", NULL, SH_FLAG },

    /* SO_NONBLOCK through setsockopt. Claimed on Linux only, and deliberately:
     * `lib/curlx/nonblock.c` already has `HAVE_FCNTL_O_NONBLOCK` above for every
     * unixes row, which is its first arm, so a target this row does not claim
     * still gets non-blocking sockets through fcntl. macOS has no SO_NONBLOCK at
     * all and Solaris/FreeBSD added it late enough that the version is not
     * knowable from these arguments. */
    { M_LINUX, 0, "HAVE_SETSOCKOPT_SO_NONBLOCK",
      "/* Define to 1 if you have a working setsockopt SO_NONBLOCK function. */",
      NULL, SH_FLAG },

    /* ---- Signals ----
     *
     * sigaction and sigsetjmp are POSIX. `lib/curl_setup.h:588-600` is about
     * sizes, not these, but `lib/vdns/hostip.c:43-44` includes <setjmp.h> and
     * <signal.h> unconditionally, so the types must exist on every target - and
     * they do, on all five families.
     *
     * signal(3) is also claimed for Windows, from `lib/config-win32.h:71`. The
     * Windows signal model is not POSIX and `lib/curl_setup.h` does not pretend
     * otherwise; the row is there because upstream's own Windows configuration
     * puts it there.
     *
     * siginterrupt is not claimed anywhere: it was withdrawn from POSIX, macOS
     * removed it in 10.14, and no compiled unit in this closure reads it. */
    { M_UNIX, X_FUNCTION, "HAVE_SIGACTION",
      "/* Define to 1 if you have the sigaction function. */", NULL, SH_FLAG },
    { M_ALL, X_FUNCTION, "HAVE_SIGNAL",
      "/* Define to 1 if you have the signal function. */", NULL, SH_FLAG },
    { M_UNIX, X_FUNCTION, "HAVE_SIGSETJMP",
      "/* Define to 1 if you have the sigsetjmp function or macro. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_SIGINTERRUPT",
      "/* Define to 1 if you have the siginterrupt function. */", NULL, SH_FLAG },

    /* ---- struct sockaddr_in6 ----
     *
     * `sin6_scope_id` is a member of `struct sockaddr_in6` on some targets and
     * not on others, and nothing about the OS family, the pointer width or the
     * byte order decides it: a 64-bit little-endian riscv64 and a 64-bit
     * little-endian x86_64 differ. Upstream therefore measures it rather than
     * tabulating it - `configure.ac:1812-1831` is one `AC_COMPILE_IFELSE` whose
     * body assigns `s.sin6_scope_id = 0` - and this file now does the same
     * through `X_MEMBER` and `--member-facts`.
     *
     * It is not merely a nicer question. This table used to answer it from a
     * closed list of architectures, and that list was narrower than the platform
     * matrix: `armeb`, `powerpc64`, `powerpc64le`, `hexagon`, `mipsel`, `thumb`
     * and `riscv32` were all refused by name, on seven cells of the published
     * 53-target run, over a fact the target compiler measures in one compile.
     * The list is gone, so no architecture can be missing from it.
     *
     * One row for every family now, rather than three rows that asserted the
     * member on Windows, the BSDs, Solaris and macOS without asking. Those were
     * true on the targets this package builds - `lib/config-win32.h:97` says so
     * for Windows - and they were still claims about headers nobody had opened.
     */
    { M_ALL, X_MEMBER, "HAVE_SOCKADDR_IN6_SIN6_SCOPE_ID",
      "/* Define to 1 if struct sockaddr_in6 has the sin6_scope_id member */",
      NULL, SH_FLAG },

    /* ---- Sockets ---- */

    { M_ALL, X_FUNCTION, "HAVE_SOCKET",
      "/* Define to 1 if you have the `socket' function. */", NULL, SH_FLAG },
    { M_UNIX, X_FUNCTION, "HAVE_SOCKETPAIR",
      "/* Define to 1 if you have the socketpair function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_PROTO_BSDSOCKET_H",
      "/* Define to 1 if you have the <proto/bsdsocket.h> header file. */", NULL, SH_FLAG },

    /* stdatomic.h is C11 on the unixes. Left off for Windows on purpose:
     * mingw-w64 has it and the probe would report yes, but
     * `lib/config-win32.h` does not claim it and `lib/easy_lock.h` has an arm
     * that does not want it. A family mask can exclude a header the target
     * does have; it just cannot manufacture one the target does not. */
    { M_UNIX, X_HEADER, "HAVE_STDATOMIC_H",
      "/* Define to 1 if you have the <stdatomic.h> header file. */", NULL, SH_FLAG },
    { M_ALL, X_HEADER, "HAVE_STDBOOL_H",
      "/* Define to 1 if you have the <stdbool.h> header file. */", NULL, SH_FLAG },

    /* strcasecmp and <strings.h> are POSIX. `lib/strcase.c` reaches
     * <strings.h> only under this row and spells the comparison inline otherwise,
     * so a target that lacked it would still build. */
    { M_UNIX, X_FUNCTION, "HAVE_STRCASECMP",
      "/* Define to 1 if you have the strcasecmp function. */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_STRINGS_H",
      "/* Define to 1 if you have the <strings.h> header file. */", NULL, SH_FLAG },

    /* The MSVC-only spellings. No compiled unit reads them. */
    { 0, 0, "HAVE_STRCMPI", "/* Define to 1 if you have the strcmpi function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_STRICMP", "/* Define to 1 if you have the stricmp function. */", NULL, SH_FLAG },

    /* `<stropts.h>` is a Solaris header and `lib/if2ip.c:47` is its only reader
     * in this closure, so it is asked about on Solaris and nowhere else. That
     * the file is present there is still measured, not assumed. */
    { M_SOLARIS, X_HEADER, "HAVE_STROPTS_H",
      "/* Define to 1 if you have the <stropts.h> header file. */", NULL, SH_FLAG },

    /* memrchr is POSIX.1-2008; `lib/curl_memrchr.c:28` is `#ifndef HAVE_MEMRCHR`
     * and carries curl's own byte-loop when this is off. */
    { M_UNIX, X_FUNCTION, "HAVE_MEMRCHR",
      "/* Define to 1 if you have the memrchr function. */", NULL, SH_FLAG },

    { M_ALL, 0, "HAVE_STRUCT_SOCKADDR_STORAGE",
      "/* if struct sockaddr_storage is defined */", NULL, SH_FLAG },
    { M_ALL, 0, "HAVE_STRUCT_TIMEVAL",
      "/* Define to 1 if you have the timeval struct. */", NULL, SH_FLAG },

    /* ---- The remaining sys header rows ----
     *
     * sys/sockio.h is Solaris-only (the ioctl SIOCGIFADDR spelling arrives
     * through it) and sys/filio.h is its predecessor on the same systems; no
     * other family reaches for them, so only Solaris is asked. */
    { M_SOLARIS, X_HEADER, "HAVE_SYS_SOCKIO_H",
      "/* Define to 1 if you have the <sys/sockio.h> header file. */", NULL, SH_FLAG },
    { M_SOLARIS, X_HEADER, "HAVE_SYS_FILIO_H",
      "/* Define to 1 if you have the <sys/filio.h> header file. */", NULL, SH_FLAG },

    /* sys/types.h and sys/utime.h are also Windows' answers, from
     * `lib/config-win32.h:44-45`, so both are M_ALL - and both are measured,
     * which matters for sys/utime.h: the glibc Zig ships has `utime.h` and no
     * `sys/utime.h`, so that row comes out undefined on every unixes target
     * here. `lib/curl_setup.h` reaches `<sys/utime.h>` under this row only. */
    { M_ALL, X_HEADER, "HAVE_SYS_TYPES_H",
      "/* Define to 1 if you have the <sys/types.h> header file. */", NULL, SH_FLAG },
    { M_ALL, X_HEADER, "HAVE_SYS_UTIME_H",
      "/* Define to 1 if you have the <sys/utime.h> header file. */", NULL, SH_FLAG },

    { M_UNIX, X_HEADER, "HAVE_SYS_IOCTL_H",
      "/* Define to 1 if you have the <sys/ioctl.h> header file. */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_SYS_PARAM_H",
      "/* Define to 1 if you have the <sys/param.h> header file. */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_SYS_SELECT_H",
      "/* Define to 1 if you have the <sys/select.h> header file. */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_SYS_UN_H",
      "/* Define to 1 if you have the <sys/un.h> header file. */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_SYS_RESOURCE_H",
      "/* Define to 1 if you have the <sys/resource.h> header file. */", NULL, SH_FLAG },

    /* termios.h is POSIX; `lib/curl_setup.h` and the tty-backed units reach for
     * it on every unixes family. */
    { M_UNIX, X_HEADER, "HAVE_TERMIOS_H",
      "/* Define to 1 if you have the <termios.h> header file. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_TERMIO_H",
      "/* Define to 1 if you have the <termio.h> header file. */", NULL, SH_FLAG },

    /* unistd.h is POSIX. Left off for Windows because nothing in the Windows
     * path includes it unguarded: `lib/curl_setup.h:519` puts it behind
     * `__DJGPP__`. */
    { M_UNIX, X_HEADER, "HAVE_UNISTD_H",
      "/* Define to 1 if you have the <unistd.h> header file. */", NULL, SH_FLAG },

    { M_UNIX, X_FUNCTION, "HAVE_UTIME", "/* Define to 1 if you have the `utime' function. */", NULL, SH_FLAG },
    { M_WINDOWS, X_FUNCTION, "HAVE_UTIME", "/* Define to 1 if you have the `utime' function. */", NULL, SH_FLAG },
    { M_UNIX, X_FUNCTION, "HAVE_UTIMES", "/* Define to 1 if you have the `utimes' function. */", NULL, SH_FLAG },
    { M_UNIX, X_HEADER, "HAVE_UTIME_H",
      "/* Define to 1 if you have the <utime.h> header file. */", NULL, SH_FLAG },

    /* argv is writable everywhere but Windows, where the CRT hands the program
     * a copy it does not share. */
    { M_UNIX, 0, "HAVE_WRITABLE_ARGV",
      "/* Define this symbol if your OS supports changing the contents of argv */",
      NULL, SH_FLAG },

    /* No platform this table describes has an unsigned time_t. */
    { 0, 0, "HAVE_TIME_T_UNSIGNED",
      "/* Define this if time_t is unsigned */", NULL, SH_FLAG },

    /* _REENTRANT is a glibc request for the thread-safe declarations, and
     * `lib/curl_setup.h:200-203` turns exactly this macro into `_REENTRANT`.
     * Claimed for the unixes: on musl and the BSDs it is accepted and harmless,
     * and on macOS the SDK defines it itself. */
    { M_UNIX, 0, "NEED_REENTRANT",
      "/* Define to 1 if _REENTRANT preprocessor symbol must be defined. */",
      NULL, SH_FLAG },
    { 0, 0, "NEED_THREAD_SAFE",
      "/* Define to 1 if _THREAD_SAFE preprocessor symbol must be defined. */",
      NULL, SH_FLAG },
    { 0, 0, "NEED_LBER_H",
      "/* Define to 1 if you need the lber.h header file even with ldap.h */",
      NULL, SH_FLAG },

    /* ---- CURL_OS ---- */

    { M_ALL, 0, "CURL_OS", "/* cpu-machine-OS */", NULL, SH_STRING },

    /* ---- Type sizes ----
     *
     * The template fills these from CMake CheckTypeSize probes of the target.
     * There is no probe here; see `size_of()` above for what each one is
     * computed from and which two upstream files agree. */

    { M_ALL, 0, "SIZEOF_INT", "/* The size of `int', as computed by sizeof. */", "int", SH_SIZE },
    { M_ALL, 0, "SIZEOF_LONG", "/* The size of `long', as computed by sizeof. */", "long", SH_SIZE },
    { M_ALL, 0, "SIZEOF_OFF_T", "/* The size of `off_t', as computed by sizeof. */", "off_t", SH_SIZE },
    { M_ALL, 0, "SIZEOF_CURL_OFF_T", "/* The size of `curl_off_t', as computed by sizeof. */", "curl_off_t", SH_SIZE },
    { M_ALL, 0, "SIZEOF_CURL_SOCKET_T", "/* The size of `curl_socket_t', as computed by sizeof. */", "curl_socket_t", SH_SIZE },
    { M_ALL, 0, "SIZEOF_SIZE_T", "/* The size of `size_t', as computed by sizeof. */", "size_t", SH_SIZE },
    { M_ALL, 0, "SIZEOF_TIME_T", "/* The size of `time_t', as computed by sizeof. */", "time_t", SH_SIZE },

    /* ---- Threads ----
     *
     * `lib/curl_setup.h:677-680` defines USE_MUTEX from HAVE_THREADS_POSIX or
     * _WIN32, and `lib/curl_threads.h:58` is
     * `#error neither HAVE_THREADS_POSIX nor _WIN32 defined` without one of the
     * two. On Windows the `_WIN32` half of that test is satisfied by the
     * compiler's own macro, so this row is the unixes only, and Windows gets
     * the native path instead. */
    { M_UNIX, 0, "HAVE_THREADS_POSIX", "/* Define if you have POSIX pthreads */", NULL, SH_FLAG },

    /* ---- Resolver ----
     *
     * The synchronous resolver. `lib/curl_setup.h:704-713` selects
     * CURLRES_SYNCH when neither USE_RESOLV_THREADED nor USE_RESOLV_ARES is
     * defined, and that is what this build uses everywhere.
     *
     * Windows is the one place upstream's own configuration chooses otherwise:
     * `lib/config-win32.h:103-106` defaults it to USE_RESOLV_THREADED. It is not
     * claimed here, and the reason is a link line rather than a header: the
     * threaded resolver needs a working threads implementation, and Windows gets
     * that from the CRT only when a threads library is named, which is a claim
     * this package cannot make for `x86_64-windows-gnu` without running a gate.
     * See `build.zig` for the same reason spelled out at the delivery level.
     */
    { 0, 0, "USE_ARES", "/* Define if you want to enable c-ares support */", NULL, SH_FLAG },
    { 0, 0, "USE_RESOLV_ARES", "/* Define if you want to enable c-ares DNS lookup */", NULL, SH_FLAG },
    { 0, 0, "USE_RESOLV_THREADED", "/* Define if you want to enable threaded DNS lookup */", NULL, SH_FLAG },

    /* ---- TLS backend: exactly one, and it is mbed-TLS ----
     *
     * `lib/curl_setup.h:727-730` turns USE_MBEDTLS into USE_SSL and lists the
     * five other USE_*SSL* macros as its alternatives. None of them is defined
     * anywhere in this table, so `lib/vtls/openssl.c`, `lib/vtls/gtls.c`,
     * `lib/vtls/wolfssl.c`, `lib/vtls/rustls.c` and `lib/vtls/schannel.c` are
     * empty translation units and `lib/vtls/vtls.c:693` and `:712` select
     * mbedTLS as the only backend. `CURL_WITH_MULTI_SSL` is off for the same
     * reason: one backend is not "multiple SSL backends".
     */
    { M_ALL, 0, "USE_MBEDTLS", "/* if mbedTLS is enabled */", NULL, SH_FLAG },

    { 0, 0, "USE_GNUTLS", "/* if GnuTLS is enabled */", NULL, SH_FLAG },
    { 0, 0, "USE_RUSTLS", "/* if Rustls is enabled */", NULL, SH_FLAG },
    { 0, 0, "USE_WOLFSSL", "/* if wolfSSL is enabled */", NULL, SH_FLAG },
    { 0, 0, "USE_SCHANNEL", "/* to enable Windows SSL */", NULL, SH_FLAG },
    { 0, 0, "USE_APPLE_SECTRUST", "/* to enable Apple OS-native certificate verification */", NULL, SH_FLAG },
    { 0, 0, "CURL_WITH_MULTI_SSL", "/* enable multiple SSL backends */", NULL, SH_FLAG },
    { 0, 0, "USE_SSLS_EXPORT", "/* if SSL session export support is available */", NULL, SH_FLAG },

    /* The one entry that is a property of the mbed-TLS headers rather than of
     * the target, and therefore an argument instead of a table answer. See the
     * refusal list at the top of this file and `--mbedtls-des-crypt-ecb` in
     * `usage()`. */
    { M_ALL, X_DES_ECB, "HAVE_MBEDTLS_DES_CRYPT_ECB",
      "/* if mbedTLS <4 has the mbedtls_des_crypt_ecb function. */", NULL, SH_FLAG },

    /* ---- SSH ----
     *
     * No libssh and no libssh2, so `lib/vssh/libssh.c` and
     * `lib/vssh/libssh2.c` are empty translation units (`lib/vssh/libssh2.c:26`
     * is `#ifdef USE_LIBSSH2`) and `lib/curl_setup.h:769-771` leaves USE_SSH
     * undefined. scp:// and sftp:// are therefore absent, and `lib/vssh/vssh.c`
     * keeps only the protocol dispatch it does not need them for. */
    { 0, 0, "USE_LIBSSH", "/* if libssh is in use */", NULL, SH_FLAG },
    { 0, 0, "USE_LIBSSH2", "/* if libssh2 is in use */", NULL, SH_FLAG },

    /* ---- Remaining third-party backends: none ---- */
    { 0, 0, "USE_OPENLDAP", "/* if you want to use OpenLDAP code instead of legacy ldap implementation */", NULL, SH_FLAG },
    { 0, 0, "USE_OPENSSL", "/* if OpenSSL is in use */", NULL, SH_FLAG },
    { 0, 0, "USE_AMISSL", "/* if AmiSSL is in use */", NULL, SH_FLAG },
    { 0, 0, "USE_GSASL", "/* if GSASL is in use */", NULL, SH_FLAG },
    { 0, 0, "USE_LIBUV", "/* if libuv is in use */", NULL, SH_FLAG },
    { 0, 0, "USE_PROXY_HTTP3", "/* if HTTP/3 proxy support is available */", NULL, SH_FLAG },
    { 0, 0, "HAVE_UV_H", "/* Define to 1 if you have the <uv.h> header file. */", NULL, SH_FLAG },
    { 0, 0, "USE_BACKTRACE", "/* if libbacktrace is in use */", NULL, SH_FLAG },
    { 0, 0, "CURL_DISABLE_OPENSSL_AUTO_LOAD_CONFIG",
      "/* Define to 1 if you do not want the OpenSSL configuration to be loaded\n   automatically */",
      NULL, SH_FLAG },

    /* ---- QUIC / HTTP/3: none ----
     *
     * No ngtcp2, no nghttp3, no quiche. Every unit under `lib/vquic/` except the
     * shared `lib/vquic/capsule.c`, `lib/vquic/cf-capsule.c` and
     * `lib/vquic/vquic.c` is an empty translation unit: `lib/vquic/cf-ngtcp2.c:26`
     * is `#if defined(USE_NGTCP2) && defined(USE_NGHTTP3)`. The QUIC-flavoured
     * capsule code that does compile is unreachable without a backend. */
    { 0, 0, "USE_NGTCP2", "/* to enable NGTCP2 */", NULL, SH_FLAG },
    { 0, 0, "USE_NGHTTP3", "/* to enable NGHTTP3 */", NULL, SH_FLAG },
    { 0, 0, "USE_QUICHE", "/* to enable quiche */", NULL, SH_FLAG },
    { 0, 0, "OPENSSL_QUIC_API2", "/* to enable openssl + ngtcp2 + nghttp3 */", NULL, SH_FLAG },
    { 0, 0, "HAVE_QUICHE_CONN_SET_QLOG_FD",
      "/* Define to 1 if you have the quiche_conn_set_qlog_fd function. */", NULL, SH_FLAG },

    /* ---- Unix domain sockets ----
     *
     * The four unixes families, where <sys/un.h> is the header curl asks for and
     * `lib/cf-ip-happy.c` and `lib/cf-socket.c` use it for the http:// over a
     * socket transport. Not claimed for Windows, even though
     * `lib/config-win32.h:111` does set it: that header is the MSVC answer, and
     * this build does not have an MSVC target. Whether mingw-w64's AF_UNIX is
     * acceptable to `lib/socketpair.c:104`'s `CURL_SOCKETPAIR` is a question for
     * a gate, not a table. See `build.zig` for the same reason at the delivery
     * level. */
    { M_UNIX, 0, "USE_UNIX_SOCKETS", "/* if Unix domain sockets are enabled */", NULL, SH_FLAG },

    /* ---- Windows-only features ----
     *
     * USE_WINDOWS_SSPI is the one Windows row this table does not claim, and
     * the reason is worth stating because it is a capability, not a spelling:
     * `lib/curl_sspi.h:30` includes <sspi.h> under it and linking the unit needs
     * -lssldbl or -lssp plus -lsecur32, none of which is a header this generator
     * can confirm for a GNU toolchain. Leaving it off makes `lib/curl_sspi.c:26`,
     * `lib/socks_sspi.c:27` and the vauth SSPI units empty translation units, and
     * `lib/curl_setup.h:744-753` leaves both USE_SPNEGO and USE_KERBEROS5 off on
     * Windows as well as everywhere else. `build.zig` records the same boundary
     * and names the two libraries. */
    { 0, 0, "USE_WINDOWS_SSPI", "/* to enable SSPI support */", NULL, SH_FLAG },
    { 0, 0, "USE_WATT32", "/* if Watt-32 is in use */", NULL, SH_FLAG },
    { 0, 0, "USE_WIN32_IDN", "/* to enable Windows IDN */", NULL, SH_FLAG },
    { 0, 0, "USE_APPLE_IDN", "/* to enable Apple IDN */", NULL, SH_FLAG },

    /* Apple's `SYS_recvmsg_x`/`SYS_sendmsg_x` fast UDP path. Left off even for
     * macOS: it is a private kernel entry point, and neither this build nor any
     * option in it asks for it. It would only be set together with
     * HAVE_APPLE_MSG_X, which the template has no row for because it is a
     * library-level probe rather than a libc one.
     */
    { 0, 0, "USE_APPLE_FAST_UDP",
      "/* to use Apple fast UDP (SYS_recvmsg_x, SYS_sendmsg_x) */", NULL, SH_FLAG },

    /* HTTPS-over-HTTPSRR needs a resolver that accepts a DoH query, and this
     * build has none: no c-ares and no threaded resolver. `lib/vdns/httpsrr.c`
     * compiles to an empty translation unit, and `lib/vdns/doh.c` already is one
     * because CURL_DISABLE_DOH is set above.
     */
    { 0, 0, "USE_HTTPSRR",
      "/* Define to 1 to query for HTTPSRR when using DoH */", NULL, SH_FLAG },

    /* mach_absolute_time is the mach monotonic clock. `lib/curlx/timeval.c:116`
     * is its reader, in the `#elif` after the POSIX clock_gettime arm, so on
     * macOS this row is what makes the timer selection reach the mach clock at
     * all rather than falling back to `gettimeofday`.
     */
    { M_MACOS, X_FUNCTION, "HAVE_MACH_ABSOLUTE_TIME",
      "/* Define to 1 if you have the mach_absolute_time function. */", NULL, SH_FLAG },

    /* ---- Byte order: nothing to claim, and the reason is in the file ----
     *
     * `--endian` is a required argument and it is validated and recorded in the
     * header this program writes, but no row above is gated on it, and that is a
     * finding rather than an oversight. curl does not describe byte order in
     * curl_config.h at all: `lib/curl_endian.h:26-33` declares readers that
     * convert *from* a stated byte order and `lib/curl_endian.c:39-45`
     * implements `Curl_read16_le` one byte at a time, so it is correct on either
     * order. The two places curl does care read the *compiler's* macros and not
     * this configuration: `lib/smb.c:298` tests `__BYTE_ORDER__` and
     * `lib/vquic/capsule.c:47` and `:50` test it the same way. So there is no
     * entry for it to gate, and inventing one would be a row describing nothing.
     * The argument is kept because it is part of the target's identity and a
     * future row may need it; it is validated because a value this program does
     * not recognise must be a refusal, not a silent pass-through.
     */

    /* ---- Encrypted Client Hello: none ---- */
    { 0, 0, "USE_ECH", "/* if ECH support is available */", NULL, SH_FLAG },

    /* ---- Backend-specific capability rows: all OpenSSL/wolfSSL ---- */
    { 0, 0, "HAVE_SSL_SET0_WBIO",
      "/* Define to 1 if OpenSSL has the `SSL_set0_wbio` function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_SSL_SET1_ECH_CONFIG_LIST",
      "/* Define to 1 if you have the SSL_set1_ech_config_list function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_DES_ECB_ENCRYPT",
      "/* Define to 1 if OpenSSL has the DES_ecb_encrypt function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_WOLFSSL_GET_PEER_CERTIFICATE",
      "/* Define to 1 if you have the wolfSSL_get_peer_certificate function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_WOLFSSL_USEALPN",
      "/* Define to 1 if you have the wolfSSL_UseALPN function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_WOLFSSL_BIO_NEW",
      "/* Define to 1 if you have the wolfSSL_BIO_new function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_WOLFSSL_BIO_SET_SHUTDOWN",
      "/* Define to 1 if you have the wolfSSL_BIO_set_shutdown function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_WC_DES_ECBENCRYPT",
      "/* Define to 1 if you have the `wc_Des_EcbEncrypt' function. */", NULL, SH_FLAG },
    { 0, 0, "HAVE_WOLFSSL_CTX_GENERATEECHCONFIG",
      "/* Define to 1 if you have the wolfSSL_CTX_GenerateEchConfig function. */",
      NULL, SH_FLAG },

    /* ---- Non-configured but recorded here so the omission is visible ----
     *
     * `_FILE_OFFSET_BITS` is the one row below whose value this build does set,
     * and only where it has an effect: 64 on every unixes family, where
     * `lib/curl_setup.h:561-582` reads SIZEOF_OFF_T (set to 8 above) rather than
     * the macro. Not set for Windows, where `lib/curl_setup.h:509-516` routes
     * lseek to _lseeki64 and no large-file macro exists. */
    { M_UNIX, 0, "_FILE_OFFSET_BITS",
      "/* Number of bits in a file offset, on hosts where this is settable. */",
      "64", SH_FLAG },

    /* ssize_t: every family here declares it, so the template's
     * "the signed version of size_t" row stays undefined. It exists in the table
     * because the template has it and because a future target that lacks it would
     * need to spell it, and it is empty rather than absent so the header shows
     * the decision. */
    { 0, 0, "ssize_t", "/* the signed version of size_t */", NULL, SH_FLAG },
};

/* Which `<...>` file each `X_HEADER` row asks about, in `entries` order. The
 * family mask on those rows says which families reach for the file; this table
 * says which file, and `--header-facts` says whether the target has it. A row
 * with `X_HEADER` and no line here, or a line here naming a row without
 * `X_HEADER`, stops the run in `check_header_rows` rather than producing a
 * configuration that asserts a header nobody measured.
 *
 * The names are the template's own `<...>` spellings, in the template's own
 * order, so this table diffs against `lib/curl_config-cmake.h.in` row for row
 * and `build_support/curl_headers_probe.c` lists the same 35 files in the same
 * order for the same reason. */
static const struct header_row header_rows[] = {
    { "HAVE_ARPA_INET_H", "arpa/inet.h" },
    { "HAVE_DIRENT_H", "dirent.h" },
    { "HAVE_FCNTL_H", "fcntl.h" },
    { "HAVE_IFADDRS_H", "ifaddrs.h" },
    { "HAVE_PWD_H", "pwd.h" },
    { "HAVE_IO_H", "io.h" },
    { "HAVE_LIBGEN_H", "libgen.h" },
    { "HAVE_LOCALE_H", "locale.h" },
    { "HAVE_NETDB_H", "netdb.h" },
    { "HAVE_NETINET_IN_H", "netinet/in.h" },
    { "HAVE_NETINET_IN6_H", "netinet/in6.h" },
    { "HAVE_NETINET_TCP_H", "netinet/tcp.h" },
    { "HAVE_NETINET_UDP_H", "netinet/udp.h" },
    { "HAVE_NETINET_IP_H", "netinet/ip.h" },
    { "HAVE_NET_IF_H", "net/if.h" },
    { "HAVE_LINUX_TCP_H", "linux/tcp.h" },
    { "HAVE_SYS_EVENTFD_H", "sys/eventfd.h" },
    { "HAVE_POLL_H", "poll.h" },
    { "HAVE_SYS_POLL_H", "sys/poll.h" },
    { "HAVE_STDATOMIC_H", "stdatomic.h" },
    { "HAVE_STDBOOL_H", "stdbool.h" },
    { "HAVE_STRINGS_H", "strings.h" },
    { "HAVE_STROPTS_H", "stropts.h" },
    { "HAVE_SYS_SOCKIO_H", "sys/sockio.h" },
    { "HAVE_SYS_FILIO_H", "sys/filio.h" },
    { "HAVE_SYS_TYPES_H", "sys/types.h" },
    { "HAVE_SYS_UTIME_H", "sys/utime.h" },
    { "HAVE_SYS_IOCTL_H", "sys/ioctl.h" },
    { "HAVE_SYS_PARAM_H", "sys/param.h" },
    { "HAVE_SYS_SELECT_H", "sys/select.h" },
    { "HAVE_SYS_UN_H", "sys/un.h" },
    { "HAVE_SYS_RESOURCE_H", "sys/resource.h" },
    { "HAVE_TERMIOS_H", "termios.h" },
    { "HAVE_UNISTD_H", "unistd.h" },
    { "HAVE_UTIME_H", "utime.h" },
};

/* Which function each `X_FUNCTION` row is asking about, in `entries` order. The
 * family mask on those rows says which families reach for the name; this table
 * says which name, and `--function-facts` says whether the target declares it.
 * A row with `X_FUNCTION` and no line here, or a line here naming a row without
 * `X_FUNCTION`, stops the run in `check_function_rows`.
 *
 * `HAVE_UTIME` appears twice in `entries` - once for the unixes and once for
 * Windows - and both carry `X_FUNCTION`, so one line here answers both. That is
 * correct rather than a duplicate: the two rows ask the same question of the
 * same declaration, and a fact file that answered it twice would be the thing
 * `check_function_rows` direction three exists to refuse.
 *
 * `build_support/curl_existence_probe.c` lists the same 47 names in the same
 * order for the same reason. */
static const struct function_row function_rows[] = {
    { "HAVE_ALARM", "alarm" },
    { "HAVE_ARC4RANDOM", "arc4random" },
    { "HAVE_ACCEPT4", "accept4" },
    { "HAVE_FNMATCH", "fnmatch" },
    { "HAVE_BASENAME", "basename" },
    { "HAVE_OPENDIR", "opendir" },
    { "HAVE_FCNTL", "fcntl" },
    { "HAVE_FREEADDRINFO", "freeaddrinfo" },
    { "HAVE_FSEEKO", "fseeko" },
    { "HAVE_GETADDRINFO", "getaddrinfo" },
    { "HAVE_GETHOSTNAME", "gethostname" },
    { "HAVE_GETEUID", "geteuid" },
    { "HAVE_GETPPID", "getppid" },
    { "HAVE_GETIFADDRS", "getifaddrs" },
    { "HAVE_GETPASS_R", "getpass_r" },
    { "HAVE_GETPEERNAME", "getpeername" },
    { "HAVE_GETSOCKNAME", "getsockname" },
    { "HAVE_IF_NAMETOINDEX", "if_nametoindex" },
    { "HAVE_GETPWUID", "getpwuid" },
    { "HAVE_GETPWUID_R", "getpwuid_r" },
    { "HAVE_GETRLIMIT", "getrlimit" },
    { "HAVE_GETTIMEOFDAY", "gettimeofday" },
    { "HAVE_STRERROR_R", "strerror_r" },
    { "HAVE_LOCALTIME_R", "localtime_r" },
    { "HAVE_GMTIME_R", "gmtime_r" },
    { "HAVE_PIPE", "pipe" },
    { "HAVE_PIPE2", "pipe2" },
    { "HAVE_EVENTFD", "eventfd" },
    { "HAVE_POLL", "poll" },
    { "HAVE_REALPATH", "realpath" },
    { "HAVE_RECV", "recv" },
    { "HAVE_SEND", "send" },
    { "HAVE_SCHED_YIELD", "sched_yield" },
    { "HAVE_SENDMSG", "sendmsg" },
    { "HAVE_SENDMMSG", "sendmmsg" },
    { "HAVE_SETLOCALE", "setlocale" },
    { "HAVE_SETRLIMIT", "setrlimit" },
    { "HAVE_SIGACTION", "sigaction" },
    { "HAVE_SIGNAL", "signal" },
    { "HAVE_SIGSETJMP", "sigsetjmp" },
    { "HAVE_SOCKET", "socket" },
    { "HAVE_SOCKETPAIR", "socketpair" },
    { "HAVE_STRCASECMP", "strcasecmp" },
    { "HAVE_MEMRCHR", "memrchr" },
    { "HAVE_UTIME", "utime" },
    { "HAVE_UTIMES", "utimes" },
    { "HAVE_MACH_ABSOLUTE_TIME", "mach_absolute_time" },
};

/* Which struct member each `X_MEMBER` row is asking about, in `entries` order.
 * The family mask on those rows says which families reach for the member; this
 * table says which member, and `--member-facts` says whether the target's
 * headers can be asked to assign it. A row with `X_MEMBER` and no line here, or
 * a line here naming a row without `X_MEMBER`, stops the run in
 * `check_member_rows`.
 *
 * `build_support/curl_existence_probe.c` carries the same key in
 * `curl_member_rows`, spelled `"<struct>::<member>"` because a bare member name
 * is not a key - two structs can each have a member called `flags`. */
static const struct member_row member_rows[] = {
    { "HAVE_SOCKADDR_IN6_SIN6_SCOPE_ID", "sockaddr_in6::sin6_scope_id" },
};

/* THE AUDIT: EVERY FUNCTION-EXISTENCE ROW, AND WHY 47 OF 83 ARE MEASURED
 * --------------------------------------------------------------------
 * 83 rows of `entries` carry a template comment that names a function, a macro
 * or an arity. 47 of them carry `X_FUNCTION` and appear in `function_rows`; the
 * other 36 are named here, by name and by reason, because "this probe cannot
 * measure it" is a decision a reader has to be able to check rather than infer
 * from an absence. A later reader who adds a measurable row and forgets this
 * list finds the row mentioned here and knows the class was considered.
 *
 *   (a) NOT A DECLARATION - a macro that must *work*, a struct member, a data
 *       type, or a property of the ABI. A probe asks whether an identifier is
 *       declared; these ask whether a second thing is true of it, and answering
 *       them from the declaration would answer a question nobody asked.
 *         HAVE_FCNTL_O_NONBLOCK            fcntl works with O_NONBLOCK
 *         HAVE_IOCTL_FIONBIO                ioctl works with FIONBIO
 *         HAVE_IOCTL_SIOCGIFADDR            ioctl works with SIOCGIFADDR
 *         HAVE_SETSOCKOPT_SO_NONBLOCK       setsockopt works with SO_NONBLOCK
 *         HAVE_IOCTLSOCKET_FIONBIO          the Windows ioctlsocket FIONBIO
 *         HAVE_CLOCK_GETTIME_MONOTONIC      clock_gettime and CLOCK_MONOTONIC
 *         HAVE_CLOCK_GETTIME_MONOTONIC_RAW  and CLOCK_MONOTONIC_RAW
 *         HAVE_SOCKADDR_IN6_SIN6_SCOPE_ID   a struct member (X_SCOPE_ID)
 *         HAVE_SUSECONDS_T                  a data type
 *         HAVE_SA_FAMILY_T                  a data type
 *         HAVE_STRUCT_SOCKADDR_STORAGE      a struct
 *         HAVE_STRUCT_TIMEVAL               a struct
 *         HAVE_WRITABLE_ARGV                a property of main's argv
 *         HAVE_GETADDRINFO_THREADSAFE       a property of the implementation
 *       The function each of these builds on - `fcntl`, `ioctl`, `setsockopt`,
 *       `clock_gettime`, `getaddrinfo` - IS measured.
 *
 *   (b) A SPELLING DIFFERENCE, not a presence. Both `strerror_r` rows name
 *       which *form* of the function the target has, and each already carries a
 *       flag that decides it from `--libc`: `HAVE_GLIBC_STRERROR_R` is `X_GNU`
 *       and `HAVE_POSIX_STRERROR_R` is `X_NOT_GNU`. The plain declaration is
 *       measured, by `HAVE_STRERROR_R`.
 *
 *   (c) A COMPILER BUILTIN, not a libc symbol. `HAVE_BUILTIN_AVAILABLE` asks
 *       whether the toolchain has `__builtin_available`, and its only reader
 *       (`lib/curl_setup.h:41-60`) asks the compiler. That is a fact about
 *       `zig cc`, which is the same for every target this build compiles.
 *
 *   (d) A LIBRARY THIS PACKAGE DOES NOT DEPEND ON. Off for a reason already
 *       stated at each row, and a measurement would be free to contradict it.
 *         HAVE_LDAP_URL_PARSE, HAVE_MEMSET_S, HAVE_MEMSET_EXPLICIT,
 *         HAVE_SIGINTERRUPT, HAVE_STRCMPI, HAVE_STRICMP,
 *         HAVE_GETHOSTBYNAME_R, HAVE_FSETXATTR, HAVE_QUICHE_CONN_SET_QLOG_FD
 *       - C11 Annex K and C23 spellings, a withdrawn name, two MSVC-only names,
 *       and the arity rows beside the last two.
 *         HAVE_SSL_SET0_WBIO, HAVE_SSL_SET1_ECH_CONFIG_LIST,
 *         HAVE_DES_ECB_ENCRYPT, HAVE_WOLFSSL_GET_PEER_CERTIFICATE,
 *         HAVE_WOLFSSL_USEALPN, HAVE_WOLFSSL_BIO_NEW,
 *         HAVE_WOLFSSL_BIO_SET_SHUTDOWN, HAVE_WOLFSSL_CTX_GENERATEECHCONFIG,
 *         HAVE_WC_DES_ECBENCRYPT
 *       - the third-party TLS backends.
 *       `HAVE_MBEDTLS_DES_CRYPT_ECB` is the one row of this group that is
 *       decided rather than defaulted: it carries `X_DES_ECB` and is refused
 *       when `--mbedtls-des-crypt-ecb` was not supplied, which is the third
 *       entry in the refusal list at the top of this file.
 *
 *   (e) THE WINDOWS SPELLINGS. `closesocket`, `CloseSocket`, `ioctlsocket`,
 *       `IoctlSocket` and `IoctlSocket FIONBIO` are winsock names, and
 *       `<winsock2.h>` is not a header this package probes for them - see
 *       `probe_groups` in `build_support/curl_existence_probe.c`. They keep the
 *       `M_WINDOWS` mask, which is what upstream's own `lib/config-win32.h`
 *       does for the same names. The `M_ALL` socket rows - `HAVE_SOCKET`,
 *       `HAVE_SEND`, `HAVE_RECV`, `HAVE_GETADDRINFO`, `HAVE_FREEADDRINFO`,
 *       `HAVE_GETPEERNAME`, `HAVE_GETSOCKNAME`, `HAVE_GETHOSTNAME` - ARE
 *       measured on Windows, through the `socket_or_winsock`,
 *       `netdb_or_winsock` and `winsock_pair` groups.
 */


/* ------------------------------------------------------------------------- */
/* Predicates                                                                  */
/* ------------------------------------------------------------------------- */

/* One refusal helper for the whole file. Nothing in this program writes a
 * partial file and then complains: the caller is told, and no bytes are
 * produced, so a failed run cannot be mistaken for a good one. */
/* `_Noreturn` rather than a plain `void`, and that is not decoration: three of
 * the callers below end their control flow with this call - `arch_has_scope_id`
 * returns an `int` and `check_libc` returns nothing - so without the annotation
 * a compiler would have to warn about a path that reaches the end of a
 * non-void function. The annotation is the truthful description of what
 * `exit(2)` on the last line already does. */
static _Noreturn void refuse(const char *fmt, const char *a1, const char *a2) {
  /* Three writes rather than one: the caller's message is a runtime format
   * string, and a runtime string cannot be pasted into a literal, so the
   * surrounding sentences and the caller's own text are separate `fprintf`
   * calls. The middle one is the only one that consumes `a1` and `a2`, which is
   * why it is written alone: the other two carry no conversion, so they take no
   * arguments. */
  fprintf(stderr,
          "curl_config_gen: refusing to write curl_config.h.\n"
          "  ");
  fprintf(stderr, fmt, a1, a2);
  fprintf(stderr,
          "\n"
          "  Nothing was written. This program emits a configuration for the\n"
          "  target it is given and does not guess one it cannot derive from\n"
          "  --os, --arch, --pointer-width, --endian, --libc,\n"
          "  --mbedtls-des-crypt-ecb and --header-facts. See\n"
          "  build_support/curl_config_gen.c.\n");
  exit(2);
}

/* The `<...>` file an `X_HEADER` row asks about, or NULL when the row does not
 * carry the flag. `check_header_rows` has already proved that every `X_HEADER`
 * row is in `header_rows`, so a NULL here means the row is not a header row and
 * the flag test in `entry_is_defined` is the only caller that reaches it. */
static const char *header_for_row(const struct entry *e) {
  const size_t count = sizeof header_rows / sizeof header_rows[0];

  if ((e->flags & X_HEADER) == 0)
    return NULL;
  for (size_t i = 0; i < count; i++) {
    if (strcmp(header_rows[i].name, e->name) == 0)
      return header_rows[i].header;
  }
  refuse("internal: the row \"%s\" carries X_HEADER but is not in header_rows. "
         "Every header-existence row needs a line in header_rows naming the file "
         "it asks about; add one and keep the same order as entries.",
         e->name, NULL);
}

/* Whether the target has one `<...>` file. Never guesses: a header no fact in
 * `--header-facts` answers for is a refusal, because writing the row as defined
 * would be the exact defect X_HEADER exists to remove. */
static int header_is_present(const struct facts *f, const char *header) {
  for (size_t i = 0; i < f->header_fact_count; i++) {
    if (strcmp(f->header_facts[i].header, header) == 0)
      return f->header_facts[i].present;
  }
  refuse("--header-facts has no answer for <%s>. The fact file is written by "
         "compiling build_support/curl_headers_probe.c for the target, and it "
         "carries one \"<header> yes|no\" line per header in header_rows. Add "
         "the missing line rather than defaulting it.", header, NULL);
}

/* The function an `X_FUNCTION` row asks about, or NULL when the row does not
 * carry the flag. Mirrors `header_for_row` exactly, and is refused in exactly
 * the same shape, because the two classes are the same argument about a
 * different question: a name curl can call, rather than a file curl can
 * include. */
static const char *function_for_row(const struct entry *e) {
  const size_t count = sizeof function_rows / sizeof function_rows[0];

  if ((e->flags & X_FUNCTION) == 0)
    return NULL;
  for (size_t i = 0; i < count; i++) {
    if (strcmp(function_rows[i].name, e->name) == 0)
      return function_rows[i].function;
  }
  refuse("internal: the row \"%s\" carries X_FUNCTION but is not in "
         "function_rows. Every function-existence row needs a line in "
         "function_rows naming the function it asks about; add one and keep "
         "the same order as entries.", e->name, NULL);
}

/* Whether the target declares one function. Never guesses: a name no fact in
 * `--function-facts` answers for is a refusal, for the same reason
 * `header_is_present` refuses - writing the row as defined would assert a
 * declaration nobody asked the target about, which is the defect
 * `HAVE_ACCEPT4` on Darwin was. */
static int function_is_present(const struct facts *f, const char *function) {
  for (size_t i = 0; i < f->function_fact_count; i++) {
    if (strcmp(f->function_facts[i].name, function) == 0)
      return f->function_facts[i].present;
  }
  refuse("--function-facts has no answer for %s. The fact file is written by "
         "build_support/curl_existence_probe.c running the target's compiler "
         "once per function, and it carries one \"<function> yes|no\" line per "
         "function in function_rows. Add the missing line rather than "
         "defaulting it.", function, NULL);
}

/* The member an `X_MEMBER` row asks about, or NULL when the row does not carry
 * the flag. Mirrors `function_for_row` exactly and is refused in the same shape,
 * because the two classes are the same argument about a different question: a
 * field curl can assign, rather than a name curl can call. */
static const char *member_for_row(const struct entry *e) {
  const size_t count = sizeof member_rows / sizeof member_rows[0];

  if ((e->flags & X_MEMBER) == 0)
    return NULL;
  for (size_t i = 0; i < count; i++) {
    if (strcmp(member_rows[i].name, e->name) == 0)
      return member_rows[i].member;
  }
  refuse("internal: the row \"%s\" carries X_MEMBER but is not in member_rows. "
         "Every member-existence row needs a line in member_rows naming the "
         "\"<struct>::<member>\" it asks about; add one and keep the same order "
         "as entries.", e->name, NULL);
}

/* Whether the target's headers can be asked to assign one member. Never guesses:
 * a member no fact in `--member-facts` answers for is a refusal, for the reason
 * `function_is_present` refuses - writing the row as defined would assert a
 * struct layout nobody asked the target about, which is exactly what the
 * architecture table this replaced did for `armeb`, `powerpc64`, `powerpc64le`,
 * `hexagon`, `mipsel`, `thumb` and `riscv32`. */
static int member_is_present(const struct facts *f, const char *member) {
  for (size_t i = 0; i < f->member_fact_count; i++) {
    if (strcmp(f->member_facts[i].member, member) == 0)
      return f->member_facts[i].present;
  }
  refuse("--member-facts has no answer for %s. The fact file is written by "
         "build_support/curl_existence_probe.c running the target's compiler "
         "once per member, and it carries one \"<struct>::<member> yes|no\" "
         "line per member in member_rows. Add the missing line rather than "
         "defaulting it.", member, NULL);
}
/* The three-way agreement between the table, the flags and the fact file, run
 * once before anything is written.
 *
 * Direction one: a row carrying `X_HEADER` must be in `header_rows` and must
 * have a fact. Direction two: a line in `header_rows` must name a row in
 * `entries` that carries `X_HEADER`, so the map cannot drift away from the
 * table. Direction three: a fact must name a header `header_rows` asks about,
 * so a fact for a header nothing reads is a refusal rather than a silent
 * widening - it is the shape a typo in the probe takes.
 *
 * Only headers this target's family reaches are required to have a fact. A
 * `M_WINDOWS` header on a Linux target is not asked about, so it needs no
 * answer; requiring one would make the fact file's contents depend on the
 * family, which is the coupling this design exists to remove. */
static void check_header_rows(const struct facts *f) {
  const size_t row_count = sizeof entries / sizeof entries[0];
  const size_t map_count = sizeof header_rows / sizeof header_rows[0];

  for (size_t i = 0; i < row_count; i++) {
    const struct entry *e = &entries[i];
    const unsigned family_bit = 1u << (unsigned)f->family;

    if ((e->flags & X_HEADER) == 0)
      continue;
    if ((e->families & family_bit) == 0)
      continue; /* not asked about on this family */
    if (header_for_row(e) == NULL)
      refuse("internal: header_for_row returned NULL for \"%s\".", e->name, NULL);
    (void)header_is_present(f, header_for_row(e));
  }

  for (size_t i = 0; i < map_count; i++) {
    int found = 0;
    for (size_t j = 0; j < row_count; j++) {
      if (strcmp(entries[j].name, header_rows[i].name) == 0) {
        if ((entries[j].flags & X_HEADER) == 0)
          refuse("header_rows names \"%s\", which exists in entries but does not "
                 "carry X_HEADER. Either the row is a header-existence row and "
                 "needs the flag, or the line in header_rows is stale.",
                 header_rows[i].name, NULL);
        found = 1;
        break;
      }
    }
    if (found == 0)
      refuse("header_rows names \"%s\", which is not a row in entries at all.",
             header_rows[i].name, NULL);
  }

  for (size_t i = 0; i < f->header_fact_count; i++) {
    int asked = 0;
    for (size_t j = 0; j < map_count; j++) {
      if (strcmp(header_rows[j].header, f->header_facts[i].header) == 0) {
        asked = 1;
        break;
      }
    }
    if (asked == 0)
      refuse("--header-facts answers for <%s>, which no X_HEADER row asks about. "
             "Every fact must name a header in header_rows, so a typo in the "
             "probe is caught here rather than read as a wider configuration.",
             f->header_facts[i].header, NULL);
  }
}

/* The same three-way agreement for the function class, run once before anything
 * is written and for the same three reasons.
 *
 * Direction one: a row carrying `X_FUNCTION` must be in `function_rows` and
 * must have a fact. Without either, the row's value would come from the family
 * mask alone, which is the defect this class exists to remove.
 *
 * Direction two: a line in `function_rows` must name a row in `entries` that
 * carries `X_FUNCTION`, so the map cannot drift away from the table.
 *
 * Direction three: a fact must name a function `function_rows` asks about, so
 * a fact for a name nothing reads is a refusal rather than a silent widening.
 * It is also what stops the probe from answering a question twice for
 * `HAVE_UTIME`, whose two `entries` rows share one line.
 *
 * As with the header class, only the functions this target's family reaches are
 * required to have a fact. Requiring the rest would make the fact file's
 * contents depend on the family, which is the coupling this design removes. */
static void check_function_rows(const struct facts *f) {
  const size_t row_count = sizeof entries / sizeof entries[0];
  const size_t map_count = sizeof function_rows / sizeof function_rows[0];

  for (size_t i = 0; i < row_count; i++) {
    const struct entry *e = &entries[i];
    const unsigned family_bit = 1u << (unsigned)f->family;

    if ((e->flags & X_FUNCTION) == 0)
      continue;
    if ((e->families & family_bit) == 0)
      continue; /* not asked about on this family */
    if (function_for_row(e) == NULL)
      refuse("internal: function_for_row returned NULL for \"%s\".", e->name,
             NULL);
    (void)function_is_present(f, function_for_row(e));
  }

  for (size_t i = 0; i < map_count; i++) {
    int found = 0;
    for (size_t j = 0; j < row_count; j++) {
      if (strcmp(entries[j].name, function_rows[i].name) == 0) {
        if ((entries[j].flags & X_FUNCTION) == 0)
          refuse("function_rows names \"%s\", which exists in entries but does "
                 "not carry X_FUNCTION. Either the row is a function-existence "
                 "row and needs the flag, or the line in function_rows is "
                 "stale.", function_rows[i].name, NULL);
        found = 1;
        break;
      }
    }
    if (found == 0)
      refuse("function_rows names \"%s\", which is not a row in entries at all.",
             function_rows[i].name, NULL);
  }

  for (size_t i = 0; i < f->function_fact_count; i++) {
    int asked = 0;
    for (size_t j = 0; j < map_count; j++) {
      if (strcmp(function_rows[j].function, f->function_facts[i].name) == 0) {
        asked = 1;
        break;
      }
    }
    if (asked == 0)
      refuse("--function-facts answers for %s, which no X_FUNCTION row asks "
             "about. Every fact must name a function in function_rows, so a "
             "typo in the probe is caught here rather than read as a wider "
             "configuration.", f->function_facts[i].name, NULL);
  }
}

/* The same three-way agreement for the member class, run once before anything
 * is written and for the same three reasons.
 *
 * Direction one: a row carrying `X_MEMBER` must be in `member_rows` and must
 * have a fact. Without either, the row's value would come from an architecture
 * table or a family mask alone, which is the defect this class exists to remove.
 *
 * Direction two: a line in `member_rows` must name a row in `entries` that
 * carries `X_MEMBER`, so the map cannot drift away from the table.
 *
 * Direction three: a fact must name a member `member_rows` asks about, so a
 * fact nothing reads is a refusal rather than a silent widening.
 *
 * As with the other two classes, only the members this target's family reaches
 * are required to have a fact. Requiring the rest would make the fact file's
 * contents depend on the family, which is the coupling this design removes. */
static void check_member_rows(const struct facts *f) {
  const size_t row_count = sizeof entries / sizeof entries[0];
  const size_t map_count = sizeof member_rows / sizeof member_rows[0];

  for (size_t i = 0; i < row_count; i++) {
    const struct entry *e = &entries[i];
    const unsigned family_bit = 1u << (unsigned)f->family;

    if ((e->flags & X_MEMBER) == 0)
      continue;
    if ((e->families & family_bit) == 0)
      continue; /* not asked about on this family */
    if (member_for_row(e) == NULL)
      refuse("internal: member_for_row returned NULL for \"%s\".", e->name,
             NULL);
    (void)member_is_present(f, member_for_row(e));
  }

  for (size_t i = 0; i < map_count; i++) {
    int found = 0;
    for (size_t j = 0; j < row_count; j++) {
      if (strcmp(entries[j].name, member_rows[i].name) == 0) {
        if ((entries[j].flags & X_MEMBER) == 0)
          refuse("member_rows names \"%s\", which exists in entries but does not "
                 "carry X_MEMBER. Either the row is a member-existence row and "
                 "needs the flag, or the line in member_rows is stale.",
                 member_rows[i].name, NULL);
        found = 1;
        break;
      }
    }
    if (found == 0)
      refuse("member_rows names \"%s\", which is not a row in entries at all.",
             member_rows[i].name, NULL);
  }

  for (size_t i = 0; i < f->member_fact_count; i++) {
    int asked = 0;
    for (size_t j = 0; j < map_count; j++) {
      if (strcmp(member_rows[j].member, f->member_facts[i].member) == 0) {
        asked = 1;
        break;
      }
    }
    if (asked == 0)
      refuse("--member-facts answers for %s, which no X_MEMBER row asks about. "
             "Every fact must name a member in member_rows, so a typo in the "
             "probe is caught here rather than read as a wider configuration.",
             f->member_facts[i].member, NULL);
  }
}
/* Whether a row is defined for these facts. */
static int entry_is_defined(const struct entry *e, const struct facts *f) {
  if ((e->families & (1u << (unsigned)f->family)) == 0)
    return 0;
  if ((e->flags & X_DES_ECB) != 0 && f->des_crypt_ecb == 0)
    return 0;
  if ((e->flags & X_GNU) != 0 && strcmp(f->libc, "gnu") != 0)
    return 0;
  if ((e->flags & X_NOT_GNU) != 0 && strcmp(f->libc, "gnu") == 0)
    return 0;
  if ((e->flags & X_64) != 0 && f->pointer_width != 64)
    return 0;
  if ((e->flags & X_32) != 0 && f->pointer_width != 32)
    return 0;
  /* Last, and never skipped: a header-existence row is defined only when the
   * caller measured that the target has the file. The family mask above has
   * already said this family asks; this says the answer. */
  if ((e->flags & X_HEADER) != 0 && header_is_present(f, header_for_row(e)) == 0)
    return 0;
  /* And the same sentence for a function-existence row, whose question is a
   * declaration rather than a file, and for a member-existence row, whose
   * question is a field that neither of them asks. All three are ANDed with the
   * family mask rather than replacing it: the mask says which families reach for
   * the name, and the probe says whether this target has it. */
  if ((e->flags & X_FUNCTION) != 0 &&
      function_is_present(f, function_for_row(e)) == 0)
    return 0;
  if ((e->flags & X_MEMBER) != 0 &&
      member_is_present(f, member_for_row(e)) == 0)
    return 0;
  return 1;
}

/* ------------------------------------------------------------------------- */
/* Argument parsing                                                            */
/* ------------------------------------------------------------------------- */

static const char *family_for_os(const char *os) {
  if (strcmp(os, "linux") == 0)
    return "linux";
  if (strcmp(os, "freebsd") == 0 || strcmp(os, "netbsd") == 0 ||
      strcmp(os, "openbsd") == 0 || strcmp(os, "dragonfly") == 0)
    return "bsd";
  if (strcmp(os, "solaris") == 0 || strcmp(os, "illumos") == 0)
    return "solaris";
  /* Mac Catalyst is Darwin. It is Mach-O, it links libSystem, and it reaches the
   * same `<netinet/in.h>`, which is what every `FAM_MACOS` row in the table
   * below is a statement about. Upstream agrees without a second case: its
   * Apple test keys on `$host` matching `*-apple-*` and a Mac Catalyst host
   * triple is `*-apple-ios<version>-macabi`.
   *
   * It was refused by name before, on `aarch64-maccatalyst` and
   * `x86_64-maccatalyst`, and the refusal was honest but wrong: this program
   * describes C libraries, and Mac Catalyst's C library is libSystem's.
   * `ios` is here for the same reason and was equally absent. */
  if (strcmp(os, "macos") == 0 || strcmp(os, "ios") == 0 ||
      strcmp(os, "maccatalyst") == 0)
    return "macos";
  if (strcmp(os, "windows") == 0)
    return "windows";
  return NULL;
}

static enum family enum_for_os(const char *os) {
  const char *name = family_for_os(os);
  if (name == NULL) {
    if (strcmp(os, "wasi") == 0) {
      /* Named separately from the generic refusal because the reason is a
       * specific fact about the TLS backend and not about this program's
       * coverage, and `build.zig` refuses the same target with the same words.
       * MBEDTLS_NET_C is compiled out on wasm32-wasi: the mbed-TLS sources
       * `#error` unless MBEDTLS_PLATFORM_IS_UNIXLIKE or _WIN32, and that macro
       * is built from `unix` / `__unix` / `__unix__` /
       * (__APPLE__ && __MACH__) / __HAIKU__ / __midipix__ / _WIN32 - none of
       * which WASI's clang defines - so mbedtls_net_connect and
       * mbedtls_net_accept do not exist there, and lib/vtls/mbedtls.c calls
       * both. */
      refuse("--os wasi: MBEDTLS_NET_C is compiled out on wasm32-wasi, so the "
             "mbed-TLS backend this package requires has no mbedtls_net_connect "
             "or mbedtls_net_accept for lib/vtls/mbedtls.c to call. "
             "See build.zig, refusalFor.", NULL, NULL);
    }
    refuse("--os \"%s\" is not one of the families this generator describes: "
           "linux, macos, ios, maccatalyst, windows, freebsd, netbsd, openbsd, "
           "dragonfly, solaris, illumos.", os, NULL);
  }
  if (strcmp(name, "linux") == 0)
    return FAM_LINUX;
  if (strcmp(name, "bsd") == 0)
    return FAM_BSD;
  if (strcmp(name, "solaris") == 0)
    return FAM_SOLARIS;
  if (strcmp(name, "macos") == 0)
    return FAM_MACOS;
  return FAM_WINDOWS;
}

/* `--libc` is a real input rather than decoration: on Linux it is what separates
 * HAVE_GLIBC_STRERROR_R from HAVE_POSIX_STRERROR_R, and on Linux it is also
 * half of the CURL_OS string. Everywhere else it names the C library so the
 * argument is recorded rather than ignored, and a name outside the accepted set
 * is refused rather than passed through.
 *
 * `bsd` and `sysv` are the two names for the families that have one C library
 * each for the purposes of every row in the table: the BSDs share a libc derived
 * from the 4.4BSD one, and Solaris and illumos share the SysV-derived one. They
 * are family names rather than product names on purpose - a caller that named
 * "freebsd13" would be asserting a version this program has no row for. */
static void check_libc(const struct facts *f) {
  static const char *const accepted[] = {
      "gnu", "musl", "mingw", "msvcrt", "darwin", "bsd", "sysv",
  };
  if (family_for_os(f->os) == NULL)
    refuse("internal: check_libc called before the family was resolved", NULL, NULL);
  if (f->family == FAM_LINUX) {
    for (size_t i = 0; i < 2; i++) {
      if (strcmp(f->libc, accepted[i]) == 0)
        return;
    }
    refuse("--libc \"%s\" with --os linux is not a libc this generator knows. "
           "Accepted for Linux: gnu, musl.", f->libc, NULL);
    return;
  }
  for (size_t i = 0; i < sizeof accepted / sizeof accepted[0]; i++) {
    if (strcmp(f->libc, accepted[i]) == 0)
      return;
  }
  refuse("--libc \"%s\" is not a libc this generator knows. Accepted: gnu, musl, "
         "mingw, msvcrt, darwin, bsd, sysv.", f->libc, NULL);
}

/* Read `--header-facts` into `f`.
 *
 * The input is the preprocessor's own output for
 * `build_support/curl_headers_probe.c` compiled for the target, and each line
 * that carries an answer looks like `CURL_HEADER <name> yes` or `CURL_HEADER
 * <name> no`. `CURL_HEADER` is a token, not a macro, so it survives `-E`; it is
 * what makes an answer line recognisable in the middle of line markers and
 * blank lines, and a line without it is not an answer this program reads.
 *
 * A line that starts with `CURL_HEADER` and is not one of the two spellings is a
 * refusal rather than a skip: a fact file this program cannot read exactly is a
 * fact file it must not act on.
 *
 * The count is bounded by `header_rows` because a fact for a header no row
 * asks about is refused by `check_header_rows`; a longer file than that is
 * either a broken probe or a different set of rows, and both stop the run. */
static void read_header_facts(const char *path, struct header_fact *facts,
                              char names[][256], size_t *out_count) {
  const size_t max = sizeof header_rows / sizeof header_rows[0];
  /* `facts` and `names` are the caller's, not this function's: `struct facts`
   * holds a pointer to them, so arrays local to this function would dangle the
   * moment it returned and every later lookup would read freed stack. `main`
   * owns them for the whole run, and `header_fact_count` records how many slots
   * were filled. */
  size_t count = 0;
  FILE *in;
  char line[512];

  memset(facts, 0, sizeof *facts * max);


  in = fopen(path, "rb");
  if (in == NULL) {
    fprintf(stderr,
            "curl_config_gen: cannot open --header-facts \"%s\" for reading.\n",
            path);
    exit(2);
  }

  while (fgets(line, sizeof line, in) != NULL) {
    const char *p = line;
    char *header;
    size_t n = 0;
    /* The width of one slot in `names`, spelled once so the bound below does not
     * read as `sizeof` of the pointer it was handed. */
    const size_t name_cap = sizeof names[0];

    while (*p == ' ' || *p == '\t')
      p++;
    if (strncmp(p, CURL_HEADER_MARKER, sizeof CURL_HEADER_MARKER - 1) != 0)
      continue; /* a line marker, a blank line, or anything else not an answer */

    /* Bounded before `header` is taken, so the slot exists before it is named. */
    if (count == max) {
      fclose(in);
      refuse("--header-facts \"%s\" carries more answers than header_rows has "
             "rows, one for each header this table asks about. A fact for a "
             "header no row asks about is not something this program can use.",
             path, NULL);
    }
    header = names[count];
    p += sizeof CURL_HEADER_MARKER - 1;
    if (*p != ' ' && *p != '\t')
      refuse("--header-facts \"%s\" has a line beginning \"%s\" with nothing "
             "after it. The probe writes \"" CURL_HEADER_MARKER " \"<header>\" yes\" "
             "or \"" CURL_HEADER_MARKER " \"<header>\" no\".", path,
             CURL_HEADER_MARKER);
    while (*p == ' ' || *p == '\t')
      p++;

    /* The header name, quoted. The quotes are what make the name survive `-E`
     * intact - `linux` is a predefined macro and a bare `linux/tcp.h` arrives
     * as `1/tcp.h` - so they are stripped here rather than the generator
     * comparing against a name the probe could not have produced. */
    if (*p != '"')
      refuse("--header-facts \"%s\" has a line whose header name is not a quoted "
             "string. The probe writes it quoted, and a bare name would be "
             "rewritten by any predefined macro in it.", path, NULL);
    p++;
    while (*p != '\0' && *p != '"' && *p != ' ' && *p != '\t' && *p != '\r' &&
           *p != '\n') {
      if (n + 1 >= name_cap) {
        fclose(in);
        /* `refuse` takes two strings, so the bound goes in prose rather than in
         * a conversion; what matters to the reader is which file and which
         * header, and both are named. */
        refuse("--header-facts \"%s\" names a header this program cannot hold. "
               "The probe writes the template's own <...> spelling, none of "
               "which is that long.", path, NULL);
      }
      header[n++] = *p++;
    }
    header[n] = '\0';
    if (*p != '"')
      refuse("--header-facts \"%s\" has an unterminated quoted name for <%s>. The "
             "probe writes \"<header>\" with both quotes.", path, header);
    p++;

    while (*p == ' ' || *p == '\t')
      p++;

    facts[count].header = header;
    if (strncmp(p, "yes", 3) == 0)
      facts[count].present = 1;
    else if (strncmp(p, "no", 2) == 0)
      facts[count].present = 0;
    else {
      fclose(in);
      refuse("--header-facts \"%s\" has a line for <%s> whose answer is neither "
             "\"yes\" nor \"no\".", path, header);
    }
    count++;
  }

  if (ferror(in) != 0) {
    fclose(in);
    refuse("--header-facts \"%s\" could not be read to the end.", path, NULL);
  }
  fclose(in);

  *out_count = count;
}

/* Read `--function-facts` into `f`.
 *
 * The input is `build_support/curl_existence_probe.c`'s output for the target:
 * one line per function, `CURL_FUNCTION "<name>" yes` or
 * `CURL_FUNCTION "<name>" no`. `CURL_FUNCTION` is a bare token so it survives
 * being written out, and a line without it is not an answer this program reads.
 * A line that starts with the marker and is not one of the two spellings is a
 * refusal rather than a skip, for the reason the header reader gives: a fact
 * file this program cannot read exactly is one it must not act on.
 *
 * The name is quoted for the same reason the header reader quotes its header -
 * to survive any rewriting between the probe and here - and the count is
 * bounded by `function_rows` because a fact for a name no row asks about is
 * refused by `check_function_rows`. A longer file than that is a broken probe
 * or a different set of rows, and both stop the run.
 *
 * `facts` and `names` are the caller's, not this function's: `struct facts`
 * holds a pointer to them, so arrays local here would dangle the moment this
 * returned. `main` owns them for the whole run. */
static void read_function_facts(const char *path, struct function_fact *facts,
                                char names[][256], size_t *out_count) {
  const size_t max = sizeof function_rows / sizeof function_rows[0];
  const size_t name_cap = sizeof names[0];
  size_t count = 0;
  FILE *in;
  char line[512];

  memset(facts, 0, sizeof *facts * max);

  in = fopen(path, "rb");
  if (in == NULL) {
    fprintf(stderr,
            "curl_config_gen: cannot open --function-facts \"%s\" for reading.\n",
            path);
    exit(2);
  }

  while (fgets(line, sizeof line, in) != NULL) {
    const char *p = line;
    char *function;
    size_t n = 0;

    while (*p == ' ' || *p == '\t')
      p++;
    if (strncmp(p, CURL_FUNCTION_MARKER, sizeof CURL_FUNCTION_MARKER - 1) != 0)
      continue; /* not an answer this program reads */

    /* Bounded before `function` is taken, so the slot exists before it is
     * named. */
    if (count == max) {
      fclose(in);
      refuse("--function-facts \"%s\" carries more answers than function_rows "
             "has rows, one for each function this table asks about. A fact for "
             "a function no row asks about is not something this program can "
             "use.", path, NULL);
    }
    function = names[count];
    p += sizeof CURL_FUNCTION_MARKER - 1;
    if (*p != ' ' && *p != '\t')
      refuse("--function-facts \"%s\" has a line beginning \"%s\" with nothing "
             "after it. The probe writes \"" CURL_FUNCTION_MARKER " \"<fn>\" "
             "yes\" or \"" CURL_FUNCTION_MARKER " \"<fn>\" no\".", path,
             CURL_FUNCTION_MARKER);
    while (*p == ' ' || *p == '\t')
      p++;

    if (*p != '"')
      refuse("--function-facts \"%s\" has a line whose function name is not a "
             "quoted string. The probe writes it quoted, and a bare name would "
             "be rewritten by any predefined macro in it.", path, NULL);
    p++;
    while (*p != '\0' && *p != '"' && *p != ' ' && *p != '\t' && *p != '\r' &&
           *p != '\n') {
      if (n + 1 >= name_cap) {
        fclose(in);
        /* `refuse` takes two strings, so the bound goes in prose rather than in
         * a conversion; what matters to the reader is which file and which
         * function, and both are named. */
        refuse("--function-facts \"%s\" names a function this program cannot "
               "hold. The probe writes the identifier itself, none of which is "
               "that long.", path, NULL);
      }
      function[n++] = *p++;
    }
    function[n] = '\0';
    if (*p != '"')
      refuse("--function-facts \"%s\" has an unterminated quoted name for %s. "
             "The probe writes \"<function>\" with both quotes.", path,
             function);
    p++;

    while (*p == ' ' || *p == '\t')
      p++;

    facts[count].name = function;
    if (strncmp(p, "yes", 3) == 0)
      facts[count].present = 1;
    else if (strncmp(p, "no", 2) == 0)
      facts[count].present = 0;
    else {
      fclose(in);
      refuse("--function-facts \"%s\" has a line for %s whose answer is neither "
             "\"yes\" nor \"no\".", path, function);
    }
    count++;
  }

  if (ferror(in) != 0) {
    fclose(in);
    refuse("--function-facts \"%s\" could not be read to the end.", path, NULL);
  }
  fclose(in);

  *out_count = count;
}

/* Read `--member-facts` into `f`.
 *
 * The input is the *same file* `read_function_facts` just read: one facts file,
 * one build step, two markers. Every line this reader skips because it does not
 * start with `CURL_MEMBER` is a `CURL_FUNCTION` line or a comment, and every
 * line `read_function_facts` skipped for the same reason is one of these. That
 * is why there are two markers rather than one spelling per line, and it is what
 * makes the second class free: no second run step, no second tracked file
 * input, no second output path that could disagree with the first.
 *
 * The key is `"<struct>::<member>"`, quoted for the reason the function reader
 * quotes its name: a bare spelling could be rewritten between the probe and here.
 * The count is bounded by `member_rows` for the reason it is bounded there.
 *
 * `facts` and `names` are the caller's, for the reason they are in the other two
 * readers: `struct facts` holds a pointer to them and `main` outlives every read
 * of them. */
static void read_member_facts(const char *path, struct member_fact *facts,
                              char names[][256], size_t *out_count) {
  const size_t max = sizeof member_rows / sizeof member_rows[0];
  const size_t name_cap = sizeof names[0];
  size_t count = 0;
  FILE *in;
  char line[512];

  memset(facts, 0, sizeof *facts * max);

  in = fopen(path, "rb");
  if (in == NULL) {
    fprintf(stderr,
            "curl_config_gen: cannot open --member-facts \"%s\" for reading.\n",
            path);
    exit(2);
  }

  while (fgets(line, sizeof line, in) != NULL) {
    const char *p = line;
    char *member;
    size_t n = 0;

    while (*p == ' ' || *p == '\t')
      p++;
    if (strncmp(p, CURL_MEMBER_MARKER, sizeof CURL_MEMBER_MARKER - 1) != 0)
      continue; /* a CURL_FUNCTION line, or anything else not an answer */

    if (count == max) {
      fclose(in);
      refuse("--member-facts \"%s\" carries more answers than member_rows has "
             "rows, one for each struct member this table asks about. A fact "
             "for a member no row asks about is not something this program can "
             "use.", path, NULL);
    }
    member = names[count];
    p += sizeof CURL_MEMBER_MARKER - 1;
    if (*p != ' ' && *p != '\t')
      refuse("--member-facts \"%s\" has a line beginning \"%s\" with nothing "
             "after it. The probe writes \"" CURL_MEMBER_MARKER " \"<struct>::<member>\" yes\" "
             "or \"" CURL_MEMBER_MARKER " \"<struct>::<member>\" no\".", path,
             CURL_MEMBER_MARKER);
    while (*p == ' ' || *p == '\t')
      p++;

    if (*p != '"')
      refuse("--member-facts \"%s\" has a line whose member key is not a quoted "
             "string. The probe writes it quoted, and a bare spelling would be "
             "rewritten by any predefined macro in it.", path, NULL);
    p++;
    while (*p != '\0' && *p != '"' && *p != ' ' && *p != '\t' && *p != '\r' &&
           *p != '\n') {
      if (n + 1 >= name_cap) {
        fclose(in);
        refuse("--member-facts \"%s\" names a member this program cannot hold. "
               "The probe writes \"<struct>::<member>\", and no struct in the "
               "table has a name that long.", path, NULL);
      }
      member[n++] = *p++;
    }
    member[n] = '\0';
    if (*p != '"')
      refuse("--member-facts \"%s\" has an unterminated quoted key for %s. The "
             "probe writes \"<struct>::<member>\" with both quotes.", path,
             member);
    p++;

    while (*p == ' ' || *p == '\t')
      p++;

    facts[count].member = member;
    if (strncmp(p, "yes", 3) == 0)
      facts[count].present = 1;
    else if (strncmp(p, "no", 2) == 0)
      facts[count].present = 0;
    else {
      fclose(in);
      refuse("--member-facts \"%s\" has a line for %s whose answer is neither "
             "\"yes\" nor \"no\".", path, member);
    }
    count++;
  }

  if (ferror(in) != 0) {
    fclose(in);
    refuse("--member-facts \"%s\" could not be read to the end.", path, NULL);
  }
  fclose(in);

  *out_count = count;
}

static void usage(void) {
  fprintf(stderr,
          "curl_config_gen - writes curl_config.h for one target.\n"
          "\n"
          "  --os <tag>                 required: linux, macos, ios, maccatalyst,\n"
          "                              windows, freebsd, netbsd, openbsd, dragonfly,\n"
          "                              solaris, illumos\n"
          "  --arch <tag>               required: the target's Zig architecture tag\n"
          "  --pointer-width <32|64>    required\n"
          "  --endian <little|big>      required\n"
          "  --libc <tag>               required: gnu, musl, mingw, msvcrt, darwin,\n"
          "                              bsd, sysv\n"
          "  --mbedtls-des-crypt-ecb <yes|no>\n"
          "                              required, no default: this is a fact about\n"
          "                              the mbed-TLS headers, not about the target\n"
          "  --header-facts <path>       required, no default: one \"<header> yes|no\"\n"
          "                              line per header in header_rows, measured\n"
          "                              for THIS target by compiling\n"
          "                              build_support/curl_headers_probe.c. The 35\n"
          "                              header-existence rows are decided from it,\n"
          "                              never from the OS family\n"
          "  --function-facts <path>    required, no default: one \"<function>\n"
          "                              yes|no\" line per function in\n"
          "                              function_rows, measured for THIS target by\n"
          "                              compiling one probe per function with\n"
          "                              build_support/curl_existence_probe.c. The\n"
          "                              47 function-existence rows are decided\n"
          "                              from it, never from the OS family\n"
          "  --member-facts <path>      required, no default: one\n"
          "                              \"<struct>::<member> yes|no\" line per\n"
          "                              member in member_rows, measured for THIS\n"
          "                              target the same way and in the same file as\n"
          "                              --function-facts; the two share one build\n"
          "                              step and are told apart by their marker.\n"
          "                              HAVE_SOCKADDR_IN6_SIN6_SCOPE_ID is\n"
          "                              decided from it, never from an\n"
          "                              architecture\n"
          "  --ca-bundle <path>         optional; compiled into CURL_CA_BUNDLE\n"
          "  --ca-path <path>           optional; compiled into CURL_CA_PATH\n"
          "  --curl-version <x.y.z>     required: the libcurl release this\n"
          "                              configures, read out of\n"
          "                              include/curl/curlver.h:35 and named in\n"
          "                              the header this program writes\n"
          "  --output <path>            required: where curl_config.h is written\n"
          "\n"
          "The output is a function of these arguments and of the files named\n"
          "by --header-facts, --function-facts and --member-facts. The program\n"
          "reads no environment variable, no host macro and no host header, and\n"
          "compiles nothing itself.\n");
}

/* ------------------------------------------------------------------------- */
/* Emission                                                                    */
/* ------------------------------------------------------------------------- */

static void emit_header_comment(FILE *out, const struct facts *f,
                                const char *version) {
  fprintf(out,
          "/* Generated by build_support/curl_config_gen.c for libcurl %s.\n"
          " *\n"
          " * Do not edit, and do not check this file in: `zig build` regenerates\n"
          " * it for the target being built, into the build cache, because\n"
          " * lib/curl_setup.h:140 includes it by bare name and its contents are a\n"
          " * property of the target rather than of this source tree.\n"
          " *\n"
          " * The generator was given exactly:\n"
          " *   --os                    %s\n"
          " *   --arch                  %s\n"
          " *   --pointer-width         %d\n"
          " *   --endian                %s\n"
          " *   --libc                  %s\n"
          " *   --mbedtls-des-crypt-ecb %s\n"
          " *   --ca-bundle             %s\n"
          " *   --ca-path               %s\n"
          " *   --header-facts          yes|no for each of the %d header-existence\n"
          " *                           rows, measured for this target by\n"
          " *                           compiling build_support/curl_headers_probe.c\n"
          " *   --function-facts         yes|no for each of the %d function-existence\n"
          " *                           rows, measured for this target by compiling\n"
          " *                           one probe per function with\n"
          " *                           build_support/curl_existence_probe.c\n"
          " *   --member-facts          yes|no for each of the %d member-existence\n"
          " *                           rows, in the same file as\n"
          " *                           --function-facts and from the same probe\n"
          " *                           run: one build step asks both questions\n"
          " *\n"
          " * Same arguments, same bytes, every time: the generator reads nothing\n"
          " * from the machine it runs on, so running it on the build host to\n"
          " * configure a cross target is correct and is what happened above. The\n"
          " * probe was likewise compiled for this target, so its answers are the\n"
          " * target's and not the host's.\n"
          " *\n"
          " * Entry order and every entry's comment are those of\n"
          " * lib/curl_config-cmake.h.in, the template upstream's CMake build\n"
          " * fills in. An entry this configuration does not set is written the way\n"
          " * CMake's own configure_file writes an unset #cmakedefine: as a C\n"
          " * comment whose body is `#undef NAME`. The literal is spelled in\n"
          " * prose because a slash-star sequence inside this comment would end\n"
          " * it early and turn the rest of the banner into C.\n",
          version, f->os, f->arch, f->pointer_width, f->endian, f->libc,
          f->des_crypt_ecb ? "yes" : "no",
          f->ca_bundle ? f->ca_bundle : "(not given)",
          f->ca_path ? f->ca_path : "(not given)",
          (int)(sizeof header_rows / sizeof header_rows[0]),
          (int)(sizeof function_rows / sizeof function_rows[0]),
          (int)(sizeof member_rows / sizeof member_rows[0]));

  /* The absent ones, by name, inside the comment. A reader of the generated
   * header can then see that a `HAVE_NETINET_IN6_H` left undefined is a measured
   * absence and not an oversight, and can match the spelling against the table
   * below it. Written before the banner's closing delimiter so it stays part of
   * that comment rather than becoming stray text between two declarations. */
  {
    int listed = 0;
    for (size_t i = 0; i < f->header_fact_count; i++) {
      if (f->header_facts[i].present != 0)
        continue;
      fprintf(out, " *%s <%s>\n", listed == 0 ? "  absent: " : "          ",
              f->header_facts[i].header);
      listed = 1;
    }
    if (listed == 0)
      fputs(" *  absent: none; the target has every header this table asks"
            " about.\n", out);
  }
  /* The absent functions, by name, in the same comment and after the absent
   * headers. A reader of the generated header can see that a `HAVE_ACCEPT4`
   * left undefined is a measured absence on that target rather than an
   * oversight, which is the whole difference `X_FUNCTION` buys. */
  {
    int listed = 0;
    for (size_t i = 0; i < f->function_fact_count; i++) {
      if (f->function_facts[i].present != 0)
        continue;
      fprintf(out, " *%s %s\n", listed == 0 ? "  absent: " : "          ",
              f->function_facts[i].name);
      listed = 1;
    }
    if (listed == 0)
      fputs(" *          none; the target declares every function this table"
            " asks about.\n", out);
  }
  /* And the absent members, in the same comment and after the absent
   * functions. A `HAVE_SOCKADDR_IN6_SIN6_SCOPE_ID` left undefined is then
   * visibly a measured absence on this target - the target's own
   * `<netinet/in.h>` would not take the assignment - rather than an
   * architecture nobody wrote down. */
  {
    int listed = 0;
    for (size_t i = 0; i < f->member_fact_count; i++) {
      if (f->member_facts[i].present != 0)
        continue;
      fprintf(out, " *%s %s\n", listed == 0 ? "  absent: " : "          ",
              f->member_facts[i].member);
      listed = 1;
    }
    if (listed == 0)
      fputs(" *          none; the target accepts every struct member this"
            " table asks about.\n", out);
  }
  fputs(" */\n", out);
}

static void emit(FILE *out, const struct facts *f, const char *version) {
  const size_t count = sizeof entries / sizeof entries[0];

  emit_header_comment(out, f, version);

  /* `_GNU_SOURCE` on the glibc family, and in the configuration rather than on
   * the compile line because that is what it is: a fact about the C library the
   * target has. Two rows in the table depend on it.
   *
   * `HAVE_GLIBC_STRERROR_R` names glibc's `__xpg_strerror_r` spelling, and
   * glibc only maps `strerror_r` onto it under `__USE_GNU`
   * (`/usr/include/string.h`, inside `#ifdef __USE_GNU`). Without the macro the
   * XSI `int strerror_r(int, char *, size_t)` is what the header declares, and
   * `lib/curlx/strerr.c:294` assigns it to a `const char *`. Upstream's
   * autotools build gets the same macro from `AC_USE_SYSTEM_EXTENSIONS`, which
   * puts `-D_GNU_SOURCE` on the command line; this generator has no command line
   * for it, and `lib/curl_setup.h:138-140` includes this header before the first
   * system header, so the header is the place the fact belongs.
   *
   * `-std=c99` would set `__STRICT_ANSI__` and hide the POSIX declarations
   * upstream's sources use; `build.zig` pins `-std=gnu99` for that reason and
   * says so. This macro is the other half of it: `gnu99` restores `_DEFAULT_SOURCE`,
   * and `_GNU_SOURCE` is what makes the glibc-specific rows above true. */
  if (f->family == FAM_LINUX && strcmp(f->libc, "gnu") == 0)
    fprintf(out, "#ifndef _GNU_SOURCE\n#define _GNU_SOURCE 1\n#endif\n");

  for (size_t i = 0; i < count; i++) {
    const struct entry *e = &entries[i];
    int defined = entry_is_defined(e, f);

    fprintf(out, "\n%s\n", e->comment);
    if (e->name == NULL)
      continue;

    /* The template's own fallback for the export symbol, reproduced at the
     * point it belongs: `lib/curl_config-cmake.h.in:180-183` writes the
     * #ifndef immediately after the CURL_EXTERN_SYMBOL row. */
    if (strcmp(e->name, "CURL_EXTERN_SYMBOL") == 0) {
      fprintf(out,
              "#ifndef CURL_EXTERN_SYMBOL\n"
              "#define CURL_EXTERN_SYMBOL\n"
              "#endif\n");
    }

    if (defined == 0) {
      fprintf(out, "/* #undef %s */\n", e->name);
      continue;
    }

    switch (e->shape) {
      case SH_FLAG: {
        /* `_FILE_OFFSET_BITS` is the one flag row that carries an explicit
         * literal rather than a bare 1: the template writes
         * `#cmakedefine _FILE_OFFSET_BITS ${_FILE_OFFSET_BITS}`, and CMake fills
         * the substitution. Every other flag row is `#cmakedefine X 1` upstream,
         * so `#define X 1` is its output verbatim. `e->value` is NULL on those
         * rows, which is why the test below guards it rather than comparing it.
         */
        if (e->value != NULL)
          fprintf(out, "#define %s %s\n", e->name, e->value);
        else
          fprintf(out, "#define %s 1\n", e->name);
        break;
      }
      case SH_STRING: {
        /* CURL_OS first, and by name rather than by sentinel: its value is
         * computed from four of the arguments rather than copied from the row,
         * so its `value` field is NULL and a NULL-first test would emit it
         * undefined. See curl_os() for the string and its provenance. */
        if (strcmp(e->name, "CURL_OS") == 0) {
          fprintf(out, "#define %s \"%s\"\n", e->name, curl_os(f));
          break;
        }
        /* The two CA rows are the other two whose value is not in the table:
         * it is whatever `-Dca-bundle` / `-Dca-path` was given, and an option
         * that was not given leaves the row undefined, which is how a build says
         * "no built-in store" instead of naming a path it does not have. */
        if (e->value == NULL) {
          fprintf(out, "/* #undef %s */\n", e->name);
        } else if (strcmp(e->value, FROM_CA_BUNDLE) == 0) {
          if (f->ca_bundle != NULL)
            fprintf(out, "#define %s \"%s\"\n", e->name, f->ca_bundle);
          else
            fprintf(out, "/* #undef %s */\n", e->name);
        } else if (strcmp(e->value, FROM_CA_PATH) == 0) {
          if (f->ca_path != NULL)
            fprintf(out, "#define %s \"%s\"\n", e->name, f->ca_path);
          else
            fprintf(out, "/* #undef %s */\n", e->name);
        } else {
          fprintf(out, "#define %s \"%s\"\n", e->name, e->value);
        }
        break;
      }
      case SH_SIZE: {
        const int n = size_of(f, e->value);
        if (n == 0)
          refuse("internal: no size rule for \"%s\" (%s)", e->value, e->name);
        fprintf(out, "#define %s %d\n", e->name, n);
        break;
      }
    }
  }

  fputc('\n', out);
}

/* ------------------------------------------------------------------------- */
/* main                                                                        */
/* ------------------------------------------------------------------------- */

int main(int argc, char **argv) {
  struct facts f;
  const char *output = NULL;
  const char *version = NULL;
  const char *os = NULL, *arch = NULL, *width = NULL, *endian = NULL;
  const char *libc = NULL, *des = NULL, *ca_bundle = NULL, *ca_path = NULL;
  const char *header_facts_path = NULL;
  const char *function_facts_path = NULL;
  const char *member_facts_path = NULL;
  /* Storage for the header probe's answers, owned here because `struct facts`
   * only points at them and `main` outlives every read of them. Sized from
   * `header_rows` so a fact file with more answers than rows is a refusal in
   * `read_header_facts` rather than an overrun. */
  struct header_fact facts[sizeof header_rows / sizeof header_rows[0]];
  char names[sizeof header_rows / sizeof header_rows[0]][256];
  /* The same two things for the function probe, sized from `function_rows` and
   * for the same reason. Separate storage rather than a second array of
   * pointers, because `read_function_facts` writes into the caller's memory and
   * `struct facts` holds the only pointer to it. */
  struct function_fact function_facts[sizeof function_rows /
                                       sizeof function_rows[0]];
  char function_names[sizeof function_rows / sizeof function_rows[0]][256];
  /* And the same two things for the member rows, sized from `member_rows`. The
   * file is the same file: `read_function_facts` and `read_member_facts` each
   * read it and each skips the other's marker, which is how one collector run
   * and one output path carry both classes. */
  struct member_fact member_facts[sizeof member_rows / sizeof member_rows[0]];
  char member_names[sizeof member_rows / sizeof member_rows[0]][256];
  FILE *out;

  memset(&f, 0, sizeof f);
  f.des_crypt_ecb = 0;
  f.header_facts = facts;
  f.function_facts = function_facts;
  f.member_facts = member_facts;

  if (argc == 1)
    usage();

  for (int i = 1; i < argc; i++) {
    const char *arg = argv[i];
    /* Every option is `--name value`, never `--name=value`, so a value that
     * looks like an option cannot be silently swallowed as a flag. */
#define NEXT(name)                                                            \
  do {                                                                        \
    if (i + 1 >= argc)                                                        \
      refuse("%s needs a value.", name, NULL);                                 \
    i++;                                                                      \
  } while (0)

    if (strcmp(arg, "--os") == 0) {
      NEXT("--os");
      os = argv[i];
    } else if (strcmp(arg, "--arch") == 0) {
      NEXT("--arch");
      arch = argv[i];
    } else if (strcmp(arg, "--pointer-width") == 0) {
      NEXT("--pointer-width");
      width = argv[i];
    } else if (strcmp(arg, "--endian") == 0) {
      NEXT("--endian");
      endian = argv[i];
    } else if (strcmp(arg, "--libc") == 0) {
      NEXT("--libc");
      libc = argv[i];
    } else if (strcmp(arg, "--mbedtls-des-crypt-ecb") == 0) {
      NEXT("--mbedtls-des-crypt-ecb");
      des = argv[i];
    } else if (strcmp(arg, "--ca-bundle") == 0) {
      NEXT("--ca-bundle");
      ca_bundle = argv[i];
    } else if (strcmp(arg, "--ca-path") == 0) {
      NEXT("--ca-path");
      ca_path = argv[i];
    } else if (strcmp(arg, "--header-facts") == 0) {
      NEXT("--header-facts");
      header_facts_path = argv[i];
    } else if (strcmp(arg, "--function-facts") == 0) {
      NEXT("--function-facts");
      function_facts_path = argv[i];
    } else if (strcmp(arg, "--member-facts") == 0) {
      NEXT("--member-facts");
      member_facts_path = argv[i];
    } else if (strcmp(arg, "--output") == 0) {
      NEXT("--output");
      output = argv[i];
    } else if (strcmp(arg, "--curl-version") == 0) {
      NEXT("--curl-version");
      version = argv[i];
    } else {
      refuse("unknown argument \"%s\". Run with no arguments for usage.", arg, NULL);
    }
#undef NEXT
  }

  if (os == NULL)
    refuse("--os is required.", NULL, NULL);
  if (arch == NULL)
    refuse("--arch is required.", NULL, NULL);
  if (width == NULL)
    refuse("--pointer-width is required.", NULL, NULL);
  if (endian == NULL)
    refuse("--endian is required.", NULL, NULL);
  if (libc == NULL)
    refuse("--libc is required.", NULL, NULL);
  if (des == NULL) {
    refuse("--mbedtls-des-crypt-ecb is required and has no default. It is a "
           "property of the mbed-TLS headers, not of the target, so none of "
           "--os, --arch, --pointer-width, --endian or --libc determines it.",
           NULL, NULL);
  }
  if (header_facts_path == NULL)
    refuse("--header-facts is required and has no default. The 35 "
           "header-existence rows ask whether the TARGET has a file, and no "
           "other argument determines that; the answers come from compiling "
           "build_support/curl_headers_probe.c for the target. See "
           "build_support/curl_headers_probe.c.", NULL, NULL);
  if (function_facts_path == NULL)
    refuse("--function-facts is required and has no default. The 47 "
           "function-existence rows ask whether the TARGET declares a name, and "
           "no other argument determines that; the answers come from compiling "
           "one probe per function with build_support/curl_existence_probe.c "
           "for the target. See build_support/curl_existence_probe.c.",
           NULL, NULL);
  if (member_facts_path == NULL)
    refuse("--member-facts is required and has no default. The "
           "member-existence row asks whether the TARGET's own headers let curl "
           "assign the member, and no argument above determines that - least of "
           "all not --arch, which is precisely why no architecture table is left "
           "here to refuse on; the answer comes from compiling one probe per "
           "member with build_support/curl_existence_probe.c for the target. See "
           "build_support/curl_existence_probe.c.", NULL, NULL);
  if (output == NULL)
    refuse("--output is required.", NULL, NULL);
  if (version == NULL)
    refuse("--curl-version is required: the header records which libcurl "
           "release it configures, read out of include/curl/curlver.h.",
           NULL, NULL);

  if (strcmp(width, "32") == 0)
    f.pointer_width = 32;
  else if (strcmp(width, "64") == 0)
    f.pointer_width = 64;
  else
    refuse("--pointer-width \"%s\" is neither 32 nor 64, and every SIZEOF_* "
           "row in lib/curl_setup.h is derived from it.", width, NULL);

  if (strcmp(endian, "little") != 0 && strcmp(endian, "big") != 0)
    refuse("--endian \"%s\" is neither little nor big.", endian, NULL);

  if (strcmp(des, "yes") == 0)
    f.des_crypt_ecb = 1;
  else if (strcmp(des, "no") == 0)
    f.des_crypt_ecb = 0;
  else
    refuse("--mbedtls-des-crypt-ecb \"%s\" is neither yes nor no.", des, NULL);

  f.os = os;
  f.arch = arch;
  f.libc = libc;
  f.endian = endian;
  f.ca_bundle = ca_bundle;
  f.ca_path = ca_path;
  f.family = enum_for_os(os);
  check_libc(&f);

  /* Read both probes' answers - three reads over two files - and check the
   * three-way agreement between the table, each of the three maps and its fact
   * file, all before anything is written, so a refusal cannot leave a
   * half-written header behind. Every check runs before anything writes. */
  read_header_facts(header_facts_path, facts, names, &f.header_fact_count);
  read_function_facts(function_facts_path, function_facts, function_names,
                      &f.function_fact_count);
  read_member_facts(member_facts_path, member_facts, member_names,
                    &f.member_fact_count);
  check_header_rows(&f);
  check_function_rows(&f);
  check_member_rows(&f);

  out = fopen(output, "wb");
  if (out == NULL) {
    fprintf(stderr, "curl_config_gen: cannot open \"%s\" for writing.\n", output);
    return 1;
  }

  emit(out, &f, version);

  if (fclose(out) != 0) {
    fprintf(stderr, "curl_config_gen: cannot finish writing \"%s\".\n", output);
    return 1;
  }
  return 0;
}
