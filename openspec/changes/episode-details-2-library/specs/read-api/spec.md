<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: An item's details are served with it, and put and removed whole
An `Item` in a container's read answers SHALL carry `details` when its library holds them: `title`,
`outline`, `aired` as `yyyy-mm-dd`, `cast` and `crew`, each a list of participants with a `name` and a
`role` in the order they are credited, and `attributions`, each a `subject`, `provider` and `value`.
`PUT /v1/libraries/{library}/containers/{id}/items/{item}/details` with a JSON `ItemDetails` SHALL
write the item's details file where the layout puts it, by writing beside it and renaming, SHALL name
it in the item's `<item>` in the container's sidecar when the sidecar does not already, and SHALL
answer 200 with the details as written. The details SHALL replace any the item had, whole. An
attribution of a field the details do not have, or of a subject other than `outline`, SHALL
be 400. `DELETE` on the same path SHALL remove the file and its name from the sidecar and answer 204,
or 404 when the item has no details. A library the silo does not serve, a container it does not hold,
and an item the container does not declare as a leaf SHALL be 404. A sidecar a put or a delete writes
SHALL be re-read into the index, and its digest changes as after an edit. `PUT` and `DELETE` SHALL
require the operator's bearer; a missing or wrong bearer SHALL be 401.

#### Scenario: an episode's details put and served
- **WHEN** the operator puts details for an episode of a season, with a title, an air date, two of the
  cast and a director
- **THEN** the answer is 200, and the season's read answer carries the episode with those details

#### Scenario: details replaced whole
- **WHEN** the operator puts details holding only a title for an episode whose details held a title and
  a cast
- **THEN** the episode's details hold the title and no cast

#### Scenario: an attributed outline with no outline
- **WHEN** the operator puts details attributing the outline to provider `tmdb` and holding no outline
- **THEN** the answer is 400, and nothing is written

#### Scenario: details removed
- **WHEN** the operator removes an episode's details
- **THEN** the answer is 204, the file is gone, and the season's sidecar no longer names it

Pinned by: `Tests/SiloTests/ServerTests.swift` (`anItemsDetailsArePutServedAndRemoved`,
`detailsAttributingAMissingFieldAreRefused`).
