<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: silo.json holds what no route changes, and the silo writes it only at startup
The silo SHALL keep in `silo.json`, in its state directory, the settings no route changes: the
`serverID`, a lower-cased UUID; the bind `host`, default `0.0.0.0`; the `port`, default `8742`; and
the `libraryRoots`, absolute paths, default none.
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
- **THEN** `silo.json` holds a fresh ServerID, host `0.0.0.0`, port `8742` and no library roots, and
  the silo listens on `0.0.0.0:8742`

#### Scenario: a gap is filled and nothing else moves
- **WHEN** `silo.json` holds a ServerID and `"port": 9000` and nothing else
- **THEN** the silo listens on 9000 with the same ServerID, and the file gains `host` and
  `libraryRoots` at their defaults

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
libraries the file names, as read at startup and as the library routes change them; a library whose
folder does not exist SHALL be unavailable, per [read-api](../read-api/spec.md), and SHALL NOT stop
the boot. Libraries in the file SHALL NOT be held to the library roots.

#### Scenario: a change survives a restart
- **WHEN** the operator turns the embedded node on and the silo restarts
- **THEN** the embedded node is on

#### Scenario: arriving configured
- **WHEN** an owner writes `settings.json` naming a library before the silo's first boot
- **THEN** the silo boots serving that library, whether or not its path lies within a root

#### Scenario: a drive late to mount
- **WHEN** a library's folder is missing at boot
- **THEN** the silo boots, serves every other library, and lists that one unavailable

Pinned by: nothing yet.

### Requirement: /v1/settings reports both files
The silo SHALL serve `GET /v1/settings` behind the operator gate, reporting every key of
`settings.json` — the libraries with their ids and paths among them — and every key of `silo.json`,
together with the resolved state directory. The `silo.json` keys and the state directory SHALL be
marked read-only; the libraries SHALL NOT be, since the library routes change them.

#### Scenario: the state directory is reported
- **WHEN** the operator reads the settings of a silo whose state directory is `/var/lib/silo`
- **THEN** the answer carries `/var/lib/silo` read-only, beside the host and port, also read-only

Pinned by: nothing yet.

## ADDED Requirements

### Requirement: Libraries are added and removed over the network, within the roots
The silo SHALL serve `POST /v1/libraries` behind the operator gate, taking an id and a path. The
path SHALL be absolute, SHALL exist as a directory, and once symbolic links are resolved SHALL lie
within one of `silo.json`'s library roots; the id SHALL be new. A taken id SHALL be 409; a path
outside every root, or any path when no roots are configured, SHALL be 403; a path that does not
exist SHALL be 422. An added library SHALL be written to `settings.json`, walked before the route
answers, and served without a restart. The silo SHALL serve `DELETE /v1/libraries/{library}` behind
the same gate; it SHALL be 409 while a job not yet in a final state names the library, and otherwise
SHALL remove the library from `settings.json` and its rows from the index, touching nothing on disk.

#### Scenario: added and served
- **WHEN** `silo.json`'s library roots are `/srv/media` and the operator adds `films` at
  `/srv/media/films`
- **THEN** the answer is the walked library, and `GET /v1/libraries` lists it without a restart

#### Scenario: a link that leads outside
- **WHEN** `/srv/media/escape` is a symbolic link to `/etc` and the operator adds it
- **THEN** the answer is 403 and nothing is written

#### Scenario: no roots, no additions
- **WHEN** `silo.json` names no library roots and the operator adds any library
- **THEN** the answer is 403

#### Scenario: removal leaves the files
- **WHEN** the operator removes a library no live job names
- **THEN** it leaves `settings.json` and the index, and every sidecar and media file under its path
  remains

Pinned by: nothing yet.
