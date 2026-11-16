<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0023-taken

Modified: 2026-11-16

# A slow request is answered when it is taken

This proposes that the silo's four remaining routes that work inside the request for longer than a
connection can be relied on answer as soon as they have taken the request, and do the work in the
background: placing a job, fetching a trial again, laying a library out, and adding a library. Each
answers 202 with the record that says how the work stands, and the client reads that record again at
a route the silo already has, or one of its own, until the work has ended. A request sent again while
the work is under way is answered with the same record, and the work is done once. Work under way
when the silo stops is taken up again when it starts.

It applies [0021-stores](Stores.md)'s first principle, *a request is answered when it is taken*, to
the routes its *What comes next* named, as
[silo-server#197](https://github.com/media-silo/silo-server/issues/197) asks. It builds on
[0022-repeats](Repeats.md), which made each of these answer a repeat as made.

## The problem

**Four routes do long work inside the request.**

- Placing a job, `POST /v1/jobs/{id}/place`, fetches the node's output into the library before it
  answers. An output is gigabytes, so the fetch can take minutes.
- Fetching a trial again, `POST /v1/trials/{id}/fetch`, fetches its output the same way.
- Laying a library out, `POST /v1/libraries/{library}/layout`, renames its folders and walks the
  library before it answers.
- Adding a library, `POST /v1/libraries`, walks the new library before it answers. A library that
  already holds a large tree takes minutes to walk.

Each also waits behind the library's lane, so it can wait first behind a walk already under way.

**A long request is fragile however long its connection may last.** Since #231 the silo's server keeps
a connection open for an hour while its answer is made, so none of these is cut off by the silo.
Something between the client and the silo can still close the connection: a proxy, a laptop that
sleeps, a network that changes. When it does, the client is told only that the connection was lost.
The work goes on without anyone waiting for it, and the client cannot tell whether it is under way,
done or failed without guessing which record to read.

**A placement can be left stuck.** A job is `placing` while its placement is made. A silo stopped
during the fetch leaves the job `placing`, and nothing ever places it: a place sent again is refused
with 409, since how the placement ends is not known, and it never will be.

**A repeat is refused while the work is under way.** A place sent while the job is `placing` is 409,
so a client whose first request lost its connection is refused when it asks again, and has to read the
job to learn the work it asked for is being done.

## What this is

**Taken, answered, made in the background.** Each route checks what it can before doing any work:
that the job is encoded and its binding's library is served, that the trial is encoded, that the
library is served and available, that the new library's path is good. A request that passes is
answered 202 with the record of the work, and the work is queued to a background service the silo
already runs. A request that fails a check is refused as it is now. A route never answers 202 for work
it has not queued.

**The record is the answer.** The client reads the work's record until it has ended:

- a placement is its job. `GET /v1/jobs/{id}` answers it `placing` while it is made, `placed` with its
  placement once it is, and `encoded` with the failure recorded when it failed, as it does now;
- a trial's fetch is its job too: `encoded` with no failure while it is fetched, `tried` once it is,
  `encoded` with the failure when it failed;
- a layout is a record of its own, the library's last layout, at
  `GET /v1/libraries/{library}/layout`: under way, or made with its moves and findings;
- an added library is its listing, which says whether a walk of it is under way, and its last walk at
  `GET /v1/libraries/{library}/scan`, as every library's is.

**A repeat is answered with the work under way.** A request sent while its work is under way is
answered 202 with the record as it stands, and nothing is queued again: a place of a `placing` job, a
fetch of a trial being fetched, a layout of a library being laid out. Work that has ended is answered
as 0022 answers it: a `placed` job 200 with the job, a `tried` trial 200 with the job, and a library
added again 200 with the library. A layout that has ended is not answered as made, since a library
can be laid out again at any time, and laying out a library already laid out moves nothing.

**Work under way at a stop is taken up at the start.** A job `placing` when the silo starts is queued
to be placed again. Its staged copy is kept when it is whole, since a copy moved from the embedded
node's work folder has left it; otherwise the output is fetched again. A placement whose presentation
is already in the library is recorded placed, as 0022 made it. A trial `encoded` is already fetched at
the start. A layout recorded under way is made again, and a library is walked at the start, as now.

**What leaves the routes.** A route that answers before its work is done cannot answer for what the
work meets. A placement refused because it would not apply, a node that does not give its output, and
a fetch that fails are recorded on the job as its failure, as they are now, and no longer answered
409 or 502. A layout's failed renames are its findings, in its record. A walk's findings are in its
last walk.

## Principles

0021's and 0022's principles stand. This proposal adds two.

1. **A 202 is a promise kept by the record.** A route answers 202 only once the work is queued, and the
   record it answers with is the one the client reads afterwards to learn how the work ended.
2. **Nothing is left under way by a stop.** Work recorded as under way when the silo stops is made when
   it starts, or recorded as ended. No record says *under way* of work nothing is doing.

## Vocabulary

- **Taken** — a request checked, its work queued and answered 202.
- **Under way** — work taken and not yet ended: a job `placing`, a trial being fetched, a layout made,
  a library walked.
- **Taken up** — work under way at a stop, queued again at the start.

## What this looks like to the operator

The operator places a job from `silo-ctl jobs place`. The command is answered at once with the job
`placing`, and prints the job every second until it is `placed`, then each of the placement's writes,
as it does now. They close the laptop halfway through a large fetch. The silo goes on; when they run
`silo-ctl jobs show` later, the job is `placed`.

They lay a library out from the console. The sheet lists the dry run's moves, as now. On *Apply*, the
sheet says the layout is under way, and then lists the moves made and any rename that failed, as the
silo's record says them. The silo restarts during the layout; when it starts, it lays the library out
again, which moves only what was not moved.

They add a library of three thousand films. It is listed at once, said to be walking, with no
containers yet, and fills in as the console reads the libraries again; its last walk is shown once
the walk has ended.

## What this asks of an implementation

Four steps, each a pull request carrying its spec change, in `openspec/changes/`:
`taken-1-placement`, `taken-2-trials`, `taken-3-layout` and `taken-4-libraries`.

### 1. Placement

`POST /v1/jobs/{id}/place` sets an encoded job `placing`, queues it and answers 202 with the job; a
`placing` job is answered 202 as it stands, queued once. The silo's job service places queued jobs
side by side, each library's writes in its lane, and on start queues every job left `placing`, keeping
a whole staged copy. A placement's refusal and its fetch's failure are the job's failure, and the
route's 502 and its 409 for a refusal leave the API. `silo-ctl jobs place` reads the job every second
until it is no longer `placing`, and prints it, or its failure, as now.

Tests: a place is answered 202 with the job `placing`, and the job is `placed` afterwards; a place
sent again while the job is `placing` is 202 and places once; a placement refused is the job's
failure, the job `encoded`; a job left `placing` at a start is placed without anyone asking; a staged
copy moved from the work folder is the one placed after a start.

### 2. Trials

`POST /v1/trials/{id}/fetch` clears an encoded trial's failure, queues it on the queue the silo's own
fetches use, and answers 202 with the job; a trial being fetched is answered 202 as it stands, queued
once, and a `tried` trial 200. The route's 502 leaves the API.

Tests: a fetch asked for is answered 202, and the trial is `tried` afterwards; a fetch that fails is
the job's failure, and asking again clears it and fetches; a fetch asked for while one is under way is
made once.

### 3. Layout

`POST /v1/libraries/{library}/layout` that is not a dry run records the library's layout under way,
queues it and answers 202 with the record; `GET /v1/libraries/{library}/layout` answers the last
layout. The record is kept as `<state>/layouts/<library>.json`; a layout under way at a start is made
again. A layout asked for while one is under way is answered with it. A dry run is answered with its
moves as now. The console's layout sheet reads the record until the layout has ended.

Tests: a layout is answered 202 under way, and its record is made with the moves afterwards; a layout
asked for while one is under way is made once; a layout recorded under way at a start is made again
and moves only what was not moved; a dry run is answered 200 with its moves and records nothing.

### 4. Libraries

`POST /v1/libraries` answers 201 once the library is in `settings.json`, and queues its walk to the
library's lane, as a walk at the start is. A library's listing says `walking` while a walk of it is
under way, its first or any other. The console says a library is walking, and keeps reading the
libraries while one is.

Tests: an added library is answered 201 before its walk, and is listed `walking` until its walk ends,
with its counts then; an add sent again while the first walk is under way is answered 200 with the
library and walks once; a library whose five-minute walk is under way is listed `walking`.

## Non-goals

- **A fetch's progress.** The record says a placement or a fetch is under way, not how many bytes have
  arrived. A node's encode reports its progress because it takes hours; a fetch on the same network
  takes minutes.
- **Stopping work under way.** A placement, a fetch or a layout is not cancelled once taken, as a store
  is not.
- **A dry run in the background.** A dry run reads and writes nothing, so a lost answer is asked again
  at no cost, and the console needs its moves before it can offer to apply them.
- **A walk on request.** The console still offers no way to start a walk. Adding a library walks it
  because the library is new.

## Open questions

1. **How many placements at once.** Each fetch takes a node's bandwidth and the library's disk, and
   each placement's writes take the library's lane. Proposed: side by side, as trials are fetched,
   with each library's writes in its lane; a limit can follow if a silo with many nodes needs one.
2. **Resuming a remote fetch.** A placement taken up at a start fetches a remote output again from the
   beginning. The worker's range downloader resumes by offset and could be used instead. Proposed: not
   in this proposal; a fetch on the same network is minutes, and a start is rare.
3. **How long a layout's record is kept.** Proposed: the last layout of each library, replaced by the
   next and removed with the library, since the console reads it only while its sheet is open.
4. **The answer to an add.** A 201 for a library not yet walked answers its counts as zero. Proposed:
   that, with `walking` true, rather than a 202, since the library itself is made and served at once;
   only its walk is under way.
