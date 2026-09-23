<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Add the library layer and silo-ctl place

**Retrospective archive — merged 2026-09-23 as pull request #2.** This change predates the
corpus; its documents were reconstructed from the merge afterwards.

## Why

The first pull request decided how a ripped file is encoded, and encoded one. Between that and
something a client watches sits the proposal's third job: putting the result where it belongs, in a
layout a client can find it in, next to the `.smd` that says what it is. None of that needs a
server: the `.smd` beside the files is the truth, a placement lists every file it will create or
change before it changes any and can be shown without being applied, and what conflicts with the
layout is shown as a finding, never resolved behind anyone's back. Building the layout, the walk,
the validator and the placer next is the roadmap's own order — with a command that places a file
into a library folder, a library can be built by hand before the server exists.

## What Changes

- A new `SiloLibrary` module fixes the library on disk: a folder per container named from its
  display title with `container.smd` inside, `{item} - {display name}.mkv` beside it, `extras/`
  inside the owning container, and every path a sidecar names relative to its own folder and unable
  to escape the container's folder.
- `LibraryWalker` finds every container from the top-level folders down each sidecar's `smd`
  paths, records each sidecar's modification time and size, and reports unreadable, mismatched and
  unreferenced sidecars as findings.
- `Validator` carries the severity split — an error is a fact a client would be misled by, a
  warning one a person should know — through per-sidecar checks, first on the value alone, then
  against the disk.
- `Placer` computes every write a placement makes — folders, the destination, the sidecars root
  first, the presentation, the findings — shows them, refuses the whole when any finding is an
  error, and applies in the order folders, file, then sidecars; existing sidecars are updated in
  place so hand edits survive.
- `TrackMapping` becomes the sidecar's own type, so a recipe's renumbered map is the thing the
  sidecar writes.
- `silo-ctl place` drives the engine from a clone of the data repository, printing the declared
  writes first and applying them unless `--dry-run`.

## Impact

- Affected specs: library, placement.
- Affected code: Sources/SiloLibrary, Sources/silo-ctl.
