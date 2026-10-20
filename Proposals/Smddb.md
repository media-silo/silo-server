<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0013-smddb

Modified: 2026-10-20

# smddb in the console

This proposes that the operator bring containers into a library from smddb, create containers smddb
does not have, and propose a library's container back to smddb, all from SiloAdmin. The console reads
smddb through a small client in SmdKit. Its first implementation is a clone of the data repository
on the Mac. Its interface is the one a service would offer: a provisional id for a new container, and
a contribution for a container proposed back. The silo gains one route, which makes containers in a
library with no media: their folders and sidecars, placed as a placement would place them, with
nothing yet to play. The silo never talks to smddb. It takes containers as documents, whoever wrote
them.

This is the third of the proposals that make the console where a library's structure is defined,
after [0005-libraries](Libraries.md) decides which libraries a silo has and
[0012-containers](Containers.md) shows a library's containers and edits them.
[0014](#what-comes-next) has a producer bind into the structure a library holds, rather than bring its
own. [0010](Drafts.md#what-comes-next), a container's own rules, follows them.

## The problem

**A container enters a library only with a file.** The only thing that writes a new sidecar is a
placement, and a placement carries the container as its producer sent it. Whatever describes the
container lives with the producer, and the library learns it when the first file arrives. A library
cannot hold a season before any of its episodes is encoded. Its structure cannot be set up in
advance, checked, and then filled.

**smddb is where containers are described, and the console cannot reach it.** A container is
authored once, in the data repository, with its alternatives, features, sequences and extras, and
given an id that every library holding it shares. The console can now edit a container a library
holds. It cannot find one in smddb, bring one into a library, or say where a library's sidecar and
smddb's record differ.

**A correction made in a library stays there.** 0012 lets the operator fix a year, add a provider id
or declare a commentary, in one library's sidecar. smddb principle 5 says provenance is recorded so
that a correction can go back upstream. Today nothing carries a sidecar's own fields back to the
repository, except someone copying XML by hand.

**A container smddb does not have needs an id from somewhere.** smddb's principle 3 is that identity
is minted there and never reissued. There is no smddb service to mint one yet. Any id the console
makes up is a promise that smddb will accept it.

## What this is

**A client for smddb, in SmdKit.** `ContainerDatabase` already lists containers, reads one by id and
matches a provider's id. It gains two calls. `provisionalID()` answers an id for a new container,
provisional until smddb accepts a container carrying it. `contribute(_:)` takes containers proposed
to smddb and answers a contribution. `LocalRepository`, the client over a clone of the data
repository, mints the id itself, re-minting while the clone has a file of that name. It contributes
by checking the containers and writing their files into the clone, and answers which files it
wrote. Committing them, and anything that follows, stays the operator's. A service implementation
can come later behind the same two calls, and nothing the console does needs to change when it does.

**Containers made in a library without a file.**
`POST /v1/libraries/{library}/containers` takes one or more containers as repository documents,
forming a tree, and `parent`, the container the library holds that names the top of the tree as a
child, or none for a container at the top of the library. It makes each container's folder and
sidecar as a placement would, writes the parent's child path, and places nothing. The request is
refused whole when the library already holds a container in it, when the parent does not name the
top of the tree, or when a document does not validate. A dry run answers what would be written.

**Importing from smddb.** In the library browser the operator searches the clone, picks a container,
and chooses which of its descendants to bring with it. The console works out the rest. It walks up
smddb's lineage to the nearest container the library already holds, which becomes the parent, and
creates everything below it. A container the library already holds is not imported: the console
shows how the library's sidecar differs from smddb's record and offers 0012's edit, based on the
sidecar it read.

**Creating a container.** The operator creates a container in the console's container form, at the
top of a library or as a child of one the library holds. Its id comes from `provisionalID()`. A
child is named in its parent's own fields by an edit of the parent, and then made by the same route
an import uses.

**Exporting to smddb.** On a container in a library, the operator proposes it to smddb. The console
takes the container's own fields from that library's sidecar as a repository document, shows how it
differs from the clone's record of the same id, if there is one, and contributes it, together with
the containers beneath it, or reached through a ref, that the library holds and smddb does not. The library's sidecar does not change. Its
presentations, children's paths and rules are the library's, and the repository document has no
place for them.

**The browser says how a container stands against smddb.** For a library container whose id the
clone also holds, the browser says whether the library's own fields match smddb's record or differ
from it. For one the clone does not hold, it says smddb does not have it.

## Principles

0012's principles stand: a library's sidecar is the container in that library, and an edit changes the
container and never the media. This proposal adds four.

1. **The silo knows containers, not where they came from.** Nothing in the silo reads smddb, or knows
   whether an id is provisional. A container imported from smddb and one the operator typed reach the
   silo the same way, as documents, through the same route.
2. **smddb is reached through one client, shaped like the service it will become.** The console asks
   the client for an id and offers it a contribution. The local implementation answers both from a
   folder. Whatever replaces it answers the same questions, and the clone stops being the only way to
   ask them.
3. **Importing copies; it does not link.** A container brought from smddb is a sidecar in the
   library from then on, and a later change to smddb's record changes nothing in the library. The
   browser shows the difference. Taking the change in is an edit the operator makes.
4. **Exporting proposes; it does not publish.** A contribution is an offer to smddb. Locally it is
   files in a clone the operator commits. Later it is a submission someone reviews. The console never
   commits, pushes or merges.

## Vocabulary

- **The clone** — a folder on the Mac holding a clone of smddb's data repository, with one file per
  container under `containers/`. The console reads and writes it through `LocalRepository`.
- **Provisional id** — an id the client issued for a container smddb has not accepted yet.
- **Contribution** — containers offered to smddb, and what the client answers about them.
- **Import** — making in a library a container smddb holds, with the descendants the operator chose.
- **Export** — contributing a library's container to smddb, from that library's sidecar.

## What SmdKit adds

`ContainerDatabase` gains:

- `provisionalID() async throws -> ContainerID`, an id for a container nobody has yet. It is
  provisional until smddb accepts a container carrying it. `LocalRepository` mints one and mints again
  while the clone has a file named for it. 64 random bits make a second try a formality, and the check
  costs one `stat`.
- `contribute(_ containers: [Container]) async throws -> Contribution`, which offers containers to
  smddb. A contribution is refused whole, and nothing written, when two of its containers share an id,
  or when a container names a child, or refers to a container, that neither the database nor the
  contribution holds. This is the referential check smddb's hosting proposal runs at submit,
  done here so that the clone is never left naming a container it lacks. `LocalRepository` writes
  each container as `save(_:)` does and answers `Contribution.written`, listing the files.
  Hosting.md's states, `pending`, `changes-requested`, `merged` and `rejected`, are the cases a service
  will add. They are not declared until a service exists to answer them.

The container-database spec changes in the same pull request, and the silo's `Package.resolved`
moves to it.

## What the silo adds

`POST /v1/libraries/{library}/containers` takes a `ContainerCreate`:

- `documents`, one or more containers as repository XML;
- `parent`, the id of a container the library holds, or absent;
- `dryRun`.

It answers a `ContainerCreateResult`: `applied`; the `writes`, each a sidecar's path relative to the
library and whether it is new; and the `findings`.

The documents form one tree. Exactly one of them, the top, is named as a child by none of the others,
and every other one is named as a child by a document in the request. With a `parent`, the top is
filed beneath the parent's folder, and the parent's own fields must name it as a child. Without one,
the top is filed at the top of the library. Each container's folder is named by the layout, as a
placement names it. Its sidecar holds the document's own fields and no presentations, and each
parent's sidecar records its child's path, as a placement records it.

- A document that cannot be read is 400, and so is a request whose documents do not form one tree.
  A library the silo does not serve, or a `parent` it does not hold, is 404.
- A request with an error-severity finding is 422, carrying the result with its findings, and
  nothing is written. Besides the validator's checks on each sidecar, it is an error when the library
  already holds a container in the request (`container <id> is already at "<path>"`, the walk's
  words for a container held twice), when the parent's own fields do not name the top
  (`<parent> does not name <top> as a child`), and when a folder the request would use holds a sidecar
  for another container (`the folder for <title> already holds <id>`, the placement's words).
- A request with `dryRun` is answered 200 with `applied` false, and writes nothing.
- Otherwise the silo makes the folders, writes the new sidecars, top first, then writes the parent's,
  and re-reads each sidecar it wrote into the index before answering 200 with `applied` true. As after
  a placement, it walks nothing.

The route is the operator's, behind the operator gate.

The new sidecars come before the parent's for the reason a placement writes its file before its
sidecars. A crash between the two leaves a folder nothing references, which the walk reports as a
warning. The other order would leave a reference to a sidecar that is not there, which is an error.

The making is SiloLibrary's, beside the placer. It computes every write before making any, and
describes them in the placement's words, `create` and `write`. It shares the placer's folder
naming, its refusal of a folder that holds another container, and its update of an existing parent
sidecar that changes only the child's path. A placement into a container made this way finds its
sidecar there, and changes only the library's facts in it, as it does for any sidecar it finds.

**A container with nothing to play is still served.** Until now every container in a library had a
presentation somewhere beneath it. A container made by this route has none until something is placed
into it. The read routes answer it as the library holds it: listed if its sidecar says listed, with
items that have no presentations. Whether to show a container with nothing to play is the player's
decision, as a profile is a filter and not the silo's decision. A player that would rather not ask
can be given a filter when one asks for it.

## What the console adds

**The clone.** SiloAdmin's settings name a folder on this Mac as the clone of smddb's data repository.
It is the same kind of folder a producer's tools on the Mac may already point at. The console reads it
through `LocalRepository`, and reads it again when the app becomes active and when the operator asks,
so that a `git pull` made outside the console is seen. The console never clones, pulls, commits or
pushes. With no folder named, or one that cannot be read, the smddb actions are unavailable and say
why.

**Import.** From a library, or from a container it holds, the operator opens smddb. The console lists
smddb's roots and searches the clone's containers by title and by provider id, as a filter over the
listing. smddb's principle 1 keeps that listing small. The operator picks a container and ticks the
descendants to bring. All of them are ticked to begin with, and the ones the library already holds
are shown and cannot be ticked. The console finds the parent, the nearest of the container's smddb
ancestors that the library holds. It asks the silo for a dry run of creating everything from just
below the parent down, shows the writes and findings, and creates them when the operator confirms.
When the parent's sidecar does not name the next container down, the dry run refuses it. The console
then offers to bring the parent's own fields from smddb first, as an edit draft, shown and stored as
0012 stores one.

**A container the library already holds.** The browser shows smddb's record beside the library's
sidecar. Taking smddb's record in opens an edit draft of the library's container whose document is
smddb's, based on the sidecar the browser read. The operator reviews its difference and stores it as
any edit.

**Create.** "New container" opens 0012's container form over an empty container with an id from
`provisionalID()`, at the top of the library or as a child of a container the library holds. For a
child, the operator chooses the parent's sequence and position. Storing a child is two requests. The
first is an edit of the parent that names the new child, based on the parent's sidecar. The second
creates the child. If the second is refused, the parent is left naming a child the library does not
hold. That is a state a library is already in whenever it holds some of a series' seasons. The
console shows the refusal and keeps the new container's draft, so it can be fixed and created again.
A new container's draft is kept on the Mac as an edit draft is, until it is created or discarded.

**Export.** On a library container, "Propose to smddb" shows the repository document the library's
sidecar makes, and its difference from the clone's record of the same id, or says the clone does not
have it. The containers it names that the clone lacks, as children beneath it or through a ref, are
offered with it from the library's sidecars, and ticked, since a contribution that names a container
smddb lacks is refused. One the library does not hold either is shown as the reason the export would
be refused. On confirming, the console
contributes them and says which files it wrote in the clone, for the operator to commit there.

**Standing against smddb.** Each container in the browser whose id the clone holds says whether the
library's own fields match smddb's record or differ from it. One the clone lacks says that smddb does
not have it. This is a comparison of two documents the console already has, and it asks the silo
nothing.

## What this looks like to the operator

The operator points SiloAdmin at their clone of the data repository and opens the `films` library.
They open smddb, search for *Alien*, and import it. The library shows *Alien (1979)* with its
theatrical and director's cuts and its commentary, and no presentations. A player browsing the
library sees the film with nothing to play, until the first encode is placed into it.

In the `tv` library, which holds *Doctor Who* with Season 13, they import Season 12 from smddb. The dry
run refuses it: the library's *Doctor Who* sidecar does not name Season 12, because it was written
before smddb's record gained it. The console offers to bring *Doctor Who*'s own fields from smddb. They
review the difference, one child entry added to the seasons, and store it. The import of Season 12
and its five serials then goes through, and the browser shows them with no presentations.

A fan documentary they own is in no smddb record. They create it at the top of the library, with an id
the client issued, add its two parts, and store it. Later, having added its TMDb id and a director's
commentary as a feature, they propose it to smddb. The console shows the new file it will write, writes
`containers/<id>.xml` into the clone, and the operator commits it and opens a pull request against the
data repository. *Alien*'s corrected outline, meanwhile, shows as differing from smddb, and they propose
that too.

## What this asks of an implementation

Three steps, one pull request each, each carrying its spec change. The silo's two are in
[`openspec/changes/`](../openspec/changes/): `smddb-2-creating` and `smddb-3-console`.

### 1. The client, in SmdKit

`ContainerDatabase.provisionalID()` and `contribute(_:)`, `Contribution`, and their `LocalRepository`
implementations. SmdKit's container-database spec changes in the same pull request. It merges first,
and the silo's `Package.resolved` moves to it.

Tests: a provisional id is not one the clone has a file for; a contribution writes each container's
file and lists them; a contribution naming a child neither the clone nor the contribution holds is
refused, and writes nothing.

### 2. Making containers in a library

SiloLibrary's making of a tree of containers without a file, and the create route with its dry run,
its refusals and its re-read of what it wrote.

Tests: a series with one season and one serial, created at the top of an empty library, makes three
folders and three sidecars with no presentations, and the library's routes answer them; a season
created beneath a series the library holds updates only the series' child path; a request naming a
container the library holds, or a parent that does not name the top, is 422 and writes nothing; a dry
run writes nothing; a placement into a created container keeps its own fields and adds the
presentation.

### 3. The console

SiloClient and SiloAdminKit learn the create route. SiloAdminKit reads the clone through
`LocalRepository`, compares a library's container with smddb's record, and keeps a new container's
draft. SiloAdmin gains the clone setting, import, create, export and the standing against smddb.
Shell-level behaviour stays `Pinned by: nothing yet.` until the shell grows a test seam.

## What comes next

**0014, structure is the console's.** A binding names an item of a container its library already
holds, and the silo takes the container from the library, not from the producer. With this proposal
the console can put every container a producer would bind into a library first, so a producer stops
carrying lineages and the silo stops accepting them.

**0010, a container's own rules,** read, drafted and tried in the console's ruleset editor.

**A smddb service,** when smddb's roadmap reaches its read and contribution APIs, is a second
implementation of the client, and the console chooses between the clone and the service in its
settings.

## Non-goals

- **Git.** Cloning, pulling, committing, pushing and opening pull requests against the data repository
  are the operator's, in the clone. The client writes files and stops.
- **Fetching containers from providers.** Building a container from a TMDb or TVDB record is authoring,
  which smddb's ingestion flow calls the one genuinely human step. The console's form is where it is
  done, by hand.
- **Removing a container from a library,** or moving one. A container made in error with nothing
  placed in it is a folder the operator can remove, and the walk forgets it. A route for it waits for
  someone to ask.
- **Discs, releases and bindings in smddb.** The client knows containers. A binding is recorded by
  whatever makes it, and contributing one is the producer's, after 0014.
- **Artwork in smddb.** smddb leaves artwork to the providers. Exporting a container carries none of
  the library's artwork, and importing one brings none.
- **Following smddb.** An imported container does not track its record. The browser shows a
  difference, and the operator decides.

## Open questions

1. **A provisional id smddb declines.** While the clone is the database, an id the clone has no file
   for is as good as smddb's own. A service may one day answer a contribution with an id of its own
   choosing. A library holding the provisional one would then need its container re-keyed in every
   sidecar that names it, which nothing does today. This proposal leaves the call shaped so the answer
   can say so, and builds no re-keying until a service gives a reason to.
2. **Which Mac holds the clone.** Each Mac running the console names its own clone, so two Macs
   administering one silo may read smddb at different commits. The silo could hold the clone instead.
   That would break principle 1, so the clone stays on the Mac until households with two consoles say
   it hurts.
3. **Creating a child in one request.** Creating a child of a held container is an edit of the parent
   and then a create, and the two are not atomic. The create could take the parent's new document and
   its digest, and make both under one lock. Two requests reuse two routes that exist. A household
   that hits the gap between them can be the reason to close it.
4. **A filter for containers with nothing to play.** Players may want the read routes to leave out
   containers with no presentations beneath them. The silo answers what the library holds, and a
   filter can be added without changing what an unfiltered request answers.
