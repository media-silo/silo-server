<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A library added is answered before its walk

## Why
Adding a library walks it before the route answers, which takes minutes for a large tree. Proposal:
[0023-taken](../../../Proposals/Taken.md). Tracking issue: silo-server#197.

## What Changes
- An add answers 201 once the library is in `settings.json`, and queues its walk.
- A library's listing says `walking` while a walk of it is under way.
- The console shows a library being walked.

## Impact
- Modified: libraries are added over the network; the libraries are listed; the console shows a
  silo's libraries.
