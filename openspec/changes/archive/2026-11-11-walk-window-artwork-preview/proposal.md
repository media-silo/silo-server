<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A walk takes the window, and artwork is seen whole

## Why
A walk was shown in a sheet of a fixed size in the middle of the console's window, which cannot be
made larger however much the walk holds. Artwork was shown only as a thumbnail, too small to tell
what an image is before choosing it.

## What Changes
- A walk takes the console's window while it lasts, in place of what the window shows, and closing
  it gives the window back as it was.
- Every image of artwork the console shows, a container's own and those TMDb offers, is shown whole
  in Quick Look when it is double-clicked, or when Space is pressed with the pointer over it, and Space
  closes it again.
