<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Set up Swift through swift-wire/setup-swift

**Retrospective archive — merged 2026-09-23 as pull request #7.** This change predates the
corpus; its documents were reconstructed from the merge afterwards.

## Why

CI installed its toolchain through `vapor/swiftly-action` with the version written into the
workflow. The version is a property of the package, not of the pipeline, and the wire
repositories it is built on had already moved to an action that reads it from the package.

## What Changes

- The build job's toolchain step becomes `swift-wire/setup-swift@v1`, which installs through
  Swiftly the toolchain `.swift-version` names.
- `.swift-version` is created, pinning `6.4.0` — the version the package is developed against
  and the floor its stack sets.

## Impact

- Affected specs: none. Toolchain selection is not a behaviour this corpus specifies.
- Affected code: `.github/workflows/build.yml`, `.swift-version`. A Swift upgrade is now a
  one-line change to the latter.
