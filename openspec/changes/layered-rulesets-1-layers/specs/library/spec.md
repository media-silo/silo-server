<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A sidecar may carry rules for what its container holds
A library sidecar's `<container>` MAY hold one `<rules>` element: the container's rules, written
as [rulesets](../rulesets/spec.md) describes, applying to every item of the container and of every
container below it. The rules are a library fact, like the presentations: a repository file carries
none. A placement SHALL keep a sidecar's `<rules>` exactly as written, comments included. A
`<rules>` element the ruleset reader refuses SHALL be an error-severity finding on its sidecar,
naming the refusal.

#### Scenario: a placement keeps the rules
- **WHEN** a presentation is placed into a container whose sidecar holds a `<rules>` element with a
  comment in it
- **THEN** the sidecar written back holds the same `<rules>` element, comment included

#### Scenario: rules that cannot be read
- **WHEN** a container's `<rules>` tests `<when fact="audio.bitrate" is="1"/>` and the library is
  walked
- **THEN** the walk reports an error on that sidecar saying `audio.bitrate` is not a fact a rule
  can test

Pinned by: nothing yet.
