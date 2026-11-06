<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# An attribution's age is kept to its provider's terms, and only CC0 content goes to smddb

## Why
A provider's content is attributed where it is kept, and SmdKit's attribution now records the day it
was read. TMDb's terms forbid keeping anything read from it for more than six months, and license
nothing it serves for smddb to hold. The silo should carry the date through every route that makes an
attribution, warn when an attribution has been kept longer than its provider allows, and send an
attributed field to smddb only when its provider's content is CC0. Proposal:
[Facts from Wikidata, content from TMDb](../../../Proposals/Wikidata.md), step 2.

## What Changes
- The API's `Attribution` and `CreateAttribution` carry `read`, `yyyy-mm-dd`, and an edit's, a create's
  and an artwork put's attribution must say it. One whose `read` is not a calendar date is 400.
- Each provider's terms are named once: how many months its content may be kept, six for TMDb and no
  limit otherwise, and whether its content is CC0, as Wikidata's is.
- The walk warns on each sidecar's attribution read longer ago than its provider's limit, every time
  it walks, since an unchanged sidecar ages too.
- A proposal to smddb contributes a field attributed to a CC0 provider as it stands, and leaves out
  one attributed to any other provider, as it left out every attributed field before.
- The console dates each attribution it makes on the day it read the content.
