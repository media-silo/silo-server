<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A placed presentation is out of date when its rules would now decide it differently
A presentation placed by a job SHALL be out of date when the facts of the committed recipe the job
ran, resolved through the stack that applies to the recipe's binding now — its binding's rules in
force, its lineage's container rules in force, then the head of the branch the recipe's ruleset
version is on, or of the standard once that branch is promoted — for the recipe's output, give
decisions that differ from the ones the recipe recorded in any stream's action or its settings, or
give a different output policy, or give no recipe. Which layer or rule decided a stream SHALL NOT be
compared. A
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
