<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A placed presentation is out of date when its rules would now decide it differently
A presentation placed by a job SHALL be out of date when the facts of the committed recipe the job
ran, resolved through the stack that applies to the recipe's binding now — its lineage's current
container rules, then the head of the branch the recipe's version is on, or of the standard once
that branch is promoted — for the recipe's output, give rules' decisions that differ from the ones
the recipe recorded in any unadjusted stream's action or its settings, or give a different output
policy, or give no recipe. Which layer or rule decided a stream SHALL NOT be compared; a stream the
recipe adjusted SHALL NOT be compared; and a change to the extraction policy SHALL NOT make a
presentation out of date. The silo SHALL work this out when it is asked, from what it holds, reading
no file and running no tool. A presentation placed without a job SHALL never be out of date.

#### Scenario: a promotion that changes a decision
- **WHEN** a presentation's commentary was encoded at 160k by `household@7`, and a branch encoding
  commentaries at 96k is promoted
- **THEN** the presentation is out of date, its commentary going from 160k to 96k

#### Scenario: a promotion that changes nothing for a presentation
- **WHEN** a presentation was made on a branch by `household@8`, and the branch is promoted as
  version 9 with version 8's document
- **THEN** the presentation is not out of date

#### Scenario: a container's rules change
- **WHEN** a container's `<rules>` gains a rule copying the video of extras, and an extra below it
  was placed with its video re-encoded
- **THEN** that extra is out of date, its video going from the encode to a copy

#### Scenario: an adjusted stream
- **WHEN** a presentation's commentary was adjusted to be copied, and the rules now encode
  commentaries at 96k instead of 160k
- **THEN** the presentation is not out of date for its commentary

Pinned by: nothing yet.

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

Pinned by: nothing yet.
