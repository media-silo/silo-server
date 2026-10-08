<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: An item may name the rules of each binding that has its own
An item in a library sidecar MAY hold, before its presentations, one `<rules>` per binding of the item
that has rules of its own, naming the binding by its id, the folder of the binding's rule versions by
`path` and the version in force by `activeVersion`, as a container's `<rules>` names its own. A
placement SHALL keep an item's `<rules>` as they stand. The walk SHALL report as an error-severity
finding a binding's version in force that is not there, or one the ruleset reader refuses, as it does
a container's; and as a warning an item's `<rules>` for a binding none of the item's presentations
names (`rules for binding <id>, which no presentation of <item> names`), since the rules are a
decision someone made and stay until removed on purpose.

#### Scenario: an item made from two bindings
- **WHEN** an item's broadcast presentation was made from one binding and its updated cut from
  another, and each binding has rules of its own
- **THEN** the item names both bindings' rules, and each presentation's `<source>` names the binding
  whose rules apply to it

#### Scenario: rules for a binding whose files have gone
- **WHEN** an item names a binding's rules and none of its presentations names that binding
- **THEN** the walk reports a warning naming the binding and the item

Pinned by: nothing yet.
