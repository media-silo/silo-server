<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A container's artwork

## Why
Nothing in the silo knows of artwork. A container's artwork becomes files beside its sidecar, found by
name, which the console puts and removes and the silo serves. Proposal:
[Containers in the console](../../../Proposals/Containers.md).

## What Changes
- A container's artwork is `poster`, `fanart`, `banner`, `logo` or `thumb`, as a `.jpg` or `.png`
  beside its `container.smd`; the sidecar lists none of it.
- `GET`, `PUT` and `DELETE /v1/libraries/{library}/containers/{id}/artwork/{kind}` read, put and
  remove one.
- A kind held as both formats is a warning the walk reports.
