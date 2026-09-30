<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: An assignment lands the job pending, facts merged and recipe resolved
`PUT /v1/jobs/{id}/assignment` SHALL take an assignment — the library, the item's container
lineage as repository documents, the item, the optional alternative and profile, the feature map,
the chapters, and optionally the ruleset by name, with an optional branch or version — and SHALL
refuse, before any resolution, with 404 for an unknown job; 409 for a job not `unassigned`,
`pending` or `failed`; and 400 with the reason when the job carries no probe, the library is
unknown to the silo, the assignment names no ruleset and the library has none, the ruleset, branch
or version does not exist, the branch is closed, a container document cannot be read, a container
of the lineage has `<rules>` the reader refuses (naming the container), the item is not in the
last container, or the feature map names a feature that container does not have. An audio stream a
feature is mapped to SHALL take its role from that feature: `commentary` for a commentary,
`isolatedMusic` for isolated music, `other` otherwise. Facts SHALL then be merged from the probe,
the origin scan and the assignment, and the recipe resolved against the item's stack: the
lineage's container rules as the index holds their sidecars, then the ruleset the assignment
names, or the library's — at the version named, else the head of the branch named, else the head
of the standard. A stream no rule decides SHALL be 422, the resolver's report as given. On success
the job SHALL become `pending` with the assignment stored naming the ruleset version actually
resolved, the stack recorded, the facts and recipe recorded, the `requirements` set to the recipe's
encoders sorted, and any failure, lease and progress cleared.

#### Scenario: the household ruleset against an episode
- **WHEN** the source file of an episode with a main mix and a mapped commentary is assigned against the
  `household` ruleset, whose first version encodes lossless main mixes as FLAC and commentaries as
  AAC, in a lineage with no container rules
- **THEN** the job is `pending`, its audio roles are `[.main, .commentary]` (the feature map
  decides; the stream's title alone is only a hint), its requirements are `["aac", "flac"]`, and
  its stored assignment names ruleset version 1

#### Scenario: a stream no rule decides
- **WHEN** the same job is assigned against a ruleset that decides no audio
- **THEN** the answer is 422

#### Scenario: the library's standard
- **WHEN** a source file is assigned into library `films`, whose ruleset is `household` with standard head
  7, naming no ruleset
- **THEN** it is resolved against `household@7`, and its stored assignment names version 7

#### Scenario: no ruleset anywhere
- **WHEN** a source file is assigned into a library with no ruleset, naming none
- **THEN** the answer is 400, and the job stays as it was

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromRegisteredToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`);
the stack and the library's standard are pinned by nothing yet.

## ADDED Requirements

### Requirement: A job records the stack it was resolved against
An assigned job SHALL record its stack: the library ruleset's `name@version`, and for each
container layer, nearest first, the container's id and the SHA-256 digest of its `<rules>`
element's canonical form, as SmdKit's `SidecarRules` holds it. The silo SHALL keep each container layer it resolves against at
`rulesets/layers/<digest>.xml` in its state directory, written once and never rewritten, so a
job's rules can be read back after its sidecar has changed.

#### Scenario: a layer outlives its sidecar
- **WHEN** a job is resolved against a container's rules, and the container's `<rules>` is then
  edited
- **THEN** the job's stack still names the first digest, and the layer stored under it is the rules
  the job was resolved against

Pinned by: nothing yet.

### Requirement: A placed presentation is out of date when its stack would now decide it differently
A presentation placed by a job SHALL be out of date when the job's recorded facts and feature map,
resolved against its stack as it now stands — its lineage's current container rules, and the head
of the branch its version is on, or of the standard once that branch is promoted — give a recipe
that differs from the recorded one in any stream's action or its settings, or in the output policy,
or give no recipe. Which rule decided a stream SHALL NOT be compared, and a change to the extraction
policy SHALL NOT make a presentation out of date. The silo SHALL re-evaluate the presentations a
change can reach when it happens: a store on the branch a job's version is on, a promotion, and a
walk that finds a container's `<rules>` digest changed, for that container and every container
below it. A presentation placed without a job SHALL never be out of date.

#### Scenario: a promotion that changes a decision
- **WHEN** a presentation's commentary was encoded at 160k by `household@7`, and a branch encoding
  commentaries at 96k is promoted
- **THEN** the presentation is out of date, its commentary going from 160k to 96k

#### Scenario: a promotion that changes nothing for a file
- **WHEN** a presentation was made on the branch by `household@8`, and the branch is promoted as
  version 9 with version 8's document
- **THEN** the presentation is not out of date

#### Scenario: a container's rules change
- **WHEN** a container's `<rules>` gains a rule copying the video of extras, and an extra below it
  was placed with its video re-encoded
- **THEN** at the next walk that extra is out of date

Pinned by: nothing yet.

### Requirement: An out-of-date presentation reports whether its source can be had
Each out-of-date presentation SHALL carry the state of its source: `held` when the node holding the
job's source last answered that it has the file, `gone` when it answered that it has not,
`unknown` when it has not answered since the presentation went out of date, and `ingestedAgain`,
naming the job, when a job has been registered whose assignment names the same source reference as
the presentation's `<source>` — today a disc and playlist, the only one the sidecar records. A
presentation with no source reference SHALL never be `ingestedAgain`. The silo SHALL ask the holder when a presentation goes out of date and whenever it next
sees that node, and SHALL NOT fetch the file to find out. An out-of-date presentation SHALL stay
reported whatever its source's state.

#### Scenario: the origin is ingested again
- **WHEN** an out-of-date presentation's source file is `gone`, and a new source file is
  registered and assigned naming the same disc and playlist
- **THEN** the presentation's source is `ingestedAgain`, naming the new job

Pinned by: nothing yet.
