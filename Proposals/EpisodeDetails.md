<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0019-episode-details

Modified: 2026-11-05

# An episode is a container of its own

This proposes that an episode be held as a container of type `episode`, as a film is held as a
`movie`: with its own document in the repository and its own sidecar in the library, in a folder of its
own beside its files. Its title, the date it was first broadcast, its cast, and who directed and wrote it
are the container's own fields. They are facts, read from Wikidata as
[0020-wikidata](Wikidata.md) has every fact read, and they go to smddb with the rest of the container.
Its outline is content, read from TMDb and attributed in its sidecar as a container's outline already
is, and it stays in the library. The walk offers each of these fields for the operator to take or leave,
a season's episodes at once or one at a time.

It revisits a non-goal of [0017-tmdb](Tmdb.md), *Titles and outlines for entries*, which stored TMDb's
episode titles nowhere, keeping to SmdKit's rule that an entry carries a title only when a provider has
none. The rule stands for entries. An episode is no longer one: the entries are what an episode
container plays, its feature and its extras. The walk it extends is [0018-tmdb-walk](TmdbWalk.md)'s.

## The problem

**A player has nothing to show on an episode's page.** An episode is an entry in its container's
sidecar carrying its references and no title. The silo serves it that way. A player that wants to say
what the episode is called, what happens in it, when it aired or who is in it has to ask a provider
itself, and every player has to do that separately.

**The silo never asks a provider.** [0017](Tmdb.md) settled that the console reaches the providers and
the silo does not. Whatever a player shows has to reach the library through the console.

**An entry is the wrong shape for an episode.** An episode's title, date and credits are facts about a
programme, which smddb should hold as it holds a film's. Put on its entry, they would make a season's
document a credits list with a sequence attached, rewritten by every edit of the season. And an episode
is more than its facts. It has versions, a broadcast cut and an updated-effects one. It has extras, a
commentary, a still. An entry has none of these except by borrowing its container's: today a version of
one episode is a sequence of the season's that refers to the rest, and an episode's extras hang off its
season's anchor. A film has all of them, because a film is a container.

## What this is

**An episode container.** A container of type `episode`, holding one sequence, `main`, of one leaf,
`feature`, of type `episode`, as a film's holds one of type `movie`. Its fields are a container's: its
title, its outline, its references (Wikidata's, and the IMDb, TMDb and TVDB ids Wikidata holds), and,
from SmdKit's change for this proposal, `premiered`, the date it was first broadcast, and `cast` and
`crew`:

```xml
<container type="episode" id="4f2a9c0e1b7d3a65">
  <title>Kassa</title>
  <premiered>2022-09-21</premiered>
  <outline>…</outline>
  <externalRef provider="wikidata" value="Q118877501"/>
  <externalRef provider="imdb" value="tt9419264"/>
  <cast>
    <participant name="Diego Luna" role="Cassian Andor">
      <externalRef provider="wikidata" value="…"/>
    </participant>
  </cast>
  <crew>
    <participant name="Toby Haynes" role="Director">
      <externalRef provider="wikidata" value="…"/>
    </participant>
  </crew>
  <sequence id="main">
    <item type="episode" id="feature"/>
  </sequence>
</container>
```

Its alternatives are its own: an updated-effects version is a second sequence in the episode's
container and an alternative naming it, not a sequence of the season's that refers to every other
episode. So are its features and its extras: a commentary over one episode is that episode's feature,
and a making-of about it is its extra.

**A participant is known by its references.** SmdKit's `Participant` gains `externalRefs`, wherever one
stands: in a container's cast or crew, or on a feature. A name is not an identity. Two people share one,
and one person is credited under several. With Wikidata's id on both sides, the director in an episode's
crew is the director on the serial's commentary, matched by reference rather than by spelling. The ids
for a person are read from Wikidata with the episode, in the same query.

**A season holds its episodes as children.** A season, or a serial, holds each episode as a child
container, in the order Wikidata gives, as a collection holds its films. In the library each episode is
a folder, `01 - Kassa/`, beside its siblings in the season's, holding `container.smd`, the episode's
presentations and its artwork. Nothing in the layout is new: 0016's folder order and 0012's artwork by
name apply as they do to every container, so an episode's still is its `thumb.jpg`.

**Facts go to smddb, content does not.** An episode's title, date, credits and references are facts,
read from Wikidata, which is CC0, or typed by the operator, and the episode's document goes to smddb as
any container's does. Its outline, read from TMDb, is attributed in its sidecar, with the date it was
read, and 0020's rule keeps it out of smddb. Its artwork never goes.

**Served as a container.** An episode is read as any container is, with its new fields. A season's read
answer lists its episodes as children, and each child's summary carries its `premiered` with its title,
so a player has a season's episode titles and dates in the read it already makes.

**Reviewed in its season's stop.** An episode is not a stop of the walk. A season is reviewed as a
season, and its episodes with it: at the season's stop, an *Episodes* group lists five fields, *Title*,
*Outline*, *Premiered*, *Cast* and *Directors and writers*, each saying how many of the season's
episodes it would change. Each field is ticked for every episode at once, and an episode opened in the
group shows its own five fields, each ticked or not. A field is offered where its provider has a value
and the episode's container lacks it or differs. As with the stop's other differences, nothing is ticked
to begin with at a held stop, and everything is ticked at a new one. A new episode is made with its
title whatever is ticked, since a container has to have one. Storing the walk edits each held episode
with a field ticked, after its season's edit, and makes each new one beneath its season. The outline is
put with its attribution and read date.

**Specials placed as containers.** 0017's and 0018's placements were written for entries. With episodes
as containers they become placements of containers: a special placed in a season's run is an episode
container among its siblings; a special that is a version of one episode is an alternative of that
episode's container; a special that is a new edition of a serial is a sequence of the serial's, of the
special's own container. A special that is an extra stays a leaf, since an extra is a file's worth.

## Principles

0017's, 0018's and 0020's principles stand. This proposal adds three.

1. **A programme is a container.** An episode, like a film, is a thing with a title, credits, versions
   and extras of its own. A leaf is what a container plays: its feature, a version, an extra.
2. **An episode's facts are the repository's.** They go to smddb as a film's do, from a CC0 source or
   the operator. Its content is attributed and stays in the library.
3. **Each field is the operator's to take.** A provider's cast list may be one the operator would rather
   not hold, and its crew runs to everyone who worked on the episode. The walk offers the fields
   separately, and the crew only as directing and writing.

## Vocabulary

- **Episode container** — a container of type `episode`, holding one leaf, its feature.
- **Premiered** — the date a container was first broadcast or released.
- **Credits** — a container's cast and crew, each a list of participants in the order credited.

## What this looks like to the operator

A season of *Andor* is drafted from Wikidata in a walk. Its stop shows twelve episodes as its children
and, under *Episodes*, the five fields, all ticked, since the season is new. The operator unticks *Cast*,
because Wikidata lists no one for these episodes, and confirms. The store lists the season, then its
twelve episodes, each made with its title, date, directors, writers and TMDb's outline. A player
browsing the season shows each episode's title and date, and an episode's page its outline, credited to
TMDb, and its credits.

A serial of *Doctor Who* holds its four parts as episode containers. The updated-effects version of the
first part is an alternative in that part's container, and the commentary over all four is the serial's
feature, mapped in each part's presentations.

## What this asks of an implementation

Each step is a pull request carrying its spec change. The silo's two are in `openspec/changes/`:
`episode-containers-2-served` and `episode-containers-3-walk`.

### 1. Premiered and credits, in SmdKit

`Container.premiered`, a `CalendarDate`; `Container.cast` and `Container.crew`; and
`Participant.externalRefs`, in the container file wherever a participant stands. A reader that predates
them ignores the elements, as it ignores anything it does not know, so the container format's version
does not change. SmdKit's container-model and container-file specs change in the same pull request. It
merges first, and the silo's `Package.resolved` moves to it.

Tests: an episode with a first date, a cast member with a character and a reference, and a director
reads back equal; a feature's participant reads back with its reference; a `premiered` that is not a
calendar date is refused.

### 2. Premiered and credits served

`premiered`, `cast` and `crew` on a container's read answers, and `premiered` on each child's summary;
a participant's `externalRefs` wherever one is served; and the validator's warning on a container whose
`premiered` falls in another year than its `year`.

Tests: an episode container's read answer carries its date and credits; a season's read answer lists
each episode's title and date; a feature's participant is served with its references; a film released
in one year and dated in another is warned on.

### 3. Episodes as containers in the walk

0020's Wikidata reading drafting each episode as an episode container beneath its season or serial, with
its facts, and its outline from TMDb. The *Episodes* group at every stop holding episode containers, its
fields ticked whole or an episode at a time, kept with the walk. The store's edits and creations. 0017's
and 0018's placements of specials, as containers. It follows 0020's Wikidata reading and its walk from
both providers.

Tests: a season drafted from Wikidata holds each episode as a container in Wikidata's order; a held
season's episodes offer each field their provider has and the episode lacks; ticking *Premiered* alone
edits each episode's date and nothing else; an episode's field unticked leaves it as the library holds
it; a new season's episodes are made with their fields and outline once it is; the crew offered holds
the episode's directors and screenwriters, each with their Wikidata id; a special placed as a version of
an episode is an alternative of the episode's container.

## What comes next

**Films' credits.** A film is a container already, so the same fields take its release date and credits
from Wikidata, and the walk's film stop offers them as a season's offers its episodes'.

**People across the library.** With references on every participant, the question
`StructuredContainers.md` put to the shared database, every commentary a director recorded, can be asked
of a library: the episodes and films a person is credited in, and the features they appear on.

**An episode's still.** As its `thumb`, put from TMDb's still with its attribution, as a container's
artwork is.

## Non-goals

- **An episode as a stop.** A season is reviewed as a season. Its episodes are reviewed in its stop.
- **Migrating episodes held as entries.** 0020 already removes and drafts again the one library drafted
  under 0017, so no episode entry is converted.
- **Every crew job.** Wikidata lists producers, composers and cinematographers too. Directing and
  writing are what a player shows.
- **Following a provider.** An episode's fields do not change when a provider's do. The next walk shows
  the difference, and 0020's read date has the outline read again before TMDb's terms say it is stale.

## Open questions

1. **Who is in an episode.** Wikidata lists an episode's cast less often than its title or date: none of
   *Andor*'s first season's episodes list theirs, where the series lists twenty-five. Offering the
   series' cast for each episode would fill the field with people who may not be in the episode.
   Proposed: the episode's own statements, with an empty field where there are none, and the gap filled
   at Wikidata.
2. **The size of smddb.** One document per episode makes a long series hundreds of documents. smddb's
   clone already lays each container out in a folder of its own, nested as the tree nests, so this is
   more files rather than a new shape. Whether a review in smddb can read a season's contribution as one
   change is worth trying.
3. **A TMDb id on a person.** TMDb numbers people apart from films and series. A `tmdb` reference on a
   participant is a person's, since nothing else is a participant, so it is read as one without a
   prefix, as 0017's third open question reads a film's and a series'.
