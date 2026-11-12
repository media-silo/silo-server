<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0021-stores

Modified: 2026-11-12

# A walk is stored as one request the silo carries out

This proposes that a walk be stored by handing the silo the whole of its store in one request, which
the silo takes, records and answers at once, and then makes in the background, step by step, as the
console's store makes it today. The request carries a key the console chose, kept with the walk before
the request is sent, so the same store sent twice is the one store, and a reply that never arrived is
asked for again rather than guessed at. The silo says how far it has got at a route of its own. The
images a store puts are sent to the silo before it, one request each, named by their digest, so the
request that carries the store is small and none of its parts has to be sent twice.

It changes how [0018-tmdb-walk](TmdbWalk.md)'s *one store at the end* is made, and not what it makes:
the walk's list of steps, its order, and its stopping at the first refusal all stand. The routes a
store's steps are made with are [0012-containers](Containers.md)'s and [0013-smddb](Smddb.md)'s, and
they stay for everything else that uses them.

## The problem

**A store is a conversation the console holds alone.** Storing a walk makes each step of its plan as
a request of its own, one after another: a `POST` of new containers, a `PUT` of a container's edit, a
download from TMDb and a `PUT` of the image, and, for a placement's edit of a container that is not a
stop, three reads of the container and then a `PUT` of the edit onto what was read. A walk of a series
is hundreds of them. Only the console knows how far it has got, and it keeps that in memory until the
store ends.

**A slow request is cut off, and the work goes on without its answer.** The silo's HTTP server closes a
connection 30 seconds after a request's body has arrived, if no answer has been sent by then. An edit
that moves folders walks the whole library before it answers, so that nothing reads a moved container
at its old path; every write also waits behind a walk already under way, the five-minute walk among
them. On a large library either takes longer than 30 seconds. A store of *Stranger Things* failed so:
its first edit sent 64 KB, nothing came back, and the connection was closed at 30,008 ms. The silo's
handlers do not stop when their connection does, so the edit was in all likelihood made. The console
said only *The network connection was lost*.

**The console cannot tell what was made.** A request that fails in transport ends the store, and the
steps made before it are forgotten with it, since the walk records a step as stored only when the store
ends. Sending them again does not repair this, because the silo's routes cannot tell a repeat from a
conflict:

- an edit repeated is refused with 409, since its base is no longer the sidecar's, though the sidecar
  now holds exactly the edit;
- containers made again are refused with 422, *already at*, though they were made where the request
  asked;
- a placement's edit repeated reads the container afresh and inserts the special a second time.

So a walk whose edit landed unanswered has that stop read again and confirmed again. A walk whose
creation landed unanswered is refused at that step at every store after it, and cannot be stored.

## What this is

**A store is a request.** `POST /v1/libraries/{library}/stores` takes a `StoreRequest`: a `key`, which
the console chooses, and the `steps`, in the order they are to be made. A step is one of four:

- *create* — `documents`, `parent` and `attributions`, as a `ContainerCreate` carries them;
- *edit* — `container`, `document`, `basedOn`, and `attributions` and `declined` when the edit sets
  them, as a `ContainerEdit` carries them;
- *put artwork* — `container`, `kind`, the `image`'s digest, and the attribution, as the artwork route
  takes it;
- *remove artwork* — `container` and `kind`.

A step names a container the library holds or one an earlier step of the same store makes. The steps
are the routes the silo already has, said in its own terms, so a store is nobody's in particular: the
walk sends one, and anything else that wants a tree of changes made can too.

**Taken at once, made in the background.** The silo checks what it can before making anything: each
document reads and names its container; each edit's base is the sidecar the library holds now; each
image is one the silo holds; each container a step names is held or made earlier in the store. A store
that passes is recorded and answered 202, and the silo makes its steps in order, with the library to
itself, as one turn of the library's lane. A step that moves folders walks the library before the next
step, as an edit does today, so each later step finds what moved where it now is. A store that fails a
check is recorded as refused with none of its steps made, and answered the same way. The answer is the
store's `StoreRecord`, and its location.

**The key is the store.** A second request with a key the library has a store for, and the same steps,
is answered that store's record, made, under way or refused, with 200; with other steps, 409. The
console keeps the key with the walk before it sends the request, so a request whose answer never
arrived, or a console that quit, asks after the key and does not send the store again.

**Progress at a route of its own.** `GET /v1/libraries/{library}/stores/{key}` answers the record: its
state, *under way*, *made* or *refused*; how many of its steps are made; the step under way; and for a
refusal, which step and the silo's words, its findings when it has them, as the step's own route would
answer. A step is said by its index, so the console says each step as it described it in the list, and
the silo holds no one's prose. The console asks every second while the store is under way, and again
whenever a walk with a key is opened.

**A record kept, and a store resumed.** Each record is a JSON file of its own under `<state>/stores`,
as a job's is under `<state>/jobs`, written whole after each step. A store under way when the silo stops
is resumed when it starts, at the step it was making. That step may or may not have been made, so a
step's own making has to recognise itself as made, which the routes need anyway:

- an edit whose document, attributions and declined refs are what the container's sidecar already holds
  is made, with nothing written, whatever its base;
- a create whose every container the library already holds, filed where the request asks, is made;
- a put of an image the kind already holds, with the same attribution, writes it again, as it does now;
- a removal of a kind the folder does not hold is made.

The single routes take the first two too, so a console that repeats an edit or a create on them,
outside a store, is answered as made rather than refused.

**Images sent before the store.** `PUT /v1/blobs/{digest}` takes an image's bytes, a JPEG or a PNG of
up to 25 MB as the artwork route takes them, and refuses bytes whose SHA-256 is not the digest named;
`HEAD` on the same path says whether the silo holds it. A put of an image the silo holds is answered as
made. The console puts each image a store names before it sends the store, skipping those the silo
holds, so an image is sent once however many times a store is, and a season of stills is a hundred small
requests rather than one of tens of megabytes. A blob no store names is removed a day after it was put.

**Every edit is a document on a base.** The console makes a placement's edit, a series' declined refs
and a drafted record's naming in its collection by reading the container, changing it and writing it
back, as the step is made. In a store sent whole, nothing is read between steps, so the console reads
each such container when it lists the store, and sends its edit as a document on the base it read, as a
stop's edit already is. Every container a store edits is edited by one step: a stop's own edit already
takes the placements made in it, and the list takes the declined refs and the naming into the edit of
the container they change when it has one. A container changed in the library between the list and the
store fails the store's check, and its edit is listed again on the sidecar as it is.

## Principles

0018's principles stand. This proposal adds four.

1. **A request is answered when it is taken.** A route that may take longer than a connection is kept
   open answers what it accepted, and says the rest at a route of its own. No answer waits on a walk.
2. **Every write can be sent twice.** A write repeated, whether its first answer arrived or not, has
   the effect it had, and is answered as made, not as a conflict.
3. **The silo keeps the record of what it made.** The console does not infer from a lost answer what
   happened; it asks.
4. **A store is the silo's routes, in order.** It names no walk, no provider and no producer. What a step
   does is what its route does, checked in the same words.

## Vocabulary

- **Store** — the steps a request hands the silo to make in one library, in order, under the key the
  request names.
- **Key** — the name a store is asked after by, chosen by whoever sends it.
- **Blob** — an image the silo holds by its digest, for a store to put.
- **Resumed** — a store made from the step it was making when the silo stopped.

## What this looks like to the operator

The operator stores a walk of *Stranger Things*: forty-eight confirmed stops and their artwork. The
sheet lists the steps as it does now. On *Store*, the console says *Sending the images*, with a count,
then the steps, one by one, as the silo makes them. The silo takes forty seconds over the series' edit,
walking the library after moving a season's folder; the sheet stays on that step, and goes on.

They close the laptop partway through. When they open it, the walk is open where they left it, and the
sheet says the store as the silo says it now: made, with every step said made. Had the silo stopped
too, it would have resumed when it started again, at the step it was making.

A second operator edits the series in the container editor after the list was made. The store is
refused before any step is made: *Stranger Things changed in the library after the walk read it*. The
series' stop is read again, and the list made again when they confirm it.

## What this asks of an implementation

Four steps, each a pull request carrying its spec change.

### 1. A repeated write is made

An edit whose document, attributions and declined refs are what the sidecar holds is answered as
applied, with nothing written and no walk, whatever its base. A create whose every container is held
where the request files it is answered as applied, with no write. A removal of a kind the folder does
not hold is answered 200.

Tests: an edit sent twice is applied twice, the second writing nothing; an edit of a sidecar changed
since its base, to a document other than what it holds, is still 409; containers made twice are
applied twice, the second writing nothing; a create of a container held elsewhere in the library is
still 422; a kind removed twice answers 200 both times.

### 2. Blobs

`PUT` and `HEAD` on `/v1/blobs/{digest}`, the bytes under `<state>/blobs`, and a blob no store names
removed a day after it was put.

Tests: a blob put is held and its `HEAD` answers 200; bytes that are not the digest named are refused;
neither a JPEG nor a PNG is 415, and over 25 MB 413; a blob put again is answered as made; a blob a day
old that no store names is removed, and one a store under way names is kept.

### 3. Stores

The store route, the record and its route, the check before any step, the steps made in order with the
library to itself, and stores under way resumed when the silo starts.

Tests: a store of an edit, a create beneath it and a put of artwork on what was created makes all three
and records each; a store sent twice with the same steps answers one record; with other steps, 409; an
edit on a stale base refuses the store before any step is made; a store naming a blob the silo does not
hold is refused before any step is made; a step the silo refuses ends the store there, recorded with the
silo's words; a store stopped after a step is resumed at it and made once.

### 4. The console stores a walk as a store

The list reading the containers a placement, a decline or a naming changes, and merging every edit of a
container into one step; the images put first; the key kept with the walk before the store is sent;
the store's progress read from its record; and a walk opened with a key asking after its store.

Tests: a walk's store sends the steps its list says, with the key kept with the walk; a placement in a
container that is not a stop is sent as an edit on the base the list read; a walk whose store's
answer never arrived asks after its key and makes nothing again; a store recorded as made marks every
step of the walk stored; a walk opened with a store under way says its step.

## What comes next

**The silo's other slow routes.** Placing a job downloads the node's output inside the request, which
can be gigabytes, and laying out a library walks it inside the request. Each can be taken and said as a
store is.

**The silo's other repeated writes.** Repeating some of the silo's routes for jobs, bindings and nodes
does more than refuse: a lost claim leaves a job leased to a node that does not know it holds it; a lost
answer to a node's poll loses its token; a binding, a recipe or a rules version made twice is two.
They are their own fixes, and principle 2 is what each should meet.

**Stores of other things.** The container editor and the smddb import could hand the silo a store,
when one of their edits moves folders.

## Non-goals

- **Making a store whole or not at all.** A library is folders and files, and folders moved cannot be
  put back cleanly. A store stops at its first refusal, as the walk's does now, and its record says
  which steps were made.
- **The silo reading a provider.** The images are the console's to read, from TMDb, and the silo's to
  hold. [0017](Tmdb.md)'s rule that the console reaches the providers stands.
- **Retiring the single routes.** The container editor, the smddb import and the artwork controls keep
  them.

## Open questions

1. **Holding the library for a whole store.** A store made as one turn of the lane keeps the checks it
   began with true, and nothing interleaves with it; it also keeps the five-minute walk and every other
   write to the library waiting until it ends, minutes for a long series. Proposed: the whole store, since
   a store is the operator's own deliberate act and its record says what it is doing.
2. **How long a record is kept.** The console reads a store's last state when it is made or when the
   walk is opened, and forgets the walk then. Proposed: thirty days, after which the key is free again.
3. **Stopping a store.** A store could be stopped after the step under way, as a job is cancelled at
   its next report. Proposed: not in this proposal; a store is listed before it is sent, and the list is
   the place to change one's mind.
4. **The connection's timeouts.** The silo's server takes swift-http-server's defaults, and its 30
   seconds begin when a request's body arrives, not when its answer is sent. Setting them deliberately
   is a fix of its own, made whether or not this proposal lands, and does not change it: a store should
   not depend on a connection lasting.
