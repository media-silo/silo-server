<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0005-libraries

Modified: 2026-10-19

# Libraries

This proposes that the operator manage a silo's libraries from the console, within folders the
machine's owner has named, and that keeping the index current stop being anyone's job but the
server's. Libraries gain routes to add and remove them, bounded by library roots in `silo.json`.
The server walks each library at startup, after anything it changes itself, when a library is
added or comes back, and on a steady cadence besides, so a change made behind its back is noticed
without being asked for. The scan route goes: what the operator needs from it — what the last walk
found — becomes something to read. And a library whose folder is missing stops being fatal: it is
unavailable, reported as such, kept rather than forgotten, and picked up again when it returns.
This builds on [0004-configuration](Configuration.md), whose `settings.json` already holds the
library list and whose `silo.json` gains the roots.

## The problem

After 0004-configuration the library list lives in `settings.json`, the file of settings the
operator changes — but nothing changes it. The libraries are written by hand while the silo is
stopped, which is the service-definition edit that proposal set out to retire, moved into a file.
0002-onboarding's second open question already named the answer: libraries grow operator routes of
their own, and the console drives them.

Keeping the index current is, today, partly the operator's job. The server walks every library at
boot and after a placement it applies, and `POST /v1/libraries/{library}/scan` covers the rest —
every change that reaches a library without passing through the server. There are several:
`silo-ctl place` files into a library with no server involved; a sidecar is corrected by hand; a
second machine writes to a library on a network share. Each leaves the index stale until someone
who knows to ask, asks. That is the shape [0003-refresh](Refresh.md) removed from the console — a
manual control standing in for a cadence — and the argument transfers whole: either the server can
tell when to look, in which case the route is noise, or it cannot, in which case the fix is to
teach it.

And a library whose folder is missing stops the boot. That suits a server started by hand, whose
person is watching; it does not suit a daemon on a machine whose media drive mounts a few seconds
after it starts, or not at all until someone plugs it back in. One late drive should not take down
every other library with it.

## What this is

**Libraries within roots.** `POST /v1/libraries` adds a library and `DELETE /v1/libraries/{library}`
removes one, both behind the operator gate, both written through to `settings.json` and applied
while the silo runs. A library added over the network must lie within one of `silo.json`'s
`libraryRoots`, which only the machine's owner writes.

**The server keeps up.** Each available library is walked at startup, when it is added, when its
folder comes back, and every five minutes regardless. A placement the server applies re-reads the
sidecars it wrote, and walks nothing. A request for a file that has gone re-reads that one container
on the spot. One walk runs per library at a
time; a walk asked for while one runs joins it.

**The last walk is read, not run.** `POST /v1/libraries/{library}/scan` goes.
`GET /v1/libraries/{library}/scan` answers the last walk's report — when it ran, what it read, and
what it found wrong — which is the part of the old route the operator needed.

**Missing is a state, not a failure.** A library whose folder is missing is unavailable: the boot
goes on, the library's index rows are kept, its files answer 503, the library listing says so, and
the server looks for the folder at every tick and walks it when it returns.

## Principles

0004-configuration's principles stand — one rule places every setting, the filesystem configures
and the network operates. This proposal adds three of its own.

1. **The index is the server's to keep current.** Freshness is a property of the server. If the
   operator has to do something to see what is on disk, the server is broken in a way a route
   cannot fix — 0003-refresh's first principle, turned to face the server.
2. **The owner draws the boundary; the operator works within it.** Where the network may add a
   library is the machine owner's answer, in `silo.json`: a default they may narrow or empty, and
   never something the network widens. Which libraries exist within
   that is the operator's, from the console.
3. **A missing library is kept, not forgotten.** A drive that is not there is far more often late,
   unplugged or asleep than gone. The server never mistakes an absent folder for an empty one: it
   waits, and says it is waiting.

## Vocabulary

- **Library root** — a folder, named in `silo.json`, within which a library added over the network
  must lie.
- **Walk** — one incremental scan of a library: every sidecar stat'd, only the changed ones read.
  The mechanism is today's `Indexer.scan`, unchanged.
- **Available** — a library whose folder exists and whose last walk was applied. **Unavailable** — a
  library whose folder is missing, or whose last walk found nothing where the index holds something.
- **Last walk** — the report of the most recent walk of a library: when it ran, the counts, the
  findings.

## Library roots

`silo.json` gains `libraryRoots`, absolute paths. A library added over the network must, once
symbolic links are resolved, lie within one of them; with an empty list, no library can be added over
the network.

The key has a default, chosen as the state directory's is, by platform and by whom the silo runs as,
and written into the file at startup like every other key:

| Platform | Default roots |
|---|---|
| macOS | `/Volumes`, and `~/Movies` when not running as root |
| Linux | `/srv`, `/media` and `/mnt` |

These are where a household's media already are. On a Mac, every external drive and mounted share
appears under `/Volumes`, and a library on the internal disk is most often in the user's `Movies`
folder. On Linux, they are the places the filesystem conventions give served data, removable media
and mounts. A fresh silo's operator can add the standard case — a drive full of films — from the
console without anyone at the machine. The resolved-path rule keeps the defaults narrower than they
look: on macOS `/Volumes` holds a link to the boot volume, which resolves to `/` and so lies outside
every root, which is why the user's `Movies` is named on its own.

A default is still the owner's. It is in the file from the first boot, where the owner reads it beside
the port and narrows it or empties it; `"libraryRoots": []` says that nothing is to be added over the
network. A silo that predates the key gains the defaults at its next boot, as a gap in `silo.json`
always is filled, and so widens what its network may add without its owner asking. The boot logs that
it wrote them, and the cost is paid once.

The roots are in `silo.json` for the reason 0004-configuration's principle 2 gives: placement writes
into libraries, so the roots bound where the network can make the silo write, and the network cannot
be the one to widen them. Libraries written into `settings.json` by hand are not held to the roots —
the roots bound what the network may add, and what the owner wrote is theirs already.

## Adding and removing

`POST /v1/libraries` adds a library, an id and a path. The path must be absolute, must exist and be a
directory, and once symbolic links are resolved must lie within a library root; the id must be new. A
taken id is 409; a path outside every root, or any path when the roots are empty, is 403; a path
that does not exist is 422. The library is written to `settings.json`, walked, and returned.

`DELETE /v1/libraries/{library}` removes one. It refuses with 409 while a job not yet in a final state
names the library. The library leaves `settings.json` and its rows leave the index; nothing on disk is
touched — no sidecar, no media file. Moving a library is removing it and adding it again.

The settings route reports the libraries, with their paths, as 0004-configuration has it; they stop
being marked read-only, since routes now change them.

## Keeping the index current

A walk was argued as costing a stat per sidecar and a read per changed one. Measured, it costs more:
an unchanged sidecar is a stat and two index reads, and the walk also lists every file in the library
to find the sidecars nothing references. On synthetic libraries built with the silo's own placer,
timed on an M4 Max's internal SSD with a warm cache, from a release build of `main`:

| Library | Files | Folders | Sidecars | First walk | Walk, nothing changed | of which, listing every file | Re-reading one sidecar |
|---|---|---|---|---|---|---|---|
| 300 films, 40 series of 5 seasons of 10 | 4,040 | 840 | 540 | 0.58 s | 79 ms | 19 ms | 1.5 ms |
| 1,500 films, 150 series of 6 seasons of 12 | 20,850 | 4,050 | 2,550 | 3.4 s | 395 ms | 104 ms | 1.4 ms |

Stat'ing the 2,550 sidecars alone takes 2 ms; the rest of an unchanged walk is the index reads. The
walk scales with the library, about 0.15 ms a sidecar on a local disk, and the re-read of one sidecar
does not. A network share was not measured. There every folder listed and every sidecar stat'd is a
round trip, and the larger library's 4,050 folders and 2,550 sidecars are thousands of them, which
puts a walk in seconds — too slow for every request, and entirely affordable in the background.

**What starts a walk.** Startup walks every available library before the first request is answered,
as today. A library added through the route is walked before the route answers. An unavailable library whose folder reappears is walked at
once. And every five minutes, every available library is walked regardless: that cadence is what
notices `silo-ctl place`, a hand edit, or another machine on the share. Five minutes is a decision,
not a setting, for 0003-refresh's reason — a number the operator must tune is a cadence the design
has not chosen.

**A placement re-reads what it wrote.** Today a placement the server applies walks its whole library
before it answers, so that the ancestors a first placement created are indexed along with the
container it changed. The placement already knows exactly which sidecars it wrote, root first, and
re-reading those, parents before children, indexes everything it changed: 1.4 ms, against 395 ms to
walk the larger library above, and seconds on a share — paid once for each episode placed. A
placement cannot leave a sidecar nothing references, since it writes a parent's reference with the
child, so the listing of every file finds nothing it made. And whatever changed in the library
without the server is the walk's to find, on its triggers, now that it has some. So a placement walks
nothing.

**A missing file is a prompt.** When the media route finds a presentation's file gone, the server
re-reads that presentation's container with `Indexer.refresh` before answering, so a deletion is
noticed the first time anyone trips over it rather than at the next tick. The answer is still the
404 the request earned.

**One walk at a time.** Walks of one library never overlap: a walk asked for while one is running
joins it and shares its report, so the tick, an addition and a reappearing folder landing together
walk the library once. A placement's re-read and a walk of the same library do not run together: the
re-read waits for a running walk to finish, so that a walk which read a sidecar before the placement
wrote it cannot index the old one after the re-read has indexed the new. Different libraries walk
independently, so a slow share never holds up a local disk.

**Filesystem events are not the mechanism.** FSEvents and inotify would notice a change the moment
it happened, but they cannot replace the walk. Changes made to a network share from another machine
are not reported to this one; inotify watches one directory at a time, not a tree; and FSEvents is
Apple's alone, where 0001-silo's discovery went out of its way to run the platform's tools as
processes so that nothing Apple-only is linked. At most they would make the walk come sooner, which
the cadence already bounds.

## Unavailable libraries

A library is unavailable when its folder does not exist — at startup, at a tick, or when a request
reaches for it. It is also unavailable when a walk finds no container at the library's top level
while the index holds containers for it. That second case is the one that matters most: a Linux
mount point with nothing mounted on it is an empty folder, not a missing one, and a walk applied to it
would remove every container the library had. So a walk that finds nothing where the index holds
something is not applied; the library is reported unavailable instead, and nothing is forgotten.

While a library is unavailable its index rows are kept — the containers stay browsable, their
metadata intact — and its media route answers 503, so a client can tell "not now" from "not ever". The
listing marks it unavailable, and the transition is logged once each way, not at every tick. At every
tick the server looks for the folder, and for a container at its top level; when both are there, the
library is walked and is available again.

The boot never stops for a library. The server comes up serving everything it can reach.

## The last walk

`POST /v1/libraries/{library}/scan` is removed. Its answer — the counts and the findings — was the
only place other than the boot log where the operator could see a sidecar that would not parse, a
sidecar nothing references, or a child path that escapes its container, and that should not be lost
with the route. So the server keeps each library's last walk, and `GET /v1/libraries/{library}/scan`,
behind the operator gate, answers it: when it ran, whether the library is available, the counts, and
the findings. The findings name paths inside the library, which is why the report stays behind the
gate.

`GET /v1/libraries`, the open listing, gains one field: whether each library is available. A client
browsing the library can then say a drive is missing, rather than leave the operator to wonder where
half the films went.

## The console's libraries

SiloAdmin shows a with-access silo's libraries: each one's path, whether it is available, when it was
last walked, and what the walk found. It adds a library by offering the silo's roots as the places to
choose within — and, with the roots emptied, says the silo has none rather than offer a path the
silo will refuse — and removes one, naming the job that holds it when the silo refuses. There is no rescan
button, and there is nothing for one to do.

## What this looks like to the operator

A Mac mini's silo is set up from the console, and its `silo.json` gains the default roots at that
first boot; nobody edits it. From SiloAdmin the operator adds `/Volumes/Media/Films` as `films`; the silo walks it and answers with the
library. That evening, someone at the machine runs `silo-ctl place` for a new film; within five
minutes it is in the index, and nobody asked. A week later a power cut brings the silo back before the
drive: it boots, serves the other libraries, lists `films` as unavailable, and answers 503 for its
files. The drive mounts a minute later; at the next tick the library is walked and available, and the
console's warning is gone before anyone thought to look for a button.

## What this asks of an implementation

Each step is a pull request, in order, after 0004-configuration's, and each carries its spec deltas
into `openspec/` per the corpus README — the deltas are written now, one change for each step under
[`openspec/changes/`](../openspec/changes/): `libraries-1-missing-is-a-state`,
`libraries-2-the-server-keeps-up`, `libraries-3-roots` and `libraries-4-console`, each applied by
its step's pull request with `openspec archive`.

### 1. Missing is a state

Availability: the boot no longer stops for a missing library; a walk that finds nothing where the index
holds something is not applied; an unavailable library's media answer 503 and the listing carries
`available`. The unavailable-library, listing and `settings.json` deltas apply here.

Tests: a missing folder at boot is logged, the rest are served, and the library is listed unavailable;
an empty mount point leaves the index untouched; a folder that returns is walked and listed available;
an unavailable library's media answer 503.

### 2. The server keeps up

The five-minute tick, the reappearance and missing-file triggers, walks coalesced per library, the last
walk kept, and the scan route turned from `POST` to `GET`. The walk, last-walk and gate deltas apply
here.

A placement the server applies re-reads the sidecars it wrote rather than walking the library. The
index's placement requirement, the placement route's and the job placement's change here too.

Tests: a sidecar changed behind the server's back is read at the next tick; concurrent walk requests
walk once; a first placement indexes every container it made, under its parent, before it answers;
a placement leaves a change made behind the server's back for the next walk; a missing file refreshes its container; the last walk is read with its findings; `POST` to
the scan route is gone.

### 3. Libraries within roots

`libraryRoots` in `silo.json`; the library list moved behind a registry that applies adds and removes
while the silo runs; `POST` and `DELETE /v1/libraries`; the settings route marking the libraries
writable. The roots, library routes and settings deltas apply here.

Tests: an added library is walked and served without a restart; a path outside the roots, through a
symbolic link that leads outside, and with the roots emptied are each refused; a fresh `silo.json`
holds the platform's default roots; removal is refused
while a live job names the library, and afterwards leaves every file on disk in place.

### 4. The console's libraries

SiloClient and SiloAdminKit learn the library routes and the last walk; SiloAdmin shows each library's
availability and last walk, and adds and removes libraries within the roots. The silo-admin delta
applies here; shell-level behaviour stays `Pinned by: nothing yet.` until the shell grows a test seam.

### 5. Checking a path, and making its folders

A follow-up, once the console had a sheet to add from. The console cannot browse the silo's disk, so
an operator typing a folder within a root learned only from a refusal that it was not there, and had
to go to the machine to make it. `POST /v1/libraries/check` takes the same body as an addition and
answers what the addition would find — each folder along the path and whether it is there, the root
the path lies within, the folders that would be made — and the refusal it would meet, with its status,
making and writing nothing. `POST /v1/libraries` takes `create`, and with it makes the missing folders
before adding the library, so long as the folder they are made in lies within a root once its links
are resolved. A root is never made: a root that is missing is far more often a drive not yet mounted
than a folder wanted, and the same rule that keeps an unmounted drive's library from being forgotten
keeps its folder from being stood in for by an empty one on the disk beneath. For the same reason no
folder is made where a drive mounts, whether or not that place is a root: directly within a folder
the platform mounts drives in — `/Volumes` on macOS; `/media`, the per-user folders within it and
within `/run/media`, and `/mnt` on Linux — or within a mount point declared while nothing is
mounted on it, which the silo tells by its device being its parent's. A mount point is declared by
`/etc/fstab`, or by a systemd mount or automount unit: the machine's own, in `/etc/systemd/system`
and `/run/systemd/system`, and those enabled from there by a `.wants` or `.requires` link. A unit a
distribution ships and nobody enabled is not read, since `tmp.mount` declares `/tmp` on machines
where nothing mounts there. Without this,
`/Volumes/Media/Films` asked for while the `Media` drive is away would be made on the boot disk,
and the drive would mount beside it as `/Volumes/Media 1`. Inside a drive that is mounted, folders
are made as anywhere. A root's place or a drive's is refused whether or not `create` was asked,
since asking would not make the folders, so that refusal is said over the folders being missing,
and the sheet offers no toggle for it. The sheet asks the check as the folder is typed and says, in one sentence, whether a
library will be created at the path, which it shows in two colours, green as far as it exists and red
past that: a library cannot be created there because those folders do not exist. With the toggle to
make them on, the missing part turns orange and the sentence says a library will be created there
and the folders made. Any other refusal of the path is given in the sentence in the silo's words — where drives are
mounted, "a library cannot be created at `/Volumes/Media/Films`: it would be created where drives
are mounted"; a
refusal of the name is shown below it, since the path it leaves is good, and the silo, judging the
path first, says by its answer which of the two it refused.

## Non-goals

- **A manual rescan.** No route, no button. If the cadence proves too slow, the answer is a better
  cadence.
- **Filesystem events,** for the reasons above. They may yet make walks come sooner; they will never
  be what makes the index correct.
- **A configurable cadence.** Five minutes is a decision.
- **Asking for the roots at install.** An installer that asks where the media are would be a third
  answer beside none and a default. The silo has no installer, and the default is in the file to be
  changed.
- **Deleting media with a library.** Removing a library forgets it; the files are the household's.
- **Watching the data repository.** `silo-ctl place` writes into a clone of the data repository and
  the library alike; the silo reads libraries, and the repository remains the ingestion tool's.

## Open questions

1. **The cadence.** Five minutes bounds how long a change made behind the server's back goes
   unnoticed, and costs one walk per library per tick. A shorter tick for local disks and a longer one
   for shares — told apart by how long the last walk took — would be the adaptive version; this
   proposal ships the fixed one and waits for the pain to argue otherwise.
2. **A library emptied on purpose.** The rule that a walk finding nothing is not applied protects an
   unmounted drive, and also refuses to forget a library whose containers were all deliberately
   deleted: it stays unavailable, and removing it is how the operator says so. If that proves
   confusing, the console could offer the removal from the unavailable state directly.
3. **Mount points the silo cannot see.** A drive mounted somewhere other than the platform's
   folders, and declared neither in `/etc/fstab` nor by a systemd unit — by autofs's maps, or a
   script — is not known to be a mount point, and a folder can be made in its place while it is
   away. Reading the automounter's maps would close most of what remains.
