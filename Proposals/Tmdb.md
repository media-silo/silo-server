<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0017-tmdb

Modified: 2026-10-21

# TMDb in the console

This proposes that the console read a container's shape from TMDb, as a draft the operator shapes
before anything is made, and show how a container a library holds differs from TMDb's record of it,
for the operator to take each difference or leave it. It starts with one provider, TMDb, reached by a
client in SiloAdminKit with a key kept on the Mac. Only facts are taken plainly from TMDb: titles,
years, structure and provider ids. What is not a fact — an outline, an image — is attributed to TMDb
in the library's sidecar, and a container proposed to smddb leaves it out. Artwork stays in the silo
and is never contributed. The silo never talks to TMDb. It takes containers as documents and records
attributions it is given.

It is one of the proposals that make the console where a library's structure is defined, and follows
[0012-containers](Containers.md), which edits a container, and [0013-smddb](Smddb.md), which brings
containers in from smddb, creates them and proposes them back. It revisits 0013's non-goal of fetching containers
from providers. smddb's own ingestion flow already names TMDb's episode groups as the starting shape
for a container that has to be authored, and this proposal makes that starting shape something the
console can fetch.

## The problem

**A container smddb lacks is typed in by hand.** 0013's "New container" opens an empty form. A series
with seven seasons and a hundred episodes is a hundred items typed one at a time, each with a provider
id copied from a browser tab. Nearly all of it is already at TMDb, in an order and with the ids the
container wants.

**A container the library holds drifts from the world.** A season gains episodes after it was made, a
provider id was never added, and a film with no poster has one at TMDb. Nothing shows the operator
what TMDb knows that the library does not.

**Not everything TMDb holds may go to smddb.** smddb's data is meant to be CC0. A title, a year and the
order of a season's episodes are facts. TMDb's overview of a film is someone's writing, and its
posters are someone's images, and neither is TMDb's to give to a CC0 database or the operator's to
contribute. 0013's export takes a container's own fields from the library's sidecar as they stand. An
outline taken from TMDb and stored there would go to smddb with the rest.

## What this is

**A TMDb client, in SiloAdminKit.** It searches movies and series, reads a movie, a series with its
seasons and episodes, an episode group, a collection, the provider ids TMDb holds for each, and the
images for each. It authenticates with a read access token the operator gives in SiloAdmin's settings,
kept in this Mac's keychain, and asks in the language the settings name. With no token the TMDb actions
are unavailable and say why.

**TMDb's reading of a container.** From a TMDb record the console builds a container: a `Container` as
SmdKit has it, with the record's title, year and type, its children as entries and child containers in
TMDb's order, and an `ExternalRef` for TMDb and each provider id TMDb knows. An episode is an entry
carrying its refs and no title, which is what SmdKit's model asks for an entry a provider has a title
for. The console shows the episode's title from TMDb as it is reviewed, and stores none. The outline is
TMDb's overview, attributed. This one reading serves both what follows.

**A draft from TMDb.** In the library browser the operator searches TMDb, picks a movie, a series or a
season, and the console makes TMDb's reading of it into a tree of new-container drafts. The operator
shapes the draft in 0012's form before creating it. They can re-type a level, regroup a season's
episodes into serials, drop what they do not hold, or choose one of TMDb's episode groups as the shape
in place of its seasons. Ids come from smddb's client, as 0013's "New container" takes them. The tree
is made through 0013's create route, under the nearest container the library already holds, found by
its TMDb ref.

**Differences from TMDb.** For a container the library holds with a TMDb ref, the browser shows TMDb's
reading beside the library's sidecar as a list of differences. These are a field that differs, a ref
TMDb knows and the sidecar lacks, a child TMDb has that the library does not, an order that differs,
and artwork TMDb has for a kind the container lacks. Each has a tick. The operator ticks the ones to
take. The console makes the ticked field, ref and order changes into one edit draft based on the
sidecar the browser read, and the ticked children into drafts of new containers, as a draft from TMDb
makes them. Nothing is taken until the operator stores the edit and creates the children.

**Attribution, in the sidecar.** A sidecar can say that a field of its container, or a kind of its
artwork, came from a provider: which provider, and the ref it came from. It is a library fact, like a
presentation or a child's path, and the repository document has no place for it. The silo records it
when an edit or an artwork put carries one, serves it with the container so that a player can credit
it, and keeps it through placements and walks.

**Export leaves the attributed out.** When 0013's export makes a repository document from a library's
sidecar, each attributed field takes smddb's record's value instead, or none when smddb has no record.
The export shows which fields were left out, and why.

## Principles

0012's and 0013's principles stand. In particular, importing copies and does not link, and the silo
knows containers, not where they came from. Attribution is the one exception, and it is the record of
whose writing a field holds. This proposal adds four.

1. **TMDb proposes; the operator decides.** Nothing from TMDb reaches a library except as a draft the
   operator stored or a container the operator created. A difference is shown with a tick, and an
   unticked difference changes nothing.
2. **smddb's identity comes first.** A container smddb holds is imported from smddb, never drafted from
   TMDb. Before drafting, the console asks the clone for a container carrying the record's TMDb ref and
   offers that import instead when it finds one. A draft from TMDb would mint a second id for something
   smddb has already named.
3. **Facts are taken; everything else is attributed.** A title, a year, a type, which episodes a season
   has and in what order, and the ids other providers give them are facts, and a draft takes them
   plainly. An outline and an image are TMDb's contributors' work. A draft takes them only with an
   attribution, and an attribution is never dropped quietly.
4. **Attributed work stays in the library.** Artwork is never contributed, attributed or not. An
   attributed field never reaches smddb. What is shown to the operator from TMDb but not stored, such as
   an episode's title, is credited where it is shown.

## Vocabulary

- **TMDb's reading** — the container the console builds from a TMDb record, with its children.
- **Draft from TMDb** — a tree of new-container drafts made from TMDb's reading, shaped before it is
  created.
- **Difference** — one way a held container's sidecar differs from TMDb's reading, which the operator
  may take or leave.
- **Fact** — what a draft takes from TMDb plainly: title, year, type, structure, order and provider ids.
- **Attribution** — a library fact naming the provider and ref a field or an artwork kind came from.

## What SmdKit adds

`Sidecar` gains `attributions: [Attribution]`. An `Attribution` names a `subject`, either a field of
the container's own (`outline`, or an alternative's outline as `alternative/<id>/outline`) or an artwork
kind (`artwork/<kind>`), together with a `provider` and the `value` of the ref the subject came from. The
sidecar writes each as `<attribution subject="outline" provider="tmdb" value="121"/>` beside its other
library facts, and the reader reads them back. `SidecarFile.sidecar(from:).container` is unchanged,
since an attribution is not part of the container.

The sidecar spec changes in the same pull request. It merges first, and the silo's `Package.resolved`
moves to it.

## What the silo adds

**Attributions in an edit.** `ContainerEdit` gains `attributions`, the set for the container's own
fields. When it is absent, the sidecar's attributions of fields stand as they are. When it is present,
it replaces them. An attribution of a field the document does not have is an error-severity finding
(`outline is attributed to tmdb but the container has none`), so removing an attributed outline takes
its attribution with it, and the console sends both. Artwork attributions are not the edit's.

**Attributions in a create.** 0013's `ContainerCreate` gains `attributions`, each naming the
`container` in the request it belongs to, with its `subject`, `provider` and `value`. They are written
into the new sidecars in the same request. A container drafted from TMDb is therefore never in the
library, even for a moment, with an outline that does not say whose it is. An attribution naming a
container the request does not carry is 400.

**Attributions on artwork.** The artwork `PUT` takes optional `provider` and `value` query parameters.
With them, the silo writes the image and records the kind's attribution in the sidecar. Without them,
it writes the image and removes any attribution the kind had, since the image is now the operator's
own. `DELETE` removes the kind's attribution with its file. When a put records an attribution, the
sidecar is written before the image. When it removes one, the image is written first. Either way an
interrupted put credits the provider for too much, rather than leaving its image uncredited. The
sidecar is re-read into the index, and its digest changes, so a draft based on it is marked behind, as after any edit.

**Attributions are served.** `LibraryContainer` and the container's read answers gain `attributions`,
each a `subject`, `provider` and `value`, so that a player showing an outline or a poster can say whose
it is. A placement keeps a sidecar's attributions as it keeps every library fact it does not own. The
walk reports an artwork attribution whose kind has no file as a warning.

The silo never calls TMDb. It records an attribution as it was given, and checks nothing about it
beyond its shape and its subject's presence.

## What the console adds

**The token and the credit.** SiloAdmin's settings take a TMDb read access token, kept in this Mac's
keychain, and a language, defaulting to the Mac's. The settings and the about panel carry TMDb's logo
and the notice its terms ask for, that the product uses the TMDb API but is not endorsed or certified
by TMDb. Wherever the console shows something from TMDb, such as a search result, a reading, a
difference, or an episode title in a draft, it marks it as TMDb's.

**Search.** From a library, or from a container it holds, the operator opens TMDb and searches movies
and series by title. A result shows its title, year, type and poster. Picking one takes the console to
smddb's import if the clone holds a container with that TMDb ref (principle 2). It takes the console to
the container's differences if the library holds one. Otherwise it opens a draft from TMDb.

**A draft from TMDb.** A movie is read as a `movie` container. A series is read as a `series` with a
child `season` container for each of TMDb's seasons, and each season holds its episodes as entries. A
collection is read as a `collection` with each movie as a child. Before the draft opens, the operator
chooses how deep to go and, for a series with episode groups, which shape to start from: TMDb's
seasons, or one of its groups, each group becoming a child container whose type the operator picks.
The tree then opens in 0012's form, one draft per container, with a provisional id each. The form shows
each episode's TMDb title beside its entry. The outline arrives filled and marked "from TMDb". Editing the
text keeps the attribution, since reworded writing is still derived from it, and removing the outline
removes it. The operator may remove the attribution alone, which the console confirms with them first,
as their saying the text is their own. A dry run of the whole tree, made through 0013's
create route, runs as the operator shapes it. Creating it makes the tree, with its attributions, in one
request, as an import does.

**Differences.** A held container with a TMDb ref shows a TMDb section in the browser. Opening it
fetches TMDb's reading and lists the differences, grouped:

- *Fields*: the title, the year, the outline. The outline is shown with its attribution, and taking it
  takes the attribution.
- *References*: each provider id TMDb knows that the sidecar lacks.
- *Children*: each of TMDb's episodes or seasons whose ref nothing beneath the container carries, with
  where TMDb puts it. A child container is offered as a draft from TMDb beneath this one. An episode
  the operator filed in a serial of their own is beneath the season, and so is not missing.
- *Order*: when the items both have, at the same level, are in a different order. Episodes regrouped
  into serials are not an order difference.

A container without a TMDb ref of its own, such as a serial the operator grouped, has no TMDb record to
read. Its section reads the nearest container above it that has one. Its differences are about the
entries it holds: their refs, and their order among themselves.
- *Artwork*: each kind the container has no file for and TMDb has an image for, with the image.

Items and children the library holds that TMDb does not are shown, and never offered for removal.
TMDb models no cuts, features or extras, so its silence about one says nothing. Taking the ticked field,
reference, child-entry and order differences makes one edit draft of the container, stored as 0012
stores one. Taking a child container makes its draft from TMDb. Taking artwork puts the image with its
attribution.

**Artwork from TMDb.** Beside each kind the container lacks, and from the differences, the operator can
browse TMDb's images for the record and put one. The console fetches the image and puts it with
`provider=tmdb` and the record's ref. TMDb's poster is offered for `poster`, its backdrops for `fanart`
and its logos for `logo`. An image the operator drops in themselves is theirs, and clears the
attribution, as 0012's artwork always was.

**Export.** 0013's export plan gains the attributed fields it left out. For each one it shows the
subject, the provider, and the value it takes instead from smddb's record. Its difference from smddb's
record is read against the document with those fields taken from smddb, so an attributed outline shows
as no difference rather than as one that cannot be proposed.

## What this looks like to the operator

The operator gives SiloAdmin a TMDb token and opens the `films` library. They search TMDb for *Alien*.
The clone has no container carrying its TMDb ref, so a draft opens: *Alien (1979)*, a movie, with refs
for TMDb, IMDb and Wikidata, and TMDb's overview marked "from TMDb". They add the director's cut as an
alternative, create it, and take TMDb's poster from the artwork section. The browser shows the poster
credited to TMDb. When they later propose *Alien* to smddb, the export says the outline was left out,
attributed to TMDb, and the document it writes into the clone has none.

In the `tv` library, *Doctor Who* holds Season 13 and carries TMDb ref `121`. Its TMDb section lists
the differences: twenty-five seasons the library does not hold, no fanart, and nothing else. They tick
Season 14 and the fanart. Season 14 opens as a draft from TMDb, a season of twenty-six episodes in
TMDb's order. The operator wants it as six serials, so they regroup the episodes into six child
containers of type serial labelled Story and title each one. The dry run shows the parent edit that
names Season 14 and the seven sidecars it will make. They create it. The fanart is put, credited to
TMDb.

A week later TMDb has gained an IMDb id for the first part of *Pyramids of Mars*. The serial has no TMDb
ref of its own, so its TMDb section reads Season 13's record. It lists the new id under References
against that entry, and taking it is a one-line edit.

## What this asks of an implementation

Four steps, one pull request each, each carrying its spec change. The silo's three are in
[`openspec/changes/`](../openspec/changes/): `tmdb-2-attribution`, `tmdb-3-drafts` and
`tmdb-4-differences`.

### 1. Attributions, in SmdKit

`Attribution`, `Sidecar.attributions`, and their reading and writing. SmdKit's sidecar spec changes in
the same pull request. It merges first, and the silo's `Package.resolved` moves to it.

Tests: a sidecar with an outline's and a poster's attribution reads back as written; a sidecar with
none writes no element; the container read from a sidecar with attributions is the container read from
one without.

### 2. Attributions in the silo

`ContainerEdit.attributions`, `ContainerCreate.attributions`, the artwork put's `provider` and
`value`, `attributions` in the read answers, placement keeping them, and the validator's and walk's
findings.

Tests: an edit carrying an outline's attribution records it, and a later edit without `attributions`
keeps it; an edit removing the outline while its attribution stands is 422; a create carrying an
attribution writes it into the new sidecar; an artwork put with a
provider records the kind's attribution, and one without removes it; a placement into a container with
attributions keeps them.

### 3. Drafts from TMDb

SiloAdminKit's TMDb client, behind a protocol so tests answer from recorded responses. TMDb's reading of
a movie, a series, a season, a collection and an episode group. The smddb-first check. Drafts from TMDb
made through 0013's create route. Export leaving the attributed out. SiloAdmin's token and language
settings, the credit, search, and the draft. Shell-level behaviour stays `Pinned by: nothing yet.`

Tests: a series' reading has a season per TMDb season and an untitled entry per episode carrying its
ref; a record whose TMDb ref the clone holds is offered as smddb's import; a draft from TMDb beneath a
held series names it in the parent and makes the tree; an export of a container with an attributed
outline writes smddb's outline, or none.

### 4. Differences and artwork from TMDb

The differences between a sidecar and TMDb's reading, the edit draft made from the ticked ones, children
as drafts from TMDb, and artwork put with its attribution.

Tests: a season TMDb has gained an episode for lists one child difference, and taking it adds one entry
in TMDb's position; an extra the library holds and TMDb lacks is listed and offered for nothing; taking
a missing ref makes an edit that adds only that ref; artwork taken from TMDb is put with its
attribution.

## What comes next

**Other providers, behind the same reading.** TVDB's season orderings (aired, DVD, absolute) and
Wikidata's serials and their parts are readings of the same kind. Wikidata is CC0, so what it holds may
go to smddb unattributed. The reading and the differences are written against a provider's reading, not
TMDb's, so that a second provider is a second client.

**Credit in the players.** A player that shows an attributed outline or image should say whose it is.
The silo serves the attribution, and what a player does with it is the player's.

## Non-goals

- **Following TMDb.** A container drafted from TMDb does not track it, as one imported from smddb does
  not track smddb. The differences show what has changed, and the operator decides.
- **Titles and outlines for entries.** SmdKit's model gives an entry a title only when no provider has
  one. A draft stores TMDb's episode titles nowhere, and shows them only while it is reviewed.
- **Removing what TMDb lacks.** TMDb's silence is not evidence, and nothing is offered for removal.
- **Contributing to TMDb.** Corrections to TMDb are made at TMDb.
- **Artwork in smddb.** Unchanged from 0013. Artwork stays in the silo, from wherever it came.
- **The silo reaching TMDb.** The token, the requests and the rate limit are the console's. A silo
  serving a household holds no third party's credentials.

## Open questions

1. **What TMDb's terms allow kept.** An attributed outline and an image are stored in the library
   indefinitely. TMDb's terms on caching and storage need reading against that before step 3. If they
   limit how long something may be kept, the attribution could carry when it was fetched, and the walk
   could warn on what has outlived it.
2. **Whether TMDb's structure is a fact.** A season's episodes and their order are facts. An episode
   group is a contributor's arrangement, and an arrangement can be protected where a fact is not. The
   proposal treats a group's shape as a starting point the operator reshapes, and contributes the
   operator's container, not the group. Whether that is enough is worth asking before a group-shaped
   container is proposed to smddb.
3. **TMDb ids across kinds.** TMDb numbers movies and series separately, so `tmdb` `121` is a series
   and also a film. The ref's meaning follows from the container's type, `movie` or not, and from the
   container above an entry. The lookup route answers both, and the console tells them apart by type. A
   prefixed value would remove the ambiguity, but smddb's data already uses the bare number.
