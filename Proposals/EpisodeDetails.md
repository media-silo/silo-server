<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0019-episode-details

Modified: 2026-11-05

# An episode's details, in an smd of its own

This proposes that a library keep, for each episode, the details a player shows on the episode's page:
its title, its outline, the date it first aired, its cast, and who directed and wrote it. They live in a
file of the episode's own, `{item}.smd`, beside the episode's presentations and named by the episode's
`<item>` in its container's sidecar, as a child container's sidecar is. The walk reads them as
[0020-wikidata](Wikidata.md) has every reading do: the title, date and credits are facts, read from
Wikidata, and the outline is content, read from TMDb and attributed to it. The walk offers each field
for the operator to take or leave. The file is a library fact through and through. The repository
document does not change, and nothing in the file is proposed to smddb.

It revisits a non-goal of [0017-tmdb](Tmdb.md), *Titles and outlines for entries*, which stored TMDb's
episode titles nowhere. That non-goal kept the repository to SmdKit's rule that an entry carries a title
only when no provider has one. The rule stands, because it is about the repository, where one source of
truth per fact is the point. What it left out is the library, which is where a household's player
looks, and which [0017](Tmdb.md) already lets keep a provider's attributed work beside the facts it
holds. The walk it extends is [0018-tmdb-walk](TmdbWalk.md)'s.

## The problem

**A player has nothing to show on an episode's page.** An episode is an entry in its container's
sidecar carrying its references and no title. The silo serves it that way. A player that wants to say
what the episode is called, what happens in it, when it aired or who is in it has to ask a provider
itself, with a key of its own, and every player has to do that separately. A player offline, or one
whose provider has never heard of the episode, shows a file name.

**The silo never asks a provider.** [0017](Tmdb.md) settled that the console reaches TMDb and the silo
does not, so a household's server holds no third party's credentials. Whatever a player shows has to
reach the library through the console, as an outline and artwork already do.

**The season's sidecar is the wrong place.** A season's sidecar is read on every walk of the library
and rewritten by every edit of the season. A season of twenty episodes, each with a cast of thirty,
would make it a credits list with a container attached. The details are also the episode's, not the
season's. An episode filed as an extra of a serial, or moved to a companion series, should take its
details with it, and an edit of the season's title should not touch them.

## What this is

**An item's details file.** A leaf entry, an episode or any other item that holds nothing, may have a
file of its own beside its presentations, named `{item}.smd` after the same `{item}` its presentations'
files begin with, or `extras/{item}.smd` for an extra. Its root names the container and the item, so a
file moved or copied to the wrong place says so:

```xml
<details container="4f2a9c0e1b7d3a65" item="one-the-first-episode">
  <title>One: The First Episode</title>
  <outline>…</outline>
  <aired>2022-09-21</aired>
  <cast>
    <participant name="Diego Luna" role="Cassian Andor">
      <externalRef provider="wikidata" value="…"/>
      <externalRef provider="tmdb" value="8688"/>
    </participant>
    …
  </cast>
  <crew>
    <participant name="Toby Haynes" role="Director">
      <externalRef provider="wikidata" value="…"/>
    </participant>
    …
  </crew>
  <attribution subject="outline" provider="tmdb" value="3504536" read="2026-11-05"/>
</details>
```

Each element is optional, and one the operator did not take is not written. `<participant name role>`
is the element a `<feature>` already uses, with the same convention: the role is what the person is to
the programme, a character for the cast and a job for the crew, as an NFO's `<actor>` has it. The
`<attribution>` is the sidecar's, with the date its content was read as 0020 adds it, and only the
outline is attributed.

**A participant is known by its references.** SmdKit's `Participant` gains `externalRefs`, written as
`<externalRef>` children of `<participant>` wherever one stands: in an item's details, and on a
container's `<feature>` in the repository document. A name is not an identity. Two people share one,
and one person is credited under several. With a provider's id on both sides, the director in an
episode's details is the director on the serial's commentary, and the interviewee on an extra is the
actor in the episode it is about, matched by reference rather than by spelling. `StructuredContainers.md`
left people's provider ids to the shared database. A reference on the participant is where that
database would hold them, so a feature proposed to smddb carries its participants' ids with it.

**Named from the sidecar.** The episode's `<item>` in its container's sidecar names the file in an
`smd` attribute, as a child container's `<item type="container">` names the child's sidecar. Every file
the library writes is named at the level it belongs to, as `StructuredContainers.md`'s fourth principle
asks, so the walk finds a details file by following its item. A details file no item names is a warning,
as a sidecar nothing references is. The `smd` attribute is a library fact like a presentation's
`file`. The container read from a sidecar with it is the container read from one without, and the
repository document never carries it.

**Kept by everything that keeps library facts.** A placement keeps an item's details, as it keeps its
other presentations. An edit of the container keeps them, and an edit that no longer declares an item
whose details the library holds is refused, as one that drops an item with presentations is. A details
file is named the way the layout names it. One that is not is a warning, as a presentation's file is.

**Served with the item.** The silo serves each item's details on the item in a container's read
answers, beside its presentations, so a player has a season's episode titles and dates in the one read
it already makes. The outline's attribution is served with it, so a player can credit it.

**Put by the console.** A route puts an item's details as a whole, writing the file and naming it in the
container's sidecar, and another removes them. The silo checks their shape and nothing about where they
came from, as with an attribution.

**Read from Wikidata and TMDb, a field at a time.** The walk reads each episode's facts with its season
from Wikidata's reading: the episode's label as its title, its publication date as the date it first
aired, its cast members with the characters they play, and its directors and screenwriters. Each person
is a Wikidata item, so each participant carries a `wikidata` reference, and the TMDb and IMDb person
ids Wikidata holds for them, in the same query. The outline is TMDb's overview of the episode, read
through the TMDb episode id Wikidata holds, and attributed to it with the date it was read. At each
stop, an *Episodes* group lists five fields: *Title*, *Outline*, *Aired*, *Cast* and *Directors and
writers*. Each field is ticked for every episode of the stop at once, and an episode opened in the group
shows its own five fields, each ticked or not. A field is offered where its provider has a value and the
library's details lack it or differ. As with the stop's other differences, nothing is ticked to begin
with at a held stop, and everything is ticked at a new one. Storing the walk puts each episode's details
after the edit or creation of its container. The details put are the library's, with the ticked fields
replaced.

## Principles

0017's and 0018's principles stand. This proposal adds three.

1. **The repository stays as 0017 left it.** An entry still carries a title only when no provider has
   one. The details are the library's copy of what the providers say, kept for the household's
   players, and the repository has no place for them.
2. **The details are the episode's.** They live in a file of the episode's own, go where the episode
   goes, and are changed by nothing but a put of them.
3. **Each field is the operator's to take.** A provider's cast list may be one the operator would rather
   not hold, and its crew runs to everyone who worked on the episode. The walk offers the fields
   separately, and the crew only as directing and writing.

## Vocabulary

- **Details** — what a library keeps about one item beyond its references and its files: title,
  outline, first air date, cast and crew.
- **Details file** — the `.smd` holding one item's details, beside its presentations.

## What this looks like to the operator

A held season of *Andor* is open in a walk. Under *Episodes* the five fields are listed, each unticked,
and each saying how many of the season's twelve episodes it would change. The operator ticks *Title*,
*Aired* and *Directors and writers*, opens the fourth episode and unticks its *Directors and writers*,
because the library already credits that episode as the operator wants it, and confirms the stop. The
store lists twelve puts of details after the season's edit. Once it runs, a player browsing the season
shows each episode's title, date and credits, and the fourth episode keeps the credits it had.

## What this asks of an implementation

Each step is a pull request carrying its spec change. The silo's two are in `openspec/changes/`:
`episode-details-2-library` and `episode-details-3-walk`.

### 1. Item details, in SmdKit

`ItemDetails` — `container`, `item`, `title`, `outline`, `aired`, `cast`, `crew` and `attributions` —
with its file's reading and writing. `Participant.externalRefs`, in the container file as in the details
file. A reader that predates it ignores the element, as it ignores anything it does not know, so the
container format's version does not change. `Sidecar.details`, each item's details file by the item's id,
read from and written to the `smd` attribute of a leaf `<item>`. An update and setting the container's
own fields leave it as it stands, as they leave the rules. SmdKit's sidecar spec changes in the same pull
request. It merges first, and the silo's `Package.resolved` moves to it.

Tests: details with every field, a participant with a reference among them, read back as written; a
feature's participant with a reference reads back with it; details with none write the bare root; an
`aired` that is not a date is refused on reading; a sidecar naming an item's details reads back with
them; the container read from it is the container read from one without.

### 2. Item details in the silo

The layout's name for a details file; the walk following an item's `smd`; the findings for a details
file that does not exist, names another item, is named as the layout would not name it, or is named by
nothing; a placement and an edit keeping them; an edit dropping an item with details refused; the
details served on the item; and the put and remove routes.

Tests: a put writes the file and names it in the sidecar, and the container's read serves them; a put
of details naming another item is 400; a removal deletes the file and the name; a placement into the
container keeps them; an edit dropping the item is 422; a details file nothing names is a warning; a
feature's participant is served with its references.

### 3. Details in the walk

Each episode's statements in 0020's Wikidata reading of a season: label, publication date, cast with
characters, directors and screenwriters, and the people's ids; and each episode's overview from TMDb.
The *Episodes* group at every stop whose container holds an entry carrying the Wikidata id of an
episode the reading has, its fields ticked whole or an episode at a time, kept with the walk. The
store's puts. It follows 0020's Wikidata reading and its walk from both providers, and replaces the
episode details step 0020 lists.

Tests: a held season's episodes offer each field its provider has and the library lacks; ticking
*Aired* alone puts details holding the date and the library's other fields as they stood; an
episode's field unticked leaves that field as the library holds it; a new season's details are
ticked and put once it is made;
the crew offered holds the episode's directors and screenwriters, each participant with its Wikidata id
and the TMDb person id Wikidata holds; the outline is put with its attribution and the date it was read.

## What comes next

**Details for films and extras.** A film held as an entry of a collection, or an extra Wikidata holds
as a film, has statements of the same shape. The file takes any leaf, so this is a reading, not a
format change.

**An episode's still.** TMDb holds a still for most episodes. As artwork it would be `{item}-thumb.jpg`
beside the episode's files, found by name as a container's artwork is, and attributed in its details.

**People across the library.** With references on every participant, the question
`StructuredContainers.md` put to the shared database, every commentary a director recorded, can be asked
of a library: the episodes a person is credited in, and the features and extras they appear on. A
console offering a feature's participants from Wikidata's people, with their ids, is the other half.

**Titles in file names.** A presentation's file is named for the item's title, or its id when it has
none, and an episode drafted from a provider has none. The details' title could name its files
instead, at the cost of a move each time the title is taken.

## Non-goals

- **Details in smddb.** The repository document has no place for an entry's details, and SmdKit's rule
  that an entry carries a title only when no provider has one stays. The facts in a details file are
  Wikidata's, and CC0, so a repository that one day carries them could take them; the outline would go
  only as 0020's rule for attributed fields has it, which for TMDb's is never. A feature's
  participants, with their references, are the repository's already, and go to smddb as they always
  have, a reference naming a person rather than copying a provider's record of them.
- **Following a provider.** Details stored do not change when a provider's do. The next walk shows the
  difference, and 0020's read date has the outline read again before TMDb's terms say it is stale.
- **Every crew job.** Wikidata lists producers, composers and cinematographers too. Directing and
  writing are what a player shows.
- **The silo reaching TMDb.** Unchanged from 0017.

## Open questions

1. **Who is in an episode.** Wikidata lists an episode's cast less often than its title or date: none of
   *Andor*'s first season's episodes list theirs, where the series lists twenty-five. Taken from the
   episode alone, most episodes' cast field would be empty. Offering the series' cast for each episode,
   as 0020's third open question raises, would fill it with people who may not be in the episode.
   Proposed: the episode's own statements, with an empty field where there are none, and the gap filled
   at Wikidata.
2. **A TMDb id on a person.** TMDb numbers people apart from films and series, as it numbers those
   apart from each other. A `tmdb` reference on a participant is a person's, since nothing else is a
   participant, so it is read as one without a prefix, as 0017's third open question reads a film's
   and a series'.
3. **An item named `container`.** An item whose `{item}` is `container` would have a details file named
   as its container's sidecar. Proposed: the layout names that one `container - details.smd`. Item ids
   are slugs of titles, so it takes an episode titled *Container* to reach it.
