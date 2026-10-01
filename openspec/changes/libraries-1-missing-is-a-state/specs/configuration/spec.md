<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

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
