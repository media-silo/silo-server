<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0020-wikidata

Modified: 2026-11-05

# Facts from Wikidata, content from TMDb

This proposes that every fact the console takes from a provider come from Wikidata. A fact is a
container's title and year, the seasons, serials and episodes it holds and their order, an episode's
title and first air date, who directed, wrote and appeared in it, and the ids other providers know it
by. Wikidata's statements are CC0, so a fact taken from it needs no attribution, may be kept for as
long as the library likes, and may go to smddb. TMDb is still read, for what only it has: outlines and
artwork. That is content, someone's writing or someone's image. It is attributed, it stays in the
library, and it is read again before TMDb's terms say it has been kept too long. An attributed field goes
to smddb only when its provider's licence is CC0. Artwork never goes to smddb.

It revises [0017-tmdb](Tmdb.md), whose reading took facts and content alike from TMDb, and its walk in
[0018-tmdb-walk](TmdbWalk.md), which it keeps as it is but for where each difference is read from. It
revises the reading of [0019-episode-details](EpisodeDetails.md) in the same way: an episode's title,
air date, cast and crew come from Wikidata, and its outline from TMDb.

## The problem

**TMDb's facts are not ours to give.** 0017 drew its line between facts and work: facts taken plainly,
work attributed, and facts free to go to smddb. TMDb's API terms do not draw that line. They license
everything the API returns, facts included, as TMDB Content, "non-exclusive, non-transferable,
non-sublicensable" (§1.A), for non-commercial use. They forbid sublicensing it and making derivatives of
it (§1.C). A container whose seasons and titles were read from TMDb and then proposed to smddb, whose
data is meant to be CC0, sublicenses TMDb's content however the operator reshaped it. One household's
library is the personal use the terms allow. smddb gathering every household's TMDb-drafted structure
would be an index of TMDb's listings under another licence.

**TMDb's content cannot be kept for ever.** The terms forbid caching "any information obtained through
or from TMDB" for longer than six months (§1.C). An outline or a poster put in 0017's walk is kept
indefinitely. 0017's first open question saw this coming and left it open.

**Tracking where each fact came from is not workable.** One way out would be to record, for every fact,
the provider it was read from, and to keep TMDb's out of what goes to smddb. Every title, year, entry,
order and reference would carry a provenance, an edit would have to say what it does to each, and a
fact read from two providers that agree would have two. The attributions 0017 introduced are worth
their cost because they are few: an outline and a handful of artwork kinds per container. Facts are
most of a container.

## What this is

**Facts come from one source.** The console reads facts from Wikidata only. A fact in the library is
then either the operator's own, typed in or decided in a walk, or Wikidata's, which is CC0. Neither
needs to say which it is, because both may go to smddb. Nothing about a fact is tracked.

**Content comes attributed.** An outline read from TMDb is attributed to TMDb, as 0017 has it, and so is
each artwork kind. An attribution also records when it was read. The library's walk warns on an
attribution more than six months old, and the console's walk offers to read it again: the same outline
or image, read afresh, with a new date, or the field removed if TMDb no longer has it.

**What goes to smddb.** 0013's export takes the container's own fields from the sidecar as they stand,
and 0017 replaced an attributed outline with smddb's or none. That becomes a rule about providers: an
attributed field is exported only when its provider's content is CC0, and replaced with smddb's or none
otherwise. Wikidata's is. TMDb's is not. Artwork is never exported, attributed or not, as 0013 already
has it.

**A Wikidata client, in SiloAdminKit.** It searches Wikidata's items, and reads through Wikidata's
query service, by SPARQL, a film, a series with its seasons, a season with its serials and episodes in
order, a serial with its parts, and each item's statements: label, publication date, director,
screenwriter, cast member with the character played, and the external ids for IMDb, TMDb (series,
season, episode, film, collection and person) and TVDB. It needs no key. It sends a User-Agent naming
SiloAdmin and its repository, as Wikimedia's policy asks, and keeps to the query service's limits. It
asks for labels in the language SiloAdmin's settings name.

**Wikidata's reading of a container.** From a Wikidata item the console builds a container as 0017 does
from a TMDb record: the item's label as its title, its year from its publication date, its children in
Wikidata's order, and a reference for Wikidata and for each provider id the item holds. A season holds
its serials, where Wikidata models them, as child containers, each holding its parts as entries in the
order of their ordinals. A season Wikidata models as episodes holds them as entries. The TMDb ids
Wikidata holds are how the console finds the outline and artwork to offer from TMDb. A container Wikidata
does not hold has no reading, and is authored by hand, as before 0017. Where Wikidata is missing
something, the place to add it is Wikidata, and the console links to the item.

**The walk, read from both.** 0018's walk stays as it is. A stop's facts are compared with Wikidata's
reading: title and year, missing children, order, missing references and, from 0019, an episode's
title, air date, cast and crew. Its content is compared with TMDb's: outline and artwork, and an
episode's outline. A stop reads TMDb only for content, through the TMDb ids its container carries or
Wikidata holds. A walk with no TMDb token still reviews every fact.

**Specials where Wikidata files them.** Wikidata has no season 0. It files a special in the season it
aired in, as *The Christmas Invasion* is in *Doctor Who*'s second series, and a special no season holds
belongs to the series alone. The first is read as an entry of its season like any other. The second
joins 0017's pool, to be placed or declined as before. TMDb's season 0 is no longer read: what it lists
is TMDb's, facts included. An extra the library holds, a featurette or a trailer, is the operator's
own, as it always was in practice, since a library holds an extra because it is on a disc.

## Principles

0017's principles stand, except that facts are taken from Wikidata rather than TMDb. This proposal adds
three.

1. **One source for facts.** Facts come from a CC0 provider, so that nothing about them needs to be
   tracked. A fact a provider has under any other licence is not taken.
2. **Content is attributed and kept no longer than its terms allow.** An attribution says whose content
   it is and when it was read, and the library warns before it outlives the provider's terms.
3. **smddb takes only what is free to give.** The operator's own work and CC0 facts and content. Never
   artwork.

## Vocabulary

- **Fact** — a title, a year, a date, a credit, a structure and its order, a provider's id.
- **Content** — an outline or an image: someone's writing or someone's work, attributed.
- **CC0 provider** — a provider whose content is released into the public domain. Wikidata is one.

## What this looks like to the operator

The operator searches for *Andor* in SiloAdmin. The result is Wikidata's item, with its two seasons. The
draft is Wikidata's reading: the series, two seasons, twelve episodes in the first, each with its
Wikidata, IMDb and TMDb ids. The outline offered is TMDb's, credited to TMDb, read through the series'
TMDb id. Six months later, the library's walk warns that the series' outline is older than TMDb's
terms allow, and the next walk of the series offers it again.

A season of *Doctor Who*, walked, holds its six serials as Wikidata has them, each with its four or six
parts. Were one of them to have no part Wikidata knows of, the console would say so, linking to the
serial's item.

## What this asks of an implementation

Each step is a pull request carrying its spec change, in `openspec/changes/` and named after the step.

### 1. Attributions read on a date, in SmdKit

`Attribution` gains `read`, the date the content was read from its provider, written as an attribute of
`<attribution>` and required: an attribution without it is refused on reading, as one without a value
is. Nothing written under 0017 is kept, as *Non-goals* says, so no attribution of unknown age has to be
read. SmdKit's sidecar spec changes in the same pull request, and the details
file 0019 adds takes it with the rest.

### 2. Attributions' age in the silo

The attribution's `read` in an edit, a create, an artwork put and a details put; the walk's warning on
an attribution older than six months; and the export's rule, a field exported only
when its attribution's provider is CC0.

### 3. The Wikidata client and its reading

SiloAdminKit's Wikidata client, behind a protocol so that tests answer from recorded responses. The
reading of a film, a series, a season with its serials or episodes, and a serial with its parts. Search
from Wikidata. Drafts from Wikidata through 0013's create route, with TMDb's outline and artwork offered
through the TMDb ids Wikidata holds.

### 4. The walk from both

The walk's facts from Wikidata's reading and its content from TMDb's; specials Wikidata files nowhere
but the series in 0017's pool; TMDb's season 0 no longer read; a stale attribution offered for reading
again.

### 5. Episode details from Wikidata

0019's third step, *Details in the walk*, reads an episode's title, air date, cast and crew from the
Wikidata reading step 3 adds and its outline from TMDb, and follows step 4. It is that proposal's to
build, and is listed here only for the order.

## What comes next

**Contributing to Wikidata.** Where Wikidata is missing a season, an episode or a credit, the operator
adds it at Wikidata, and the next walk reads it. A console that drafts the statements for the operator
to submit would close the loop, and would be Wikidata's to accept or not.

**Other CC0 providers.** The rule is about licences, not about Wikidata. Another source whose facts are
CC0 could be read beside it.

## Non-goals

- **Tracking where a fact came from.** The rule is that facts come from one place, so that nothing
  needs to.
- **Facts from TMDb where Wikidata has none.** A gap in Wikidata is filled at Wikidata, or by the
  operator.
- **Migrating what 0017 drafted.** The one library drafted from TMDb under 0017 holds four series. They
  are removed and drafted again from Wikidata once this lands, so nothing marks, checks or converts
  facts taken from TMDb, and no attribution without a read date is kept.
- **Artwork in smddb.** Unchanged.

## Open questions

1. **How much Wikidata holds.** Five English-language series were tried while writing this. For four
   of them Wikidata held the seasons and 331 episodes, 326 of them with TMDb ids, and for the fifth,
   *Doctor Who*, its thirteenth season as serials with their parts. It holds an episode's cast less
   often: none of *Andor*'s first season's episodes list theirs, where the series lists twenty-five. A
   library of less prominent or non-English series will find more gaps.
2. **Two numberings in one season.** Wikidata numbers a *Doctor Who* season's serials and its episodes
   with the same ordinal, one to six and one to twenty-six, in the same season statement. The reading
   tells them apart by the item's type and by each part's *part of*. A series modelled some other way
   needs its own reading, and the walk should say when it meets one.
3. **Episode cast.** With cast taken from Wikidata, an episode's cast is what its item lists. For most
   episodes that is nothing. The series' cast, which Wikidata often lists with the characters, could be
   offered for each episode instead, as 0019 offered TMDb's regular cast.
