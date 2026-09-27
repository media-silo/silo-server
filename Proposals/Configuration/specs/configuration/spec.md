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
when it is missing. `SILO_STATE_DIR` SHALL be the only environment variable the silo reads for its
own configuration.

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

Pinned by: nothing yet.

### Requirement: silo.json holds what no route changes, and the silo writes it only at startup
The silo SHALL keep in `silo.json`, in its state directory, the settings no route changes: the
`serverID`, a lower-cased UUID; the bind `host`, default `0.0.0.0`; and the `port`, default `8742`.
At startup, before it serves anything, the silo
SHALL read the file; when it does not exist the silo SHALL create it with every key at its default,
minting the ServerID; when it lacks a key the silo SHALL add the key at its default and write the
file back atomically. A complete file SHALL NOT be rewritten, and the silo SHALL write the file at no
other time; no route SHALL write it. A file that does not parse SHALL stop the boot with the parse
error and SHALL be left unchanged. A key the silo does not know SHALL be logged by name and kept. A
ServerID minted into a state directory that already holds an operator credential, nodes or jobs
SHALL be logged as a warning.

#### Scenario: first boot writes the defaults
- **WHEN** the silo boots over an empty state directory
- **THEN** `silo.json` holds a fresh ServerID, host `0.0.0.0` and port `8742`, and the silo listens
  on `0.0.0.0:8742`

#### Scenario: a gap is filled and nothing else moves
- **WHEN** `silo.json` holds a ServerID and `"port": 9000` and nothing else
- **THEN** the silo listens on 9000 with the same ServerID, and the file gains `host` at its
  default

#### Scenario: a malformed file is not repaired
- **WHEN** `silo.json` does not parse
- **THEN** the boot stops naming the parse error, and the file is byte-for-byte as it was

#### Scenario: a typo is reported
- **WHEN** `silo.json` holds `"prot": 9000`
- **THEN** the log names `prot` as unknown, the key stays in the file, and the silo listens on the
  port the file's `port` key gives

#### Scenario: a new identity over old state is loud
- **WHEN** `silo.json` is deleted from a state directory that holds `operator-credential.json`, and
  the silo boots
- **THEN** it mints a new ServerID and logs a warning that a new identity was minted over existing
  state

Pinned by: nothing yet.

### Requirement: settings.json holds what routes change, and the silo manages it
The silo SHALL keep in `settings.json`, in its state directory, the settings an operator route
changes: the `name`, default `Silo on <host name>`; the `libraries`, each an id and a path, default
none; `embeddedNode`, default false; and `advertise`, default true. At startup the silo SHALL treat
the file as it treats `silo.json` — created when missing, filled where a key is missing, left
unchanged and the boot stopped when it does not parse, unknown keys logged and kept — so that the
name is fixed at first boot. After startup the silo SHALL hold the settings in memory and SHALL
write the file whole, atomically, whenever a route changes a setting. The silo SHALL serve the
libraries the file names, as read at startup; a library whose folder does not exist SHALL stop the
boot with an error naming the library.

#### Scenario: a change survives a restart
- **WHEN** the operator turns the embedded node on and the silo restarts
- **THEN** the embedded node is on

#### Scenario: arriving configured
- **WHEN** an owner writes `settings.json` naming a library before the silo's first boot
- **THEN** the silo boots serving that library

Pinned by: nothing yet.

### Requirement: /v1/settings reports both files
The silo SHALL serve `GET /v1/settings` behind the operator gate, reporting every key of
`settings.json` — the libraries with their ids and paths among them — and every key of `silo.json`,
together with the resolved state directory. The `silo.json` keys, the state directory and the
libraries SHALL be marked read-only, the libraries because no route yet changes them.

#### Scenario: the state directory is reported
- **WHEN** the operator reads the settings of a silo whose state directory is `/var/lib/silo`
- **THEN** the answer carries `/var/lib/silo` read-only, beside the host and port, also read-only

Pinned by: nothing yet.

### Requirement: A settings patch applies whole, and takes effect at once
The silo SHALL serve `PATCH /v1/settings` behind the operator gate, taking any of the name, the
embedded node and advertising, and SHALL apply all of the body or none of it; an empty name SHALL be
400. The answer SHALL be the settings as they then stand. Each change SHALL be written to
`settings.json` and SHALL take effect without a restart: turning the embedded node on SHALL start its
loop, and turning it off SHALL stop it claiming while a job in flight runs to completion; turning
advertising on or off SHALL start or drop the advertisement; a new name SHALL be served and
re-advertised.

#### Scenario: an invalid field refuses the whole patch
- **WHEN** a patch carries an empty name and turns advertising off
- **THEN** the answer is 400, and advertising is unchanged

#### Scenario: the embedded node stops between jobs
- **WHEN** the embedded node is turned off while it is encoding a job
- **THEN** that job completes, and no further job is claimed

Pinned by: nothing yet.
