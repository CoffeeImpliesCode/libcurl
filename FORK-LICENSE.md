# FORK-LICENSE.md — the grant for this fork's own files

[`NOTICE.md`](NOTICE.md) is the inventory: which files are upstream's, which are
this fork's, and which term covers each. This file is the grant itself, for the
second group only.

## 1. The native source is not covered by anything below

The 418 files under `lib/`, `include/`, and `COPYING`, `README` and
`RELEASE-NOTES` are curl's, whole from `curl-8.22.0.tar.xz` and never edited.
They carry the `curl` licence as recorded per file in `NOTICE.md`, whose
authoritative text is `COPYING`, sha256
`82f2f4427d6545ee5aaac4f0b80428da6cc8ba41c2cf5da3a03680ec327b9681`. Three of
those files are ISC instead of curl, one is `curl AND ISC`, and two carry a
public-domain block inside a curl file; that inventory, not this file, is what
says so.

Nothing in this file re-grants, narrows, widens or conditions any of those
terms, and nothing here asserts that Daniel Stenberg, the curl contributors, or
any named author wrote, reviewed or endorsed a line of fork code.

## 2. The fork-authored material

Everything else in this repository — the Zig build, the generated-configuration
C generator, the typed module and its aggregate translation header, the tests
and the example, the consumer package, the runtime-loading route, the packaging,
the integrity script and the documentation — was written for this fork. The
per-file list is in [`NOTICE.md`](NOTICE.md), "Fork-specific notice"; it is
bound by this grant whether or not a given file had landed when this file was
written. None of it is upstream material and none of it is derived from a
third-party source.

### Grant

**Those files are released under the `curl` licence**, matching the primary
upstream term of this project. It is a permissive MIT/X derivative rather than
stock MIT — `NOTICE.md`, "The upstream term", names the four differences — and
the identifier that says so is `curl`.

```
curl Licence

Copyright (c) 2026 the contributors to this fork

All rights reserved.

Permission to use, copy, modify, and distribute this software for any purpose
with or without fee is hereby granted, provided that the above copyright
notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF THIRD PARTY RIGHTS. IN
NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
OR OTHER DEALINGS IN THE SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall not
be used in advertising or otherwise to promote the sale, use or other dealings
in this Software without prior written authorization of the copyright holder.
```

Everything above except the title line and the copyright line is `COPYING`
verbatim: the permission is `COPYING:8-10`, the warranty disclaimer `:12-18`
and the advertising clause `:20-22`. Two adaptations, both deliberate:

* The copyright line names **this fork's contributors**, not
  `Copyright (c) 1996 - 2026, Daniel Stenberg, <daniel@haxx.se>, and many
  contributors, see the THANKS file` (`COPYING:3-4`). Attributing fork-authored
  files to upstream authors would be false, and the notice this grant carries
  is the fork's own.
* The title is `curl Licence` rather than `COPYING`'s
  `COPYRIGHT AND PERMISSION NOTICE`.

The advertising clause is **kept**, because it is part of the term being
adopted. A fork grant that dropped it would be granting a term upstream never
granted, and `curl` would then be a misdescription of what this text says.

The same obligation the `curl` licence imposes on curl's own code applies to
this text: keep the notice with copies of the fork's files.

### Authority for that grant

The owner of this repository authorized per-project licensing for fork-authored
additions as part of the SDK contract migration, with the term chosen per
project to match that project's primary upstream terms where that is
appropriate. curl's primary upstream term is the `curl` licence, so `curl` is
the choice. The authorization is recorded here and in `NOTICE.md`; the term
above is the owner's, reached by that authorization and not by any upstream
grant.

The owner is not named and no individual copyright holder is invented: the
copyright line above is deliberately the collective one.

### SPDX identifier

```
curl
```

That is the identifier, with no `LicenseRef-` wrapper and no `MIT`. The
distinction is deliberate in both directions. A fork whose primary term carries
added conditions needs an identifier that names them, and `curl` is upstream's
own registered-style identifier for exactly this term, so a scanner reading
`curl` stops at the right place. Writing `MIT` instead would be wrong for three
reasons a downstream reader can check against `COPYING`: the permission is
granted "with or without fee" rather than "free of charge" (`:8-9`), the
copyright is followed by `All rights reserved.` (`:6`), and the advertising
clause (`:20-22`) has no counterpart in stock MIT. `MIT` is neither the term
adopted here nor an accurate description of it.

Every fork-authored **source, build, packaging and script** file carries
`SPDX-License-Identifier: curl` on its own line inside the file's header
comment, and `tools/check-provenance.sh` fails naming the file if one does not.
The tag's position inside the block is not pinned, because the convention in
this workspace is to close the header with it. The
documentation and digest records do not carry a tag: they are prose and data,
and `NOTICE.md` names each of them explicitly so that a scanner finding no
identifier in `README.md` reads a recorded reason rather than an apparent gap.

### What this does not do

* It does not re-license, sublicense or add a condition to any curl file, and
  it does not touch the ISC files, the public-domain blocks or the FSF automake
  notices inventoried in `NOTICE.md`.
* It does not assert that Daniel Stenberg, the curl contributors, Red Hat, the
  Internet Software Consortium, Alexander Peslyak, the Free Software
  Foundation or any other named party authored, reviewed, endorsed or is
  affiliated with the fork's files.
* It does not discharge curl's attribution obligation. A consumer who ships a
  libcurl 8.22.0 binary, static or shared library, or header set, still owes
  the notice in `COPYING`; see `NOTICE.md` for where it travels.
* It does not claim that the `curl` terms are the only ones the owner could have
  chosen for independently authored work. They are the terms chosen, and they
  happen to match upstream's.

## 3. Material carried but not authored here

There is none. This repository vendors no third-party code, no downloaded
header and no external data file. The 418 files listed in `UPSTREAM.sha256` are
the complete upstream material, and nothing was added to them.

What this build generates is not carried material either, and the distinction
is worth keeping exact rather than dropping a category to make the sentence
short. `curl_config.h` is generated by `build_support/curl_config_gen.c`
from the target's facts and lands in the build cache rather than in this tree;
`runtime/generate.zig` does the same for the runtime dispatch. Nothing is
fetched to make them, no third-party code is in them, and neither is installed
or shipped: every file under `runtime/` and `build_support/` in this tree is a
fork-authored file under section 2.

## 4. Why a separate file at all

`NOTICE.md` names which fork-authored files carry an `SPDX-License-Identifier`
line and which carry the same grant in prose without one, and which upstream
file carries which term. This file exists so that the authority, the grant text
and the limits of that grant live in one place, next to the inventory rather
than scattered across the files themselves.