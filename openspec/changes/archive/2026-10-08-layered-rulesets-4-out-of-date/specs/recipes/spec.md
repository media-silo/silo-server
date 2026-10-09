<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A placed presentation is out of date when its rules would now decide it differently
A presentation placed by a job SHALL be out of date when the facts of the committed recipe the job
ran, resolved through the stack that applies to the recipe's binding now — its binding's rules in
force, its lineage's container rules in force, then the head of the branch the recipe's ruleset
version is on, or of the standard once that branch is promoted — for the recipe's output, give
decisions that differ from the ones the recipe recorded in any stream's action or its settings, or
give a different output policy, or give no recipe. Which layer or rule decided a stream SHALL NOT be
compared, and a change to the extraction policy SHALL NOT make a presentation out of date. A
presentation placed without a job SHALL never be checked.

#### Scenario: a promotion that changes a decision
- **WHEN** a presentation's commentary was encoded at 160k by `household@7`, and a branch encoding
  commentaries at 96k is promoted
- **THEN** the presentation is out of date, its commentary going from 160k to 96k

#### Scenario: a promotion that changes nothing for a presentation
- **WHEN** a presentation was made on a branch by `household@8`, and the branch is promoted as
  version 9 with version 8's document
- **THEN** the presentation is current

#### Scenario: a person's decision stands
- **WHEN** a presentation's first audio stream was copied by its binding's rule, and the ruleset's
  rule for that kind of stream changes from FLAC to another encode
- **THEN** the presentation is current for that stream

Pinned by: `Tests/SiloTests/CheckTests.swift` (`aPromotionThatChangesADecisionLeavesThePresentationOutOfDate`, `aPromotionThatChangesNothingForAPresentationLeavesItCurrent`, `aPersonsDecisionStandsWhenTheRulesBeneathItChange`).

### Requirement: The silo checks placed presentations in the background and records what it finds
The silo SHALL keep, for each presentation placed by a job, its latest check: the stack it was checked
against, when, and the outcome — `current`, `outOfDate` with each stream that would change and from
what to what, or `unresolvable` with the resolver's reason. A check SHALL be begun by a ruleset version
stored, a promotion, a binding's rules moved to a new version, and a walk that finds a sidecar whose
`<rules>` names another version than the index last held; and SHALL reach, for a ruleset, the placed
recipes whose ruleset version is on the changed branch, or on the standard after a promotion; for a
binding's rules, that binding's placed recipes; and for a container's, every placed recipe whose
binding's lineage holds the container. The work remaining SHALL be every presentation whose latest
check's stack is not the stack that applies to it now, so a check stopped or interrupted SHALL resume
with what is left and check nothing twice, and changes in quick succession SHALL leave one stack to
check against. A check SHALL read no media file, run no tool and change no recipe: it resolves
recorded facts through rules the silo and the library already hold.

#### Scenario: a container's rules move on
- **WHEN** a container's `<rules>` moves from version 1 to version 2, and the library is walked
- **THEN** the presentations made from bindings of items below the container are checked against
  version 2, and no other presentation is checked

#### Scenario: stopped half way
- **WHEN** a check of forty presentations is stopped after twenty, and the silo starts again
- **THEN** the twenty left are checked, and the twenty done are not checked again

Pinned by: `Tests/SiloTests/CheckTests.swift` (`aContainersRulesReachThePresentationsBelowItAndNoOthers`, `aCheckStoppedHalfWayResumesWithWhatIsLeft`, `aPromotionThatChangesADecisionLeavesThePresentationOutOfDate`).

### Requirement: An out-of-date presentation is reported with its binding's sources and their copies
Each out-of-date presentation SHALL be reported with the sources of its recipe's binding, in segment
order, each with the copies the silo records of it, and SHALL be able to be made again exactly when
every source has at least one copy. The silo SHALL ask no holder whether it still has a file. An
out-of-date presentation SHALL stay reported whatever its sources' copies.

#### Scenario: a source registered again
- **WHEN** an out-of-date presentation's only source has no copy, and a producer registers a source
  under the same natural key with a copy
- **THEN** the presentation's source is that same source, now with the copy, and it can be made
  again

Pinned by: `Tests/SiloTests/CheckTests.swift` (`aPromotionThatChangesADecisionLeavesThePresentationOutOfDate`, for the sources and their copies). A source registered again is pinned by `Tests/SiloStoreTests/SourceStoreTests.swift` (`aNaturalKeyFindsTheSourceAlreadyRegistered`), which measures that it is the same source with the copy added.
