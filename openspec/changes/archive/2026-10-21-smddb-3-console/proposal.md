<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# smddb in the console

## Why
The console can see and edit a library's containers, but cannot reach smddb, where containers are
described. It reads a clone of smddb's data repository on the Mac through SmdKit's client, imports
containers into a library, creates new ones with a provisional id, and proposes a library's container
back. Proposal: [smddb in the console](../../../Proposals/Smddb.md).

## What Changes
- The console names a clone of smddb's data repository on this Mac and reads it through SmdKit's
  `LocalRepository`, never committing, pulling or pushing.
- A container is imported from smddb into a library with the descendants the operator chooses,
  beneath the nearest smddb ancestor the library holds.
- A container the library holds is shown against smddb's record, and taking the record in is an edit.
- A container is created in the console with a provisional id, at the top of a library or as a child
  of one it holds.
- A library's container is proposed to smddb by contributing its own fields to the clone.
