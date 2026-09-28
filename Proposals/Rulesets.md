<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0006-rulesets

Modified: 2026-09-28

# Rulesets

This proposes that the operator read, add and change a silo's rulesets from the console. SiloAdmin
shows each ruleset the silo holds, every version of it, the document as it was stored and the
silo's reading of that document — the rules in the order that decides between them. It adds a
ruleset by copying one or from a starter that decides every stream, and changes one by editing its
document as text and storing the result as the next version. Because a stored version is forever,
nothing is stored until the operator has seen three things: the silo's verdict on the draft, how it
differs from the version it started from, and which decisions it would change on files the silo has
already been asked to encode. The silo gains what the console needs for that and nothing more: the
versions it holds, its reading of a document, a check that stores nothing, the resolver run against
a draft, and a store that refuses to land on a version the operator never saw.

## The problem

A ruleset is the one thing in a silo that a household writes rather than discovers. The routes for
it have existed since [0001-silo](Silo.md): `GET /v1/rulesets` lists the rulesets at their latest
versions, `GET /v1/rulesets/{name}` returns a document, `PUT` stores a new version, and
`POST /v1/rulesets/{name}/resolve` runs the resolver as a dry run
([read-api](../openspec/specs/read-api/spec.md)). The console uses none of them. Changing how a
household's commentaries are encoded means writing XML in an editor on some machine, then putting it
with `curl` and the passkey, which is the one thing [0002-onboarding](Onboarding.md) arranged for
the operator never to type.

The routes are also not quite enough for a console, even once it calls them.

**The history is invisible.** Every store is a new version and a version is never rewritten, which
is what lets a job say which rules made its file. But the list answers only the latest version of
each ruleset, so no client can say which versions exist without asking for them one number at a
time until one is missing.

**A change is judged by storing it.** A document the reader refuses is refused by the store, which
is right, but it is also the only way to find out. And a document the reader accepts can still be
wrong in the way that matters: a rule inserted above `lossless-main` that quietly takes every TrueHD
track. The dry run would show that, but only against a stored version. So the way to try a change is
to store it, which spends a version number that no job will ever name and leaves the history
cluttered with experiments nobody meant to keep.

**Two editors can store past each other.** A store is always the latest plus one. Two operators — or
one operator with two Macs — who each start from version 3 both store successfully, as 4 and 5, and
5 silently undoes 4. Nothing in the answer says that happened.

**Only the silo knows what a document means.** The console could link `SiloKit` and read the XML
itself, but then a console one release behind the silo would disagree with it about a document —
refusing a fact the silo knows, or accepting a format the silo would refuse — and the operator would
be shown a reading of the rules that is not the one their files are encoded by.

## What this is

**The rulesets in the console.** For a silo it holds a passkey for, SiloAdmin lists the rulesets,
and for each shows its versions, the document of any version exactly as stored, the silo's reading
of it, and how many of the silo's jobs name that version.

**A reading, from the silo.** `GET /v1/rulesets` reports every version each ruleset has.
`GET /v1/rulesets/{name}` carries the silo's reading of the document beside its bytes: the
extraction policy, each rule in document order with the name a recipe calls it by, its conditions and
its action, and the output policy. The console renders the reading and never parses XML.

**A draft is checked and tried, not stored.** `POST /v1/rulesets/{name}/check` asks the silo what it
would make of a document stored under a name — the reading, or the refusal a store would give — and
stores nothing. `POST /v1/rulesets/{name}/resolve` also accepts a document in place of a stored
version. The console uses the one as the operator types and the other to show, before storing, what
the draft would decide differently on the files the silo's jobs recorded.

**A store names what it replaces.** `PUT /v1/rulesets/{name}` accepts `basedOn`, the version the
draft was made from — zero for a name that must be new — and answers 409 when the latest version is
no longer that one. Without it, a store behaves as it does today.

## Principles

0001-silo's principles stand — a decision is recorded with what it decided, and a ruleset is
immutable once named. This proposal adds four of its own.

1. **The document is the ruleset.** The console edits the text the silo stores, byte for byte, so a
   comment a person wrote by hand survives an edit made from the console. The reading is a view of
   the document, never a second place a rule can be written.
2. **The silo is the only reader.** What a document means is what the silo that will resolve against
   it says it means. The console shows the silo's reading and the silo's refusals, and decides
   nothing about a ruleset for itself.
3. **A change is seen before it is stored.** A stored version is kept for as long as the silo is, so
   the time to find a mistake is before the store: the verdict, the difference from the base
   version, and the decisions that change are all in front of the operator before the button that
   stores is.
4. **History is added to, never edited.** Going back to an earlier version is storing that version's
   document as the next one. Nothing the console does removes, renames or rewrites a version.

## Vocabulary

- **Draft** — a document being edited in the console. It lives in the console alone, and becomes a
  version only when stored.
- **Base** — the version a draft was made from, or none for a draft of a new ruleset.
- **Reading** — the silo's account of what a document says: its extraction policy, its rules in
  order, each with its name, conditions and action, and its output policy.

## What the silo adds

### The versions

`RulesetSummary` gains `versions`: every version the silo holds of the ruleset, ascending. The
existing `version` stays, and stays the latest, so a client that reads only it is unaffected.

### The reading

`RulesetDocument`, as `GET /v1/rulesets/{name}` answers it, gains `reading`: the document as the
silo's reader understood it. Each rule carries the name a recipe calls it by — its `id`, or `#n` for
its 1-based position when it has none — so a decision in a recipe can be traced to the rule in the
reading without the client counting elements. The reading also carries the name and version the
ruleset is known by, which are where the silo found it; the `name` and `version` attributes inside
the document are what the person who wrote it typed, and the silo has never read them as anything
more ([index-and-rulesets](../openspec/specs/index-and-rulesets/spec.md)).

`reading` is left out of a store's answer. The store answers the version it assigned; a client that
wants the reading asks for it, and a store's answer stays the size of the request.

### The check

`POST /v1/rulesets/{name}/check` takes a `RulesetDocument` and does everything a store would do
except store: the name is checked as a store checks it, the document is read, and the answer is 200
with the reading, or 400 with a `Problem` whose detail is the one a store of the same document would
have given. It changes nothing, so it answers without a token, as the resolver's dry run does.

A check and a store agree because they are the same code path with the write taken out. That is the
point of the route; a check that could pass a document the store then refused would be worse than
none.

### The resolver against a draft

`ResolveRequest` gains an optional `document`. When present, the facts are resolved against that
document, read as the check reads it, instead of a stored version; the recipe's `ruleset` names the
ruleset with no version, since the draft has none. A document the reader refuses is 400, as a check
would answer, and a `version` query alongside a document is 400, since the two name different
rulesets. The route stays a dry run: nothing is stored.

The facts to resolve against are the ones the silo already recorded. Every assigned job carries the
facts it was resolved from, its feature map and the recipe it got. So the question "what would this
change" is answerable without a file in hand: resolve the draft against each job's facts and compare
the result with the recipe the job recorded. That comparison is the console's; the silo supplies the
parts.

### The store that names its base

`PUT /v1/rulesets/{name}` accepts an optional `basedOn` in its body. When present, the store goes
ahead only if the name's latest version is `basedOn` — or, for zero, only if the name has no version
yet — and otherwise answers 409 with a `Problem` naming the latest version. The comparison is made
under the lock the version number is already taken under, so there is no moment between the check and
the write for another store to land in.

When `basedOn` is absent the store is today's: the next version, whatever came before. `silo-ctl`, a
script, and a person with `curl` keep working, and each of them is storing on purpose. The console
always sends it.

## What the console shows

A with-access silo's detail gains a Rulesets section beside its settings. It lists each ruleset by
name with its latest version, and selecting one opens it.

A ruleset opens at its latest version, with a picker for the others. Its document is shown as the
silo stored it, comments and all. Beside it is the reading: the extraction policy; then the rules,
grouped by scope and numbered in document order within each, because order within a scope is the
only precedence there is and the grouping is how a person asks "what decides audio"; then the output
policy. A rule is shown by its name, its conditions as one line each, and its action. A scope whose
last rule has conditions is marked as having no catch-all, since a stream that falls through it will
stop a job.

For each version, the console counts the jobs whose assignment names it, from the jobs it can
already list. "Version 3 — named by 41 jobs" is what tells the operator that changing a rule changes
nothing already encoded, and that version 3 is still what those files were made by.

The section keeps itself current as the rest of the console does
([0003-refresh](Refresh.md)): the list follows the console's sweep, and a version stored from
elsewhere appears without being asked for. It never touches an open draft.

## Adding and changing

**A new ruleset** starts from a copy of an existing ruleset at any version, or from the starter: the
default extraction policy, the three condition-less copy rules that decide every stream, and the
default output — the smallest ruleset a job can be resolved against. The operator names it; the name
is checked by the silo as the draft is. When the draft is a copy, the console changes the copy's
`name` attribute to the new name, as an edit the operator can see in the text, so the document
stored says what it is.

**A change** starts from the version on screen, which becomes the draft's base. The draft is edited
as text. As the operator types, and a moment after they stop, the console checks the draft: the
reading beside the text follows the draft, and a refusal is shown in the silo's words in place of it.
The draft is kept by the console until it is stored or discarded, and survives the section being
closed.

**Before the store**, the console shows the draft against its base: the text that changed, and the
decisions that would. For the jobs whose assignment names this ruleset, newest first, up to fifty,
it resolves the draft against each job's recorded facts and feature map and lists every stream whose
deciding rule or action differs from the job's recorded recipe — the job, the stream, and what it got
against what it would get now. A stream the draft decides nowhere is listed the same way, as the
error a job would meet. These jobs are not re-encoded; the list says what the next such file would
get, which is the question a person changing a rule is asking.

**The store** sends the draft with its base. A 201 shows the new version, and the draft is gone. A
409 means someone stored first: the console keeps the draft, shows the version that landed in the
meantime and how it differs from the base, and lets the operator re-base the draft on it — their
edit made again, by them, over the newer text — or discard it. The console does not merge. A merge
of two edits to an ordered list of rules can be textually clean and still reorder what decides a
stream.

**Going back** to an earlier version is a store of that version's document, based on the latest,
reached from the version picker. It is a new version, shown and counted like any other, and the
history reads as what happened: version 5 is version 3 again.

## What this looks like to the operator

The household has been encoding commentaries at 160k stereo AAC, and wants 96k. From SiloAdmin the
operator opens the silo's rulesets and `household`: version 3, named by 41 jobs. They read the audio
rules — `lossless-main`, `commentary`, `#5` — and choose to edit. In the draft they change
`bitrate="160k"` to `96k`; the reading beside it follows. Before storing, the console shows the one
line that changed and, of the 41 jobs, the 12 commentary streams that would now be encoded at 96k,
each by `commentary` as before. They store; the silo answers version 4. The next commentary a node
claims is made by version 4, and each of the 41 jobs still names version 3, because that is what
made its file.

A week later, from the laptop, they try a rule dropping forced subtitles and mistype the fact as
`subtitle.forcd`. The reading gives way to the silo's refusal — not a fact a rule can test — before
they reach the store. They fix it; the preview shows that three jobs would lose a stream; they decide
against it and discard the draft. Nothing was stored, and the history still ends at version 4.

## What this asks of an implementation

Each step is a pull request, in order, and each carries its spec deltas into `openspec/` per the
corpus README — the deltas are written now, under [`specs/`](Rulesets/specs/) beside this proposal.
They touch only the ruleset requirements, so they apply as written whether or not
[0005-libraries](Libraries.md) has landed first.

### 1. What the silo tells the console

`versions` in the summary, `reading` in the document, the check route, a draft document in the
resolver's request, and `basedOn` on the store, with the OpenAPI document and SiloClient brought up
to date. The read-api and index-and-rulesets deltas apply here.

Tests: the list reports every version; a document's reading names its rules as the recipe does,
`#n` for the unnamed, and names the ruleset by where it was stored whatever its attributes say; a
check answers the reading of a good document and, for a bad document and a bad name, exactly the
refusal a store gives, storing nothing either way; a draft resolves as `name` with no version, a
refused draft is 400 and a draft with a `version` query is 400; a store based on the latest lands, a
store based on anything else is 409 naming the latest and stores nothing, zero lands only on a new
name, and a store with no `basedOn` behaves as today; two stores racing on one base land one 201 and
one 409.

### 2. The console reads the rulesets

SiloAdminKit learns the ruleset routes and the jobs that name each version; SiloAdmin shows the list,
the versions, the document and the reading, and marks a scope with no catch-all. The first silo-admin
delta applies here.

### 3. The console changes them

Drafts — new from a copy or the starter, a change from a version, a return to an earlier one — the
check as the operator types, the preview against the jobs, the store with its base, and the 409
re-base. The second silo-admin delta applies here. The engine's parts — the preview's comparison of
recipes and the store's refusal — are pinned by tests in SiloAdminKit; the shell stays
`Pinned by: nothing yet.` until it grows a test seam.

## Non-goals

- **A form for writing rules.** A form would write the XML from its fields, and so throw away the
  comments and layout a person wrote — principle 1 — and it would be a second expression of the rule
  language to keep in step with the first, which 0001-silo's second principle refuses. The rule
  language was made small enough to read — seven operators, three actions, no "or" and no nesting —
  and the reading beside the text is the help a person writing it needs.
- **Deleting, renaming or rewriting a version.** Jobs name versions, and a placed file's recipe names
  its ruleset. A ruleset no longer wanted is simply not named by new assignments.
- **Merging drafts.** For the reason above: textually clean is not the same as deciding the same.
- **Line numbers in a refusal.** The reader works on a parsed tree, which does not keep where each
  element was. A refusal names the rule, fact or attribute at fault, which is enough to find it in a
  document of a few dozen lines.
- **Re-encoding what a change would change.** The preview says what the next such file would get.
  Re-making a placed file is a new job, asked for by a person, and no part of this proposal.
- **The ingestion tool's view of rulesets.** It reads a ruleset's extraction policy; it does not edit
  rulesets, and does not need to.

## Open questions

1. **Which ruleset is the silo's.** 0001-silo says the ingestion tool reads the extraction policy
   "from the silo's active ruleset", but no silo names one: an assignment names its ruleset, and a
   tool has nothing to ask for before it has one. A `defaultRuleset` would be a setting an operator
   route changes, so by 0004-configuration's rule it belongs in `settings.json`, and the console would
   mark it in this section. It is left to the proposal that builds the tool's registration, which is
   where the question is first asked.
2. **How many jobs the preview reads.** Fifty of the newest is enough to see a pattern on a household
   library and cheap to resolve; a change that only matters to an old DVD rip may not show in it. A
   filter — by kind, or by format — may prove more useful than a larger number.
3. **Reading without a passkey.** The ruleset routes that read are open, as the other read routes
   are, and the console shows rulesets only for a silo it holds a passkey for. A without-access silo's
   rules could be shown read-only; nothing in them is a secret. Whether that is worth a second shape
   of the section is a question for when someone asks for it.
