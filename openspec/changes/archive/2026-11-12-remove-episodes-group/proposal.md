<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A season's episodes have their fields ticked each at its own stop

## Why
A season's *Episodes* group ticked a field at every episode beneath it at once, with counts of how
many each would change. Beside the stop's own fields it read as a second set of them, and what it did
to the episodes' stops was hard to see. Each episode's stop already offers its fields.

## What Changes
- The *Episodes* group is removed: each episode's fields are ticked at its own stop.
- *Confirm and everything beneath* confirms each stop beneath with the ticks the operator set there,
  and otherwise the defaults.
- A walk kept with fields ticked in an *Episodes* group keeps the ticks its episodes' stops took from
  it; what was ticked in the group itself is no longer read.
