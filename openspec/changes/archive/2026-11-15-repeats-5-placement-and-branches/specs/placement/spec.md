<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A refused placement is answered whole, with its findings
A placement whose presentation the library already holds — the presentation the request names, of its
item, alternative and profile, its file at the path the placement would write, with the tracks and
chapters the request asks for — SHALL be answered 200 with `applied` true, that presentation's id and
no writes, moving no file and changing no sidecar, so that a placement sent again is answered as the
first was. Any other placement an error-severity finding stops SHALL NOT be applied: no file moves, no
sidecar changes. The answer SHALL be 409 carrying the `PlacementResult` — `applied` false and the
findings shown — so the caller reads what refused it.

#### Scenario: a destination that already exists
- **WHEN** a file is placed at a path where the library holds a file its sidecar records no
  presentation of
- **THEN** the answer is 409 with `applied` false, the findings include
  `already exists; nothing is overwritten`, and the file offered for placing remains where it
  was

#### Scenario: a placement sent again
- **WHEN** a file is placed, and the same body is sent again
- **THEN** the second answer is 200 with `applied` true, the presentation id the first answered and no
  writes, and the library holds one presentation of the item

Pinned by: `Tests/SiloTests/ServerTests.swift` (`zPlacementIsShownThenAppliedAndRefusedTheSecondTime`), `Tests/SiloLibraryTests/PlacementTests.swift` (`whatCannotBePlacedIsRefusedWithReasons`), `Tests/SiloTests/RepeatTests.swift` (`aJobWhosePresentationIsAlreadyPlacedIsRecordedPlaced`).
