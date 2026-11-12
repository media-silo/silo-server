<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A drafted episode's leaf is named `episode`

## Why
An episode drafted as a container held one leaf named `feature`, the name a film's leaf has, though
the leaf is of type `episode` and what it holds is the episode.

## What Changes
- An episode drafted from Wikidata, and a special placed among a season's episode containers, holds
  one sequence `main` of one leaf `episode` of type `episode`.
- Episodes already held keep the leaf they have.

## Impact
- Modified: a walk drafts each episode as a container; a special placed among a season's episodes is
  an episode container.
