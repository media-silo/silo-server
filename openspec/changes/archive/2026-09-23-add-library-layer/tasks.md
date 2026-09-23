<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Tasks

**Retrospective archive — every task was completed in pull request #2 (merged 2026-09-23).**

## 1. The layout

- [x] 1.1 Fix the on-disk layout: a folder per container named from its display title with
  `container.smd` inside, `{item} - {display name}.mkv` beside it, `extras/` inside the owning
  container
- [x] 1.2 Sanitise titles for a filesystem and keep every path a sidecar names relative to, and
  unable to escape, its container's folder

## 2. The walk and the validator

- [x] 2.1 Walk a library from its top-level folders down each sidecar's `smd` paths, recording
  modification time and size and reporting every sidecar nothing references
- [x] 2.2 Check each sidecar's value and then the files it names on disk, as error and warning
  findings that nothing resolves

## 3. The placer

- [x] 3.1 Compute every write a placement makes — folders, the destination, the sidecars root
  first, the presentation, the findings — and refuse it whole when any finding is an error
- [x] 3.2 Apply in a fixed order — folders, the file, then the sidecars — updating existing
  sidecars in place so hand edits survive, and make the sidecar's `TrackMapping` the map a recipe
  renumbers

## 4. `silo-ctl place`

- [x] 4.1 Add the `place` subcommand, reading the container tree from a clone of the data
  repository, showing the declared writes first and applying them unless `--dry-run`

## 5. Tests

- [x] 5.1 Pin the first placement making the tree, a second updating only what changed, refusals
  with reasons, the walk's findings, name sanitising and path containment
