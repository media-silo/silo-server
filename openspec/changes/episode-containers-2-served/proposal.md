<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A container's first date and credits are served

## Why
An episode is held as a container of its own, and SmdKit gives a container the date it premiered and
its cast and crew, each participant with its references. A player should have them in the reads it
already makes: an episode's page from the episode's container, and a season's episode titles and dates
from the season's. Proposal: [An episode is a container of its own](../../../Proposals/EpisodeDetails.md),
step 2.

## What Changes
- A `Container` in the read answers carries `premiered`, `cast` and `crew`, and a `ContainerSummary`
  carries `premiered`.
- A participant, in a container's credits or on a feature, carries its `externalRefs`.
- The validator warns on a container whose `premiered` falls in another year than its `year`.
