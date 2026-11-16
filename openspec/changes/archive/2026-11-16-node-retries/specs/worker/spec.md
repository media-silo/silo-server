<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A request lost in transport is sent again, waiting longer each time
A request the worker or silo-node sends SHALL be sent again when it is lost in transport — the silo
unreachable, or the connection lost before its answer — after a wait of one second, doubling with
each retry to at most thirty, each wait drawn at random from the upper half of its delay. An answer
from the silo, a refusal among them, SHALL NOT be sent again, nor SHALL a request cancelled on
purpose. A progress report lost in transport SHALL be sent again while the encode runs on, until the
lease the last answered report renewed would lapse, two minutes after it; a retry that would wait
past then SHALL NOT be made, and the encode SHALL end with the transport's error. A completion lost in
transport SHALL be sent again for up to an hour, and once given up SHALL NOT be followed by a fail:
the encode is good, and the job is the silo's to reclaim when its lease lapses. The node inside the
silo speaks to it without a transport, and has nothing to send again.

#### Scenario: a report is lost while the encode runs
- **WHEN** a progress report is lost in transport while an encode runs
- **THEN** the encode runs on, the report is sent again, and the job is completed as if none was lost

#### Scenario: the reports are lost past the lease
- **WHEN** every progress report is lost in transport for longer than the job's lease
- **THEN** the encode ends and the job is failed

#### Scenario: a completion's answer is lost
- **WHEN** the silo makes a completion and its answer is lost in transport
- **THEN** the completion is sent again, the silo answers it as made, and the job is encoded once

#### Scenario: a completion is never answered
- **WHEN** a completion is lost in transport for longer than it is sent again
- **THEN** no fail is sent, and the job is left for the silo to reclaim

#### Scenario: a refusal is the answer
- **WHEN** the silo refuses a request
- **THEN** the refusal is not sent again

Pinned by: `Tests/SiloTests/BackoffTests.swift` (`aTransportErrorIsSentAgainWaitingLongerEachTime`,
`anAnswerIsNotSentAgain`, `aRetryThatWouldWaitPastTheDeadlineIsNotMade`, `aCancelEndsTheWaiting`),
`Tests/SiloTests/WorkerRetryTests.swift` (`aReportOrACompletionLostInTransportIsSentAgain`,
`reportsLostPastTheLeaseEndTheEncode`, `aCompletionNeverAnsweredIsNotTurnedIntoAFail`).

## MODIFIED Requirements

### Requirement: The loop polls every few seconds and rides out its errors
The loop SHALL run until it is cancelled: after a pass that found no work, and after any thrown
error, it SHALL sleep the poll interval — five seconds by default, `silo-node --poll` seconds on
the command line — and go on, the error logged rather than raised. A failure inside the one job a
pass holds SHALL be reported to the silo by `fail` with the reason — `cancelled` when the stop
came from outside or from the silo — and SHALL not keep the loop from the next claim, except a
completion never answered, which is logged and not failed. The fail report's own failure SHALL be
swallowed: the job is the silo's to reclaim when the lease lapses.

#### Scenario: a dead ffmpeg does not kill the node
- **WHEN** an encode throws
- **THEN** the job is failed with the error's description, the error is logged, and the loop
  sleeps the poll interval and claims again

Pinned by: nothing yet.
