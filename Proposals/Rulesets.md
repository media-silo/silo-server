<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0008-rulesets

Modified: 2026-10-09

# Rulesets in the console

This proposes that the operator read, change and try a silo's rulesets from the console. SiloAdmin
shows each ruleset the silo holds, its versions and branches, the document of any version as it was
stored, and the silo's reading of it — the rules in the order that decides between them. It changes
a ruleset by editing its document as text and storing the result as the next version, on the
standard or on a branch; it starts, tries and promotes branches; it shows and sets each library's
standard; and it shows what the background check has found out of date. Because a stored version is
forever, nothing is stored until the operator has seen the silo's verdict on the draft, how it
differs from the version it started from, and which placed presentations it would make differently.

The silo gains what the console needs for that and nothing more: the versions of a ruleset with
their branches, its reading of a document, a check that stores nothing, the impact of a draft that
stores nothing, and a store that refuses to land on a head the operator never saw.

This is the first of four proposals that make the console where a library's structure is defined:
this one, the silo's rulesets; [0009](#what-comes-next), a container's own rules; then importing and
creating containers, and proposing them to smddb. The ingestion app keeps what it ingests — sources,
bindings, jobs and placement — and works within the structure the console defines.

## The problem

A ruleset is the one thing in a silo that a household writes rather than discovers. Its routes have
grown with [0007-layered-rulesets](LayeredRulesets.md): rulesets are listed and read, stored as
versions on the standard or a branch, branches started and promoted, and a promotion's impact read
([read-api](../openspec/specs/read-api/spec.md)). The console uses none of them. Changing how a
household's commentaries are encoded means writing XML in an editor on some machine and putting it
with `curl` and the passkey, which is the one thing [0002-onboarding](Onboarding.md) arranged for
the operator never to type.

The routes are also not quite enough for a console, even once it calls them.

**The history is invisible.** The list answers each ruleset at its latest version, and the branch
list answers each branch's head; no client can say which versions exist, which branch each is on, or
what made what, without asking for them one number at a time.

**A change is judged by storing it.** A document the reader refuses is refused by the store, which is
right, but it is also the only way to find out. And a document the reader accepts can still be wrong
in the way that matters: a rule inserted above `lossless-main` that quietly takes every TrueHD track.
A branch's impact shows that, but only for a version already stored. So the way to try an edit is to
store it — on a branch, if the operator is careful — which spends a version for every keystroke worth
looking at.

**Two editors can store past each other.** A store is the next version of its branch. Two operators —
or one operator with two Macs — who each start from version 3 both store successfully, and the second
silently undoes the first. Nothing in the answer says that happened.

**Only the silo knows what a document means.** The console could link SiloKit and read the XML
itself, but then a console one release behind the silo would disagree with it about a document, and
the operator would be shown a reading of the rules that is not the one their files are made by.

## What this is

**The rulesets in the console.** For a silo it holds a passkey for, SiloAdmin lists the rulesets, and
for each shows its branches, its versions on each, the document of any version exactly as stored, the
silo's reading of it, and how many placed presentations each version made.

**A reading, from the silo.** `GET /v1/rulesets` reports every version each ruleset has, with its
branch, its parent and the presentations it made. `GET /v1/rulesets/{name}` carries the silo's
reading beside the document's bytes: the extraction policy, each rule in document order with the name
a recipe calls it by, its conditions and its action, and the outputs. The console renders the reading
and never parses XML.

**A draft is checked and its impact read, and nothing stored.** `POST /v1/rulesets/{name}/check` asks
what the silo would make of a document stored under a name — the reading, or the refusal a store
would give. `POST /v1/rulesets/{name}/impact` asks what a draft would make differently of the placed
presentations its base made, as a branch's impact does for a stored version. The console uses the one
as the operator types and the other before the store.

**A store names what it replaces.** `PUT /v1/rulesets/{name}` accepts `basedOn`, the head the draft
was made from on the branch it is stored to — zero for a name that must be new — and answers 409 when
the head is no longer that one. Without it, a store behaves as it does today.

**The rest is already there.** Branches are started, stored on and promoted by the routes 0007 added,
a promotion's impact read, a library's standard set, and its out-of-date presentations read from the
background check. The console calls them.

## Principles

0001-silo's principles stand — a decision is recorded with what it decided, and a ruleset is immutable
once named — and so do 0007's. This proposal adds four of its own.

1. **The document is the ruleset.** The console edits the text the silo stores, byte for byte, so a
   comment a person wrote by hand survives an edit made from the console. The reading is a view of the
   document, never a second place a rule can be written.
2. **The silo is the only reader.** What a document means is what the silo that will resolve against
   it says. The console shows the silo's reading, refusals and impact, and decides nothing about a
   ruleset for itself.
3. **A change is seen before it is stored.** The verdict, the difference from the base and the
   presentations the change would make differently are all in front of the operator before the button
   that stores is.
4. **History is added to, never edited.** Going back to an earlier version is storing its document as
   the next one. Nothing the console does removes, renames or rewrites a version.

## Vocabulary

- **Draft** — a document being edited in the console. It lives in the console alone, and becomes a
  version only when stored.
- **Base** — the version a draft was made from, and the branch it was on; or none, for a new ruleset.
- **Reading** — the silo's account of what a document says: its extraction policy, its rules in
  order, each with its name, conditions and action, and its outputs.

## What the silo adds

### The versions

`RulesetSummary` gains `versions`: every version of the ruleset, ascending, each with its `branch`, its
`parent`, and `presentations`, the number of placed presentations whose committed recipe names it. It
also gains `standard`, the standard's head. The existing `version` stays the latest number, so a
client that reads only it is unaffected.

### The reading

`RulesetDocument`, as `GET /v1/rulesets/{name}` answers it, gains `reading`: the document as the
silo's reader understood it. Each rule carries the name a recipe calls it by — its `id`, or `#n` for
its position — so a decision in a recipe is traced to its rule without the client counting elements;
each condition is given as the fact, the test and its value; each action as `copy`, `drop` or the
encode's settings. The reading names the ruleset by where it was stored; the `name` attribute inside
the document is what the person who wrote it typed.

### The check

`POST /v1/rulesets/{name}/check` takes a `RulesetDocument` and does everything a store would do
except store: the name is checked as a store checks it, the document read, and the answer is 200 with
the reading, or 400 with a `Problem` whose detail is the one a store of the same document would give.
It changes nothing, so it answers without a token, as the resolver's dry run does. A check and a store
agree because they are the same path with the write taken out; a check that passed a document the
store then refused would be worse than none.

### The impact of a draft

`POST /v1/rulesets/{name}/impact` takes a draft document and the version it is based on, and answers
what the background check's comparison would find if the draft were in force in place of that
version's branch: every placed presentation whose committed recipe names a version on that branch,
resolved again with the draft in the ruleset's place and the rest of its stack as it stands, and
reported as an out-of-date presentation is — the streams that would change, from what to what. A
refused document is 400, as a check would answer. It records nothing and changes nothing, and answers
without a token, as the branch impact route does.

### The store that names its base

`PUT /v1/rulesets/{name}` accepts an optional `basedOn`. When present, the store goes ahead only if
the head of the branch it is stored to is `basedOn` — or, for zero, only if the name has no version
yet — and otherwise answers 409 with a `Problem` naming the head. The comparison is made under the
lock the version number is already taken under. When `basedOn` is absent the store is today's;
`silo-ctl`, a script and a person with `curl` keep working, each storing on purpose. The console
always sends it.

## What the console shows

A with-access silo's detail gains a **Rulesets** section beside its settings, listing each ruleset by
name with its standard's head.

A ruleset opens at its standard's head, with its branches beside it, each with its base, its head,
the standard version it is up to date with, and whether it has been promoted. A version is chosen by
branch and number. Its document is shown as the silo stored it, comments and all; beside it is the
reading: the extraction policy; the rules, grouped by scope and numbered in document order within
each, because order within a scope is the only precedence there is; then the outputs. A rule is shown
by its name, its conditions one line each, and its action. A scope whose last rule has conditions is
marked as having no catch-all, since a stream that falls through it stops an application. Each
version shows how many placed presentations it made.

The **Libraries** in the settings section each show their standard, and the operator can name or
clear it. Each library also opens its **out-of-date** presentations, read from the background check:
each with its container and item, the rules that made it and the rules it was checked against, the
streams that would change, and whether its sources have copies; and how many presentations are still
to be checked.

The sections keep themselves current as the rest of the console does ([0003-refresh](Refresh.md)): a
version stored or a branch promoted from elsewhere appears without being asked for. A refresh never
touches an open draft.

## Changing, trying and promoting

**A change** starts from a version on screen, which becomes the draft's base. The draft is edited as
text. As the operator types, and a moment after they stop, the console checks the draft: the reading
beside the text follows the draft, and a refusal is shown in the silo's words in place of it. The
draft is kept by the console until it is stored or discarded, and survives the section being closed.

**Before the store** the console shows the draft against its base: the text that changed, and the
draft's impact — every placed presentation it would make differently, and how. These are not made
again; the list says what the rules in force would then say of them, which the background check will
report once the draft is stored and in force.

**The store** goes to the base's branch, to another branch, or to a new branch started from the base
when the base is on the standard — the way to try a change on a few bindings before every one meets
it. It sends `basedOn`, the head of the branch it goes to. A 201 shows the new version, and the draft
is gone. A 409 means someone stored first: the console keeps the draft, shows the version that landed
and how it differs from the base, and lets the operator re-base the draft on it — their edit made
again, by them, over the newer text — or discard it. The console does not merge: two edits to an
ordered list of rules can merge cleanly as text and still change which rule decides a stream.

**A new ruleset** starts from a copy of an existing ruleset at any version, or from the starter: the
default extraction policy, the three condition-less copy rules that decide every stream, and the
default output — the smallest ruleset an application can resolve against. The name is checked by the
silo as the draft is. A copy's `name` attribute is changed to the new name, as an edit the operator can
see in the text.

**Promotion** is offered on a branch with its impact beside it: what promoting would put out of date,
from the silo's branch impact. A refusal — the standard has gained versions the branch has not taken
in — is shown with those versions and how they differ from the branch's base, and the operator brings
the branch up to date by editing a draft on it that takes them in, stored with `upToDateWith` naming
the standard's head; then promotion is a fast-forward.

**Going back** to an earlier version is a store of that version's document, based on the head, reached
from the version on screen. It is a new version like any other, and the history reads as what
happened: version 5 is version 3 again.

## What this looks like to the operator

The household has been encoding commentaries at 160k stereo AAC, and wants 96k. From SiloAdmin the
operator opens the silo's rulesets and `household`: version 3 on the standard, which made 41 placed
presentations. They read the audio rules — `lossless-main`, `commentary`, `#5` — and edit. In the draft
they change `bitrate="160k"` to `96k`; the reading beside it follows. Before storing, the console shows
the one line that changed and, of the 41, the 12 whose commentary would be encoded at 96k. They store
it to a new branch, `speech-96k`; the producer applies that branch to the next three bindings it makes,
and the operator listens to the results. Satisfied, they promote: the impact beside the button lists
the same 12, the standard's version 5 is the branch's document, and the library's out-of-date list
fills with them as the background check works through.

A week later, from the laptop, they try a rule dropping forced subtitles and mistype the fact as
`subtitle.forcd`. The reading gives way to the silo's refusal before they reach the store. They fix
it; the impact shows three presentations would lose a stream; they discard the draft. Nothing was
stored.

## What this asks of an implementation

Each step is a pull request, in order, and each carries its spec deltas into `openspec/` per the
corpus README — the deltas are written now, one change for each step under
[`openspec/changes/`](../openspec/changes/): `rulesets-console-1-silo`,
`rulesets-console-2-reading` and `rulesets-console-3-changing`. They touch the ruleset requirements
of read-api and the silo-admin spec, and apply whether or not [#29](https://github.com/media-silo/silo-server/pull/29)
has landed first.

### 1. What the silo tells the console

`versions` and `standard` in the summary, `reading` in the document, the check route, the impact of a
draft, and `basedOn` on the store, with the OpenAPI document and SiloClient brought up to date. The
`rulesets-console-1-silo` change applies here.

Tests: the list reports every version with its branch, parent and the presentations it made; a
document's reading names its rules as a recipe does; a check answers the reading of a good document
and, for a bad document and a bad name, exactly the refusal a store gives, storing nothing either
way; a draft's impact matches what the background check reports once the draft is stored and in
force, and stores nothing; a store based on the head lands, one based on anything else is 409 naming
the head and stores nothing, zero lands only on a new name, and a store with no `basedOn` is today's;
two stores racing on one base land one 201 and one 409.

### 2. The console reads the rulesets

SiloAdminKit learns the ruleset, branch, library-standard and out-of-date routes; SiloAdmin shows the
list, the branches and versions, the document and the reading with its catch-all mark, each library's
standard, and the out-of-date presentations. The `rulesets-console-2-reading` change applies here.

### 3. The console changes them

Drafts — a change from a version, a new ruleset from a copy or the starter, a return to an earlier
version — the check as the operator types, the difference and impact before the store, the store with
its base to the standard or a branch, the 409 re-base, setting a library's standard, and promotion
with its impact and its refusal. The `rulesets-console-3-changing` change applies here. The engine's
parts are pinned by tests in SiloAdminKit; the shell stays `Pinned by: nothing yet.` until it grows a
test seam, as the settings pane does.

## What comes next

0009 does the same for a container's own rules — read, shown, changed and tried, in the same editor —
with a silo route to set them, as a binding's rules have. After it, a library's containers are
imported from smddb or created in the console, through a small smddb client in SmdKit that the
console and the ingestion app share, and proposed back to smddb from the console. The ingestion app
then works within the structure the console defines: it registers sources, makes bindings into the
containers it finds, and records its decisions as a binding's rules.

## Non-goals

- **A form for writing rules.** A form would write the XML from its fields, and so throw away the
  comments and layout a person wrote — principle 1 — and it would be a second expression of the rule
  language to keep in step with the first. The language was made small enough to read, and the
  reading beside the text is the help a person writing it needs.
- **Deleting, renaming or rewriting a version.** Recipes name versions, and every placed
  presentation's `.smd` names the version that made it.
- **Merging drafts or branches.** Textually clean is not the same as deciding the same.
- **Line numbers in a refusal.** The reader works on a parsed tree, which keeps no positions. A refusal
  names the rule, fact or attribute at fault, which is enough in a document of a few dozen lines.
- **Making out-of-date presentations again.** The console shows what is out of date and whether it can
  be made again; making it is applying the rules to its binding and making a job, which is the
  ingestion app's, and placing over an existing file is 0007's non-goal still.
- **Container and binding rules.** A container's rules are 0009's; a binding's are the ingestion app's
  last step.

## Open questions

1. **Reading without a passkey.** The ruleset routes that read are open, as the other read routes are,
   and the console shows rulesets only for a silo it holds a passkey for. A without-access silo's rules
   could be shown read-only; nothing in them is a secret.
2. **A draft kept on the Mac.** A draft lives in the console until stored. Whether a draft survives the
   app quitting, and whether two Macs should see each other's, is for when someone loses one.
