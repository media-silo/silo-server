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

**A provider's season 0 is not a season.** TMDb, like TVDB, files a series' specials as season 0. It is
a mixture: specials that aired between episodes, featurettes, trailers, a feature-length special TMDb
also holds as a movie, and runs of a companion programme TMDb has no series for. Read as a season, it
would put a making-of beside a Christmas special and call them a season of the show.

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

**Specials, unassigned until the operator places them.** Season 0 is read as a pool of unassigned
specials, not as a season. Each special is placed by the operator, with a suggestion and its reason
pre-filled. It can become an entry in a sequence, an extra, a child container, the same thing as
another TMDb record, a special in a series of the operator's own, or declined. A special left
unassigned holds nothing up: the tree is created without it, and it waits in the pool.
[Specials](#specials) has the whole of it.

**Differences from TMDb.** For a container the library holds with a TMDb ref, the browser shows TMDb's
reading beside the library's sidecar as a list of differences. These are a field that differs, a ref
TMDb knows and the sidecar lacks, a child TMDb has whose ref nothing the container holds or refers to
carries, an order that differs, artwork TMDb has for a kind the container lacks, and the specials still
unassigned. Each has a tick. The operator ticks the ones to
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
whose writing a field holds. This proposal adds five.

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
5. **One thing is one entry, however many times a provider lists it.** A special TMDb also holds as a
   movie, or as an episode of another series, has one home in the library. That entry carries every
   TMDb id it is known by, and everywhere else refers to it. A ref is how a second place shows a thing,
   as smddb's structured containers already have it, and never a copy.

## Vocabulary

- **TMDb's reading** — the container the console builds from a TMDb record, with its children.
- **Draft from TMDb** — a tree of new-container drafts made from TMDb's reading, shaped before it is
  created.
- **Difference** — one way a held container's sidecar differs from TMDb's reading, which the operator
  may take or leave.
- **Fact** — what a draft takes from TMDb plainly: title, year, type, structure, order and provider ids.
- **Attribution** — a library fact naming the provider and ref a field or an artwork kind came from.
- **Unassigned** — a special from a provider's season 0 that the operator has neither placed nor
  declined.
- **Duplicate** — a special that is also another TMDb record: a movie, or an episode of another series.
- **Breakout** — a series of the operator's own, holding specials TMDb files in season 0 and has no
  series for.
- **Declined** — a library fact naming a provider's ref the operator chose not to hold.

## Specials

**The pool.** A series' season 0 is read as its specials, unassigned, each with its TMDb episode id,
air date, runtime, title and the provider ids TMDb holds for it. The pool belongs to the series it was
read from. In a draft it sits beside the tree, and for a held series it is a group in its differences.
Nothing in the pool reaches the library until the operator places it, and an unassigned special does
not stop the rest of the tree from being created.

**Where a special can go.** The smd model has six answers, and the operator picks one per special:

- **An entry in a sequence.** A special that aired in the run, such as a Christmas episode between two
  others, becomes an entry at that position, carrying its refs.
- **An extra.** A featurette becomes an extra of the series, a season or a serial, typed with one of
  the extra types 0011 names.
- **A child container.** A special that is a story in its own right becomes a container beneath the
  series, drafted as a child.
- **The same as another TMDb record, a duplicate.** The special's home is the entry or container that
  record reads as: in this library, in another, or drafted or imported now, smddb first. The home's
  entry carries both TMDb ids, its own and the special's, and the series refers to it as
  `container#item`, from its extras or its sequence.
- **Into a breakout.** The operator makes a series of their own for specials that read as a programme
  TMDb does not model, as *Behind the Sofa* is in smddb's structured containers, usually with
  `listed="false"`. Each special becomes an entry in it carrying its TMDb id, and the series refers to
  it, normally from each story's extras. Later specials can join a breakout made before.
- **Declined.** A trailer, a promotional clip, anything the library will not hold. The series' sidecar
  records the ref as declined, so the differences stop offering it.

**Suggestions, never applied.** For each special the console pre-fills the placement it thinks most
likely, and says why. It is the operator's to take, change or ignore.

- smddb's record, when the clone holds the series: where it filed a special with that ref.
- The operator's own earlier choices: a special whose siblings went into a breakout is suggested for
  that breakout.
- A matching provider id: when the special's IMDb or TVDB id is another TMDb record's, found through
  TMDb's lookup by external id, it is suggested as that record's duplicate.
- An episode group that places the special in an order: that position.
- Its air date: between two of the series' episodes, an entry at that position.
- Its runtime and title: short, with words such as "Behind the Scenes", "Making of" or "Trailer", an
  extra of the type the words suggest, or declined for a trailer.

**A special is covered once something carries its ref.** An entry the series holds, an extra, a child,
the home of a duplicate, or an entry in a breakout all carry the special's TMDb id. So does a declined
ref in the series' sidecar. The differences look for the ref in what the series holds and in what it
refers to, so a special placed anywhere stops being listed, and a declined one is listed only in a
collapsed group, where it can be reconsidered.

**A container read through what refers to it.** A breakout has no TMDb record, and a TMDb episode
cannot be fetched by its id alone: it is reached through its series. A container with no TMDb ref of its
own is therefore read through the nearest container above it that has one, or, when nothing above it
does, through a container in the library that refers to its items. Its differences are about its
entries' refs.

**A TMDb id read in context.** An entry carrying two TMDb ids, its own and a special's, holds numbers
from two of TMDb's ranges, which the bare value cannot tell apart. The console never reads an entry's
`tmdb` ref on its own. It compares the values in a reading with the values the library carries, so the
reading says what each number is.

## What SmdKit adds

`Sidecar` gains `attributions: [Attribution]`. An `Attribution` names a `subject`, either a field of
the container's own (`outline`, or an alternative's outline as `alternative/<id>/outline`) or an artwork
kind (`artwork/<kind>`), together with a `provider` and the `value` of the ref the subject came from. The
sidecar writes each as `<attribution subject="outline" provider="tmdb" value="121"/>` beside its other
library facts, and the reader reads them back. `SidecarFile.sidecar(from:).container` is unchanged,
since an attribution is not part of the container.

`Sidecar` also gains `declined: [ExternalRef]`, written as `<declined provider="tmdb" value="…"/>`.
It is a library fact too: the operator's choice not to hold something a provider lists, which another
library holding the same container may make differently.

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

**Declined refs.** `ContainerEdit` gains `declined`, which stands when absent and replaces when present,
as `attributions` does. `LibraryContainer` carries the sidecar's `declined`. The global container read
does not, since a player has no use for what a library chose not to hold. A placement keeps them.

**Refs across libraries.** The silo serves an entry's `ref` as it is written, and a client resolves it
through `GET /v1/containers/{id}`, which answers from whichever library holds the container. A series
in `tv` referring to a duplicate's home in `films` therefore resolves today, and nothing about it
changes here.

The silo never calls TMDb. It records an attribution or a declined ref as it was given, and checks
nothing about either beyond its shape and, for an attribution, its subject's presence.

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
child `season` container for each of TMDb's seasons except season 0, and each season holds its episodes
as entries. Season 0 is the series' pool of unassigned specials, shown beside the tree with each
special's suggestion. A collection is read as a `collection` with each movie as a child. Before the draft opens, the operator
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
- *Children*: each of TMDb's episodes or seasons whose ref nothing the container holds, beneath it or
  through a ref, carries, with where TMDb puts it. A child container is offered as a draft from TMDb
  beneath this one. An episode the operator filed in a serial of their own is beneath the season, and
  so is not missing.
- *Order*: when the items both have, at the same level, are in a different order. Episodes regrouped
  into serials are not an order difference.
- *Artwork*: each kind the container has no file for and TMDb has an image for, with the image.
- *Unassigned specials*: for a series, each season 0 special nothing covers, with its suggestion, to
  be placed as a draft is. Specials TMDb has gained since the series was made arrive here, and not
  under Children.
- *Declined*: collapsed, the specials the series' sidecar declines, each of which can be placed after
  all, which removes its decline.

A container with no TMDb ref of its own, such as a serial the operator grouped or a breakout, is read
through the nearest container above it that has one, or through a container in the library that refers
to its items, as [Specials](#specials) says. Its differences are about the entries it holds: their refs,
and their order among themselves.

Items and children the library holds that TMDb does not are shown, and never offered for removal.
TMDb models no cuts, features or extras, so its silence about one says nothing. Taking the ticked field,
reference, child-entry and order differences, and the specials placed in the container or declined,
makes one edit draft of the container, stored as 0012 stores one. A special placed elsewhere, in a
duplicate's home or a breakout, is an edit of that container too, and the console lists each edit it
will store before storing any. Taking a child container makes its draft from TMDb. Taking artwork puts
the image with its attribution.

**Artwork from TMDb.** Beside each kind the container lacks, and from the differences, the operator can
browse TMDb's images for the record and put one. The console fetches the image and puts it with
`provider=tmdb` and the record's ref. TMDb's poster is offered for `poster`, its backdrops for `fanart`
and its logos for `logo`. An image the operator drops in themselves is theirs, and clears the
attribution, as 0012's artwork always was.

**Export.** 0013's export plan gains the attributed fields it left out. For each one it shows the
subject, the provider, and the value it takes instead from smddb's record. Its difference from smddb's
record is read against the document with those fields taken from smddb, so an attributed outline shows
as no difference rather than as one that cannot be proposed. A declined ref is a library fact and goes
nowhere.

A series whose special's home is in another library refers to a container 0013's export looks for only
in the series' own library. When smddb lacks the home, the export lists it as the reason it would be
refused, as 0013 lists any container neither smddb nor the library holds. The operator proposes the
home from its own library first.

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

The series' unassigned specials list over a hundred. The operator works through a few of them.

- A feature-length special's IMDb id is a TMDb movie's, so the console suggests it as that movie's
  duplicate. The `films` library holds the film, and the operator takes the suggestion. The film's
  entry gains the special's TMDb episode id, and *Doctor Who*'s sequence refers to it at the place it
  aired.
- A run of short behind-the-scenes pieces, one per story, reads as a programme. The operator makes a
  breakout, *Behind the Sofa*, unlisted, and files the Season 13 pieces in it. Each serial's extras
  refer to its piece. The next piece they open is suggested for *Behind the Sofa*, beside its
  siblings.
- A trailer is declined.

The rest stay unassigned, and nothing waits on them. The next time the operator opens *Doctor Who*'s
differences, the placed ones and the trailer are not listed as missing, and the trailer sits in the
collapsed declined group.

A week later TMDb has gained an IMDb id for the first part of *Pyramids of Mars*. The serial has no TMDb
ref of its own, so its TMDb section reads Season 13's record. It lists the new id under References
against that entry, and taking it is a one-line edit.

## What this asks of an implementation

Four steps, one pull request each, each carrying its spec change. The silo's three are in
[`openspec/changes/`](../openspec/changes/): `tmdb-2-attribution`, `tmdb-3-drafts` and
`tmdb-4-differences`.

### 1. Attributions, in SmdKit

`Attribution`, `Sidecar.attributions`, `Sidecar.declined`, and their reading and writing. SmdKit's
sidecar spec changes in the same pull request. It merges first, and the silo's `Package.resolved` moves
to it.

Tests: a sidecar with an outline's and a poster's attribution and a declined ref reads back as written;
a sidecar with neither writes no element; the container read from a sidecar with them is the container
read from one without.

### 2. Attributions and declined refs in the silo

`ContainerEdit.attributions` and `ContainerEdit.declined`, `ContainerCreate.attributions`, the artwork
put's `provider` and `value`, `attributions` in the read answers and `declined` in the library's, a
placement keeping both, and the validator's and walk's findings.

Tests: an edit carrying an outline's attribution records it, and a later edit without `attributions`
keeps it; an edit removing the outline while its attribution stands is 422; a create carrying an
attribution writes it into the new sidecar; an artwork put with a
provider records the kind's attribution, and one without removes it; an edit carrying `declined` records
it, and the library's container reads it; a placement into a container with attributions and declined
refs keeps them.

### 3. Drafts from TMDb

SiloAdminKit's TMDb client, behind a protocol so tests answer from recorded responses. TMDb's reading of
a movie, a series, a season, a collection and an episode group. The smddb-first check. Season 0 as the
pool, the six placements and their suggestions. Drafts from TMDb made through 0013's create route. Export leaving the attributed out. SiloAdmin's token and language
settings, the credit, search, and the draft. Shell-level behaviour stays `Pinned by: nothing yet.`

Tests: a series' reading has a season per TMDb season but season 0 and an untitled entry per episode
carrying its ref, and its specials unassigned; a special whose IMDb id is a TMDb movie's is suggested as
that movie's duplicate, and taking it adds the special's id to the home's entry and a ref from the
series; specials filed in a breakout are its entries, referred to from the series; a series created with
specials unassigned holds none of them; a record whose TMDb ref the clone holds is offered as smddb's
import; a draft from TMDb beneath a
held series names it in the parent and makes the tree; an export of a container with an attributed
outline writes smddb's outline, or none.

### 4. Differences and artwork from TMDb

The differences between a sidecar and TMDb's reading, the edit draft made from the ticked ones, children
as drafts from TMDb, and artwork put with its attribution.

Tests: a season TMDb has gained an episode for lists one child difference, and taking it adds one entry
in TMDb's position; an extra the library holds and TMDb lacks is listed and offered for nothing; taking
a missing ref makes an edit that adds only that ref; a special placed as a duplicate or in a breakout,
or declined, is not listed as missing, and a declined one is listed as declined; a breakout's entries
are read through the series that refers to them; artwork taken from TMDb is put with its attribution.

## What comes next

**Other providers, behind the same reading.** TVDB's season orderings (aired, DVD, absolute) and
Wikidata's serials and their parts are readings of the same kind. Wikidata is CC0, so what it holds may
go to smddb unattributed. The reading and the differences are written against a provider's reading, not
TMDb's, so that a second provider is a second client. TVDB records where a special airs, before or
after which season and episode. That is exactly the placement question, and it would be the strongest
suggestion the pool has.

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
   duplicate's home makes it sharper: one entry carries numbers from two of TMDb's ranges, and only a
   reading tells which is which, as [Specials](#specials) has the console do. A value that coincides
   with an episode id of the series being read would be taken for it. A prefixed value would remove the
   ambiguity, but smddb's data already uses the bare number.
4. **Whether a ref across libraries should be checked.** The silo validates no `container#item` ref
   today, within a library or across them. A duplicate's home in another library makes a ref that can
   break silently when the home is removed. A walk that reports a ref nothing resolves would catch it,
   and belongs with the silo's other checks rather than with this proposal.
