<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: The console shows the moves an edit makes, and lays a library out again
Before a container draft is stored, SiloAdmin's review SHALL list the folders the silo's dry run
says the store would move, `from` and `to`. A library's detail SHALL offer to lay the library out
again: the console SHALL ask the silo for the layout's dry run, show its moves and findings, and
apply them when the operator confirms, showing any rename that failed in the silo's words.

#### Scenario: a title edit reviewed
- **WHEN** the operator reviews an edit correcting a film's year
- **THEN** the review lists the film's folder moving to the name with the corrected year

#### Scenario: a library laid out again
- **WHEN** the operator lays out a library whose folders were renamed by hand
- **THEN** the console lists each folder's move before anything moves, and after applying, the library's last walk warns of none of them

Pinned by: `Tests/SiloAdminKitTests/AdminConsoleTests.swift` (`aLibraryIsLaidOutFromTheConsole`).
The review's list and the layout sheet are pinned by nothing yet, as the rest of the shell is.
