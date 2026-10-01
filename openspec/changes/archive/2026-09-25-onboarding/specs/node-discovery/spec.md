<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The silo advertises itself for as long as it runs
The `silo` executable SHALL run an `Advertiser` background service which, when `SILO_ADVERTISE`
is true — the default — advertises the silo's configured port as `_silo._tcp`, under the name
from its server identity, with TXT `v=1` and `id=<server-id>`; while the silo is in bootstrap the
TXT SHALL also carry `b=1`, and a configured silo SHALL carry no `b` key. The advertised name SHALL
track the identity's name, so a rename at setup changes the advertisement rather than requiring a
restart. It SHALL keep the advertisement up for the life of the process and drop it at shutdown.
`SILO_ADVERTISE=false` SHALL advertise nothing. On a machine with no Bonjour tool, or where
launching one fails, the silo SHALL log `not advertising` with the reason once and idle, never
failing to boot over it.

#### Scenario: the advertisement identifies the server
- **WHEN** a bootstrap silo is advertised under a unique name on a machine with a responder, and
  a browse follows
- **THEN** it is found by name, with its port and `v=1`, `id` equal to the minted ServerID, and
  `b=1` in its TXT records — and once setup completes, a fresh browse finds the same `id`, the
  new name, and no `b` key

#### Scenario: advertising is off
- **WHEN** the silo boots with `SILO_ADVERTISE=false`
- **THEN** no advertisement process starts and the silo serves as usual

Pinned by: nothing yet.
