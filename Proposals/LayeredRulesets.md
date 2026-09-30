<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0006-layered-rulesets

Modified: 2026-09-29

# Layered rulesets

This proposes three changes to what a ruleset is and how it is used.

First, the rules that decide a file come in layers. A library names the ruleset that is its
standard; a container may carry rules of its own in its `.smd`, for everything inside it; and the
rules nearest the file are tried first, so a container says only what differs and everything else
falls through to the library's rules.

Second, a ruleset has branches. A trial set of rules is a branch of the standard, used on the
ingestions the operator chooses, and promoted to be the standard when it has earned it.

Third, the silo records exactly which rules made each file, and says which files the rules would
now decide differently — out of date — and whether the source each would be re-made from can be
had.

The ruleset language itself, [rulesets](../openspec/specs/rulesets/spec.md), is unchanged: a
container's rules are written in it, and so is every branch.

## The problem

A household's rules are not one list. The same library holds a series whose DVD extras are fine at
CRF 22 and a film restoration whose extras are the reason it was bought; a season with a
commentary on every episode and another with an isolated score that must never be touched. Today
there are two ways to say so, and both are poor. A container-specific rule can be written into the
one household ruleset with conditions that pick the container out — but no fact names a container,
and the conditions that stand in for one (`kind`, `format`, a duration) catch other files by
accident. Or a second ruleset can be written for the exceptional container, copying every rule it
does not change; and when the household ruleset changes, the copy does not.

[0001-silo](Silo.md) saw this coming and deferred it: "Whether a ruleset may reference another …
Not until there are two." There are two.

The versions are a line. Every store is the next number, and every assignment that does not name a
version takes the latest. So trying a change on a few rips means storing it as the latest, where
every other ingestion picks it up too; and backing it out means storing the old document again.
There is no way to say "these rules, for these rips, until I decide."

And the record stops at the job. A job knows the ruleset version it was resolved against, which
answers "what made this file". Nothing answers the next question: now the rules have changed, which
files would they make differently — and of those, which can be made again? A household that
changes its commentary bitrate has no way to find the forty files made at the old one, except to
remember.

## What this is

**Layers.** The rules that apply to a file are a stack of layers, nearest first: the rules of the
container that holds the item, then those of its parent, and so on up the lineage, and last the
library's ruleset. For each stream the first matching rule anywhere in the stack decides, exactly as
the first matching rule in one ruleset does today. A container's rules live in its `.smd`, in a
`<rules>` element written in the ruleset language.

**A library names its standard.** Each library in `settings.json` may name a ruleset, set by
`PUT /v1/libraries/{library}/ruleset`. An assignment that names no ruleset is resolved against the
library's, at the head of its standard; on a library with none, it must name one, as today.

**Branches.** A ruleset has a `standard` branch — every version stored today is on it — and any
number of named branches, each started from a version of the standard. An assignment may name a
branch. Promoting a branch makes its head the standard's next version, and is refused unless the
branch already holds everything the standard has gained since the branch began.

**Provenance.** A job records the stack it was resolved against: the ruleset version, and for each
container layer the container and a digest of its rules, with the silo keeping every layer it has
resolved against by that digest. What made a file stays readable after the sidecar changes.

**Out of date.** A placed presentation is out of date when resolving its recorded facts against the
stack that applies now decides any stream differently from its recorded recipe. The silo keeps this
current as the rules change, and reports each out-of-date presentation with what would change and
whether its source is available: still held by the node that ripped it, gone, or ripped again.

Re-making an out-of-date presentation is not part of this proposal; see
[Non-goals](#non-goals).

## Principles

0001-silo's principles stand — the `.smd` is the truth, a decision is recorded with what it
decided, a ruleset is immutable once named. This proposal adds four of its own.

1. **The nearest rules speak first.** A container says what is different about it, and nothing
   else; what it does not decide, the rules above it do. Precedence across layers is the same rule
   as precedence within one — first match wins — so there is still only one rule to learn.
2. **What a container wants travels with the container.** A container's rules are in its `.smd`,
   so a library copied to another disk, restored from backup or handed to another silo keeps them.
   The library's standard is the silo's to keep, because it is the silo's policy, not the
   container's.
3. **Out of date is about decisions, not versions.** A file made by version 3 is not out of date
   because version 4 exists; it is out of date when version 4 would make it differently. A change
   that decides nothing differently touches no file.
4. **Nothing is re-made behind the operator's back.** The silo says what is out of date and whether
   it could be re-made. Deciding to spend an encode on it, and the source it needs, is the
   operator's.

## Vocabulary

- **Layer** — one set of rules in a stack: the library's ruleset, or a container's `<rules>`.
- **Stack** — the layers that apply to one file, nearest first: the item's container, its
  ancestors in turn, then the library's ruleset.
- **Standard** — a ruleset's `standard` branch, and the rules a library uses unless told otherwise.
- **Branch** — a named line of versions of a ruleset, started from a version of the standard.
- **Promotion** — making a branch's head the standard's next version.
- **Out of date** — a placed presentation whose stack, as it stands now, would decide one of its
  streams differently from the recipe it was made by. The operator's word for it was *dirty*; that
  word means something else to anyone who uses git, which is where branches come from.

## Layers

### A container's rules

A container's `.smd` may carry one `<rules>` element, holding rule elements exactly as a ruleset
does:

```xml
<container id="00000000000000a3" type="serial">
  <title>Pyramids of Mars</title>
  …
  <rules>
    <!-- The 2004 restoration's extras are the point; keep them whole. -->
    <video id="restoration-extras">
      <when fact="kind" ne="episode"/>
      <copy/>
    </video>
  </rules>
</container>
```

It holds rules and nothing else: no `<extraction>`, because the rip happens before the assignment
says which container a file belongs to, so only the library's ruleset can speak to it; and no
`<output>`, because the container a file is written into is one decision for a library, and a
presentation in a different container format beside its siblings is a surprise nobody asked for.
The rules apply to every item of the container and of every container below it.

A container's rules are a library fact, like its presentations: the repository file the shared
store holds carries no `<rules>`, and the sidecar puts them back. That makes this a change to the
sidecar format, which [smddb's StructuredContainers](https://github.com/project-smd/smddb) owns and
SmdKit's `SmdSidecar` reads and writes, proposed there as
[Rules in the sidecar](https://github.com/project-smd/SmdKit/pull/17) (SmdKit#16):
`Sidecar.rules` carries the element without interpreting it, in one canonical form whose bytes are
what a job's digest is taken over; an update leaves it as it stands, since a placement knows nothing
of it; and changing it is a call of its own. This proposal's first step waits on it. A placement
already keeps a hand-written `<rules>` today, because it updates the document on disk, but by
accident, and nothing can read the element.

A `<rules>` element the ruleset reader refuses is an error-severity finding on the sidecar, reported
by the walk like any other. An assignment whose stack includes it is refused, naming the container,
rather than resolved as if the layer were not there.

### The stack

An item's stack is built from its lineage, which the assignment already carries: the nearest
container's `<rules>`, as the index holds its sidecar, then each ancestor's, then the library's
ruleset — the one the assignment names, or the library's standard. A container with no sidecar yet
— the first rip of a new series — contributes no layer.

Resolution tries, for each stream, the rules of the stream's scope in the first layer in document
order, then the next layer's, and so on; the first rule that matches decides. So a container's
rules usually have no catch-all: a condition-less rule in a container's `<rules>` decides every
stream of its scope that reaches it, and the library's rules below it never speak. That is sometimes
what is meant — `<audio><copy/></audio>` in the restoration's rules says "never touch this audio" —
so it is allowed, and the reading says plainly that the layer ends its scope.

A decision records the layer its rule came from as well as the rule, since `#2` means nothing
without saying whose second rule it was: `household@7` for the library's ruleset, or the
container's id for a container's rules.

### Why not media-type layers

The operator's first sketch had overrides per container or per media type. Media type needs no
layer: `kind` is a fact every rule can test, and first-match already lets `kind`-specific rules
stand ahead of general ones in the library's ruleset. A layer per media type would be a second way to
say what a condition already says, with its own precedence to learn — which layer wins when a
featurette is in a container that has rules of its own? Containers are different: no fact names
one, which is why they need a layer.

## Branches

### The standard and its branches

Every ruleset has a `standard` branch. Every version stored today is on it, and a store with no
branch named goes on it, so nothing that stores rulesets today changes.

A branch is started from a version of the standard, which becomes its *base*, and holds versions of
its own. Version numbers stay one sequence per ruleset, across all its branches: the standard's 7
and a branch's 8 and 9 are `household@7`, `household@8` and `household@9`. So `name@version` still
names exactly one document, every job already recorded still means what it did, and a job needs no
new field to say which branch made it — the version knows. Each version records its branch and its
parent: the previous version on its branch, or the base for a branch's first.

An assignment may name a ruleset's branch; it is resolved against the branch's head, or a version
the assignment names. Which rips go to a trial branch is the operator's choice, made per assignment
— and so, in practice, the ingestion tool's to offer.

### Promotion

Promoting a branch stores its head's document as the standard's next version, recording the branch
head it came from, and closes the branch; a further trial is a new branch.

Promotion replaces; it does not merge. If the standard has gained versions since the branch's base,
promoting would silently throw them away, so it is refused, naming the versions the branch has not
taken in. The operator brings the branch up to date by storing a new version on it that includes
what the standard gained — by hand, because two edits to an ordered list of rules can merge cleanly
as text and still change which rule decides a stream — and declaring, as the store's
`upToDateWith`, the standard version it now takes in. Then promotion is a fast-forward, and nothing is lost that nobody looked at.

Before promoting, the operator can ask what it would change: every placed presentation made under
the library's standard that the branch's head would decide differently, reported exactly as an
out-of-date presentation is, with its source. That is the question "which content could be updated"
asked before the answer is committed to.

## Provenance and out-of-date presentations

### What a job records

A job records its stack: the ruleset version it resolved against, and for each container layer the
container's id and a SHA-256 digest of the `<rules>` element's canonical form. The silo keeps every
container layer it has resolved against under `rulesets/layers/<digest>.xml` in its state directory,
written once and never rewritten, so a job's rules can be read back exactly after the sidecar has
moved on — principle 4 of 0001-silo, extended to rules that live outside the silo.

### Out of date

A placed presentation is **out of date** when its job's recorded facts and feature map, resolved
against the stack that applies to it now — the current `<rules>` of its lineage and the head of the
branch the job used, or of the standard once that branch is promoted — give a recipe whose decisions
differ from the recorded recipe in any stream's action or settings, or in the output policy, or
give no recipe at all. Which rule decided a stream is not compared: a stream re-decided by a
renamed rule to the same action is not out of date.

Changes to extraction make nothing out of date. They change what the next rip keeps; a placed file
can only be made again from a new rip, and that is the operator's call.

The silo re-evaluates out-of-date-ness when the rules change: a store on a branch a placed job used,
a promotion, and a walk that finds a sidecar whose `<rules>` digest differs from the one the index
last held — for the presentations of that container and every container below it. Resolution is a
pure function of recorded facts, so this costs no file reads and no tools.

A presentation placed without a job — `silo-ctl place`, or a sidecar written by hand — has no
recorded facts or recipe, and is never reported out of date; the report counts such presentations
so the operator knows the answer is partial.

### Whether the source can be had

Each out-of-date presentation is reported with the state of its source:

- **held** — the node that holds the job's source answered for the file when last asked;
- **gone** — the node answered that the file is not there;
- **unknown** — the node has not answered since the presentation went out of date;
- **ripped again** — a job has been registered whose assignment names the same source, by the disc
  and playlist the presentation's `<source>` records, which is the natural key that survives a
  re-rip.

The silo asks a holder when a presentation goes out of date and whenever it next sees that node, and
never fetches the file to find out. An out-of-date presentation whose source is gone stays reported:
the day someone re-rips the disc, it becomes one that can be re-made.

### The report

`GET /v1/libraries/{library}/out-of-date` answers the library's out-of-date presentations, each
with its container, item and file, the job that made it and the stack it was made by, the streams
that would change — from what to what — and its source state; plus the count of presentations with
no recorded provenance. `GET /v1/rulesets/{name}/branches/{branch}/impact` answers the same shape for
the presentations a promotion would put out of date.

## What this looks like to the operator

The household's standard is `household@7`, and `films` names it. The operator decides the
commentaries are too big and starts a branch, `speech-96k`, from version 7; stores the change as
version 8 on it; and assigns the next three rips to it. The three commentaries come out at 96k,
each job recording `household@8`. The operator listens, likes them, and asks what promotion would
change: 41 presentations, each with one commentary stream going from 160k to 96k — 29 whose sources
are still held by the ripping Mac, 12 gone. They promote; the standard's version 9 is version 8's
document. The three trial files are not out of date, because version 9 decides them exactly as
version 8 did. The 41 are, and the report says which can be re-made today.

Months later the operator opens the Pyramids of Mars sidecar and adds a `<rules>` element keeping
the restoration's extras whole. At the next walk the silo notices the new digest; the two extras
already placed at CRF 22 turn out of date — sources gone, since the discs were ripped on a laptop
long since wiped. They stay on the report. When the box set comes off the shelf again and the disc
is re-ripped, they show as ripped again.

## What this asks of an implementation

Each step is a pull request, in order, and each carries its spec deltas into `openspec/` per the
corpus README — the deltas are written now, under [`specs/`](LayeredRulesets/specs/) beside this
proposal, against the corpus as the rulesets spec leaves it. The console's view of all this — the
stack, branches, promotion and the report — is [0007-rulesets](Rulesets.md)'s to design, rewritten
on this model; the draft #39 becomes it.

### 1. Layers

The `<rules>` element in the sidecar (after smddb and SmdKit carry it), the stack built from the
lineage, resolution across it, decisions naming their layer, the library's ruleset in
`settings.json`, and assignments that name no ruleset. The rulesets, recipes, library, configuration
and jobs-assignment deltas apply here.

Tests: a container's rule decides ahead of the library's, and a stream it does not match falls
through; the nearer of two containers decides; a condition-less container rule ends its scope; a
refused `<rules>` is a finding and refuses the assignment, naming the container; a decision names
its layer; an assignment naming no ruleset takes the library's standard, and one on a library with
none is refused.

### 2. Branches

Versions recording branch and parent, stores on a branch, assignments naming a branch, promotion as
a fast-forward, and the branch routes. The rulesets and read-api branch deltas apply here.

Tests: a branch's versions share the ruleset's sequence and each names its parent; a store with no
branch is on the standard; an assignment on a branch takes its head; promotion stores the head as
the standard's next version and closes the branch; promotion over versions the branch has not taken
in is refused, naming them, and succeeds once the branch declares them.

### 3. Provenance and out-of-date presentations

The stack recorded on the job, container layers kept by digest, re-evaluation on each trigger,
source states, the report and the impact route. The jobs and read-api out-of-date deltas apply here.

Tests: a job records its stack and a layer is readable by its digest after the sidecar changes; a
promotion that decides a stream differently puts its presentation out of date and one that decides
the same does not; a sidecar's new `<rules>` puts the presentations below it out of date at the
next walk; a presentation placed without a job is counted, not reported; each source state is
reported, and a registered rip with a matching source shows as ripped again; the impact of a branch
equals the report after its promotion.

## Non-goals

- **Re-making an out-of-date presentation.** Doing it means a placement that replaces a file the
  library already holds, where today a placement refuses a destination that exists — "nothing is
  overwritten" is 0001-silo's seventh principle, that conflicts are shown and never resolved, made
  concrete, and relaxing it deserves its own argument. The report is built so that the proposal which does it has everything it needs.
- **Merging branches.** Promotion is a fast-forward; bringing a branch up to date is a person's
  edit. A textually clean merge of two rule edits can change which rule decides a stream.
- **Layers for media types**, argued above: `kind` is a condition.
- **Extraction or output per container**, argued above.
- **Branches of a container's rules.** A container's rules are edited where they live, in the
  `.smd`; their history is the layers the silo has kept by digest. A household that wants to trial a
  container override does so on a branch of the library's ruleset, with a rule testing what it can.
- **One source, several presentations.** Making a full-quality and a mobile presentation from one
  rip, each resolved with its own profile, is its own proposal; `profile` is already a fact every
  layer can test, so it will compose with this one without change.

## Open questions

1. **How long jobs are kept.** Provenance and the out-of-date report both read the job store, which
   [jobs](../openspec/specs/jobs/spec.md) sizes at "tens of records, not thousands", held in memory.
   A library's placed jobs grow without bound. Either placed jobs move to a store that is read on
   demand, or a placed job is reduced to its provenance — facts, feature map, recipe, stack, source —
   and the rest discarded. The second is enough for everything here.
2. **Naming the container in a rule.** With layers there is no need for a `container` fact, and this
   proposal adds none. A household that keeps its exceptions in the library's ruleset rather than in
   sidecars — to see them all in one place — would want one; the cost is a fact that is the same for
   every stream and a second way to say what a layer says.
3. **A container's rules in the ingestion tool.** The tool assigns, so it is the natural place to
   show which layers a rip will meet. Whether it reads them from the silo or from the sidecar in its
   own clone of the data repository depends on how the tool reaches the library, which is not yet
   built.
