<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0018-tmdb-walk

Modified: 2026-10-24

# A held tree reviewed against TMDb

This proposes that a held container's differences from TMDb be reviewed as a walk through its tree,
not one container at a time. Opening a container's differences starts a walk rooted at it. The
operator works through a queue of the containers beneath it, each read against TMDb as it comes up. A
sidebar shows the tree as the walk finds it, what each container's state is, and lets the operator go
back to any of them. A series' unassigned specials stay beside the walk from the first container to
the last, so each can be placed in the container it belongs to when that container is open. Nothing
reaches the silo until the operator stores the walk, and the store lists everything it will do first.

It revises the *Differences* of [0017-tmdb](Tmdb.md), whose reading and differences it keeps as they
are. What changes is how the operator moves between containers, where the specials are placed from,
and when what they took is stored. It also widens 0017's *Where a special can go*: a special can be an
alternative of the container it belongs to, as an omnibus edition or a version of one episode is, and
a companion series it goes into can be one the library already holds, listed or not.

## The problem

**A series is reviewed a container at a time.** 0017's differences belong to the container they were
opened on. A held *Doctor Who* lists its own fields, its missing seasons and its artwork. Each season's
differences, an IMDb id TMDb gained for an episode or a poster the season lacks, are found only by
going back to the browser and opening that season, and then each serial beneath it. Nothing records
which have been looked at. A series with twenty-six seasons and a hundred and fifty serials is two
hundred sheets opened one after another from the browser, with the operator keeping the list.

**A special is placed from the wrong place.** Most of a series' specials belong beneath one of its
seasons: a Christmas special between two of that season's episodes, a making-of as an extra of the
story it was made for. 0017 shows the pool only on the series. The operator places a special in
*Season 14* from the series' sheet without seeing *Season 14*, and when they open *Season 14* later,
the pool is not there to place the next one.

**Some specials are another cut of what the library holds.** TMDb files an omnibus edition of a serial,
or its first episode with new effects, as a special. Neither is an entry beside the others or an extra.
Each is another way to play the container: the omnibus in place of the parts, the new version of
episode 1 in place of the old, with the other parts as they were. SmdKit's model has this already, as
an alternative naming the sequence it plays, but 0017 gives a special no way to become one.

**A companion series is only ever new and unlisted.** 0017's breakout is a series of the operator's
own for specials that read as a programme of their own. As built, the console offers only a breakout
made in the same draft, and makes every one unlisted. A companion the library already holds, such as
a series of concert specials the operator made last year, cannot be chosen, and one the household
browses to directly cannot be made.

**Taking breaks the flow.** Taking a container's differences opens its edit draft in the editor, and
taking a missing child opens a draft from TMDb in a sheet of its own. Each is a separate place to
finish and store. A special cannot be placed in a season the library does not hold yet, because that
season exists only once its draft is created, in another sheet.

## What this is

**A walk.** Opening a held container's differences starts a walk rooted at it. The walk's first stop is
the container itself, read against TMDb and listed as 0017 lists it. Each group of differences can be
ticked whole, ticked in part, or left.

**Confirming a stop.** When the operator confirms a stop, its ticked differences become the container's
pending change, and its children join the walk as pending stops. Every container the library holds
beneath it joins. A missing child joins only if the operator ticked it under *Children*, as a new stop,
a draft from TMDb. A missing child left unticked is not walked. Confirming a season queues its serials
in the same way, so the walk goes down the whole tree. Confirming a stop with nothing ticked records
that the operator looked and took nothing.

**The queue.** The pending stops are visited in the tree's order: depth first, each container's
children in the order its sequence holds them, and a new child where TMDb puts it. *Next* opens the
first pending stop. A stop is read against TMDb when it is opened, with the progress 0017's reading
shows. While the operator works on one stop, the console may read the next. A stop the operator never
reaches changes nothing.

**The sidebar.** Beside the open stop, the sidebar shows the walk's tree as far as it has found it.
Each stop shows its title, its type and its state:

- *pending*, queued and not yet opened;
- *open*, the stop being shown;
- *changed*, confirmed with a pending change;
- *looked at*, confirmed with nothing taken;
- *new*, a draft from TMDb to be created, with its state as a stop beside it.

Selecting any stop opens it. A confirmed stop opens with its ticks and placements as the operator left
them, and confirming it again replaces its pending change. Unticking a child the operator ticked
before removes that new stop and everything beneath it from the walk, and the console says what will go
first.

**The pool beside every stop.** When the walk's root is a series, or is beneath one, the series'
unassigned specials sit in a panel beside every stop, with their suggestions, as 0017's pool has them.
Placing a special from the panel offers the open stop first: an entry in its sequence at a position, or
one of its extras. The other placements stay available anywhere: a duplicate's home, a companion
series, a child container, or declined. A special whose suggestion names the open stop is marked as
suggested here only when something ties it there: its title names the stop, one of its entries, the
story TMDb titles an entry a part of, or a container beneath it, or smddb files it there. An air date
alone marks nothing, since too many specials air near a season they have nothing to do with, and a
series' own title, which most of its specials carry, ties nothing either. A placed special leaves the panel and becomes part of the pending change of the
container it was placed in, which then shows as *changed*. Removing it from that change returns it to
the panel. The panel counts how many are still unassigned, and a special left there holds nothing up,
as in 0017.

**A special as an alternative.** A special can also be placed as an alternative of the open stop, a cut
of the container naming the sequence it plays, as SmdKit's model has it:

- **In an alternate sequence the container has**, at a position, as any entry is placed.
- **As a new edition**, an omnibus: a new sequence holding the special as its only entry, named by a
  new alternative with the title the operator gives it, such as *Omnibus*.
- **As a version of one item**, an episode with new effects: a new sequence holding the special where
  that item was and referring to each of the sequence's other items, named by a new alternative, such
  as *Special edition*. The other items are referred to, not copied, so each stays one entry.

The special's entry carries its refs wherever it is placed, so it counts as covered as any placed
special does. 0017's suggestions gain two, ahead of the air date: a special whose title names the open
container, with a word such as "Omnibus" or "Compilation" or with a runtime within a tenth of one of
its sequences together, is suggested as a new edition of it; a special whose title names one of its
items with words such as "Special Edition", "Enhanced" or "New Effects" is suggested as a version of
that item. A runtime alone is not enough: a Christmas special can run as long as a two-part serial
does. In a walk these are read from each stop as it is read, since the series' reading has none of the
serials' episodes to compare with.

**A special in a companion series.** A companion series is what 0017 calls a breakout: a series beside
this one, holding specials that read as a programme TMDb has no series for, which the open stop refers
to from its extras or a sequence. Placing a special in one offers every series the library holds that
is not this walk's, listed or unlisted, as well as a new one. A new companion takes the title the
operator gives it and is unlisted to begin with, as most companions are, and the operator can list it
for one the household browses to directly. It is created at the top of the library, first among the
store's creations, so the references to it resolve. A companion TMDb does know, whose episodes the
specials are, is not a companion series but a duplicate's home, as in 0017, drafted from TMDb first
when no library holds it.

**A new stop.** A missing child the operator ticked is a draft from TMDb beneath its parent, made as
0017's draft makes one, with ids from smddb's client. Its stop shows what it will be created with: the
fields and references TMDb has for it, and any artwork TMDb offers, all ticked to begin with, since the
library holds nothing to keep. TMDb is not yet asked for a season's own images, so a new season offers
none, and its poster is put once it is held, as any container's is. The operator unticks what they do
not want and shapes it as 0017's form shapes a draft: re-typing it, or grouping its episodes into
containers of the kind they choose, such as serials. Each group the shaping makes is a new stop beneath it.
The episodes a held container lacks are grouped the same way at its own stop, and each group chosen
is made beneath it when the walk is stored, where its first episode would have gone. Specials can be placed in a new stop
as in a held one. A new stop is made only once it is confirmed, with everything beneath it in one
creation, right after the edit of its parent that names it; one ticked and never reached makes nothing.

**One store, at the end.** Nothing reaches the silo until the operator stores the walk. Before it is
stored, the console lists everything it will do, in the order it will do it:

1. any companion series made for specials, at the top of the library, through 0013's create route;
2. the edits of other containers that specials placed elsewhere make, a duplicate's home or a
   companion series the library holds, so that what the walk's own edits refer to is there;
3. the edit of each changed container, in the tree's order, based on the sidecar its stop read,
   including the specials placed in it and the declined refs, each followed by the creation of the new
   containers it names beneath it, through 0013's create route;
4. the artwork put, each with its attribution.

A new container beneath a held one is created after its parent's edit, not before: the create route
refuses a container whose parent does not yet name it, so the parent's edit, which names it, has to
land first. A special placed in a new season is stored with that season. An edit a placement makes of a
container that is itself a confirmed stop is part of that stop's edit, so the stop's edit is not
refused for a sidecar the store changed a step earlier. The store runs in that order, and the first
refusal stops it. The console says what was stored and what was not, and the walk keeps what was not,
to be stored again once the operator has dealt with the refusal. An edit based on a sidecar that has
changed since its stop read it is refused as 0012 refuses a stale edit, and that stop is read again,
pending with its ticks kept until the operator confirms it again.

**A walk is kept on this Mac.** A walk is work in progress, as a draft is, and is kept on this Mac
until it is stored or discarded: its stops, their states, ticks and placements, and the pool. Opening
the differences of a container that roots a kept walk offers to resume it or start again. The silo
holds nothing of a walk.

## Principles

0017's principles stand: TMDb proposes and the operator decides, smddb's identity comes first, facts
are taken and everything else attributed, attributed work stays in the library, and one thing is one
entry. This proposal adds three.

1. **A decision is made where it is about.** The operator places a special while looking at the
   container it goes in, and reviews a season's differences while that season is open. The pool comes
   to the container rather than the operator going back to the pool.
2. **Nothing is stored until the walk is, and the store says everything first.** A walk is one piece of
   work and is stored as one, in an order that makes every reference resolve, after a list of every
   edit, creation and put it makes.
3. **Leaving is free.** A stop never opened, a child never ticked and a special never placed change
   nothing and hold nothing up. A walk stored halfway down the tree stores what was confirmed.

## Vocabulary

- **Walk** — a review of a held container and everything beneath it against TMDb, kept on this Mac
  until it is stored or discarded.
- **Stop** — one container of a walk, held or new, with its differences and its state.
- **Pending stop** — a stop the walk has queued and the operator has not opened.
- **Pending change** — what confirming a stop took: its edit, the specials placed in it, its artwork.
- **Companion series** — a series beside the one being walked, held already or new, listed or
  unlisted, holding specials TMDb has no series for: 0017's breakout.
- **Alternative** — as SmdKit has it, a cut of a container, naming the sequence it plays.
- **New stop** — a missing child the operator ticked, a draft from TMDb to be created when the walk is
  stored.

## What this looks like to the operator

In the `tv` library, *Doctor Who* holds twenty-six seasons and carries TMDb ref `121`. The operator
opens its differences, and a walk starts with *Doctor Who* as its first stop. The sidebar shows the
series alone. The pool beside it lists a hundred and forty unassigned specials. The series lacks
fanart, and its outline differs from TMDb's. The operator ticks the Artwork group whole and leaves
Fields, and confirms. The sidebar fills with twenty-six pending seasons.

*Next* opens *Season 1*. TMDb holds a TVDB id for each of its episodes that the sidecar lacks. The
operator ticks References whole and confirms. *Season 1* shows as changed, and its four serials join
the sidebar beneath it as pending. *Next* opens *An Unearthly Child*, the first of them, which differs
in nothing. They confirm it, and it shows as looked at.

At *Season 18*, the panel suggests *K9 and Company* for the season, since it aired between two of
this season's episodes, without marking it as suggested here, since nothing in its title names the
season. The operator places it as an entry after the last episode, and the panel's
count goes down by one. At *The Five Doctors*, a serial they hold in *Season 20*, they place a
making-of as one of its extras.

At *The Daleks* in *Season 1*, the panel marks two specials as suggested here. *The Daleks: Omnibus*
runs close to the serial's seven episodes together, and the operator places it as a new edition titled
*Omnibus*. *The Dead Planet (Special Edition)* names the serial's first episode, and they place it as a
version of that episode, titled *Special edition*, which holds it in that episode's place and refers to
the other six.

At *Season 10*, a concert special is one TMDb has no series for. The library already holds *Doctor Who
at the Proms*, a listed series the operator made for such concerts, and they place the special in it,
referred to from the season's extras.

At *Season 26*, they realise they never placed the 1983 Children in Need special in *Season 20*. They
select *Season 20* in the sidebar, which opens with its ticks as they left them, place the special,
and confirm again.

TMDb has a *Season 27* the library does not hold. It was listed under the series' Children, and the
operator did not tick it, so it was never walked. They select *Doctor Who* in the sidebar, tick *Season
27*, and confirm again. *Season 27* joins the sidebar as new. When they open it, its year and
references are ticked. They leave them ticked, regroup its episodes into two serials, place the
season's Christmas special as an entry between them, and confirm.

They store the walk. The list shows the edit of *Doctor Who*, which names *Season 27*, followed by the
creation of *Season 27* and its two serials, then the edits of each season and serial they changed,
then the fanart, credited to TMDb. The store makes them in that order. The specials they did not place
are still unassigned, and wait in the pool for the next walk.

## What this asks of an implementation

Each step below is a pull request, and its spec deltas are in `openspec/changes`, named after the step.

### 1. A walk through what the library holds

The walk in SiloAdminKit: its stops, their states and the queue's order; confirming a stop, which
queues the children the library holds beneath it; reopening and confirming a stop again; the pool
beside every stop, and a special placed in the open stop becoming part of its pending change; and one
store, listed first and run in order, stopping at the first refusal. The walk's sheet in SiloAdmin
replaces 0017's differences sheet: the sidebar, the open stop, the panel and the store's list.

Tests: confirming a series queues each season it holds, in its sequence's order, and confirming a
season queues its serials; a confirmed stop reopened keeps its ticks, and confirming it again replaces
its pending change; a special placed in a season is stored in that season's edit and leaves the pool;
a stop never opened stores nothing; the store lists every edit before it stores any, and a refused
edit stops the store, keeping what it had not stored.

### 2. Specials as alternatives, and in companion series

A special placed in the open stop as an alternative: in an alternate sequence the container has, as a
new edition in a sequence of its own, or as a version of one item, in a new sequence that refers to the
others; each new sequence named by a new alternative. The two suggestions that propose them. A special
placed in a companion series the library holds, listed or not, or in a new one, listed or not as the
operator chooses.

Tests: a special placed as a new edition makes a sequence holding it alone and an alternative naming
it; a special placed as a version of an episode makes a sequence holding it in that episode's place
and referring to the rest; a special placed in an alternate sequence the container has goes at its
position; an omnibus is suggested as a new edition, and an episode's special edition as its version;
a special placed in a listed companion series the library holds is an entry of it, referred to from
the open stop; a new companion series made listed is created listed.

### 3. New containers in the walk

A missing child ticked under *Children* as a new stop: a draft from TMDb beneath its parent, its
fields, references and artwork ticked to begin with, shaped as 0017's form shapes a draft, and created
by the store before anything that refers to it. Unticking it removes it and what is beneath it.

Tests: a ticked missing season joins the walk as new, with TMDb's fields ticked; a special placed in it
is stored after it is created, in its own sidecar; a serial its shaping makes is a new stop beneath it;
unticking the season removes it and its serials from the walk.

### 4. A walk kept on this Mac

A walk kept between launches, resumed or discarded from the differences of the container that roots it,
and a stop whose sidecar has changed since it was read, read again before its change is stored.

Tests: a walk kept and reopened has its stops, states, ticks and placements; a discarded walk is gone;
an edit whose sidecar changed after its stop read it is refused, and its stop is read again.

## What comes next

**Walking from smddb.** 0013's differences from smddb's record are a reading of the same kind, and the
same walk could review a held tree against smddb, a container at a time.

**Other providers.** The walk is written against 0017's reading, so a second provider's reading, as
0017's *What comes next* has it, would be walked the same way.

## Non-goals

- **Taking everything at once.** There is no action that confirms every stop with everything ticked.
  Each container is the operator's to look at, which is the reason for the walk.
- **Walking upwards or sideways.** A walk covers its root and what is beneath it. A container elsewhere
  in the library is changed only by the edits specials placed in it make, and those are listed before
  they are stored.
- **The silo holding a walk.** A walk is the console's work in progress, as a draft is.
- **Removing what TMDb lacks.** As in 0017, nothing is offered for removal.

## Open questions

1. **How far ahead to read.** Reading the next pending stop while the operator works on one makes
   *Next* immediate, and costs TMDb requests for a stop the operator may never open. One stop ahead is
   proposed. More could be worth it for a season whose serials are each a handful of questions.
2. **A walk rooted below a series.** A walk opened on a season still has the series' specials beside
   it, read through the series above it. Whether the panel should show only the specials suggested for
   that season, or all of them, is worth trying with an operator.
3. **Two walks over one tree.** A walk rooted at a series and another rooted at one of its seasons can
   both hold pending changes for that season. Storing either is safe, since a stale edit is refused,
   but the console could say, when the second walk starts, that the first holds pending changes beneath
   it.
