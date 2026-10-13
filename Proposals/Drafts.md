<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0009-drafts

Modified: 2026-10-13

# Drafts

This proposes that a draft of a ruleset is a working copy kept by the console that wrote it, the way a
clone keeps uncommitted work: saved on the Mac as it is edited, listed in the sidebar under the branch
it was started from, outliving the app, and stored on the silo only when the operator commits it. A
commit is the store 0008 already made — a version based on the head the draft was started from —
and is refused, keeping the draft, when that head has moved. The silo keeps versions, and nothing
else; it never holds work in progress, so two people never edit one thing at once.

Trying rules before they are in force is done with versions, on a branch. A branch's version is
applied to chosen bindings as one can be today, and a job made from a recipe may be a **trial**: encoded
like any job, its output kept in a trial area of the silo's state, served from there to look at and
compare with what is placed, and never placed. A branch whose trials look right is promoted, and its
head becomes the standard's next version.

It also proposes that the console edits a draft in a **form** built from the rule language's schema.
The form creates, changes, reorders and deletes rules and outputs, and leaves every comment and every
character it did not touch exactly as written. A toggle switches between the form and the raw text.
When the text cannot be read, the form says where and why, and the text is edited directly until it
can be. The console reads the XML itself, with the reader the silo runs. The silo stays the final
word: it reads every store and refuses one it cannot read.

It builds on [Rulesets in the console](Rulesets.md) and reverses one of its decisions: that the console
never parses a ruleset. That decision kept the first step small. Using that step showed what it cost.

## The problem

A draft in the console today is a value in one window's memory. It survives the section closing and
the section refreshing, and nothing else. Quitting the app loses it, and nothing in the sidebar says a
ruleset has work in progress on it.

A change cannot be tried without putting it in the library, either. The impact says which placed
presentations a change would make differently, and how, stream by stream. But how a new encode
setting actually comes out, or whether a rule meant for commentaries catches the stream it was meant
for in a release laid out unusually, is seen by encoding something and looking at it. Today that means
storing the change on a branch, applying the branch, making a job and placing it. Placing puts the
output in the library, where a binding already placed from the standard has its presentation in the
way, and where what was only being looked at becomes a presentation the library serves.

And a draft is written by hand. The operator types the rule language and remembers its elements,
its facts and their values, the seven tests and which facts take which, and an encode's attributes.
The reading beside the text confirms what was written, but it cannot help write it. 0008 argued that
a form would throw away the comments and layout a person wrote, so it chose the text. That was a
false choice: the form need not write the document. It can edit the document, element by element,
and leave the rest alone.

## Where a draft lives

Three models were weighed for keeping a draft somewhere other than one window's memory.

- **On the silo, shared.** Every console sees one draft and edits it. Two people editing it at once
  then need either a revision guard that throws one person's typing away, or merging edits as they are
  made, as a shared document does. The first is unpleasant to use and the second is far more than a
  household's rules need.
- **On the silo, held by one console.** The draft is stored centrally but belongs to the console that
  started it. It is shared storage that cannot be shared, and it asks what happens to a draft whose
  console is gone.
- **On the Mac, committed to the silo.** The draft is the console's working copy, kept on disk. The
  silo holds only what was committed, and a commit over a head that moved is refused, to be re-based
  and committed again.

The third is how version control already works, and it is how 0008's store already behaves: a store
names the head it was based on and is refused with the head that landed. This proposal takes it. What
is shared is a version, and a branch is how unfinished work is shared: a change worth showing someone
else, or finishing on another Mac, is committed to a branch of its own.

## What this is

**A draft is the console's.** It is kept on the Mac, per silo, as text and the version it was based on,
saved as it is edited. It is listed under its base's branch, or under its name for a ruleset the silo
holds no version of. It ends when it is stored or discarded, and forgetting the silo deletes it.

**A commit is a store.** It is the store 0008 made, to the base's branch, another branch, or a new
branch started from the base, and it is refused exactly when that store is: the text cannot be read,
or the branch's head is no longer the base. A refusal keeps the draft, shows what landed, and offers to
re-base.

**A trial is a job that is never placed.** A job made as a trial is claimed and encoded like any other.
Its output is fetched into a trial area of the silo's state, served from there, and the job ends
`tried`. Its recipe names the version that made it, as every recipe does, so a trial's provenance is
exact without anything new: what is tried is always a version.

**A branch is tried, then promoted.** A change that needs trying is committed to a branch, applied
from it to the bindings worth trying, and its trials compared with what is placed. A later version on
the branch is tried the same way. When the trials look right the branch is promoted, and its head
becomes the standard's next version, as 0008 made it.

**The console edits through the document, never around it.** The form reads the draft with a reader
that knows where in the text each element lies. Each change it makes replaces the characters of the
elements it touches, and nothing else. A rule that is added is written in the indentation of its
neighbours, and a rule that is moved takes its comments with it.

## Principles

1. **The silo holds versions, never work in progress.** Nothing on the silo is edited by two people at
   once, because nothing on the silo is edited.
2. **A draft is never lost to a refusal.** A store refused for a moved head or for unreadable text
   keeps the draft as it was, on disk.
3. **Provenance is a version.** A placed presentation and a trial each name the version that made
   them. Nothing is tried that was not committed.
4. **A trial never enters the library.** The only way into a library is placement, and placement
   refuses a trial.
5. **What the form did not touch is byte for byte what was there.** Comments, blank lines, attribute
   order and quoting outside the elements a change touches all survive, and a test checks that they do.
6. **One reader.** The console reads with the reader the silo runs. What the console says is readable,
   the silo reads the same way, except for what only the silo can know: whether the name is free and
   whether the base is still the head.

## Vocabulary

- **Draft** — a ruleset's text being written in one console, kept on that Mac with the version it was
  based on.
- **Commit** — storing a draft as a version, which ends the draft.
- **Re-base** — moving a draft's base to its branch's current head, its text unchanged.
- **Trial** — a job made to be looked at rather than placed, and its output.
- **Trial area** — `<state>/trials`, where a trial's output is fetched to and served from.

## What the console does

### Drafts in the sidebar

The Rulesets section lists each ruleset with its branches, and under each branch the drafts based on
it; a draft of a ruleset the silo holds no version of is listed under its name. Opening a draft opens
the editor. A change is a draft based on the version on screen; a new ruleset is a draft from the
starter or a copy; going back is a draft whose text is an earlier version's document. The console saves
the draft to disk a moment after the operator stops, so quitting loses nothing. A draft whose base is no
longer its branch's head is marked as behind before it is committed, so the operator can re-base first.

### Form and text

The editor has two views of one draft. The **form** shows the rules by scope in the order that
decides, and the outputs. A rule's conditions are chosen from the rule language's facts, each fact
offering only the tests it takes and, where the vocabulary is closed, only its values. An action is
copy, drop, or an encode with its settings as fields. Rules are added, deleted, edited, and dragged to
reorder within their scope. The **text** is the raw document, as #65 edits it. The toggle switches
between them on the same draft. When the text cannot be read, the form shows the reader's refusal,
with the line and column for malformed XML, and does nothing until the text reads again.

The console reads with SiloKit's ruleset reader, extended to keep each element's range in the text.
The form's edits are splices into the text. The silo still checks the draft as it is edited, as 0008
made it, for what only the silo can say: the stack it resolves through and the impact.

### Review, commit and trials

The review before a commit stays as 0008 made it: the difference from the base and the impact. A
commit refused because the head moved shows the version that landed and its difference from the base,
and offers to re-base or discard. From a version on a branch, the operator picks bindings to try,
starting with the presentations its impact lists, applies the branch to them, makes trials of the
recipes, follows them, and compares each trial with what is placed: the decisions stream by stream,
and the two files side by side to play.

## What the silo adds

### Trials

`POST /v1/jobs` takes `trial`. A trial job commits its recipe and is claimed and encoded as any job is.
When it is encoded, the silo fetches its output into the trial area itself, as placement would fetch it
into a library, and the job becomes `tried`. The output is served by range at `/v1/trials/{job}/file`,
and a trial lists with its job, its recipe's ruleset version and branch, its binding and output, and the
encode's result. Placement refuses a trial. The background check never sees one, since it reads only
placed presentations. A trial is deleted when the operator deletes it, its job with it.

Nothing else on the silo changes. Applying a branch's version to a binding, storing on a base and
promoting are 0008's.

## What this looks like to the operator

The operator opens `household`, starts a draft from the standard's head, version 3, and drags the
commentary rule above the lossless rule in the form. The text shows the rule moved with its comment,
and nothing else different. They lower the commentary bitrate, quit for the evening, and find the draft
in the sidebar under the standard the next day. The impact lists twelve presentations with a
commentary. They commit the draft to a new branch, `speech-96k`, as its version 4, apply the branch to
three of the twelve bindings, and make trials of the three recipes. The trials encode, and sit beside
the placed files, the commentary at 96k where it was 160k. They promote `speech-96k`; the standard's
version 5 is version 4's document. The background check finds the twelve out of date, which is what
the impact said it would.

## What this asks of an implementation

Four steps, one pull request each, each carrying its spec change.

### 1. Drafts on the Mac

The console keeps drafts on disk per silo, lists them in the sidebar under their base's branch, saves
them as they are edited, and marks one that is behind. A store refused keeps the draft on disk. The
console reads a draft itself with SiloKit and shows the parsed view, read-only, toggled with the text.
Forgetting a silo deletes its drafts.

### 2. The form

SiloKit's reader keeps each element's range, and an editing layer splices changes into the text. The
form creates, edits, reorders and deletes rules and outputs through it.

### 3. Trials on the silo

Trial jobs, fetched to the trial area and ending `tried`; the trial routes; placement refusing a trial.

### 4. Trials in the console

Choosing bindings to try a branch's version on, making and following the trials, and comparing each
trial with what is placed.

## What comes next

0010 does for a container's own rules what 0008 and this proposal do for a ruleset: read, drafted,
tried and committed in the same editor, with a silo route to set them. After it, a library's
containers are imported from smddb or created in the console, through a small smddb client in SmdKit
that the console and the ingestion app share, and proposed back to smddb from the console.

## Non-goals

- **Drafts on the silo.** Work in progress is shared by committing it to a branch.
- **A draft on two Macs.** A draft is one console's. Finishing a change elsewhere is committing it to a
  branch and starting the next draft from there.
- **Merging.** A commit over a moved head is refused and re-based by hand, as a store is.
- **Trying what was not committed.** A trial names a version. A change worth trying is committed to a
  branch first; branches are cheap, and promotion is the only way their versions reach the standard.
- **Placing a trial.** A version worth placing is applied and placed as any version is.
- **A form that writes the document.** The form edits the document a person wrote. It never
  regenerates it.
- **Ingestion-specific policy in the ruleset.** What a source keeps is said by drop rules, which a
  producer reads through the resolver's dry run.

## Open questions

1. **Trial retention.** Trials are deleted when the operator says so. A silo that runs many may want
   a limit on the trial area's size, or trials that go when their branch is promoted.
2. **A trial without a node.** A trial runs on whatever node claims it, as any job does. A trial that
   should run on the embedded node, so that it can be compared before a slow node gets to it, would
   need a claim preference no job has yet.
3. **A branch's many small versions.** Trying a change three times makes three versions on its branch.
   Promotion takes only the head, so the standard's history stays one version per promotion, but a
   branch's list may want collapsing in the console once it is promoted.
