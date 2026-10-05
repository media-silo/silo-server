<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0007-layered-rulesets

Modified: 2026-10-05

# Layered rulesets

This proposes three changes to what a ruleset is and how it is used.

First, the rules that decide an entry come in layers. A library names the ruleset that is its
standard; a container may carry rules of its own in its `.smd`, for everything inside it; and the
rules nearest the entry are tried first, so a container says only what differs and everything else
falls through to the library's rules.

Second, a ruleset has branches. A trial set of rules is a branch of the standard, applied to the
bindings the operator chooses, and promoted to be the standard when it has earned it.

Third, the silo says which placed presentations the rules would now decide differently — out of
date — and whether the sources each would be made again from can be had. A committed recipe
already records what made its presentation; this proposal has it record the container layers too,
and compares.

The ruleset language itself, [rulesets](../openspec/specs/rulesets/spec.md), is unchanged: a
container's rules are written in it, and so is every branch. So is the ingestion model,
[0006-ingestion](Ingestion.md): sources, bindings, recipes made by applying a ruleset to a binding,
and jobs that run a committed recipe. This proposal changes what an application resolves against,
and reads what it leaves behind.

## The problem

A household's rules are not one list. The same library holds a series whose DVD extras are fine at
CRF 22 and a film restoration whose extras are the reason it was bought; a season with a
commentary on every episode and another with an isolated score that must never be touched. Today
there are two ways to say so, and both are poor. A container-specific rule can be written into the
one household ruleset with conditions that pick the container out — but no fact names a container,
and the conditions that stand in for one (`kind`, `format`, a duration) catch other entries by
accident. Or a second ruleset can be written for the exceptional container, copying every rule it
does not change, and applied to its bindings by name; and when the household ruleset changes, the
copy does not.

[0001-silo](Silo.md) saw this coming and deferred it: "Whether a ruleset may reference another …
Not until there are two." There are two.

The versions are a line. Every store is the next number, and every application that does not name
a version takes the latest. So trying a change on a few bindings means storing it as the latest,
where every other application picks it up too; and backing it out means storing the old document
again. There is no way to say "these rules, for these bindings, until I decide."

And the record stops at the recipe. A committed recipe knows the ruleset version it was resolved
against, which answers "what made this presentation". Nothing answers the next question: now the
rules have changed, which presentations would they make differently — and of those, which can be
made again? A household that changes its commentary bitrate has no way to find the forty
presentations made at the old one, except to remember.

## What this is

**Layers.** The rules that apply to an entry are a stack of layers, nearest first: the rules of the
container that holds the item, then those of its parent, and so on up the lineage, and last the
ruleset applied. For each stream the first matching rule anywhere in the stack decides, exactly as
the first matching rule in one ruleset does today. A container's rules live in its `.smd`, in a
`<rules>` element written in the ruleset language.

**A library names its standard.** Each library in `settings.json` may name a ruleset, set by
`PUT /v1/libraries/{library}/ruleset`. An application that names no ruleset takes the library's
standard, at the moment it is made, as [0006-ingestion](Ingestion.md#bindings) anticipates; on a
library with none, it must name one, as today.

**Branches.** A ruleset has a `standard` branch — every version stored today is on it — and any
number of named branches, each started from a version of the standard. An application may name a
branch. Promoting a branch makes its head the standard's next version, and is refused unless the
branch already holds everything the standard has gained since the branch began.

**Provenance.** A recipe records the stack it was resolved against: the ruleset version, as it does
today, and for each container layer the container and a digest of its rules, with the silo keeping
every layer it has resolved against by that digest. Each decision names the layer its rule came
from. The committed recipe a job ran is then the whole of what made a presentation, readable after
the sidecar has moved on.

**Out of date.** A placed presentation is out of date when its committed recipe's facts, resolved
against the stack that applies now, decide a stream differently from what the rules decided then.
A stream the producer adjusted is the ingestion's decision and is not compared. The silo works this
out when it is asked, and reports each out-of-date presentation with what would change and whether
every source of its binding has a copy.

Placing a new presentation over an out-of-date one is not part of this proposal; see
[Non-goals](#non-goals). Making the new recipe is not new at all: it is applying the rules to the
binding again.

## Principles

0001-silo's principles stand — the `.smd` is the truth, a decision is recorded with what it
decided, a ruleset is immutable once named — and so do 0006-ingestion's. This proposal adds four of
its own.

1. **The nearest rules speak first.** A container says what is different about it, and nothing
   else; what it does not decide, the rules above it do. Precedence across layers is the same rule
   as precedence within one — first match wins — so there is still only one rule to learn.
2. **What a container wants travels with the container.** A container's rules are in its `.smd`,
   so a library copied to another disk, restored from backup or handed to another silo keeps them.
   The library's standard is the silo's to keep, because it is the silo's policy, not the
   container's.
3. **Out of date is about decisions, not versions.** A presentation made by version 3 is not out of
   date because version 4 exists; it is out of date when version 4 would make it differently. A
   change that decides nothing differently touches no presentation.
4. **Nothing is made again behind the operator's back.** The silo says what is out of date and
   whether it could be made again. Applying the rules again, making a job of the draft and spending
   an encode on it are the operator's.

## Vocabulary

- **Layer** — one set of rules in a stack: the ruleset applied, or a container's `<rules>`.
- **Stack** — the layers that apply to one entry, nearest first: the item's container, its
  ancestors in turn, then the ruleset applied.
- **Standard** — a ruleset's `standard` branch, and the rules a library applies unless told
  otherwise.
- **Branch** — a named line of versions of a ruleset, started from a version of the standard.
- **Promotion** — making a branch's head the standard's next version.
- **Out of date** — a placed presentation whose stack, as it stands now, would decide one of its
  unadjusted streams, or its output, differently from what its committed recipe's rules decided.
  The operator's word for it was *dirty*; that word means something else to anyone who uses git,
  which is where branches come from.

## Layers

### A container's rules

A container's `.smd` may carry one `<rules>` element, holding rule elements exactly as a ruleset
does:

```xml
<container id="00000000000000a3" type="serial">
  <title>Pyramids of Mars</title>
  …
  <rules>
    <!-- The restoration's extras are the point; keep them whole. -->
    <video id="restoration-extras">
      <when fact="kind" ne="episode"/>
      <copy/>
    </video>
  </rules>
</container>
```

It holds rules and nothing else: no `<extraction>`, because a producer makes a source before any
binding says which container it belongs to, so only a library's ruleset can speak to it; and no
`<output>`, because what a library makes of every entry is one decision for the library, and a
container whose entries come out in another format, or in profiles their siblings lack, is a
surprise nobody asked for. The rules apply to every item of the container and of every container
below it.

A container's rules are a library fact, like its presentations: the repository file the shared
store holds carries no `<rules>`, and the sidecar puts them back. smddb's StructuredContainers owns
that format and SmdKit's `SmdSidecar` reads and writes it; both now carry the element
([SmdKit#17](https://github.com/project-smd/SmdKit/pull/17), implemented in
[SmdKit#19](https://github.com/project-smd/SmdKit/pull/19)). `Sidecar.rules` holds it without
interpreting it, in one canonical form whose bytes are what a recipe's digest is taken over; an
update leaves it as it stands, since a placement knows nothing of it.

A `<rules>` element the ruleset reader refuses is an error-severity finding on the sidecar,
reported by the walk like any other. An application whose stack includes it is refused, naming the
container, rather than resolved as if the layer were not there.

### The stack

A binding carries the item's lineage, root first, as repository documents. Its stack is built from
that lineage when a ruleset is applied: the nearest container's `<rules>`, as the index holds its
sidecar, then each ancestor's, then the ruleset applied — the one the application names, or the
library's standard. A container with no sidecar yet — the first entry bound into a new series —
contributes no layer. The stack is taken at the moment of the application, as the ruleset version
is: a container's rules changed afterwards reach the binding when the rules are applied again.

Resolution tries, for each stream, the rules of the stream's scope in the first layer in document
order, then the next layer's, and so on; the first rule that matches decides. So a container's
rules usually have no catch-all: a condition-less rule in a container's `<rules>` decides every
stream of its scope that reaches it, and the ruleset's rules below it never speak. That is
sometimes what is meant — `<audio><copy/></audio>` in the restoration's rules says "never touch
this audio" — so it is allowed, and the reading says plainly that the layer ends its scope.

Each of the ruleset's outputs is resolved through the same stack, with the `profile` fact set to
its profile, so a container's rule can speak to one output by testing `profile`. The outputs
themselves, and the extraction policy, are the ruleset's alone.

A decision records the layer its rule came from as well as the rule, since `#2` means nothing
without saying whose second rule it was: `household@7` for the ruleset, or the container's id for a
container's rules. An adjustment leaves a decision's layer and rule as they were, as it leaves its
rule today, and records the action it replaced.

### Why not media-type layers

The operator's first sketch had overrides per container or per media type. Media type needs no
layer: `kind` is a fact every rule can test, and first-match already lets `kind`-specific rules
stand ahead of general ones in the library's ruleset. A layer per media type would be a second way
to say what a condition already says, with its own precedence to learn — which layer wins when a
featurette is in a container that has rules of its own? Containers are different: no fact names
one, which is why they need a layer.

## Branches

### The standard and its branches

Every ruleset has a `standard` branch. Every version stored today is on it, and a store with no
branch named goes on it, so nothing that stores rulesets today changes.

A branch is started from a version of the standard, which becomes its *base*, and holds versions of
its own. Version numbers stay one sequence per ruleset, across all its branches: the standard's 7
and a branch's 8 and 9 are `household@7`, `household@8` and `household@9`. So `name@version` still
names exactly one document, every recipe already committed still means what it did, and a recipe
needs no new field to say which branch made it — the version knows. Each version records its
branch and its parent: the previous version on its branch, or the base for a branch's first.

An application may name a ruleset's branch; it is resolved against the branch's head, or a version
the application names. Which bindings a trial branch is applied to is the operator's choice, made
per application — and so, in practice, the producer's to offer when it applies the rules as the
last step of an ingestion.

### Promotion

Promoting a branch stores its head's document as the standard's next version, recording the branch
head it came from, and closes the branch; a further trial is a new branch.

Promotion replaces; it does not merge. If the standard has gained versions since the branch's base,
promoting would silently throw them away, so it is refused, naming the versions the branch has not
taken in. The operator brings the branch up to date by storing a new version on it that includes
what the standard gained — by hand, because two edits to an ordered list of rules can merge cleanly
as text and still change which rule decides a stream — and declaring, as the store's
`upToDateWith`, the standard version it now takes in. Then promotion is a fast-forward, and nothing
is lost that nobody looked at.

Before promoting, the operator can ask what it would change: every placed presentation made under
the library's standard that the branch's head would decide differently, reported exactly as an
out-of-date presentation is. That is the question "which content could be updated" asked before the
answer is committed to.

## Provenance and out-of-date presentations

### What a recipe records

A recipe already names the ruleset version it was resolved against, and keeps the facts it was
resolved with, what the rules decided, the adjustments made and the result. It gains its stack's
container layers: for each, nearest first, the container's id and a SHA-256 digest of the
`<rules>` element's canonical form. The silo keeps every container layer it has resolved against
under `rulesets/layers/<digest>.xml` in its state directory, written once and never rewritten, so a
recipe's rules can be read back exactly after the sidecar has moved on — principle 4 of 0001-silo,
extended to rules that live outside the silo.

The presentation a committed recipe made is found through the job that ran it, whose placement
names the presentation. A presentation placed without a job — `silo-ctl place`, `POST
/v1/libraries/{library}/place`, or a sidecar written by hand — has no recipe.

### Out of date

A placed presentation is **out of date** when its committed recipe's facts, resolved against the
stack that applies to its binding now, give rules' decisions that differ from the ones it recorded
in any unadjusted stream's action or settings, or give a different output policy, or give no recipe
at all. The stack that applies now is the current `<rules>` of the binding's lineage, then the head
of the branch the recipe's version is on — or of the standard, once that branch is promoted — and
the output is the one of the recipe's profile. Which layer or rule decided a stream is not compared:
a stream re-decided by a renamed rule, or by a container's rule that says what the ruleset said, to
the same action, is not out of date.

An adjusted stream is not compared. The producer decided it, as the last step of the ingestion, and
a change of rules does not undo that decision; if the rules now decide the adjusted stream as the
producer did, the adjustment was right, and if they decide it otherwise, it is still the
ingestion's call. The adjustment is reported with the presentation, so the operator can see it.

Changes to extraction make nothing out of date. They change which of an origin's streams the next
source keeps; a placed presentation can only gain them from a new source, which is the producer's
to make.

The silo works out which presentations are out of date when it is asked. Resolution is a pure
function of recorded facts and the rules, so this costs no file reads and no tools; every input —
the committed recipe, its binding, the index's sidecars and the stored rulesets — is already held.
Nothing is kept current as the rules change, so nothing can fall behind them.

### Whether the sources can be had

Each out-of-date presentation is reported with the sources of its binding, each with the copies the
silo records of it. The presentation can be made again today when every source has at least one:
applying the rules to the binding makes a draft, and a job can be made from it, since a job is
refused only when a source has no copy.

A source whose copies have all gone stays a source, and its presentations stay reported. A producer
that registers the same source again, under the same natural key, finds that source and adds a
copy to it, and every out-of-date presentation that needs it can be made again without the silo
matching anything afterwards. A source registered with no natural key is a new source when
registered again, and the presentations that need the old one are not told; that is what natural
keys are for.

The silo reports the copies it records and asks no holder whether it still has the file: a copy is
added and removed by the producer that holds it, as [sources](../openspec/specs/sources/spec.md)
describes. See open question 3.

### The report

`GET /v1/libraries/{library}/out-of-date` answers the library's out-of-date presentations, each
with its container, item, file and profile, the committed recipe that made it and the stack it was
made by, the streams that would change — from what to what — the adjusted streams left alone, and
the sources of its binding with their copies; plus the count of presentations placed without a job.
`GET /v1/rulesets/{name}/branches/{branch}/impact` answers the same shape for the presentations a
promotion would put out of date, changing nothing.

## What this looks like to the operator

The household's standard is `household@7`, and `films` names it. The operator decides the
commentaries are too big and starts a branch, `speech-96k`, from version 7; stores the change as
version 8 on it; and the producer applies it, by branch, to the next three bindings. The three
commentaries come out at 96k, each recipe recording `household@8`. The operator listens, likes them,
and asks what promotion would change: 41 presentations, each with one commentary stream going from
160k to 96k — 29 whose sources still have a copy on the machine that registered them, 12 whose
sources have none. They promote; the standard's version 9 is version 8's document. The three trial
presentations are not out of date, because version 9 decides them exactly as version 8 did. The 41
are, and the report says which can be made again today.

Months later the operator opens the Pyramids of Mars sidecar and adds a `<rules>` element keeping
the restoration's extras whole. The next time the report is read, the two extras already placed at
CRF 22 are out of date, their sources with no copy. They stay on the report. When the discs come off
the shelf and their titles are registered again under the same natural keys, the sources gain
copies, and the two can be made again.

## What this asks of an implementation

Each step is a pull request, in order, and each carries its spec deltas into `openspec/` per the
corpus README — the deltas are written now, one change for each step under
[`openspec/changes/`](../openspec/changes/): `layered-rulesets-1-layers`,
`layered-rulesets-2-branches` and `layered-rulesets-3-out-of-date`, each applied by its step's pull
request with `openspec archive`. The console's view of all this — the stack, branches, promotion and
the report — is 0008-rulesets' to design, rewritten on this model; the draft
[#39](https://github.com/media-silo/silo-server/pull/39) becomes it.

### 1. Layers

The sidecar's `<rules>` read and checked by the walk; the stack built from a binding's lineage;
resolution across it; recipes recording their container layers, kept by digest; decisions naming
their layer; the library's ruleset in `settings.json`; and applications that name no ruleset. The
`layered-rulesets-1-layers` change applies here.

Tests: a container's rule decides ahead of the ruleset's, and a stream it does not match falls
through; the nearer of two containers decides; a condition-less container rule ends its scope; a
refused `<rules>` is a finding and refuses the application, naming the container; a decision names
its layer; a recipe records its layers and a layer is readable by its digest after the sidecar
changes; an application naming no ruleset takes the library's standard, and one on a library with
none is refused.

### 2. Branches

Versions recording branch and parent, stores on a branch, applications naming a branch, promotion
as a fast-forward, and the branch routes. The `layered-rulesets-2-branches` change applies here.

Tests: a branch's versions share the ruleset's sequence and each names its parent; a store with no
branch is on the standard; an application on a branch takes its head; promotion stores the head as
the standard's next version and closes the branch; promotion over versions the branch has not taken
in is refused, naming them, and succeeds once the branch declares them.

### 3. Out-of-date presentations

The comparison, the report and the impact route. The `layered-rulesets-3-out-of-date` change applies
here.

Tests: a promotion that decides a stream differently puts its presentation out of date and one that
decides the same does not; a sidecar's new `<rules>` puts the presentations below it out of date; an
adjusted stream is not compared; a presentation placed without a job is counted, not reported; a
presentation whose sources have copies can be made again, and one whose source has none becomes so
when the source is registered again under its natural key; the impact of a branch equals the report
after its promotion.

## Non-goals

- **Placing over an out-of-date presentation.** Making the new draft is applying the rules again,
  and making a job of it is as today; but placing its output means replacing a file the library
  already holds, where a placement refuses a destination that exists — "nothing is overwritten" is
  0001-silo's seventh principle, that conflicts are shown and never resolved, made concrete, and
  relaxing it deserves its own argument. The report is built so that the proposal which does it has
  everything it needs.
- **Merging branches.** Promotion is a fast-forward; bringing a branch up to date is a person's
  edit. A textually clean merge of two rule edits can change which rule decides a stream.
- **Layers for media types**, argued above: `kind` is a condition.
- **Extraction or outputs per container**, argued above.
- **Branches of a container's rules.** A container's rules are edited where they live, in the
  `.smd`; their history is the layers the silo has kept by digest. A household that wants to trial a
  container override does so on a branch of the library's ruleset, with a rule testing what it can.
- **Re-checking an adjustment.** An adjusted stream is the ingestion's decision, and stays so.

## Open questions

1. **How long records are kept.** The report reads every placed job and its committed recipe. The
   [jobs](../openspec/specs/jobs/spec.md) store is sized at "tens of records, not thousands", held in
   memory, and the recipe store is held the same way; a library's placed jobs and committed recipes
   grow without bound. Either both move to stores read on demand, or a placed job is reduced to the
   link from its recipe to its presentation. The second is enough for everything here.
2. **Naming the container in a rule.** With layers there is no need for a `container` fact, and this
   proposal adds none. A household that keeps its exceptions in the library's ruleset rather than in
   sidecars — to see them all in one place — would want one; the cost is a fact that is the same for
   every stream and a second way to say what a layer says.
3. **Whether a copy is still there.** The silo trusts the copies producers record. A holder that
   deletes a file without saying leaves a presentation reported as able to be made again, and the
   job made for it fails when the node cannot fetch the file. Asking each holder when the report is
   read would catch that sooner, at the cost of the report reaching every producer.
4. **An output the rules gained.** A ruleset that gains a `mobile` output makes no presentation out of
   date — none was made by that output — but every entry now lacks a presentation the rules would
   make. Reporting those as *missing* is the same comparison asked of the outputs rather than the
   streams, and is left until a household has added an output to a library already full.
