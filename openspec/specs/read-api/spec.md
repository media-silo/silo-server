<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Read API

## Purpose

The read API is the HTTP surface a client browses: the libraries the silo
serves, their containers and presentations, provider lookup and title search,
a container as its sidecar, a presentation as bytes, the stored rulesets, the
resolver's dry run, and the one read that is also a trigger — a scan. Every
answer comes from the index, which is the index-and-rulesets capability's to
keep; this spec starts at the routes and stops at the index's door. Placement,
jobs and nodes are other capabilities' routes and are not described here.

Rationale: [Silo proposal — Discovery and playback](../../../Proposals/Silo.md) —
the read routes follow Hosting.md's, so a client of the shared store finds a
library familiar; principles 1 (the `.smd` is the truth) and 8 (not a playback
engine) govern.
Documentation: [README](../../../README.md).

## Requirements

### Requirement: The HTTP surface is the OpenAPI document
The routes SHALL be versioned under `/v1` and described by the OpenAPI document
at `Sources/SiloAPI/openapi.yaml` (OpenAPI 3.1.0, title `Silo`, server `/v1`),
from which the `SiloAPI` target's types are generated: the build is the check
that the document and the implementation agree, since each operation the
document names is served by a controller's handler and no handler answers an
operation the document does not name. Two routes that stream bytes SHALL be
served beside the document, since an operation buffers its body whole:
`GET /v1/media/{presentation}` and `GET /v1/containers/{id}/smd`; the
document's description SHALL say so. `GET /health` SHALL be answered 200, an
operational endpoint outside the document on purpose. A request nothing routes
SHALL be 404 with the body `{"detail":"not found"}` as `application/json`.

#### Scenario: the health endpoint answers, outside the document
- **WHEN** a client asks `GET /health`
- **THEN** the answer is 200

#### Scenario: a route nothing owns
- **WHEN** a client asks `GET /nowhere`
- **THEN** the answer is 404 with `{"detail":"not found"}` as `application/json`

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theLibraryIsBrowsable`).
A test comparing the whole app against the document is pinned by nothing yet.

### Requirement: The API's types are the sidecar's elements as JSON
One model, per principle 2: the document's schemas SHALL be the sidecar's
elements as JSON, never a separate API vocabulary. A `Container` SHALL carry
the sidecar's `type`, `title`, `displayTitle`, `year`, `typeLabel`, `outline`,
`listed`, `defaultAlternative`, `alternatives`, `features` with their
`participants`, `sequences`, `extrasAnchor`, `extras`, `externalRefs`, and its
child containers as summaries; an `Item` SHALL carry its `optional`, `ref`,
`externalRefs` and `presentations`; a `Presentation` SHALL carry `id`,
`alternative`, `profile`, `displayName`, `file`, `source`, `tracks` and
`chapters`, with a track's `audio` and `subtitle` counting from one among the
streams of that kind. The mapping SHALL run one way only: the API is a
projection of the model, never a place the model is edited.

#### Scenario: a container reads as the sidecar's values
- **WHEN** a client asks `GET /v1/containers/0000000000000003`
- **THEN** the 200 answer carries `"typeLabel":"Story"`,
  `"parent":"0000000000000001"`, and in its presentations
  `"displayName":"mobile"`, `"file":"Part One.mkv"` and a track's `"audio":3`

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theLibraryIsBrowsable`).

### Requirement: The libraries are listed, with what they hold
`GET /v1/libraries` SHALL answer 200 with one object per configured library —
its `id`, the count of `containers` under its roots, and the count of
`presentations` across those containers, walked the whole tree down.

#### Scenario: the one library and its counts
- **WHEN** a client asks `GET /v1/libraries`
- **THEN** the 200 answer names `"id":"main"` and counts `"presentations":2`

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theLibraryIsBrowsable`).

### Requirement: The listed roots are browsable; the unlisted are reachable by id
`GET /v1/containers` SHALL answer 200 with the listed roots — containers
nothing holds, and that are listed — each as a `ContainerSummary` (`id`,
`library`, `type`, `title`, `displayTitle`, `year`, `typeLabel`, `outline`,
`listed`, `parent`); a `library` query parameter SHALL narrow the answer to one
library. An unlisted container SHALL NOT appear here, but SHALL be reachable by
id and through the containers that reference it. `GET /v1/containers/{id}`
SHALL be 404 on an id nothing holds and on a malformed id — a container id is
sixteen lowercase hex characters, minted by the shared store.

#### Scenario: the roots omit the unlisted
- **WHEN** a client asks `GET /v1/containers`
- **THEN** the 200 answer contains `Doctor Who (1963)` and not
  `Behind the Sofa`

#### Scenario: an unlisted container answers by id
- **WHEN** a client asks `GET /v1/containers/0000000000000004`
- **THEN** the answer is 200

#### Scenario: ids that name nothing
- **WHEN** a client asks `GET /v1/containers/00000000000000ff` or
  `GET /v1/containers/not-an-id`
- **THEN** the answer is 404

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theLibraryIsBrowsable`).

### Requirement: One container answers with its presentations
`GET /v1/containers/{id}` SHALL answer 200 with the container and, for every
item in its sequences and extras, the presentations the index holds for that
item — the same presentations the media route takes, by id, stable across
rescans. A container the index does not hold SHALL be 404.

#### Scenario: the serial and its presentations
- **WHEN** a client asks `GET /v1/containers/0000000000000003`
- **THEN** the 200 answer's sequences list the serial's three parts, each part
  an item with its presentations

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theLibraryIsBrowsable`).

### Requirement: A profile is a filter, never a decision
Given `?profile=` on `GET /v1/containers/{id}`, the answer's items SHALL keep
only presentations of that profile. The silo SHALL NOT pick, substitute or
synthesise a presentation on a client's behalf: per principle 8 the silo is
not a playback engine, and a client that wants a profile reads the item's
presentations and picks. An item with no presentation of the profile SHALL
read as having none.

#### Scenario: the mobile filter
- **WHEN** a client asks `GET /v1/containers/0000000000000003?profile=mobile`
- **THEN** the 200 answer contains `Part One - mobile.mkv` and does not
  contain `"file":"Part One.mkv"` — filtered, never substituted

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theLibraryIsBrowsable`).

### Requirement: A container is served as its sidecar
`GET /v1/containers/{id}/smd` SHALL answer 200 with the sidecar's bytes
exactly as the index recorded them, with `Content-Type`
`application/xml; charset=utf-8` and the document's `Content-Length`. A
container the index does not hold SHALL be 404.

#### Scenario: the bytes as they are on disk
- **WHEN** a client asks `GET /v1/containers/0000000000000003/smd`
- **THEN** the 200 answer's body equals, byte for byte, the library's
  `Doctor Who (1963)/Pyramids of Mars/container.smd`, and
  `GET /v1/containers/00000000000000ff/smd` is 404

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theSidecarIsServedAsItIs`).

### Requirement: A provider's id and a title are discoverable
`GET /v1/lookup?provider=&value=` SHALL require both parameters and answer 200
with a `ContainerSummary` for every container carrying the reference, directly
or through an item. `GET /v1/search?q=` SHALL require `q` (at least one
character) and answer 200 with a `SearchHit` — `container`, `item`, `title` —
for each title matching, across containers and items.

#### Scenario: a tvdb id resolves
- **WHEN** a client asks `GET /v1/lookup?provider=tvdb&value=76107`
- **THEN** the 200 answer names container `0000000000000001`

#### Scenario: a title fragment matches
- **WHEN** a client asks `GET /v1/search?q=part`
- **THEN** the 200 answer contains `Part Two`

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theLibraryIsBrowsable`).

### Requirement: A presentation is served as bytes, whole and by range
`GET /v1/media/{presentation}` SHALL take a presentation's id and answer the
file, streaming; an id nothing holds SHALL be 404. The head SHALL carry
`Accept-Ranges: bytes`, an `ETag` of `"<size>-<modification time>"`, the
`Content-Length` and a `Content-Type` from the file's extension — `.mkv` as
`video/x-matroska`, `.mp4` and `.m4v` as `video/mp4`, anything else
`application/octet-stream`. One satisfiable single range — `bytes=a-b`,
`bytes=a-` or `bytes=-n`, an end past the file clipped to the last byte —
SHALL be 206 with `Content-Range: bytes <start>-<end>/<size>`; several ranges,
or a unit that is not `bytes`, SHALL be answered as the whole file; a range
the file cannot satisfy SHALL be 416 with `Content-Range: bytes */<size>`.
HEAD SHALL be answered as the GET's head alone, and the file SHALL go to the
writer a chunk at a time rather than buffered whole. A presentation placed
during the server's run SHALL be served by its new id at once, without a scan
being asked for.

#### Scenario: the whole file
- **WHEN** a client asks `GET /v1/media/{presentation}` for a 3000-byte
  presentation
- **THEN** the answer is 200 with `Accept-Ranges: bytes`,
  `Content-Type: video/x-matroska`, an `ETag`, and the body's bytes are the
  file's

#### Scenario: a part of the file
- **WHEN** the client sends `Range: bytes=100-199`
- **THEN** the answer is 206, `Content-Range: bytes 100-199/3000`, and the
  body is exactly those hundred bytes; `bytes=2900-` answers 206 from byte
  2900 to the end, and `bytes=-10` answers with
  `Content-Range: bytes 2990-2999/3000`

#### Scenario: a range the file cannot satisfy
- **WHEN** the client sends `Range: bytes=5000-`
- **THEN** the answer is 416 with `Content-Range: bytes */3000`, and
  `GET /v1/media/0000000000000000` is 404

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`mediaIsServedWholeAndByRange`, `rangesAreParsedAsTheSpecificationSays`,
`zPlacementIsShownThenAppliedAndRefusedTheSecondTime`).

### Requirement: A scan re-reads what changed, and is the operator's to run
`POST /v1/libraries/{library}/scan` SHALL walk the library and re-read only
the sidecars whose modification time or size differs from the index's record,
answering 200 with a `ScanReport` — the counts `read`, `unchanged`, `removed`
and the `findings`, each a `severity` of `error` or `warning` with an optional
`path` and its `text`. A library the silo is not configured with SHALL be 404.
The route is the operator's alone; the gate itself is the token requirement
below.

#### Scenario: a scan with nothing to read
- **WHEN** the operator posts to `/v1/libraries/main/scan` against an
  unchanged library
- **THEN** the 200 answer reports `"read":0` and `"unchanged":3`

#### Scenario: a library the silo does not serve
- **WHEN** the operator posts to `/v1/libraries/other/scan`
- **THEN** the answer is 404

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aScanIsAnOperatorsToo`).

### Requirement: The stored rulesets are read at their latest version, or the one asked for
`GET /v1/rulesets` SHALL answer 200 with one `RulesetSummary` — `name` and
`version` — per ruleset, at its latest version. `GET /v1/rulesets/{name}`
SHALL answer 200 with a `RulesetDocument`: the `name`, the `version`, and the
`document` as the XML that was stored, byte for byte; a `version` query
parameter SHALL select a version other than the latest. A name the silo does
not hold, or a version it does not hold, SHALL be 404.

#### Scenario: the list, the latest and a named version
- **WHEN** `household` has been stored twice and a client asks
  `GET /v1/rulesets`, `GET /v1/rulesets/household` and
  `GET /v1/rulesets/household?version=1`
- **THEN** the list reads `household@2`, the latest answers version 2, and
  version 1's `document` equals, byte for byte, the document first stored

#### Scenario: names and versions the silo does not hold
- **WHEN** a client asks `GET /v1/rulesets/household?version=9` or
  `GET /v1/rulesets/nothing`
- **THEN** the answer is 404

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`).

### Requirement: Every ruleset store is a new version, and is the operator's
`PUT /v1/rulesets/{name}` with a JSON `RulesetDocument` SHALL store the
`document` as the name's next version — the latest plus one, or 1 for a new
name — and answer 201 with the version the silo assigned; a `version` in the
body SHALL be ignored on a store, since numbering is the silo's. A document
the ruleset reader refuses SHALL NOT be stored, and the answer SHALL be 400
with a `Problem` whose `detail` says why. The route is the operator's.

#### Scenario: two stores are numbered in order
- **WHEN** the operator puts the household ruleset at `/v1/rulesets/household`
  twice
- **THEN** the answers are 201 with `version` 1 and then 2

#### Scenario: a document that is not a ruleset is refused
- **WHEN** the operator puts a document testing `<when fact="nope" is="1"/>`
- **THEN** the answer is 400 with `not a fact a rule can test` in the problem
  detail, and nothing is stored

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`).

### Requirement: The resolver runs as a dry run
`POST /v1/rulesets/{name}/resolve` with a JSON `ResolveRequest` — the source's
`facts` and optional track `mappings` — SHALL answer 200 with the `Recipe` the
resolver makes against the ruleset's latest version, or the version `?version=`
names: its `ruleset` as `name@version`, one decision per source stream naming
the `rule` that made it, the `output` policy, the `layout`, and `warnings`. A
ruleset or version the silo does not hold SHALL be 404, and a stream no rule
decides SHALL be 422 with a `Problem` detail naming the stream. The route is a
dry run: no library, index or ruleset SHALL change because of it, and nothing
is encoded.

#### Scenario: the recipe before anything is encoded
- **WHEN** a client posts the fixture's facts to
  `/v1/rulesets/household/resolve`
- **THEN** the 200 answer's decisions name the rules `small-extras`,
  `lossless-main` and `commentary`, and its ruleset reads `household@2`

#### Scenario: a stream no rule decides
- **WHEN** the same facts are posted against a ruleset whose only rule is a
  video catch-all
- **THEN** the answer is 422 with `no rule decides audio 1` in the problem
  detail

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`).

### Requirement: The operator's token gates mutation; the server is told itself through its environment
Every mutation route on this surface — the scan and the ruleset store — SHALL
require the `Authorization` header to carry the configured operator token as
`Bearer <token>`, matched exactly; a missing or wrong token SHALL be 401. No
token configured SHALL mean no operator route works, which is the safe way
round for a server otherwise open on a household network. The read routes
SHALL answer without any token. The silo SHALL read its environment once,
before anything is served: `SILO_LIBRARIES` as `name=path,name=path` — or one
bare path, which is the library `main` — `SILO_STATE_DIR` for its state
directory (default `silo-state`), and `SILO_OPERATOR_TOKEN` for the
operator's, an empty value meaning none; a configured library whose path does
not exist SHALL stop the boot with an error naming the library.

#### Scenario: the gate on the routes this spec owns
- **WHEN** a client puts `/v1/rulesets/household` with no `Authorization`
  header, or with `Bearer wrong`
- **THEN** the answer is 401 both times, while `Bearer secret` — the token the
  environment configured — is 201, and a scan follows the same rule

#### Scenario: the environment the server reads
- **WHEN** the suite's server is brought up
- **THEN** its environment is `SILO_LIBRARIES`, `SILO_STATE_DIR` and
  `SILO_OPERATOR_TOKEN`, and the read routes answer under the library `main`

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`, `aScanIsAnOperatorsToo`).
