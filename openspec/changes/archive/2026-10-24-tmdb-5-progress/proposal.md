<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A reading against TMDb as it goes

## Why
Reading a long series against TMDb asks TMDb and the silo hundreds of questions, one for each season
and several for each special, and the console showed nothing while it did: an operator comparing a
series with decades of specials watched a spinner and could not tell whether anything was happening.
The reading now says each step as it goes, shows what it has found, and asks several questions at
once. Proposal: [TMDb in the console](../../../Proposals/Tmdb.md).

## What Changes
- A reading against TMDb says the step it is on and counts the questions a step asks.
- The differences found so far are shown as they are found, and a series' specials are listed while
  their suggestions are read; none is taken until the reading is over.
- A failed reading says why with what it found, and closing the differences stops the reading.
- A draft's specials' suggestions show how many are read.
- A step's questions are asked several at once, at most six, and a request TMDb answers 429 is asked
  again after TMDb's wait, at most three times.
