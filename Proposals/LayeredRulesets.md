<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0007-layered-rulesets

Modified: 2026-10-08

# Layered rulesets

This proposes four changes to what a ruleset is and how it is used.

First, the rules that decide an entry come in layers. A library names the ruleset that is its
standard; a container may have rules of its own, kept in versioned files beside its `.smd`, for
everything inside it; and the rules nearest the entry are tried first, so a container says only what
differs and everything else falls through to the library's rules.

Second, a person's decision about one entry is a layer too: the binding's own rules, nearest of all.
It replaces adjusting a draft recipe, so the decision is kept, versioned, and made again the same way
whenever the entry's file is.

Third, a ruleset has branches. A trial set of rules is a branch of the standard, applied to the
bindings the operator chooses, and promoted to be the standard when it has earned it.

Fourth, every presentation the silo places records, in its `.smd`, the binding it was made from and
every set of rules that made it; and the silo works out, in the background, which placed
presentations its current rules would make differently, and whether their sources can be had to make
them again.

The ruleset language, [rulesets](../openspec/specs/rulesets/spec.md), gains two facts — a stream's
index — and is otherwise unchanged: a container's rules, a binding's and every branch are written in
it. The ingestion model, [0006-ingestion](Ingestion.md), stands: sources, bindings, recipes made by
applying a ruleset to a binding, and jobs that run a committed recipe. The `.smd` format these
layers live in is smddb's, amended for them in
[smddb#37](https://github.com/project-smd/smddb/pull/37) and
[smddb#38](https://github.com/project-smd/smddb/pull/38), and read and written by SmdKit
([SmdKit#23](https://github.com/project-smd/SmdKit/pull/23),
[SmdKit#26](https://github.com/project-smd/SmdKit/pull/26)).

## The problem

A household's rules are not one list. The same library holds a series whose DVD extras are fine at
CRF 22 and a film restoration whose extras are the reason it was bought; a season with a commentary
on every episode and another with an isolated score that must never be touched; an episode whose
commentary, alone among its siblings', was recorded by different people and wants different
treatment. Today there are two ways to say so, and both are poor. A container-specific rule can be
written into the one household ruleset with conditions that pick the container out — but no fact
names a container, and the conditions that stand in for one (`kind`, `format`, a duration) catch
other entries by accident. Or a second ruleset can be written for the exceptional container, copying
every rule it does not change, and applied to its bindings by name; and when the household ruleset
changes, the copy does not.

[0001-silo](Silo.md) saw this coming and deferred it: "Whether a ruleset may reference another …
Not until there are two." There are two.

A person's last word on one entry is worse off. The producer adjusts a draft recipe — keep this
track, the rules would re-encode it — and the adjustment lives on that draft alone. Apply the rules
again, because they changed or because the household wants a mobile output it did not make before,
and the adjustment is gone; nobody is told.

The versions are a line. Every store is the next number, and every application that does not name a
version takes the latest. So trying a change on a few bindings means storing it as the latest, where
every other application picks it up too; and backing it out means storing the old document again.

And the record stops at the silo. A committed recipe knows the ruleset version it was resolved
against, which answers "what made this presentation" for as long as the silo's state lasts; the
library itself does not say. Nothing answers the next question either: now the rules have changed,
which presentations would they make differently — and of those, which can be made again? A household
that changes its commentary bitrate has no way to find the forty presentations made at the old one,
except to remember.

## What this is

**Layers.** The rules that apply to an entry are a stack, nearest first: the binding's own rules,
then the rules of the container that holds the item, then those of its parent, and so on up the
lineage, and last the ruleset applied. For each stream the first matching rule anywhere in the stack
decides, exactly as the first matching rule in one ruleset does today.

**Rules beside the `.smd`, by version.** A container's rules are versioned files in a folder beside
its `.smd`, `rules/<n>.xml`, and the `.smd` names the folder and the version in force:
`<rules path="rules" activeVersion="4"/>`. A binding's rules are the same, in a folder of their own,
named on the item the binding binds: `<rules binding="…" path="rules/bindings/…" activeVersion="2"/>`.
A version is never edited; a change is the next version, and the old ones stay for the files they
made. smddb argues the format; SmdKit reads and writes it.

**A library names its standard.** Each library in `settings.json` may name a ruleset, set by
`PUT /v1/libraries/{library}/ruleset`. An application that names no ruleset takes the library's
standard, at the moment it is made, as [0006-ingestion](Ingestion.md#bindings) anticipates; on a
library with none, it must name one, as today.

**A person's decision is the binding's rules.** `PUT /v1/bindings/{id}/rules` stores the binding's
next version of its rules — typically one rule naming one stream, which the new facts `audio.index`
and `subtitle.index` make possible — and applying the rules again makes a draft that already carries
the decision. Adjusting a draft goes: a draft is always what the rules decided, and nothing is
patched on top of it.

**Branches.** A ruleset has a `standard` branch — every version stored today is on it — and any
number of named branches, each started from a version of the standard. An application may name a
branch. Promoting a branch makes its head the standard's next version, and is refused unless the
branch already holds everything the standard has gained since the branch began.

**Provenance, in the library.** A recipe records its stack: the ruleset version, as it does today,
and every layer above it — whose it is, its version, and the digest of that version's file — and each
decision names the layer its rule came from. When the silo places a presentation it writes, into the
`.smd`, `<source binding>` with a copy of the binding's segments by natural key, and `<transform>`,
the stack that made it. A library copied, restored or handed to another server says what made each of
its files, and keeps every version of every rule that did.

**Out of date, in the background.** When rules change — a ruleset stored or promoted, a container's
or a binding's rules moved to a new version — the silo works out, in a background process it can
stop and resume, which placed presentations the change can reach, resolves each again through the
rules now in force, and records the outcome: still current, checked against these rules; or out of
date, with what would change. A report reads those records, says how many are still to be checked,
and gives each out-of-date presentation with whether every source of its binding has a copy.

Placing a new presentation over an out-of-date one is not part of this proposal; see
[Non-goals](#non-goals). Making the new recipe is not new at all: it is applying the rules to the
binding again, and every decision a person made comes with it.

## Principles

0001-silo's principles stand — the `.smd` is the truth, a decision is recorded with what it decided,
a ruleset is immutable once named — and so do 0006-ingestion's. This proposal adds five of its own.

1. **The nearest rules speak first.** A container says what is different about it, and nothing
   else; what it does not decide, the rules above it do. Precedence across layers is the same rule
   as precedence within one — first match wins — so there is still only one rule to learn.
2. **What an entry wants travels with the library.** A container's and a binding's rules are beside
   the `.smd`, and every presentation's provenance in it, so a library copied to another disk,
   restored from backup or handed to another silo keeps them. The library's standard is the silo's to
   keep, because it is the silo's policy, not the container's.
3. **One mechanism for decisions.** A rule in a ruleset, a container's exception and a person's call
   on one entry are all rules in layers. A recipe is always what its stack decided; nothing is
   patched on afterwards, so nothing is lost when the rules are applied again.
4. **Out of date is about decisions, not versions.** A presentation made by version 3 is not out of
   date because version 4 exists; it is out of date when version 4 would make it differently. A
   change that decides nothing differently touches no presentation.
5. **Nothing is made again behind the operator's back.** The silo says what is out of date and
   whether it could be made again. Applying the rules again, making a job of the draft and spending
   an encode on it are the operator's.

## Vocabulary

- **Layer** — one set of rules in a stack: a binding's own rules, a container's, or the ruleset
  applied.
- **Stack** — the layers that apply to one entry, nearest first: the binding's, the item's
  container's, its ancestors' in turn, then the ruleset applied.
- **Version in force** — of a container's or a binding's rules, the one its `<rules>` names as
  `activeVersion`; the others stay in the folder for the files they made.
- **Standard** — a ruleset's `standard` branch, and the rules a library applies unless told
  otherwise.
- **Branch** — a named line of versions of a ruleset, started from a version of the standard.
- **Promotion** — making a branch's head the standard's next version.
- **Out of date** — a placed presentation whose stack, as it stands now, would decide one of its
  streams, or its output, differently from what its committed recipe decided. The operator's word
  for it was *dirty*; that word means something else to anyone who uses git, which is where branches
  come from.
- **Check** — the silo's record that it resolved a placed presentation again through a given stack,
  and what it found.

## Layers

### A container's rules

A container's `.smd` may end in one `<rules>` element naming a folder of rule versions beside it and
the version in force:

```xml
<container id="00000000000000a3" type="serial">
  <title>Pyramids of Mars</title>
  …
  <rules path="rules" activeVersion="4"/>
</container>
```

and `rules/4.xml`, beside it, holds rule elements exactly as a ruleset does:

```xml
<rules>
  <!-- The restoration's extras are the point; keep them whole. -->
  <video id="restoration-extras">
    <when fact="kind" ne="episode"/>
    <copy/>
  </video>
</rules>
```

A version file holds rules and nothing else: no `<extraction>`, because a producer makes a source
before any binding says which container it belongs to, so only a library's ruleset can speak to it;
and no `<output>`, because what a library makes of every entry is one decision for the library. The
rules apply to every item of the container and of every container below it — an episode container,
when an episode has alternatives or features of its own, included.

A `<rules>` naming a version file that is not there, or a version file the ruleset reader refuses, is
an error-severity finding on the sidecar, reported by the walk like any other; an application whose
stack includes it is refused, naming the container, rather than resolved as if the layer were not
there.

### The stack

A binding carries the item's lineage, root first, as repository documents. Its stack is built from
that lineage when a ruleset is applied: the binding's own rules (step 2), then the nearest
container's rules as the index holds its sidecar, then each ancestor's, then the ruleset applied —
the one the application names, or the library's standard. A container with no sidecar yet, or no
`<rules>`, contributes no layer. The stack is taken at the moment of the application, as the ruleset
version is: rules changed afterwards reach the binding when the rules are applied again, and the
background check says which placed presentations that matters for.

Resolution tries, for each stream, the rules of the stream's scope in the first layer in document
order, then the next layer's, and so on; the first rule that matches decides. So a container's rules
usually have no catch-all: a condition-less rule decides every stream of its scope that reaches it,
and the rules below never speak. That is sometimes what is meant — `<audio><copy/></audio>` in the
restoration's rules says "never touch this audio" — so it is allowed.

Each of the ruleset's outputs is resolved through the same stack, with `profile` set to its profile,
so a layer can speak to one output by testing `profile`. The outputs themselves, and the extraction
policy, are the ruleset's alone.

### A stream by its index

`audio.index` and `subtitle.index` join the facts: a stream's index from one among the joined media's
streams of its kind, as `<track>` and the feature map count. A rule in a ruleset has little use for
them, since a ruleset is written for every entry; a binding's rules have every use, since they speak
of one entry's streams: `<audio><when fact="audio.index" is="1"/><copy/></audio>`.

### Why not media-type layers

The operator's first sketch had overrides per container or per media type. Media type needs no
layer: `kind` is a fact every rule can test, and first-match already lets `kind`-specific rules stand
ahead of general ones in the library's ruleset. Containers are different: no fact names one, which is
why they need a layer.

## A binding's own rules

A person's decision about one entry — this disc's second audio stream is the Atmos object track; keep
it as it is — is a rule in the binding's own rules, the layer nearest any file made from the binding.
It belongs to the binding, not the item, because it speaks of the binding's own streams, which
another binding of the same item numbers differently; and it is named on the item the binding binds,
once, because every presentation made from the binding shares it:

```xml
<item type="episode" id="part1">
  <rules binding="5b0e7c1a-…-91d2" path="rules/bindings/5b0e7c1a-…-91d2" activeVersion="2"/>
  <presentation …>…</presentation>
</item>
```

**Setting them.** `PUT /v1/bindings/{id}/rules` takes a rules document, reads it as a container's
rules are read, and stores it as the binding's next version; `GET` answers the version in force and
lists the others. Applying the rules to the binding again then makes a draft that carries the
decision, and a job is made from it as today. A decision for one output only says so with a
condition on `profile`, in the one version in force: a binding has one set of rules in force, and
every presentation made from it is checked against them.

**Where they live before there is a library to hold them.** At ingestion a person decides before
anything is placed, and the item's container may have no folder and no `.smd` yet. So the silo keeps
a binding's versions in its own state until the binding's first placement, and that placement writes
them into the library in order: the version files, then the presentation, then the item's `<rules>`
reference. After that the library holds them, and a later version is written there directly — the
file first, then the reference — while the silo's copy is only ever a staging area. Placement still
makes folders only as news: a binding's rules folder appears when a file made from the binding does.

**Adjustments go.** A draft's adjustments were a second mechanism for the same decision, lost on
every application. `PUT /v1/recipes/{id}/adjustments` is removed; a draft is what its stack decided,
and its decisions name their layers, so a stream a person decided says it was the binding's rule
that decided it.

**What not to put there.** Some decisions are really facts: "audio 2 is a commentary" is the
binding's feature map, and a producer's marks in the input spec say what a stream is. A binding's
rules are for decisions — what to do with a stream — not for correcting what a stream is.

## Branches

### The standard and its branches

Every ruleset has a `standard` branch. Every version stored today is on it, and a store with no branch
named goes on it, so nothing that stores rulesets today changes.

A branch is started from a version of the standard, which becomes its *base*, and holds versions of
its own. Version numbers stay one sequence per ruleset, across all its branches: the standard's 7 and
a branch's 8 and 9 are `household@7`, `household@8` and `household@9`. So `name@version` still names
exactly one document, every recipe already committed still means what it did, and a recipe needs no
new field to say which branch made it — the version knows. Each version records its branch and its
parent: the previous version on its branch, or the base for a branch's first.

An application may name a ruleset's branch; it is resolved against the branch's head, or a version
the application names. Which bindings a trial branch is applied to is the operator's choice, made
per application — and so, in practice, the producer's to offer when it applies the rules as the last
step of an ingestion.

### Promotion

Promoting a branch stores its head's document as the standard's next version, recording the branch
head it came from, and closes the branch; a further trial is a new branch.

Promotion replaces; it does not merge. If the standard has gained versions since the branch's base,
promoting would silently throw them away, so it is refused, naming the versions the branch has not
taken in. The operator brings the branch up to date by storing a new version on it that includes what
the standard gained — by hand, because two edits to an ordered list of rules can merge cleanly as text
and still change which rule decides a stream — and declaring, as the store's `upToDateWith`, the
standard version it now takes in. Then promotion is a fast-forward, and nothing is lost that nobody
looked at.

Before promoting, the operator can ask what it would change: every placed presentation made under the
library's standard that the branch's head would decide differently, reported exactly as an
out-of-date presentation is. That is the question "which content could be updated" asked before the
answer is committed to.

## Provenance and out-of-date presentations

### What a recipe records, and what the `.smd` says

A recipe records its stack, nearest first: for each layer above the ruleset, whose it is — a binding
or a container — its version and the SHA-256 of that version's file, and last the ruleset and its
version. Each decision names its layer beside its rule, since `#2` means nothing without saying
whose second rule it was.

When the silo places a presentation it writes two things into the `.smd` beside the file, in the form
smddb defines:

```xml
<presentation profile="mobile" file="Part Three - mobile.mkv">
  <source binding="5b0e7c1a-…-91d2">
    <segment scheme="discTitle" value="3F1AC2E9/00004.mpls" from="2" to="2"/>
  </source>
  <transform ruleset="household" version="7">
    <layer binding="5b0e7c1a-…-91d2" version="2" digest="sha256:77ab…"/>
    <layer container="00000000000000a3" version="4" digest="sha256:41d0…"/>
  </transform>
  …
</presentation>
```

`<source>` names the binding — the silo's binding id, which is smddb's, a UUID minted once and kept
if the binding is contributed — with a copy of its segments by their sources' natural keys, so the
file describes itself without the silo; a segment whose source has no natural key keeps its place
without one. `<transform>` is the recipe's stack. The binding's own optional source reference, which
named a disc title for the sidecar, goes: the sidecar's source is derived from the binding.

### Out of date

A placed presentation is **out of date** when its committed recipe's facts, resolved through the
stack that applies to its binding now — its binding's rules in force, its lineage's container rules
in force, and the head of the branch its ruleset version is on, or of the standard once that branch
is promoted — for the recipe's output, give decisions that differ from the ones the recipe recorded
in any stream's action or settings, or give a different output policy, or give no recipe at all.
Which layer or rule decided a stream is not compared: a stream re-decided by a renamed rule, or by a
container's rule that says what the ruleset said, to the same action, is not out of date.

A stream a person decided is decided again by the same binding rule, so a change of the ruleset
beneath it does not report it; a change of the binding's rules does, because that is a change of the
decision.

Changes to extraction make nothing out of date. They change which of an origin's streams the next
source keeps; a placed presentation can only gain them from a new source, which is the producer's to
make.

### The background check

Working this out on request would read no media file and run no tool — resolution is a pure function
of recorded facts and the rules — but it would record nothing either: no "made by version 4, checked
against version 6", and no way to show progress through a large library. So the silo checks in the
background, and keeps what it finds.

**A check record per placed presentation.** For each committed recipe whose job placed a
presentation, the silo keeps its latest check: the stack it was checked against, when, and the
outcome — `current`, `outOfDate` with the streams that would change from what to what, or
`unresolvable` with the resolver's reason. The committed recipe itself never changes.

**What starts it.** A ruleset version stored on a branch, a promotion, a binding's rules moved to a
new version, and a walk that finds a sidecar whose `<rules>` names a different version than the index
last held.

**Which presentations a change can reach.** A ruleset change reaches every placed recipe whose
ruleset version is on that branch, or on the standard after a promotion. A binding's rules reach the
binding's placed recipes. A container's rules reach every placed recipe whose binding's lineage
includes the container — by the lineage, not the recorded stack, because a container gaining rules
for the first time is in no stack yet. The silo keeps an index from container to the placed recipes
below it for this.

**Interruptible without a cursor.** The work remaining is every placed presentation whose latest
check's stack is not the stack that applies to it now. Each check is recorded as it finishes; a
restart, a crash or the process being stopped loses nothing but the check in flight, and the next run
picks up what is left. Two changes in quick succession leave one stack to check against, not two.

**The report.** `GET /v1/libraries/{library}/out-of-date` reads the records: each out-of-date
presentation with its container, item, file and profile, the stack it was made by and the stack it was
checked against, the streams that would change, and the sources of its binding with their copies;
how many presentations are still to be checked; and how many were placed without a job, which have
no recipe and are never checked. `GET /v1/rulesets/{name}/branches/{branch}/impact` answers the same
shape for a promotion that has not happened, resolving on request and recording nothing, since it is
one question asked before a decision.

### Whether the sources can be had

Each out-of-date presentation is reported with the sources of its binding, each with the copies the
silo records of it. It can be made again today when every source has at least one: applying the rules
to the binding makes a draft, and a job can be made from it.

A source whose copies have all gone stays a source, and its presentations stay reported. A producer
that registers the same source again, under the same natural key, finds that source and adds a copy,
and every out-of-date presentation that needs it can be made again without the silo matching anything
afterwards. A source registered with no natural key is a new source when registered again; that is
what natural keys are for.

## What this looks like to the operator

The household's standard is `household@7`, and `films` names it. The operator decides the
commentaries are too big and starts a branch, `speech-96k`, from version 7; stores the change as
version 8 on it; and the producer applies it, by branch, to the next three bindings. The three
commentaries come out at 96k, each `.smd` recording `household@8` in its `<transform>`. The operator
listens, likes them, and asks what promotion would change: 41 presentations, each with one commentary
stream going from 160k to 96k — 29 whose sources still have a copy, 12 whose sources have none. They
promote; the standard's version 9 is version 8's document. The background check runs; the three trial
presentations are checked current against version 9, because it decides them exactly as version 8
did, and the 41 are out of date. The report says which can be made again today.

Ingesting the next box set, the producer notices that one episode's disc carries an object-audio track
as its second stream, which the rules would encode to FLAC. It stores the binding's first rules — copy
audio 2 — applies the rules again, and the draft copies it, its decision naming the binding's rule.
When that episode is made again a year later for a new mobile output, the decision comes with it.

Months later the operator adds rules to the Pyramids of Mars serial keeping the restoration's extras
whole: `rules/1.xml` beside its `.smd`, and `<rules path="rules" activeVersion="1"/>` in it. At the next
walk the silo sees the new reference, and the background check finds the two extras already placed at
CRF 22 out of date, their sources with no copy. They stay on the report. When the discs come off the
shelf and their titles are registered again under the same natural keys, the sources gain copies, and
the two can be made again.

## What this asks of an implementation

Each step is a pull request, in order, and each carries its spec deltas into `openspec/` per the
corpus README — the deltas are written now, one change for each step under
[`openspec/changes/`](../openspec/changes/): `layered-rulesets-1-layers`,
`layered-rulesets-2-binding-rules`, `layered-rulesets-3-branches` and
`layered-rulesets-4-out-of-date`, each applied by its step's pull request with `openspec archive`. The
console's view of all this — the stack, branches, promotion and the report — is 0008-rulesets' to
design, rewritten on this model; the draft [#39](https://github.com/media-silo/silo-server/pull/39)
becomes it.

### 1. Layers and provenance

The SmdKit pin moved to a revision with rules by reference and presentation provenance; containers'
`<rules>` read through the index and their version files read and checked by the walk; the stack
built from a binding's lineage and resolved through; `audio.index` and `subtitle.index`; the library's
ruleset in `settings.json`, and applications that name no ruleset; recipes recording their stack and
decisions naming their layer; placement writing `<source binding>` and `<transform>`; and the
binding's own source reference, `silo-ctl place --source` and the place route's `source` removed. The
`layered-rulesets-1-layers` change applies here.

Tests: a container's rule decides ahead of the ruleset's, and a stream it does not match falls
through; the nearer of two containers decides; a condition-less container rule ends its scope; a
missing or refused version file is a finding and refuses the application, naming the container; a
rule picks a stream by its index; a decision names its layer and a recipe its stack, with each
layer's version and digest; an application naming no ruleset takes the library's standard, and one
on a library with none is refused; a placed presentation's `.smd` names its binding, its segments by
natural key and its transform.

### 2. A binding's own rules

The binding layer; `PUT` and `GET /v1/bindings/{id}/rules`; versions staged in the silo until the
binding's first placement and written into the library by it; later versions written to the library
directly; adjustments removed. The `layered-rulesets-2-binding-rules` change applies here.

Tests: a binding's rule decides ahead of every container's; a decision made in a binding's rules is
carried into a draft made by applying the rules again; a binding's rules stored before placement are
in the silo's state and not the library, and the first placement writes the files, the presentation
and then the reference; a later version is written to the library and the reference moved; the
adjustments route is gone.

### 3. Branches

Versions recording branch and parent, stores on a branch, applications naming a branch, promotion as
a fast-forward, and the branch routes. The `layered-rulesets-3-branches` change applies here.

Tests: a branch's versions share the ruleset's sequence and each names its parent; a store with no
branch is on the standard; an application on a branch takes its head; promotion stores the head as
the standard's next version and closes the branch; promotion over versions the branch has not taken
in is refused, naming them, and succeeds once the branch declares them.

### 4. Out-of-date presentations

Check records, the background check with its triggers and its index from container to placed
recipes, the report and the impact route. The `layered-rulesets-4-out-of-date` change applies here.

Tests: a promotion that decides a stream differently leaves its presentation out of date and one that
decides the same leaves it current, checked against the new version; a container's rules moved to a
new version reach the presentations below it and no others; a binding's rules reach its own; a stream
a binding rule decides is not reported when the ruleset beneath it changes; the check, stopped half
way, resumes with what is left and checks nothing twice; a presentation placed without a job is
counted, not checked; a presentation whose sources have copies can be made again, and one whose
source has none becomes so when the source is registered again under its natural key; the impact of a
branch equals the report after its promotion.

## Non-goals

- **Placing over an out-of-date presentation.** Making the new draft is applying the rules again, and
  making a job of it is as today; but placing its output means replacing a file the library already
  holds, where a placement refuses a destination that exists — "nothing is overwritten" is
  0001-silo's seventh principle, that conflicts are shown and never resolved, made concrete, and
  relaxing it deserves its own argument. The report is built so that the proposal which does it has
  everything it needs.
- **Merging branches.** Promotion is a fast-forward; bringing a branch up to date is a person's edit.
  A textually clean merge of two rule edits can change which rule decides a stream.
- **Layers for media types**, argued above: `kind` is a condition.
- **Extraction or outputs per container or binding**, argued above.
- **Branches of a container's or a binding's rules.** Their versions are a line in their folder; a
  household that wants to trial an override does so on a branch of the library's ruleset, with a rule
  testing what it can.
- **Rules per item.** A plain episode, a leaf item, has no layer of its own; an episode that needs
  one is an episode container, as it is when it has alternatives or features of its own, or its
  binding's rules say it.

## Open questions

1. **How long records are kept.** The check reads every placed job and its committed recipe. The
   [jobs](../openspec/specs/jobs/spec.md) store is sized at "tens of records, not thousands", held in
   memory, and the recipe store is held the same way; a library's placed jobs, committed recipes and
   check records grow without bound. Either they move to stores read on demand, or a placed job is
   reduced to the link from its recipe to its presentation.
2. **Naming the container in a rule.** With layers there is no need for a `container` fact, and this
   proposal adds none. A household that keeps its exceptions in the library's ruleset rather than in
   the library would want one; the cost is a fact that is the same for every stream and a second way
   to say what a layer says.
3. **Whether a copy is still there.** The silo trusts the copies producers record. A holder that
   deletes a file without saying leaves a presentation reported as able to be made again, and the job
   made for it fails when the node cannot fetch the file. Asking each holder when the report is read
   would catch that sooner, at the cost of reaching every producer.
4. **An output the rules gained.** A ruleset that gains a `mobile` output makes no presentation out of
   date — none was made by that output — but every entry now lacks a presentation the rules would
   make. Reporting those as *missing* is the same check asked of the outputs rather than the streams,
   and is left until a household has added an output to a library already full.
5. **Rules edited by hand while the silo runs.** A version file written and a reference moved by hand
   are noticed at the next walk. Whether the silo should watch the library for them, rather than wait
   for a walk, depends on how often a household edits rules by hand rather than through the silo.
