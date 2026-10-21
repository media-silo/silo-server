<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# An index another version made is rebuilt

## Why
The index's schema has changed by editing its one migration in place, so a file made before the
index was keyed by library still holds the old tables, its migration recorded as done, and every
write to it fails: walks stop, and a write the silo makes is not read back. The index is a cache,
so a file another version made is emptied on opening and the walk fills it again.

## What Changes
- The index file carries its version in SQLite's `user_version`; a file of another version is emptied when it is opened, and stamped with this one.
- The version is raised whenever the tables, or what is derived into them such as a presentation's id, change.
