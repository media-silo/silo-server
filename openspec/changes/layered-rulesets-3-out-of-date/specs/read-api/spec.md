<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: The out-of-date presentations of a library are read, and so is a promotion's impact
`GET /v1/libraries/{library}/out-of-date` SHALL answer 200 with the library's out-of-date
presentations — each with its container, item, file and profile, the committed recipe that made it
and the stack it was made by, every stream that would change with what it got and what it would get,
the streams adjusted and left alone, and its binding's sources with their copies — and the count of
the library's presentations placed without a job. `GET /v1/rulesets/{name}/branches/{branch}/impact`
SHALL answer, in the same shape, the presentations that promoting the branch would put out of date,
changing nothing. Both SHALL be open, as the queue is, and a copy SHALL be rendered without its
secret. A library, ruleset or branch the silo does not hold is 404.

#### Scenario: a promotion's impact is its outcome
- **WHEN** a branch's impact is read and the branch is then promoted, with nothing else changing
- **THEN** the library's out-of-date presentations afterwards are those the impact listed

#### Scenario: presentations with no recipe are counted
- **WHEN** a library holds one presentation placed by a job and two placed without one, and the
  rules have changed so that every one of them would be made differently
- **THEN** the report lists the one, and counts two placed without a job

Pinned by: nothing yet.
