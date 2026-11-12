<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A stop's artwork shows its size

## Why
A stop shows each image TMDb offers at the width of its column, from a smaller copy TMDb serves, so
the operator cannot tell from it how large the image put would be.

## What Changes
- TMDb's answer for a record's images says each image's width and height, and the console keeps them
  with the images: in a held stop's reading, and in a new stop's draft.
- A stop's artwork says the size of the image it would put, in pixels, after its attribution, when
  TMDb says it.
- A walk kept before sizes were read is read as having none.

## Impact
- Modified: a stop's artwork chosen from TMDb's images.
