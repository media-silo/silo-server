<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Editing a container in a library

## Why
Once a container's sidecar is in a library nothing changes its own fields but a hand edit on the
silo's machine. The operator edits them from the console, onto the sidecar they read, and no library
fact changes. Proposal: [Containers in the console](../../../Proposals/Containers.md).

## What Changes
- `PUT /v1/libraries/{library}/containers/{id}` sets a container's own fields in one library's sidecar,
  based on the digest of the sidecar the editor read, with a dry run.
- An edit that would take away what a presentation or a child sidecar in the library still names is
  refused with its findings.
- A library's container answers its sidecar's digest.
- The walk warns of a container folder not named as the layout would name it.
