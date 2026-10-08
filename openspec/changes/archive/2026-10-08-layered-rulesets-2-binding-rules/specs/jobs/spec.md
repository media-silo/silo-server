<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: Placement writes a binding's rules before the presentation names them
Placing a job's output SHALL, when the job's binding has rules kept in the silo's state, write every
one of their versions into the library's `rules/bindings/<binding id>` folder first, then the
presentation, then the item's `<rules>` naming the version in force, through the sidecar's own call
for setting a binding's rules; and SHALL then keep them in the library alone. A placement that is
refused SHALL write none of them.

#### Scenario: a binding's first placement
- **WHEN** a job is placed whose binding has two versions of its rules in the silo's state, version 2
  in force
- **THEN** the library holds both version files, the item names version 2 of the binding's rules, the
  presentation's `<transform>` names version 2, and the silo's state no longer holds them

Pinned by: `Tests/SiloTests/BindingRulesTests.swift` (`rulesStoredBeforePlacementMoveIntoTheLibraryWithTheFirstFile`). A refused placement writing none of them is pinned by nothing yet.
