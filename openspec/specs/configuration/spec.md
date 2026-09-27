<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Configuration

## Purpose

Where a silo's configuration lives and who may change it. The silo resolves its state directory
from `SILO_STATE_DIR` or, absent it, a well-known place on the machine, because a silo is a daemon
and one silo per machine is the expected case; the working directory plays no part. This spec covers
that resolution, which `silo-node` shares under its own variable and folder name.

Rationale: [Configuration proposal](../../../Proposals/Configuration.md) — the state directory is the silo's identity and where filesystem recovery happens, so it needs a home the operator can find.
Documentation: [README](../../../README.md).

## Requirements

### Requirement: The state directory resolves to a known place on the machine
The silo SHALL resolve its state directory once, at boot, before anything reads it: from
`SILO_STATE_DIR` when it is set and not empty, a relative value keeping its meaning against the
working directory; otherwise from the platform default. The default SHALL be decided by the
effective user id: running as root, `/Library/Application Support/Silo` on macOS and
`/var/lib/silo` on Linux; running as anyone else, `~/Library/Application Support/Silo` on macOS and
`$XDG_STATE_HOME/silo` on Linux, `XDG_STATE_HOME` defaulting to `~/.local/state`. Neither the working
directory nor systemd's `STATE_DIRECTORY` SHALL play any part in the resolution. The boot SHALL log
the resolved path and whether the variable or the default supplied it, and SHALL create the folder
when it is missing.

#### Scenario: a daemon started in /
- **WHEN** the silo boots as root on Linux with its working directory at `/` and `SILO_STATE_DIR`
  unset
- **THEN** its state directory is `/var/lib/silo`, and the log says the platform default chose it

#### Scenario: a service account names its folder
- **WHEN** the silo boots as a non-root service account with `SILO_STATE_DIR=/var/lib/silo`
- **THEN** its state directory is `/var/lib/silo`, and the log says the variable chose it

#### Scenario: an inherited STATE_DIRECTORY is ignored
- **WHEN** the silo boots as root on Linux with `STATE_DIRECTORY=/var/lib/other` inherited and
  `SILO_STATE_DIR` unset
- **THEN** its state directory is `/var/lib/silo`

Pinned by: `Tests/SiloKitTests/StateDirectoryTests.swift` (`theDefaultIsTheMachinesAndTheUsers`,
`theVariableWinsAndSaysSo`, `anEmptyVariableIsUnset`, `aRelativeVariableKeepsItsMeaning`,
`anInheritedStateDirectoryChangesNothing`, `anAbsoluteXDGStateHomeIsHonouredAndARelativeOneIgnored`).
The boot's log line and the folder's creation are pinned by nothing yet.
