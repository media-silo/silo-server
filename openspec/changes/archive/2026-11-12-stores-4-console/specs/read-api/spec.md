<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A library's store is taken at once, under the key it names, and made in the background
`POST /v1/libraries/{library}/stores` with a JSON `StoreRequest` — `key`, a name chosen by whoever
sends it, of letters, digits, `-`, `_` and `.`, up to 128 of them; and `steps`, each exactly one of the
four, in the order they are to be made, `create`, carrying `documents`,
`parent` and `attributions` as a `ContainerCreate` does; `edit`, carrying `container`, `document`,
`basedOn`, `attributions` and `declined` as a `ContainerEdit` does; `putArtwork`, carrying
`container`, `kind`, `image`, the digest of a blob, and `provider`, `value` and `read`, all or none, as
the artwork route takes them; and `removeArtwork`, carrying `container` and `kind` — SHALL check the
store before making any of it, SHALL record it, and SHALL answer at once with its `StoreRecord`.

- The check SHALL refuse the store when a document cannot be read or names another container, when
  an edit's `basedOn` is not the digest of the sidecar the library holds and its document is not what
  the sidecar already holds, when an `image` names a blob the silo does not hold, or when a step names a
  container the library does not hold and no earlier step makes. An edit of a container an earlier
  step makes SHALL NOT be checked against a base; with an empty `basedOn` it SHALL be made on the
  sidecar the earlier steps left, which its sender could not have read. A store the check refuses SHALL be
  recorded as `refused` with none of its steps made, naming the first step refused and the reason, and
  SHALL be answered 202 as a store taken is.
- A store the check passes SHALL be answered 202 and SHALL be made in the background, its steps in
  order, each as its own route makes it and with that route's findings, in one turn of the library's
  lane, so that no other write to the library and no walk of it comes between them. A step that moves
  folders SHALL have the library walked before the next step is made, so that each later step finds
  what moved where it now is. A step its route would refuse SHALL end the store there, recorded as
  `refused` at that step with the route's words and findings; the steps before it stand.
- A request naming a key the library has a store for SHALL be answered that store's record with 200
  when its steps are the store's, and 409 when they are not; nothing SHALL be made again.
- A library the silo does not serve SHALL be 404, and a key that cannot be one 400. A step that is
  not exactly one of the four SHALL refuse the store at the check.

The route SHALL require the operator's bearer; a missing or wrong bearer SHALL be 401.

#### Scenario: a store of an edit, a creation beneath it and its artwork
- **WHEN** the operator sends a store of three steps: an edit naming a new season as a child of a series
  the library holds, the season's creation beneath the series, and a put of a poster on the season from
  a blob the silo holds
- **THEN** the answer is 202, and once the store is made the series names the season, the library holds
  the season, and the season's folder holds the poster

#### Scenario: a store sent twice
- **WHEN** the operator sends a store, and then sends the same key with the same steps
- **THEN** the second answer is 200 with the first store's record, and each step is made once

#### Scenario: a key sent again with other steps
- **WHEN** the operator sends a store, and then sends the same key with a step more
- **THEN** the second answer is 409, and the second request's steps are not made

#### Scenario: an edit on a sidecar that has changed
- **WHEN** a store's second step edits a container whose sidecar has changed since the edit's base
- **THEN** the store is recorded as refused at its second step, and none of its steps is made

#### Scenario: an image the silo does not hold
- **WHEN** a store's step puts artwork from a digest the silo holds no blob for
- **THEN** the store is recorded as refused at that step, and none of its steps is made

#### Scenario: an edit of a container the store makes
- **WHEN** a store's first step makes a series, and its second edits the series with an empty base,
  declining a special
- **THEN** the store is made, and the series' sidecar declines the special

#### Scenario: a step the silo refuses as it is made
- **WHEN** a store's second step creates a container the library already holds, beneath a container
  its first step made
- **THEN** the store is recorded as refused at its second step with the route's finding, its first
  step is made, and its third is not

Pinned by: `Tests/SiloTests/StoreServiceTests.swift` (`aStoreIsMadeInOrderAndSentTwiceIsMadeOnce`,
`aStoreTheCheckRefusesMakesNothing`, `aStepTheSiloRefusesEndsTheStoreThere`,
`anEditOfAContainerTheStoreMadeIsOnWhatItMade`),
`Tests/SiloTests/ServerTests.swift` (`aStoreIsTakenAtOnceAndSaidAtARouteOfItsOwn`).
