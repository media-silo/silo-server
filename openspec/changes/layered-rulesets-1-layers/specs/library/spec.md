<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A sidecar may name versioned rules for what its container holds
A library sidecar's `<container>` MAY end in one `<rules>` element naming, by `path`, a folder of rule
versions beside the sidecar and, by `activeVersion`, the version in force, version `n` being the file
`<path>/<n>.xml`; the rules apply to every item of the container and of every container below it,
written as [rulesets](../rulesets/spec.md) describes. The rules are a library fact, like the
presentations: a repository file carries none. A placement SHALL keep a sidecar's `<rules>` exactly
as it stands. The walk SHALL report as an error-severity finding on the sidecar a `<rules>` whose
version in force is not there (`rules version <n> is not there`), and one whose version file the
ruleset reader refuses, naming the refusal.

#### Scenario: a placement keeps the reference
- **WHEN** a presentation is placed into a container whose sidecar names version 4 of its rules
- **THEN** the sidecar written back still names version 4

#### Scenario: rules that cannot be read
- **WHEN** a container's rules in force test `<when fact="audio.bitrate" is="1"/>` and the library
  is walked
- **THEN** the walk reports an error on that sidecar saying `audio.bitrate` is not a fact a rule
  can test

#### Scenario: a version that is not there
- **WHEN** a container's sidecar names version 5 of its rules and only versions 1 to 4 are in the
  folder
- **THEN** the walk reports an error on that sidecar, `rules version 5 is not there`

Pinned by: nothing yet.
