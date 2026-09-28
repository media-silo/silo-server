<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: The console shows a silo's rulesets as the silo reads them
For a silo classified with access, SiloAdmin SHALL list the rulesets `GET /v1/rulesets`
reports, each with its latest version, and for a ruleset the operator opens SHALL show every
version it holds, and for the version shown its document exactly as the silo stored it and the
reading the silo gives of it: the extraction policy, the rules grouped by scope in document
order, each by the name a recipe calls it, and the output policy. A scope whose last rule has
conditions SHALL be marked as having no catch-all. For each version the console SHALL show how
many of the silo's jobs name it in their assignment. The console SHALL NOT read a ruleset
document itself: what it shows of a document's meaning is the silo's reading. The list SHALL
follow the console's sweep, a version stored elsewhere appearing without being asked for.

#### Scenario: a ruleset opens at its latest version
- **WHEN** the operator opens `household`, stored twice, with three jobs naming version 1
- **THEN** version 2 is shown, its document as stored and its reading beside it, with versions
  1 and 2 on offer and version 1 counted as named by three jobs

#### Scenario: a scope with no catch-all
- **WHEN** the operator opens a ruleset whose last audio rule tests `audio.lossless`
- **THEN** the audio scope is marked as having no catch-all

Pinned by: nothing yet.

### Requirement: The console changes a ruleset only by storing a draft it has shown
SiloAdmin SHALL change a silo's rulesets only by storing a draft: a new ruleset, from a copy of
a version or from the starter — the default extraction, a condition-less copy rule per scope and
the default output — or a change, whose base is the version it was made from; a return to an
earlier version SHALL be a draft of that version's document, based on the latest. A draft SHALL
be edited as the document's text, and SHALL be checked with `POST /v1/rulesets/{name}/check` as
it changes, the reading shown following the draft and a refusal shown in the silo's words. Before
the store, the console SHALL show the draft's difference from its base, and, for up to fifty of
the newest jobs whose assignment names the ruleset, each stream whose deciding rule or action
under the draft differs from the job's recorded recipe, and each stream the draft decides
nowhere. The store SHALL send the draft with `basedOn` — its base, or 0 for a new ruleset. On a
409 the console SHALL keep the draft, show the version that landed and its difference from the
base, and offer to re-base the draft or discard it, and SHALL NOT merge. The console SHALL NOT
delete, rename or rewrite a version.

#### Scenario: a change is previewed against the jobs
- **WHEN** the operator changes `household`'s `commentary` bitrate from `160k` to `96k` in a
  draft based on the latest version, and twelve of its jobs' streams are commentaries
- **THEN** before the store the console shows the one changed line and the twelve streams, each
  decided by `commentary` before and after, now at 96k

#### Scenario: a refused draft is named before the store
- **WHEN** the operator types a rule testing `subtitle.forcd`
- **THEN** the silo's refusal is shown in place of the reading, and nothing has been stored

#### Scenario: someone stored first
- **WHEN** a draft based on version 3 is stored after another console stored version 4
- **THEN** the silo answers 409, the draft is kept, and version 4 is shown with its difference
  from version 3

#### Scenario: going back is a new version
- **WHEN** the operator returns `household`, at version 4, to version 3
- **THEN** version 3's document is stored as version 5, based on 4

Pinned by: nothing yet.
