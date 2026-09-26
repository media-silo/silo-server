<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A node mints its identity once and keeps it
`silo-node` SHALL, on a run that finds no `identity.json` in its state directory, mint a
`NodeIdentity` — an id, a lower-cased UUID, and a secret, 32 random bytes rendered as 64
lower-case hex characters by the same `FileRef.mintSecret()` the silo mints secrets with — and
write it atomically; a run that finds one SHALL reuse it. The state directory SHALL be resolved as
the silo's is, per [configuration](../configuration/spec.md), with `--state-dir` in place of
`SILO_STATE_DIR` and its own folder name: `--state-dir`, then `/Library/Application Support/Silo
Node` or `/var/lib/silo-node` running as root and `~/Library/Application Support/Silo Node` or
`$XDG_STATE_HOME/silo-node` otherwise. When
approval delivers the token, the token SHALL be written into the same `identity.json`, so a restart
neither registers a new identity nor asks for the token a second time.

#### Scenario: first run
- **WHEN** `silo-node` starts with an empty state directory
- **THEN** it writes `identity.json` holding a fresh id and secret, and registers with them

#### Scenario: later runs
- **WHEN** `silo-node` starts over a state directory an earlier run used
- **THEN** it registers with the same id and secret it minted on the first run

#### Scenario: a node beside a silo
- **WHEN** a silo and `silo-node` run as the same user on one machine with no state directory given
- **THEN** they keep their state in different folders

Pinned by: nothing yet.

### Requirement: The silo advertises itself for as long as it runs
The `silo` executable SHALL run an `Advertiser` background service which, while the advertising
setting is on — a stored setting, on by default and pinned by `SILO_ADVERTISE`, per
[configuration](../configuration/spec.md) — advertises the silo's identity name and its configured
port as `_silo._tcp` with TXT `v=1` and `id=<server-id>`; it SHALL keep the advertisement up while
the setting stays on and drop it at shutdown. The service SHALL follow the setting while the silo
runs, starting or dropping the advertisement as it changes, and SHALL re-advertise under a new name
when the silo is renamed. While the silo is in bootstrap the TXT records SHALL also carry `b=1`, so
what browses can tell a server waiting on its person from one that has one. With the setting off
the silo SHALL advertise nothing. On a machine with no Bonjour tool, or where launching one fails,
the silo SHALL log `not advertising` with the reason once and idle, never failing to boot over it.

#### Scenario: the advertisement identifies the server
- **WHEN** the silo advertises itself
- **THEN** the advertisement's name is the identity's name and its TXT records carry `v=1` and
  the server's id — and `b=1` while the silo is in bootstrap, absent once it is not

#### Scenario: the advertisement is browsable
- **WHEN** a silo is advertised under a unique name on a machine with a responder, and a browse follows
- **THEN** it is found by name, with its port and `v=1` in its TXT records

#### Scenario: advertising is off
- **WHEN** the silo boots with `SILO_ADVERTISE=false`
- **THEN** no advertisement process starts and the silo serves as usual

#### Scenario: turned off while running
- **WHEN** the operator turns advertising off on a silo that is advertising
- **THEN** the advertisement is dropped, without a restart

Pinned by: `Tests/SiloTests/NodeTests.swift` (`anAdvertisedSiloIsFound`, skipped where no responder runs). The id and `b=1` records, the setting and its live changes, and the seed name are pinned by nothing yet.
