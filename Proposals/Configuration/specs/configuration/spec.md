<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

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
- **WHEN** the silo boots as root on Linux with its working directory at `/` and neither variable set
- **THEN** its state directory is `/var/lib/silo`, and the log says the platform default chose it

#### Scenario: a service account names its folder
- **WHEN** the silo boots as a non-root service account with `SILO_STATE_DIR=/var/lib/silo`
- **THEN** its state directory is `/var/lib/silo`, and the log says the variable chose it

#### Scenario: an inherited STATE_DIRECTORY is ignored
- **WHEN** the silo boots as root on Linux with `STATE_DIRECTORY=/var/lib/other` inherited and
  `SILO_STATE_DIR` unset
- **THEN** its state directory is `/var/lib/silo`

Pinned by: nothing yet.

### Requirement: Local settings are read once and never written over the network
The silo SHALL read its local settings from the environment once, at boot, and hold them for the
life of the process: the state directory; the bind host, `SILO_HOST`, default `0.0.0.0`; the port,
`SILO_PORT`, default `8742`; the operator token override, `SILO_OPERATOR_TOKEN`, an empty value
meaning none; the encoder tools, `FFMPEG_PATH` and `FFPROBE_PATH`; and the library roots,
`SILO_LIBRARY_ROOTS`, comma-separated absolute paths, default none. No route SHALL change a local
setting.

#### Scenario: the defaults
- **WHEN** the silo boots with none of the local settings' variables set
- **THEN** it listens on `0.0.0.0:8742`, has no operator token override and no library roots

Pinned by: nothing yet.

### Requirement: Stored settings live in the state directory, and the environment pins them
The silo SHALL keep its stored settings — the libraries, the embedded node and advertising — in
`settings.json` in the state directory, written atomically, and the name in `server.json` as
[onboarding](../onboarding/spec.md) has it. Unstored, the libraries SHALL default to none, the
embedded node to off, and advertising to on. When a stored setting's variable is set —
`SILO_LIBRARIES`, `SILO_EMBEDDED_NODE` or `SILO_ADVERTISE` — the setting SHALL be pinned: its value
SHALL be the environment's, whatever is stored, and every write to it SHALL be refused.
`SILO_LIBRARIES` SHALL pin the list whole. The name SHALL have no pin; `SILO_NAME` keeps its meaning
as the seed of a minted identity.

#### Scenario: stored survives a restart
- **WHEN** the operator turns the embedded node on and the silo restarts with `SILO_EMBEDDED_NODE`
  unset
- **THEN** the embedded node is on

#### Scenario: the environment pins
- **WHEN** `settings.json` stores the embedded node on and the silo boots with
  `SILO_EMBEDDED_NODE=false`
- **THEN** the embedded node is off, and reported as pinned by `SILO_EMBEDDED_NODE`

Pinned by: nothing yet.

### Requirement: /v1/settings reports every setting and where it came from
The silo SHALL serve `GET /v1/settings` behind the operator gate, reporting every stored and every
local setting with its value and its source — `environment`, `stored` or `default` — and, for a
setting the environment supplied, the variable that did. Local settings SHALL be reported as not
writable, and the state directory SHALL be among them.

#### Scenario: sources are named
- **WHEN** the silo boots with `SILO_ADVERTISE=false`, a stored library, and nothing said of the
  embedded node
- **THEN** advertising reports `environment` with `SILO_ADVERTISE`, the libraries `stored`, and the
  embedded node `default`

Pinned by: nothing yet.

### Requirement: A settings patch applies whole, and takes effect at once
The silo SHALL serve `PATCH /v1/settings` behind the operator gate, taking any of the name, the
embedded node and advertising, and SHALL apply all of the body or none of it. A pinned setting in
the body SHALL refuse the request with 409 naming the variable that pins it; an empty name SHALL be
400. The answer SHALL be the settings as they then stand. Each change SHALL take effect without a
restart: turning the embedded node on SHALL start its loop, and turning it off SHALL stop it
claiming while a job in flight runs to completion; turning advertising on or off SHALL start or drop
the advertisement; a new name SHALL be written to `server.json` and re-advertised.

#### Scenario: one pinned field refuses the whole patch
- **WHEN** `SILO_ADVERTISE` is set and a patch names both the advertising and a new name
- **THEN** the answer is 409 naming `SILO_ADVERTISE`, and the name is unchanged

#### Scenario: the embedded node stops between jobs
- **WHEN** the embedded node is turned off while it is encoding a job
- **THEN** that job completes, and no further job is claimed

Pinned by: nothing yet.

### Requirement: Libraries are added and removed over the network, within the roots
The silo SHALL serve `POST /v1/libraries` behind the operator gate, taking an id and a path. The
path SHALL be absolute, SHALL exist as a directory, and once symbolic links are resolved SHALL lie
within a library root; the id SHALL be new. A pinned list or a taken id SHALL be 409; a path outside
every root, or any path when no roots are configured, SHALL be 403; a path that does not exist SHALL
be 422. An added library SHALL be stored, scanned as `POST /v1/libraries/{library}/scan` scans, and
served without a restart. The silo SHALL serve `DELETE /v1/libraries/{library}` behind the same
gate; it SHALL be 409 while the list is pinned or while a job not yet in a final state names the
library, and otherwise SHALL remove the library and its index rows, touching nothing on disk.
Libraries named by `SILO_LIBRARIES` SHALL NOT be held to the roots.

#### Scenario: added and served
- **WHEN** `SILO_LIBRARY_ROOTS=/srv/media` and the operator adds `films` at `/srv/media/films`
- **THEN** the answer is the scanned library, and `GET /v1/libraries` lists it without a restart

#### Scenario: a link that leads outside
- **WHEN** `/srv/media/escape` is a symbolic link to `/etc` and the operator adds it
- **THEN** the answer is 403 and nothing is stored

#### Scenario: no roots, no additions
- **WHEN** `SILO_LIBRARY_ROOTS` is unset and the operator adds any library
- **THEN** the answer is 403

#### Scenario: removal leaves the files
- **WHEN** the operator removes a library no live job names
- **THEN** it leaves the list and the index, and every sidecar and media file under its path remains

Pinned by: nothing yet.
