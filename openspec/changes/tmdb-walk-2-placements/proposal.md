<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Specials as alternatives, and in companion series

## Why
TMDb files an omnibus edition of a serial, or an episode with new effects, as a special, and each is
another way to play the container it belongs to, not an entry beside the others or an extra. SmdKit
models that as an alternative naming the sequence it plays, and a special had no way to become one.
A companion series was only ever new and unlisted, so one the library holds, or one the household
browses to, could not take a special. Proposal: [A held tree reviewed against
TMDb](../../../Proposals/TmdbWalk.md).

## What Changes
- A special can be placed as an alternative of a container: in an alternate sequence it has, as a new
  edition in a sequence of its own, or as a version of one item in a new sequence that refers to the
  others, each new sequence named by a new alternative.
- A special whose title names a container as an omnibus, or one of its items as a special edition, is
  suggested as that alternative.
- A special can be placed in any series the library holds as its companion, listed or not, or in a new
  one, unlisted to begin with and listed when the operator says.
