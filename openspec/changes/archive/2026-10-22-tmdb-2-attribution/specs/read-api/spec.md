<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: The API's types are the sidecar's elements as JSON
One model, per principle 2: the document's schemas SHALL be the sidecar's
elements as JSON, never a separate API vocabulary. A `Container` SHALL carry
the sidecar's `type`, `title`, `displayTitle`, `year`, `typeLabel`, `outline`,
`listed`, `defaultAlternative`, `alternatives`, `features` with their
`participants`, `sequences`, `extrasAnchor`, `extras`, `externalRefs`, its
`attributions` — each a `subject`, `provider` and `value` — and its child containers as
summaries; an `Item` SHALL carry its `optional`, `ref`,
`externalRefs` and `presentations`; a `Presentation` SHALL carry `id`,
`alternative`, `profile`, `displayName`, `file`, `source` — its binding and
segments — `transform` — its ruleset, version and layers — `tracks` and
`chapters`, with a track's `audio` and `subtitle` counting from one among the
streams of that kind. The mapping SHALL run one way only: the API is a
projection of the model, never a place the model is edited.

#### Scenario: a container reads as the sidecar's values
- **WHEN** a client asks `GET /v1/containers/0000000000000003`
- **THEN** the 200 answer carries `"typeLabel":"Story"`,
  `"parent":"0000000000000001"`, and in its presentations
  `"displayName":"mobile"`, `"file":"Part One.mkv"` and a track's `"audio":3`

#### Scenario: an attributed outline reads with its attribution
- **WHEN** a container's sidecar attributes its outline to provider `tmdb` with value `348`, and a
  client asks for the container
- **THEN** the 200 answer carries the outline, and in its `attributions` the subject `outline`,
  provider `tmdb` and value `348`

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theLibraryIsBrowsable`,
`attributionsAreServedWithTheContainer`).

### Requirement: A library's containers are read within the library
`GET /v1/libraries/{library}/containers` SHALL answer 200 with a
`ContainerSummary` for each container at the top of the library, listed or not.
`GET /v1/libraries/{library}/containers/{id}` SHALL answer 200 with a
`LibraryContainer`: the `library`; the `path` of its sidecar relative to the
library root, as a walk's findings on the sidecar name it; the `container` as
the library's own sidecar says it, with that library's presentations, in the form
`GET /v1/containers/{id}` answers; and `declined`, the refs the sidecar declines, each a
`provider` and `value`, which `GET /v1/containers/{id}` does not carry. `GET /v1/libraries/{library}/containers/{id}/smd`
SHALL answer the library's sidecar bytes as `GET /v1/containers/{id}/smd` answers
a sidecar. Each SHALL be 404 for a library the silo does not serve and for a
container the library does not hold, whether or not another library holds it.
These are read routes, and SHALL answer without a token.

#### Scenario: an unlisted container at the top of a library
- **WHEN** a library's top-level folders hold a listed series and an unlisted one, and a
  client asks for the library's containers
- **THEN** the 200 answer carries both, where `GET /v1/containers` carries the listed one
  alone

#### Scenario: each library's own view
- **WHEN** `films` and `films-4k` each hold a sidecar for one container, and a client asks
  each library for it
- **THEN** each answer names its own library and carries that library's presentations

#### Scenario: a container another library holds
- **WHEN** a client asks `films` for a container only `films-4k` holds
- **THEN** the answer is 404

#### Scenario: a library's declined refs
- **WHEN** a library's sidecar for a series declines a ref of provider `tmdb`, and a client asks
  the library for the series, and then asks `GET /v1/containers/{id}` for it
- **THEN** the library's answer carries the declined ref in `declined`, and the global answer
  carries none

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aLibrarysContainersAreReadWithinIt`,
`aLibrarysDeclinedRefsAreReadWithinIt`).

### Requirement: A container's own fields are edited in one library, on the sidecar the editor read
`PUT /v1/libraries/{library}/containers/{id}` with a JSON `ContainerEdit` — `document`, the
container as its repository XML; `basedOn`, the digest of the sidecar it was made from;
`dryRun`; `attributions`, optional, each a `subject`, `provider` and `value`; and `declined`,
optional, each a `provider` and `value` — SHALL set the container's own fields in that library's sidecar to the document's,
and SHALL change none of the library's facts but the paths of the folders it moves, the attributions of the
container's own fields and its declined refs: its presentations, its rules and its artwork's attributions stay as they
stand. With `attributions` absent, the sidecar's attributions of the container's own fields SHALL
stand as they are; present, they SHALL replace them, and one whose subject is an artwork kind SHALL
be 400. With `declined` absent, the sidecar's declined refs SHALL stand as they are; present,
they SHALL replace them. A sidecar's digest is the SHA-256 of its bytes as the index read
them, in lowercase hexadecimal, and the `LibraryContainer` a library's container route answers
SHALL carry it as `digest`. The answer SHALL be a `ContainerEditResult`: `applied`, the
sidecar's bytes as written or as they would be, their `digest`, the `findings`, and `moves`, each a
folder's path relative to the library `from` and `to`, made or as they would be made.

- A document that cannot be read, or that names another container, SHALL be 400, and a library
  the silo does not serve or a container it does not hold SHALL be 404.
- A `basedOn` that is not the digest of the sidecar the library holds SHALL be 409, decided
  under the lock the write is made under, with a `Problem` naming the digest it holds; nothing
  SHALL be written.
- An edit whose resulting sidecar has an error-severity finding SHALL be 422, carrying the
  result with its findings, and nothing SHALL be written. Besides the validator's checks, an
  item the document no longer declares SHALL be an error when the library holds presentations
  of it (`item <id> has presentations in this library`) or a sidecar for the container it names
  (`item <id> is a container this library holds`). An attribution, carried or left standing, of a
  field the document does not have is the validator's error
  (`<subject> is attributed to <provider> but the container has none`), so an outline is not
  removed while its attribution stands.
- An edit with `dryRun` true SHALL be answered 200 with `applied` false and write nothing.
- Otherwise the silo SHALL write the sidecar; SHALL rename the container's folder when the name
  the layout gives it is no longer the folder's, recording the new path in its parent's sidecar;
  SHALL rename the folder of each child the container holds whose position among its children the
  edit changed, recording each new path in the container's sidecar; SHALL re-read each sidecar it
  wrote, and each container it moved with the containers beneath it, into the index, under the same
  lock as the moves, so that no request finds a moved container at its old path; and SHALL answer
  200 with `applied` true, so that the next read of the container shows the edit. A rename
  that fails SHALL leave that folder where it is and SHALL be a warning-severity finding,
  `folder "<from>" could not be renamed "<to>": <reason>`; the rest of the edit stands.
- A presentation's id SHALL be the same after a move as before it.

The route SHALL require the operator's bearer, as every route that writes does; a missing or
wrong bearer SHALL be 401.

#### Scenario: a title corrected
- **WHEN** the operator puts a container's document with its year changed from 1997 to 1979,
  based on the digest the library's container route answered
- **THEN** the answer is 200 with `applied` true, the library's container reads the year 1979,
  its folder is renamed from `Alien (1997)` to `Alien (1979)` and listed in `moves`, and its
  presentations, keeping their ids, its children's paths and its rules are as they were

#### Scenario: an edit made from a sidecar that has changed
- **WHEN** an edit is based on a digest, and the sidecar has since been changed by another edit
- **THEN** the answer is 409 naming the digest the library holds, and the sidecar is unchanged

#### Scenario: an alternative a presentation names
- **WHEN** an edit removes the `theatrical` alternative, and the library holds two presentations
  of that alternative
- **THEN** the answer is 422 with an error for each presentation naming the alternative, and the
  sidecar is unchanged

#### Scenario: an item that has presentations
- **WHEN** an edit removes item `part1`, of which the library holds a presentation
- **THEN** the answer is 422 with the finding `item part1 has presentations in this library`,
  and the sidecar is unchanged

#### Scenario: a dry run
- **WHEN** an edit that would apply is put with `dryRun` true
- **THEN** the answer is 200 with `applied` false and the sidecar as it would be written, and the
  sidecar on disk is unchanged

#### Scenario: an edit without the operator's bearer
- **WHEN** an edit is put with no `Authorization` header
- **THEN** the answer is 401

#### Scenario: a child inserted before another
- **WHEN** a series holding a serial in `01 - Pyramids of Mars` is edited to name another child
  before it
- **THEN** the serial's folder is renamed `02 - Pyramids of Mars`, the series' sidecar records
  `02 - Pyramids of Mars/container.smd`, and the presentations beneath keep their ids

#### Scenario: an outline taken with its attribution
- **WHEN** the operator puts a document with a new outline, carrying an attribution of `outline` to
  provider `tmdb`
- **THEN** the answer is 200 with `applied` true, and the library's container reads the outline with
  that attribution

#### Scenario: an edit that carries no attributions
- **WHEN** a container's outline is attributed to a provider, and an edit changing only its year
  carries no `attributions`
- **THEN** the outline's attribution stands

#### Scenario: an attributed outline removed alone
- **WHEN** an edit removes a container's outline and carries no `attributions`, and the sidecar
  attributes the outline to `tmdb`
- **THEN** the answer is 422 with the finding
  `outline is attributed to tmdb but the container has none`, and the sidecar is unchanged

#### Scenario: a ref declined
- **WHEN** the operator puts a container's document unchanged, carrying `declined` with provider
  `tmdb` and one value
- **THEN** the answer is 200 with `applied` true, the library's container reads that declined ref,
  and its own fields are as they were

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aContainersOwnFieldsAreEditedOntoTheSidecarRead`,
`anEditMovesTheFoldersItRenames`, `anEditCarriesTheAttributionsOfItsFields`,
`anEditCarriesTheRefsItDeclines`).

### Requirement: A container's artwork is read, put and removed by kind
The `LibraryContainer` a library's container route answers SHALL carry `artwork`, the kinds the
container's folder holds, read from the folder when asked rather than from the index.
`GET /v1/libraries/{library}/containers/{id}/artwork/{kind}` SHALL answer 200 with the kind's
image and its content type, or 404 when the folder holds none; it is a read route, and SHALL
answer without a token. `PUT` on the same path SHALL take the image's bytes and SHALL accept a
JPEG or a PNG, told by the bytes' signature rather than the declared type: anything else SHALL be
415, and an image over 25 MB SHALL be 413. It SHALL write the file as `<kind>.jpg` or
`<kind>.png` by writing beside it and renaming, SHALL remove the kind's file in the other format
if there is one, and SHALL answer 200 with the kind and its format. A `PUT` MAY carry the query parameters `provider` and `value`, both or
neither, one alone being 400: with them, the silo SHALL record in the container's sidecar the
attribution of `artwork/<kind>` to that provider and value, and without them SHALL remove any
attribution the kind had. When a put records an attribution, the sidecar SHALL be written before
the image, and when it removes one, the image before the sidecar, so that an interrupted put
credits the provider for too much rather than leaving its image uncredited. A sidecar a put or a
delete writes SHALL be re-read into the index, and its digest changes as after an edit. `DELETE`
on the same path SHALL remove the kind's file, and the kind's attribution if it has one, and
answer 204, or 404 when there is none. A kind that is not one of
the artwork kinds, a library the silo does not serve, and a container it does not hold SHALL be
404. `PUT` and `DELETE` SHALL require the operator's bearer; a missing or wrong bearer SHALL be
401.

#### Scenario: a poster put and served
- **WHEN** the operator puts a JPEG as a container's `poster`
- **THEN** the answer is 200, the container's `artwork` includes `poster`, and getting the
  poster answers the same bytes as `image/jpeg`

#### Scenario: a PNG replaces a JPEG
- **WHEN** the operator puts a PNG as the `poster` of a container whose folder holds
  `poster.jpg`
- **THEN** the folder holds `poster.png` and no `poster.jpg`

#### Scenario: a file that is not an image
- **WHEN** the operator puts a text file as a `poster`
- **THEN** the answer is 415, and the folder is unchanged

#### Scenario: a poster removed
- **WHEN** the operator deletes a container's `poster`
- **THEN** the answer is 204, the folder holds no poster, and getting the poster is 404

#### Scenario: a poster put with its attribution
- **WHEN** the operator puts a JPEG as a container's `poster` with `provider` `tmdb` and `value`
  `348`
- **THEN** the answer is 200, and the container carries an attribution of `artwork/poster` to
  `tmdb` with value `348`

#### Scenario: an attributed poster replaced with the operator's own
- **WHEN** a container's `poster` is attributed to a provider, and the operator puts a PNG as its
  `poster` with no provider
- **THEN** the poster is the PNG, and the container carries no attribution of it

#### Scenario: a provider with no value
- **WHEN** the operator puts a poster with a `provider` and no `value`
- **THEN** the answer is 400, and the folder and the sidecar are unchanged

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aContainersArtworkIsPutServedAndRemoved`,
`aContainersArtworkIsPutWithItsAttribution`).

### Requirement: Containers are made in a library without a file
`POST /v1/libraries/{library}/containers` with a JSON `ContainerCreate` — `documents`, one or more
containers as repository XML; `parent`, the id of a container the library holds, or absent;
`dryRun`; and `attributions`, optional, each naming the `container` in the request it belongs to,
with its `subject`, `provider` and `value` — SHALL make each container in that library as a placement would make it, and SHALL place
no file. The documents SHALL form one tree: exactly one of them, the top, is named as a child by
none of the others, and every other is named as a child by a document in the request. With a
`parent`, the top SHALL be filed beneath the parent's folder; without one, at the top of the
library. Each container's sidecar SHALL hold the document's own fields, the request's attributions of
them, and no presentations, and
each parent's sidecar SHALL record its child's path. The answer SHALL be a `ContainerCreateResult`:
`applied`, the `writes`, each a sidecar's path relative to the library and whether it is new, and
the `findings`.

- A document that cannot be read, documents that do not form one tree, and an attribution naming a
  container the request does not carry or an artwork kind SHALL be 400, and a
  library the silo does not serve or a `parent` it does not hold SHALL be 404.
- A request with an error-severity finding SHALL be 422, carrying the result with its findings, and
  nothing SHALL be written. Besides the validator's checks on each sidecar, it SHALL be an error
  when the library already holds a container in the request
  (`container <id> is already at "<path>"`), when the parent's own fields do not name the top as a
  child (`<parent> does not name <top> as a child`), and when a folder the request would use holds a
  sidecar for another container (`the folder for <title> already holds <id>`).
- A request with `dryRun` true SHALL be answered 200 with `applied` false and write nothing.
- Otherwise the silo SHALL make the folders, write the new sidecars from the top down and then the
  parent's, re-read each sidecar it wrote into the index, and answer 200 with `applied` true, so
  that the next read of the library shows the containers. It SHALL NOT walk the library.

The route SHALL require the operator's bearer, as every route that writes does; a missing or wrong
bearer SHALL be 401.

#### Scenario: a series made at the top of an empty library
- **WHEN** the operator creates a series, one of its seasons and one serial of that season in a
  library with nothing in it, with no parent
- **THEN** the answer is 200 with `applied` true and three new sidecars, and the library's
  containers answer the series, with the season and the serial beneath it and no presentations

#### Scenario: a season made beneath a series the library holds
- **WHEN** the operator creates a season beneath a series the library holds, whose own fields name
  the season as a child
- **THEN** the season's sidecar is new, the series' sidecar is updated with the season's path alone,
  and the series' presentations and own fields are as they were

#### Scenario: a container the library already holds
- **WHEN** a request carries a serial the library already holds, beneath a season it does not
- **THEN** the answer is 422 with the finding that the serial is already at its folder, and nothing
  is written

#### Scenario: a parent that does not name the top
- **WHEN** a season is created beneath a series the library holds, and the series' sidecar does not
  name the season as a child
- **THEN** the answer is 422 with the finding that the series does not name the season, and nothing
  is written

#### Scenario: a dry run
- **WHEN** a request that would apply is posted with `dryRun` true
- **THEN** the answer is 200 with `applied` false and the writes it would make, and the library is
  unchanged

#### Scenario: a placement into a container made this way
- **WHEN** a serial has been created with no presentations, and a presentation of one of its parts
  is then placed with a lineage carrying a different outline for the serial
- **THEN** the serial's sidecar keeps the outline it was created with, and holds the presentation

#### Scenario: a create without the operator's bearer
- **WHEN** a create is posted with no `Authorization` header
- **THEN** the answer is 401

#### Scenario: a film made with an attributed outline
- **WHEN** the operator creates a film with an outline, and the request attributes the film's
  outline to provider `tmdb`
- **THEN** the film's new sidecar holds the outline and its attribution, and the library's container
  reads both

Pinned by: `Tests/SiloTests/ServerTests.swift` (`containersAreMadeInALibraryWithoutAFile`,
`aCreateCarriesItsAttributions`).
