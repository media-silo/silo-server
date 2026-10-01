<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Configuration

## Why
Where a silo's configuration lives: SILO_STATE_DIR as the one variable, the state directory at a known place, silo.json and settings.json divided by whether a route can change a setting, and the default port off 8080. Proposal: [Configuration](../../../../Proposals/Configuration.md). #28 proposed it; #30, #31, #32 and #33 implemented it.

## What Changes
- The state directory resolved to a known place, and the default port moved to 8742.
- silo.json and settings.json, and no environment but SILO_STATE_DIR.
- The settings route, and the name, embedded node and advertising following their settings.
- SiloAdmin showing and changing a silo's settings.
