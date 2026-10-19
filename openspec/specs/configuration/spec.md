<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Configuration

## Purpose

Where a silo's configuration lives and who may change it. The silo resolves its state directory
from `SILO_STATE_DIR` or, absent it, a well-known place on the machine, because a silo is a daemon
and one silo per machine is the expected case; the working directory plays no part, and `silo-node`
shares the resolution under its own variable and folder name. Everything else the silo is told lives
in that directory, in two files divided by one rule — whether an operator route can change the
setting: `silo.json` for what none can, read at startup, and `settings.json` for what routes change,
managed by the silo while it runs. The settings route reports both and patches the second, and what it
changes takes effect without a restart.

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

Pinned by: `Tests/SiloKitTests/StateDirectoryTests.swift` (`theDefaultIsTheMachinesAndTheUsers`,
`theVariableWinsAndSaysSo`, `anEmptyVariableIsUnset`, `aRelativeVariableKeepsItsMeaning`,
`anInheritedStateDirectoryChangesNothing`, `anAbsoluteXDGStateHomeIsHonouredAndARelativeOneIgnored`).
The boot's log line and the folder's creation are pinned by nothing yet.

### Requirement: silo.json holds what no route changes, and the silo writes it only at startup
The silo SHALL keep in `silo.json`, in its state directory, the settings no route changes: the
`serverID`, a lower-cased UUID; the bind `host`, default `0.0.0.0`; the `port`, default `8742`; and
the `libraryRoots`, absolute paths, whose default is decided by the platform and the effective user
id as the state directory's is: on macOS `/Volumes`, and the user's `~/Movies` when not running as
root; on Linux `/srv`, `/media` and `/mnt`. An empty list SHALL mean no roots. At startup, before it
serves anything, the silo
SHALL read the file; when it does not exist the silo SHALL create it with every key at its default,
minting the ServerID; when it lacks a key the silo SHALL add the key at its default and write the
file back atomically, logging each key it added. A complete file SHALL NOT be rewritten, and the silo SHALL write the file at no
other time; no route SHALL write it. A file that does not parse SHALL stop the boot with the parse
error and SHALL be left unchanged. A key the silo does not know SHALL be logged by name and kept. A
ServerID minted into a state directory that already holds an operator credential, nodes or jobs
SHALL be logged as a warning.

#### Scenario: first boot writes the defaults
- **WHEN** the silo boots over an empty state directory
- **THEN** `silo.json` holds a fresh ServerID, host `0.0.0.0`, port `8742` and the platform's default
  library roots, and the silo listens on `0.0.0.0:8742`

#### Scenario: the default roots
- **WHEN** the silo boots over an empty state directory as a user other than root on macOS, and as
  root on Linux
- **THEN** the macOS file's library roots are `/Volumes` and the user's `~/Movies`, as an absolute
  path, and the Linux file's are `/srv`, `/media` and `/mnt`

#### Scenario: roots emptied by the owner stay empty
- **WHEN** `silo.json` holds `"libraryRoots": []` and every other key
- **THEN** the silo boots with no library roots, and the file is not rewritten

#### Scenario: a gap is filled and nothing else moves
- **WHEN** `silo.json` holds a ServerID and `"port": 9000` and nothing else
- **THEN** the silo listens on 9000 with the same ServerID, the file gains `host` and
  `libraryRoots` at their defaults, and the log names both keys as added

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

Pinned by: `Tests/SiloStoreTests/ConfigurationFileTests.swift` (`aFreshDirectoryGetsBothFilesAtTheirDefaults`,
`theDefaultRootsAreWhereAHouseholdsMediaAre`, `rootsEmptiedByTheOwnerStayEmpty`,
`aGapIsFilledAndACompleteFileIsNotRewritten`, `aMalformedFileStopsTheBootAndSurvivesIt`,
`aValueOfTheWrongKindIsRefusedByName`, `anUnknownKeyIsReportedAndKeptThroughWrites`,
`existingStateIsRecognised`). The boot's warning over existing state and its log lines are pinned by
nothing yet.

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

Pinned by: `Tests/SiloStoreTests/ConfigurationFileTests.swift` (`aFreshDirectoryGetsBothFilesAtTheirDefaults`,
`anUnknownKeyIsReportedAndKeptThroughWrites`, `settingsAreWrittenWholeAndReadBack`),
`Tests/SiloTests/ServerIdentityTests.swift` (`identityIsMintedOnceAndKeptAcrossRestartsAndARename`),
`Tests/SiloTests/ServerTests.swift` (the suite's fixture arrives configured through `settings.json`),
`Tests/SiloTests/LibrariesTests.swift` (`aDriveLateToMountIsUnavailableAndTheRestAreServed`).

### Requirement: /v1/settings reports both files
The silo SHALL serve `GET /v1/settings` behind the operator gate, reporting every key of
`settings.json` — the libraries with their ids and paths among them — and every key of `silo.json`,
together with the resolved state directory. The `silo.json` keys and the state directory SHALL be
marked read-only; the libraries SHALL NOT be, since the library routes change them.

#### Scenario: the state directory is reported
- **WHEN** the operator reads the settings of a silo whose state directory is `/var/lib/silo`
- **THEN** the answer carries `/var/lib/silo` read-only, beside the host and port, also read-only

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theSettingsAreReportedAndPatchedWhole`).

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

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theSettingsAreReportedAndPatchedWhole`),
`Tests/SiloTests/SettingsFollowingTests.swift` (`theEmbeddedNodeFollowsItsSetting`,
`theAnnouncementFollowsTheSettingTheNameAndBootstrap`). The job in flight running to completion when
the embedded node is turned off is pinned by nothing yet.

### Requirement: A library may name its ruleset
Each library in `settings.json` MAY carry `ruleset`, the name of a ruleset the silo holds: the
library's standard, which an application that names no ruleset takes. A library without one has no
standard. `PUT /v1/libraries/{library}/ruleset`, behind the operator's token, SHALL set or, with a
null name, clear it, written through to `settings.json` and applied at once; a library the silo does
not have, or a name it holds no ruleset under, SHALL be 404 and change nothing.

#### Scenario: a library's standard is set
- **WHEN** the operator sets a library's ruleset to `household`
- **THEN** `settings.json` names `household` for that library, and the next application to a
  binding into it that names no ruleset applies `household`

#### Scenario: a ruleset the silo does not hold
- **WHEN** the operator sets a library's ruleset to a name no ruleset is stored under
- **THEN** the answer is 404, and `settings.json` is as it was

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aLibraryNamesItsStandardRuleset`), `Tests/SiloStoreTests/RulesLayerFileTests.swift` (`aLibrarysRulesetIsKeptInTheSettingsFile`), `Tests/SiloTests/StackTests.swift` (`anApplicationNamingNoRulesetTakesTheLibrarysStandard`).

### Requirement: Libraries are added and removed over the network, within the roots
The silo SHALL serve `POST /v1/libraries` behind the operator gate, taking an id and a path. The
path SHALL be absolute, SHALL exist as a directory, and once symbolic links are resolved SHALL lie
within one of `silo.json`'s library roots; the id SHALL be new. A taken id SHALL be 409; a path
outside every root, or any path when the roots are empty, SHALL be 403; a path that does not
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

#### Scenario: empty roots, no additions
- **WHEN** `silo.json`'s library roots are an empty list and the operator adds any library
- **THEN** the answer is 403

#### Scenario: removal leaves the files
- **WHEN** the operator removes a library no live job names
- **THEN** it leaves `settings.json` and the index, and every sidecar and media file under its path
  remains

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aLibraryIsAddedWithinTheRootsAndRemovedLeavingItsFiles`,
`yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI`, for the refusal while a live job names the
library), `Tests/SiloTests/LibrariesTests.swift` (`withTheRootsEmptiedNothingIsAddedOverTheNetwork`,
`aRootIsMatchedByWholeComponents`).
