<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## RENAMED Requirements

- FROM: `### Requirement: The tool registers a rip the moment it finishes`
- TO: `### Requirement: A producer registers a mezzanine with its input spec`
- FROM: `### Requirement: An assignment lands the job pending, facts merged and recipe resolved`
- TO: `### Requirement: An assignment lands the job pending, facts derived and recipe resolved`

## MODIFIED Requirements

### Requirement: A producer registers a mezzanine with its input spec
`POST /v1/jobs` with a body of the mezzanine's `segments` and its input spec SHALL create the job
as `unassigned` and answer 201 with it. A body without an input spec, or with one the silo refuses
as [input-specs](../input-specs/spec.md) describes, or with no segment or more than one, SHALL be
400 with the reason, and create nothing. The silo SHALL NOT probe the mezzanine or accept any other description of it. The
route SHALL be behind the operator's token: a request without it gets 401.

#### Scenario: registration over HTTP
- **WHEN** a client posts a mezzanine and its input spec to `/v1/jobs` without a token, then again
  with `Authorization: Bearer <operator token>`
- **THEN** the first answer is 401 and the second is 201 with the job, `unassigned`

#### Scenario: a registration without a description
- **WHEN** a client posts a mezzanine's segment with no input spec
- **THEN** the answer is 400, and no job is created

#### Scenario: a mezzanine across two files
- **WHEN** a client posts a mezzanine of two segments and an input spec
- **THEN** the answer is 400, saying a mezzanine holds one segment, and no job is created

Pinned by: `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`); the refusals are pinned by nothing yet.

### Requirement: An assignment lands the job pending, facts derived and recipe resolved
`PUT /v1/jobs/{id}/assignment` SHALL take an assignment — the library, the item's container
lineage as repository documents, the item, the optional alternative and profile, the feature map,
the chapters, the ruleset by name with an optional version, and optional adjustments — and SHALL
refuse, before any resolution, with 404 for an unknown job; 409 for a job not `unassigned`,
`pending` or `failed`; and 400 with the reason when the library is unknown to the silo, the
ruleset version does not exist, a container document cannot be read, the item is not in the last
container, or the feature map names a feature that container does not have. An audio stream a
feature is mapped to SHALL take its role from that feature: `commentary` for a commentary,
`isolatedMusic` for isolated music, `other` otherwise. Facts SHALL then be derived from the job's
input spec and the assignment, the recipe resolved against the stored ruleset — its latest version
unless the assignment names one — and the assignment's adjustments applied to it, as
[recipes](../recipes/spec.md) describes. A stream no rule decides SHALL be 422, the resolver's
report as given, and an adjustment the resolver refuses SHALL be 400 naming it. On success the job
SHALL become `pending` with the assignment stored naming the ruleset version actually resolved, the
facts and the adjusted recipe recorded, the `requirements` set to the recipe's encoders sorted, and
any failure, lease and progress cleared.

#### Scenario: the household ruleset against an episode
- **WHEN** a mezzanine whose input spec holds a main mix and an unmarked second audio stream is
  assigned against the `household` ruleset, whose first version encodes lossless main mixes as
  FLAC and commentaries as AAC, with the second stream mapped to a commentary feature
- **THEN** the job is `pending`, its audio roles are `[.main, .commentary]` (the feature map
  decides), its requirements are `["aac", "flac"]`, and its stored assignment names ruleset
  version 1

#### Scenario: a stream no rule decides
- **WHEN** the same job is assigned against a ruleset that decides no audio
- **THEN** the answer is 422

#### Scenario: an adjustment recorded
- **WHEN** the same job is assigned with an adjustment giving its main mix `copy` and the note
  "keep the Atmos object track"
- **THEN** the job is `pending`, its recipe copies the main mix and records that the rule chose
  FLAC and the note, and its requirements are `["aac"]`

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromRegisteredToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`); adjustments are pinned by nothing yet.

## REMOVED Requirements

### Requirement: The job record carries the whole of a file's way to one presentation
**Reason**: The record carried the probe and MakeMKV facts a job was registered with, which the
silo no longer receives; a job now carries the input spec its producer registered.
**Migration**: The requirement added below, "The job record carries the whole of a mezzanine's way
to one presentation", states the record with the input spec in their place.

## ADDED Requirements

### Requirement: The job record carries the whole of a mezzanine's way to one presentation
A job SHALL have an `id` (a lowercased UUID by default), a `state` of exactly one of `unassigned`,
`pending`, `claimed`, `encoding`, `encoded`, `placing`, `placed`, `failed`, `cancelling`,
`cancelled`, `createdAt` and `updatedAt` timestamps (`updatedAt` refreshed on every change), the
mezzanine's `segments` — a list of file references, whose media joined in order the input spec's
streams describe, and which for now holds exactly one — the `input` spec the producer registered
it with, and
then everything the queue learns: the `assignment`, its adjustments among it, the derived `facts`,
the resolved `recipe`, the `requirements` (the encoders the recipe needs), the `attempts`, the
current `lease`, the latest `progress`, the `output` file reference, the `result`, the `placement`
summary, and the `failure` reason. A file reference SHALL carry its `holder` (the node the file is
on), its `url`, the holder's own `path` for opening locally, its `sizeBytes`, and the `secret` that
guards it. An attempt SHALL record its node, when it started and ended, and an outcome of `lost`,
`failed`, `cancelled` or `encoded`. A lease SHALL name a node and when it expires. A job is
*active* in exactly the states `claimed`, `encoding` and `cancelling`. While a mezzanine holds
exactly one segment, a job's *source*, wherever a requirement speaks of one, SHALL be that
segment's file reference.

#### Scenario: a freshly registered mezzanine
- **WHEN** a producer registers a mezzanine with one segment and its input spec
- **THEN** the job is `unassigned` with a lowercased UUID id, the segment and input spec as given,
  and no assignment, facts, recipe, requirements, attempts, lease, progress, output, result,
  placement or failure

Pinned by: `Tests/SiloTests/JobTests.swift` (`aJobGoesFromRegisteredToPlaced`), `Tests/SiloTests/ServerTests.swift` (`yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI`).
