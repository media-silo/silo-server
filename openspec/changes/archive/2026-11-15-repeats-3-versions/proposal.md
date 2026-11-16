<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A document already in force is that version

## Why
A binding's rules put again, or a ruleset stored again, is a second version with the first's document,
and a ruleset stored again on its base is refused as if another editor had stored before it. A document
the version in force already holds is answered as that version instead, and a store on a ruleset that
exists says the head it was made from. Proposal: [0022-repeats](../../../Proposals/Repeats.md).

## What Changes
- A binding's rules whose document is the bytes of the version in force are answered 200 as that
  version, and nothing is stored.
- A ruleset store whose document is the bytes of its branch's head is answered 200 as the head, and
  nothing is stored, whatever its `basedOn`.
- A store on a ruleset that has a version is 400 without `basedOn`; a new name needs none.

## Impact
- Modified: a binding's rules are versioned and set by their own route; every store is a new version
  the silo numbers; every ruleset store is a new version, and is the operator's.
