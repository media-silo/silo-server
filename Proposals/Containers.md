<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0012-containers

Modified: 2026-10-18

# Containers in the console

This proposes that the operator see a silo's containers from the console, library by library, and
change them there. SiloAdmin shows each library as the tree of containers its folders hold, and a
container with everything its sidecar says: its own fields, its alternatives, features, sequences and
extras, the presentations placed for each item, its artwork, and what the library's last walk found
wrong with it. The operator edits a container's own fields in a form, and the silo writes the edit
into that library's sidecar, leaving every library fact in it as it stands, and only onto the
sidecar the editor read. Artwork, which nothing in the silo knows of today, is a set of files found
beside the sidecar by name. The console puts and removes them, and the silo serves them.

The silo gains what that needs. Its index learns that one container can be in several libraries,
each with its own sidecar. It gains a library's view of its containers, a route that edits a
container's own fields in one library, and routes for artwork.

This is the second of the proposals that make the console where a library's structure is defined,
after [0005-libraries](Libraries.md) decides which libraries a silo has.
[0013](#what-comes-next) brings containers into a library from smddb, or creates them, and proposes
a library's container back to smddb. [0014](#what-comes-next) has a producer bind into the structure
a library holds rather than bring its own. [0010](Drafts.md#what-comes-next), a container's own
rules, follows them.

## The problem

**The console cannot see what a library holds.** SiloAdmin shows a library's path, its standard and
its out-of-date presentations, and nothing of its containers. The read routes answer every container
and presentation, but only a player calls them, and a player shows what it is for, not what is wrong.
An operator who wants to know whether a season is in the library, which of its episodes have files,
or why a container is missing from the player has nothing in the console to look at.

**A container cannot be changed once it is in a library.** Its sidecar is written once, from the
lineage the first placement carries. After that a placement updates only the library's facts, its
presentations and its children's paths, and never the container's own fields. That is right for a
placement, which knows nothing of the container but what it was handed. It also means nothing changes
those fields at all. A title spelled wrongly, an outline worth adding, a missing provider id, a
feature nobody declared until a disc turned out to have a commentary: each is a hand edit of
`container.smd` on the silo's machine, made by someone who knows the format and that the silo will
notice at its next walk.

**The index thinks a container is in one library.** A container's id is minted once and is the same
wherever it is filed, so a household that keeps films in two libraries, one of them for the 4K
copies, has one container with a sidecar in each. The index keys its container rows on the id alone.
Each library's walk replaces the row the other wrote. Removing a library's sidecar removes the row,
and with it the presentations the other library still holds. The libraries are told apart only as
the walks happen to run.

**Nothing knows of artwork.** A player that wants a poster has nowhere to look, and an operator who
has one has nowhere to put it. smddb leaves artwork to the providers and names no file for it, and
the sidecar lists none.

## What this is

**A library's containers, in the console.** For a silo it holds a passkey for, SiloAdmin shows each
library's containers as a tree, from the folders at its top down through the children each sidecar
names, listed and unlisted alike. A container shows its sidecar as the silo read it: its own fields,
its alternatives and features, its sequences and extras with each item's presentations, its children,
its artwork, and the findings of the library's last walk on its sidecar.

**One container, a sidecar per library.** The index keys a container's rows by library and id. A
container in two libraries is two containers in the index, each read from its own sidecar, and
removing one leaves the other. A library holds a container once: a second sidecar for the same id
in one library is an error the walk reports. `GET /v1/libraries/{library}/containers` and
`GET /v1/libraries/{library}/containers/{id}` read a library's own view. `GET /v1/containers/{id}`
answers as before for a container in one library, and for one in several answers from the first of
them in the order `settings.json` lists the libraries, and says which.

**A container's own fields are edited in one library.** `PUT /v1/libraries/{library}/containers/{id}`
takes the container as its repository document and `basedOn`, the digest of the sidecar the editor
read. The silo writes the document's fields into that sidecar and changes no library fact. The edit
is refused, and nothing written, when the sidecar has changed since, when the result would not
validate, or when the edit would take away an item, alternative or feature a presentation in the
library still names. A dry run answers what would be written, with its findings, and writes nothing.

**Artwork is found by name.** A container's artwork is a file beside its `container.smd`, named for
its kind: `poster`, `fanart`, `banner`, `logo` or `thumb`, as a `.jpg` or a `.png`. The sidecar lists
none of it. `GET`, `PUT` and `DELETE` on `/v1/libraries/{library}/containers/{id}/artwork/{kind}` read,
put and remove one.

**A title edit moves nothing.** A container's folder is named from its display title when it is
made, and an edit that changes the title leaves the folder where it is. The walk warns of a folder
not named as the layout would name it, as it already warns of a file. Putting a library's folders
and files back where the layout says is a deliberate act of its own, for later.

## Principles

0008-rulesets' principles stand: the silo's reading is the one shown, and a store names what it
replaces. This proposal adds four.

1. **A library's sidecar is the container in that library.** What a library says a container is, is
   its sidecar. The console edits it there. It does not edit smddb's record, or a copy kept on the
   Mac, and it does not edit another library's sidecar. Where two libraries' sidecars differ, both
   are true of their libraries.
2. **An edit changes the container, and never the media.** The container's own fields are the
   operator's to change. A library's facts — its presentations, its children's paths, its rules — are
   made by placing and by setting rules, and an edit leaves them as they stand. An edit that would
   leave a library fact naming something the container no longer has is refused, not resolved.
3. **What the operator can see on disk, the console can see.** The tree, the presentations and the
   walk's findings are already the silo's. The console shows them and adds no reading of its own.
4. **Paths are made, not maintained.** The layout names a folder when it is made. An edit does not
   move files, because a move in a library is a change to every client that knows a path, and
   deserves to be asked for.

## Vocabulary

- **Own fields** — what a container says of itself and its structure: type, title, year, type label,
  outline, listed, external references, alternatives, features, sequences, extras and the extras
  anchor. The repository document carries exactly these.
- **Library facts** — what a library's sidecar adds to a container: its items' presentations, its
  children's `smd` paths, and its rules.
- **Digest** — the SHA-256 of a sidecar's bytes as the index read them, written in lowercase
  hexadecimal: what an edit names to say which sidecar it was made from.
- **Artwork** — an image beside a container's sidecar, found by its name.

## What the index changes

The container, item and external-reference rows gain the library as part of their key, and the walk
of one library writes and removes only its own. A presentation's id is already the hash of its
library and path, and does not change. The index is derived state, so the change is a new schema and a
walk of every library, and nothing is migrated.

The walk keeps one sidecar per container per library. A sidecar that names a container the walk has
already found in the library is reported as an error, `container <id> is already at "<path>"`, and
not indexed. Nothing the walk does decides which of the two is right.

## What the silo adds

### A library's view of its containers

`GET /v1/libraries/{library}/containers` answers a `ContainerSummary` for each container at the top of
the library, listed or not, since the operator needs to see an unlisted container that a player does
not. `GET /v1/libraries/{library}/containers/{id}` answers a `LibraryContainer`: the `library`, the
sidecar's `digest`, the `artwork` kinds the container's folder holds, and the `container` as the
global route answers it. `GET /v1/libraries/{library}/containers/{id}/smd` answers that library's
sidecar bytes. Each is 404 for a library the silo does not serve, or a container the library does not
hold. All three are read routes, open as the others are.

### The edit

`PUT /v1/libraries/{library}/containers/{id}` takes a `ContainerEdit`: `document`, the container as
its repository XML; `basedOn`, the digest of the sidecar it was made from; and `dryRun`. It answers a
`ContainerEditResult`: `applied`, the sidecar's bytes as written or as they would be written, its
`digest`, and the `findings`.

- A document that cannot be read, or that names another container, is 400.
- A `basedOn` that is not the digest of the sidecar the library holds now is 409. It names the digest
  it holds, decided under the lock the write is made under, and nothing is written.
- An edit whose result has an error-severity finding is 422. It carries the result, with the
  findings that refused it, and nothing is written. Among them are the validator's own errors — a
  presentation naming an alternative that is not there, a track for a feature that is not there —
  and one the edit adds: an item the document no longer has, whose presentations, or child sidecar,
  the library still holds (`item <id> has presentations in this library` or
  `item <id> is a container this library holds`).
- An edit with `dryRun` is answered 200 with `applied` false, and writes nothing.
- Otherwise the silo writes the sidecar and re-reads it into the index before answering 200 with
  `applied` true.

409 is the answer a ruleset store gives a head that has moved, and is kept for the same thing here.
A placement refused by its findings answers 409 too. The edit answers 422 instead, so that one route
does not give one status for two refusals that ask different things of the editor.

The write is SmdKit's: setting a sidecar's container replaces its own fields with the value's, keeps
every library fact and every comment on what it does not change, and refuses a value for another
container. It is the counterpart of the update a placement makes, which keeps the container's own
fields and changes only the library's facts. SmdKit gains it first, with its spec.

The edit is the operator's. It is behind the operator gate, as every route that writes is.

### The folder's name

The walk warns of a container folder whose name is not the one the layout would give the container
now: `folder "<name>" is not the name the layout would give it, "<expected>"`. It is the folder's
version of the warning a file already has, and is how a title edit that moved nothing shows up as a
difference between what is on disk and what the layout would make.

### Artwork

A container's artwork is the file beside its `container.smd` named `<kind>.jpg` or `<kind>.png`, for
the kinds `poster`, `fanart`, `banner`, `logo` and `thumb`. These are the names a media server
already looks for in a folder, and the library already gives every container a folder of its own.
smddb's structured containers sketched a rule that named artwork after the sidecar's own file name.
The library names every sidecar `container.smd`, so that rule does not carry over here. A kind
with both a `.jpg` and a `.png` beside one sidecar is a warning the walk reports, and the `.jpg` is
the one served.

Artwork is read from the folder when it is asked for, and not indexed: a changed image changes no
sidecar, and the walk's incremental read would not see it.

- `GET /v1/libraries/{library}/containers/{id}/artwork/{kind}` answers the image, with its content type,
  or 404. It is a read route, open.
- `PUT` on the same path takes the image's bytes as a JPEG or a PNG, told by its signature rather than
  its declared type. Anything else is 415, and an image over 25 MB is 413. The silo writes the file by
  writing beside it and renaming, and removes the other format's file for the kind if there is one.
  It answers 200 with the kind and its format.
- `DELETE` on the same path removes the kind's file, and answers 204, or 404 when there is none.

`PUT` and `DELETE` are the operator's.

## What the console adds

**The library browser.** Each library of a silo with access opens to its tree of containers, top-level
containers first and each one's children beneath, read from the library's own routes. Selecting a
container shows it: its own fields, its alternatives and features, its sequences and extras with the
presentations each item has in this library (by display name, profile, alternative and file), the
items that have none, its children, its artwork, and the last walk's findings on its sidecar. The
browser keeps itself current as the rest of the console does.

**The container editor.** Editing a container opens a form over its own fields. The form adds, edits,
removes and reorders alternatives, features, sequences, items and extras, and edits the external
references. An edit is a draft, kept on the Mac as a ruleset draft is: for the silo by its
`ServerID`, the library and the container, with the digest it was based on. It outlives the section,
the refresh and the app, and a draft whose sidecar has changed since is marked behind. As the operator
types, and a moment after they stop, the console asks the silo for a dry run of the edit and shows
the findings. Before it stores, it shows the document's difference from the sidecar it was based on
and the findings. A 409 keeps the draft, shows the sidecar that landed and how it differs from the
base, and offers to re-base the draft on it or discard it. The console does not merge.

**Artwork.** The container shows each kind it has. The operator drops an image onto a kind to put it,
or removes it.

## What this looks like to the operator

The operator opens the `films` library and finds *Alien* listed as `Alien (1997)`, which is wrong.
They open it, correct the year to 1979, and see the dry run come back with one warning: the folder
`Alien (1997)` is not the name the layout would give it, `Alien (1979)`. They store the edit, and the
player shows 1979 at once; the folder stays where it is until they choose to lay the library out
again. While they are there they add the director's commentary as a feature, so that the next
encode of the disc can map a track to it, and drop a poster onto the container. Later they try to
remove the theatrical cut from its alternatives, and the dry run refuses it: two presentations in
the library are of that cut.

## What this asks of an implementation

Five steps, one pull request each, each carrying its spec change. The four silo changes are in
[`openspec/changes/`](../openspec/changes/): `containers-1-per-library`, `containers-3-editing`,
`containers-4-artwork` and `containers-5-console`.

### 1. A container per library

The index keyed by library and container; the walk's error for a container held twice in one library;
the library's view of its containers; and the global route answering from the first library that
holds the container, saying which.

Tests: a container in two libraries is indexed twice, and removing one library's sidecar leaves the
other's container and presentations; a second sidecar for one id in a library is reported and not
indexed; the library routes answer an unlisted root, and 404 for a container another library holds.

### 2. Setting a sidecar's container, in SmdKit

`SidecarFile` sets a container's own fields in a sidecar, keeping its library facts and comments, and
refuses a value for another container. Its sidecar spec changes in the same pull request. It merges
first, and the silo's `Package.resolved` moves to it.

### 3. The edit

The edit route with `basedOn`, the dry run and its refusals; the digest on the library's container;
the walk's warning for a folder not named as the layout would name it.

Tests: an edit of a title is written, read back, and leaves the presentations, children's paths and
rules as they were; an edit based on a sidecar changed since is 409 and writes nothing; an edit
removing an alternative a presentation names, or an item with presentations, is 422 with its finding;
a dry run writes nothing; a title edit leaves the folder, and the walk warns of its name.

### 4. Artwork

The artwork routes and the walk's warning for a kind held twice.

Tests: a JPEG put as a poster is served back with its content type; a PNG put as the same kind removes
the JPEG; a file that is neither is 415; `DELETE` removes it.

### 5. The console

SiloClient and SiloAdminKit learn the library's container routes, the edit and artwork; SiloAdmin
gains the library browser, the container editor with its drafts, and artwork. Shell-level behaviour
stays `Pinned by: nothing yet.` until the shell grows a test seam.

## What comes next

**0013, smddb in the console.** A small smddb client in SmdKit, shared by the console and any
producer, with a local implementation over a clone of the data repository to begin with. It will
import a container from smddb into a library, or create one, with an id from the client's
provisional-id call: local for now, and the service's to issue when there is a service. It will
propose a library's container back to smddb by exporting the chosen library's sidecar as a
repository document. Import onto a container a library already holds is this proposal's edit.

**0014, structure is the console's.** A binding names an item of a container its library already
holds, and the silo takes the container from the library rather than from the producer. Containers
enter a library from the console, and a producer binds into them.

**0010, a container's own rules,** read, drafted and tried in the console's ruleset editor.

## Non-goals

- **Moving files on an edit.** A title, a year or an item's title changes no path. Re-laying a library
  out is its own act, still to be proposed.
- **Removing media.** An edit cannot take away an item that has presentations; removing a presentation
  is not this proposal's, and the files are the household's.
- **Creating containers.** A container enters a library by placement, or by 0013.
- **Editing smddb.** The console edits a library's sidecar. Proposing the change to smddb is 0013's.
- **Artwork for items.** An episode's still or an extra's thumbnail is an item's, and an item shares its
  container's folder. Naming it needs the item's own stem, which the layout gives each presentation's
  file rather than the item; it waits until someone asks.
- **Fetching artwork.** The silo stores what it is given. Finding a poster at a provider is the
  console's, or the operator's.

## Open questions

1. **The global route for a container in several libraries.** This proposal answers from the first
   library in settings order and names it. A player might prefer every library's presentations of the
   container together, which would mean choosing whose own fields to answer with. Settings order is a
   decision nobody has to remember. Merging can wait for someone with two libraries to ask.
2. **An edit that changes what a rule would decide.** Changing an item's type, or moving it into the
   extras, changes the facts a rule tests of its binding. A placed presentation is not reported out of
   date by it, for the reason [silo-server#77](https://github.com/media-silo/silo-server/issues/77)
   gives. The dry run could warn that the edit touches an item with presentations, until #77 is fixed.
3. **The kinds of artwork.** Five kinds is a start. Whether the vocabulary belongs in SmdKit, as the
   extra types now do, is for when a second reader needs it.
