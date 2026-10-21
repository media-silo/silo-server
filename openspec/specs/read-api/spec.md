<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Read API

## Purpose

The read API is the HTTP surface a client browses: the libraries the silo
serves, their containers and presentations, provider lookup and title search,
a container as its sidecar, a presentation as bytes, the stored rulesets, the
resolver's dry run, and the one read that is also a trigger — a scan. Every
answer comes from the [index](../index/spec.md), or, for a ruleset, from the
store [rulesets](../rulesets/spec.md) describes, and each of those is its own
capability's to keep; this spec starts at the routes and stops at their door. Placement,
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

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theLibraryIsBrowsable`).

### Requirement: The libraries are listed, with what they hold
`GET /v1/libraries` SHALL answer 200 with one object per configured library —
its `id`, the count of `containers` under its roots, the count of
`presentations` across those containers, walked the whole tree down, and
whether it is `available`.

#### Scenario: the one library and its counts
- **WHEN** a client asks `GET /v1/libraries`
- **THEN** the 200 answer names `"id":"main"`, counts `"presentations":2`, and
  reads `"available":true`

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
rescans. A container the index does not hold SHALL be 404. A container held by
more than one library SHALL be answered as the first of them in the order
`settings.json` lists the libraries holds it — its sidecar and that library's
presentations — and the answer SHALL name that `library`.

#### Scenario: the serial and its presentations
- **WHEN** a client asks `GET /v1/containers/0000000000000003`
- **THEN** the 200 answer's sequences list the serial's three parts, each part
  an item with its presentations

#### Scenario: a container in two libraries
- **WHEN** `settings.json` lists `films` before `films-4k`, each holds a sidecar
  for one container, and a client asks for the container
- **THEN** the 200 answer names `films` as its library and carries the
  presentations `films` holds and not those `films-4k` holds

Pinned by: `Tests/SiloTests/ServerTests.swift` (`theLibraryIsBrowsable`,
`aLibrarysContainersAreReadWithinIt`).

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
  `Doctor Who (1963)/01 - Pyramids of Mars/container.smd`, and
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
being asked for. A presentation whose file the route finds missing SHALL be
served from the file its container's sidecar records once the route has re-read
it, when that is another file that is there, by the same id; only when the
re-read leaves no file for the id SHALL the answer be 404.

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

#### Scenario: a file moved
- **WHEN** a presentation's file is moved within its container's folder and its
  sidecar edited to name it there, and a client asks for the presentation by the
  id it had before
- **THEN** the answer is 200 with the file from its new path

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`aMovedFileIsServedByTheIdItHad`, `mediaIsServedWholeAndByRange`, `rangesAreParsedAsTheSpecificationSays`,
`zPlacementIsShownThenAppliedAndRefusedTheSecondTime`).

### Requirement: The stored rulesets are read at their latest version, or the one asked for
`GET /v1/rulesets` SHALL answer 200 with one `RulesetSummary` per ruleset: its `name`; its `version`,
the latest number; its `standard`, the standard's head; and its `versions`, every version ascending,
each with its `branch`, its `parent` and `presentations`, the number of placed presentations whose
committed recipe names it. `GET /v1/rulesets/{name}` SHALL answer 200 with a `RulesetDocument`: the
`name`, the `version`, its `branch`, the `document` as the XML that was stored, byte for byte, and the
`reading` — each rule in document order with the name a recipe calls it by
(its `id`, or `#n` for its position), its scope, its conditions as fact, test and value, and its
action, and the outputs; a `version` query parameter SHALL select a version other than the latest. The
reading SHALL name the ruleset by where it was stored, whatever the document's own attributes say. A
name the silo does not hold, or a version it does not hold, SHALL be 404.

#### Scenario: the list, the latest and a named version
- **WHEN** `household` has been stored twice and a client asks
  `GET /v1/rulesets`, `GET /v1/rulesets/household` and
  `GET /v1/rulesets/household?version=1`
- **THEN** the list reads `household@2` with versions 1 and 2 on the standard, the latest answers
  version 2, and version 1's `document` equals, byte for byte, the document first stored

#### Scenario: names and versions the silo does not hold
- **WHEN** a client asks `GET /v1/rulesets/household?version=9` or
  `GET /v1/rulesets/nothing`
- **THEN** the answer is 404

#### Scenario: a reading names its rules as a recipe does
- **WHEN** a ruleset's document holds a rule with `id="commentary"` and, fifth in the document, a
  condition-less `<audio><copy/></audio>`
- **THEN** the reading names the first `commentary` and the second `#5`, each with its scope, its
  conditions and its action

#### Scenario: what each version made
- **WHEN** a ruleset's version 1 made three placed presentations and its version 2 none
- **THEN** the list reports `presentations` 3 for version 1 and 0 for version 2

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`, `aRulesetIsReadWholeADraftCheckedAndAStoreBasedOnItsHead`),
`Tests/SiloTests/CheckTests.swift` (`eachVersionReportsThePresentationsItMade`).

### Requirement: Every ruleset store is a new version, and is the operator's
`PUT /v1/rulesets/{name}` with a JSON `RulesetDocument` SHALL store the `document` as the next version
of the name — on the standard, or on the `branch` the body names — and answer 201 with the version the
silo assigned; a `version` in the body SHALL be ignored on a store, since numbering is the silo's. A
document the ruleset reader refuses SHALL NOT be stored, and the answer SHALL be 400 with a `Problem`
whose `detail` says why. The body MAY carry `basedOn`, the head of the branch it is stored to that the
document was made from, or zero for a name that must be new; the store SHALL then go ahead only if
that is still the head, decided under the lock the version number is taken under, and otherwise SHALL
store nothing and answer 409 with a `Problem` naming the head. Without `basedOn` the store SHALL go
ahead whatever the head. The route is the operator's.

#### Scenario: two stores are numbered in order
- **WHEN** the operator puts the household ruleset at `/v1/rulesets/household`
  twice
- **THEN** the answers are 201 with `version` 1 and then 2

#### Scenario: a document that is not a ruleset is refused
- **WHEN** the operator puts a document testing `<when fact="nope" is="1"/>`
- **THEN** the answer is 400 with `not a fact a rule can test` in the problem
  detail, and nothing is stored

#### Scenario: two editors from one base
- **WHEN** two stores to the standard are each based on version 3, the standard's head
- **THEN** the first is 201 with version 4, and the second is 409 naming version 4 and stores nothing

#### Scenario: a new name, and one that is not new
- **WHEN** a store is based on zero for a name the silo has no version of, and another based on zero
  for `household`
- **THEN** the first is 201 with version 1, and the second is 409

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`, `aRulesetIsReadWholeADraftCheckedAndAStoreBasedOnItsHead`).

### Requirement: The resolver runs as a dry run
`POST /v1/rulesets/{name}/resolve` with a JSON `ResolveRequest` — one or more input specs, joined in
order as a binding's segments are, and what a binding would add to them: the optional `kind` and
`extra`, each absent when left out, the
`roles` of the audio streams a feature map names, and the track `mappings` for renumbering — SHALL
answer 200 with a `Recipe` for each of the ruleset's outputs, in the ruleset's order, resolved
against its latest version, or the version `?version=` names: each with its `ruleset` as
`name@version`, its output, one decision per stream naming the `rule` that made it, the `layout`,
and `warnings`. A ruleset or version the silo does not hold SHALL be 404; an input spec the silo
refuses, or specs that cannot be joined, SHALL be 400 with the reason; and a stream no rule decides
for any output SHALL be 422 with a `Problem` detail naming the stream and the output. The route is a
dry run: no source, binding, recipe, job, library, index or ruleset SHALL change because of it, and
nothing is encoded.

#### Scenario: the recipe before anything is encoded
- **WHEN** a client posts the input spec of an episode with a lossless main mix and a commentary to
  `/v1/rulesets/household/resolve`, `household` being at version 2 with one output
- **THEN** the 200 answer holds one recipe, whose decisions name the rules `lossless-main` and
  `commentary` for the two audio streams, and whose ruleset reads `household@2`

#### Scenario: an extra resolved without a binding
- **WHEN** the same input spec is posted with `extra` true against a ruleset whose first video rule
  holds when `extra` is true
- **THEN** the recipe's video decision names that rule, and posted without `extra` it does not

#### Scenario: a stream no rule decides
- **WHEN** the same input spec is posted against a ruleset whose only rule is a video catch-all
- **THEN** the answer is 422 with `no rule decides audio 1` in the problem detail

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`, `theDryRunTakesWhetherTheItemIsAnExtra`).

### Requirement: The operator's credential gates mutation; the server is told itself through its state directory
Every mutation route on this surface — the library routes and the ruleset
store — and the last-walk read SHALL
require the `Authorization` header to carry a bearer the operator credential
accepts, per [onboarding](../onboarding/spec.md); a missing or wrong bearer
SHALL be 401. No credential installed SHALL mean no operator route works, which
is the safe way round for a server otherwise open on a household network. The
read routes SHALL answer without any token. Of its environment the silo SHALL
read only `SILO_STATE_DIR`, before anything is served; everything else it is
told — where it listens and which libraries it serves — SHALL come from
`silo.json` and `settings.json` in its state directory, as
[configuration](../configuration/spec.md) sets out.

#### Scenario: the gate on the routes this spec owns
- **WHEN** a client puts `/v1/rulesets/household` with no `Authorization`
  header, or with `Bearer wrong`
- **THEN** the answer is 401 both times, while `Bearer secret` — the token the
  installed credential accepts — is 201, and the last-walk read follows the same rule

#### Scenario: the environment the server reads
- **WHEN** the suite's server is brought up over a state directory whose
  `settings.json` names the library `main` and whose credential accepts
  `secret`
- **THEN** its environment is `SILO_STATE_DIR` alone, and the read routes
  answer under the library `main`

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`rulesetsAreVersionedAndTheOperatorGateHolds`, `aScanIsAnOperatorsToo`).

### Requirement: A ruleset's branches are listed, started, stored on and promoted
`GET /v1/rulesets/{name}/branches` SHALL answer 200 with each branch of the ruleset — its name,
its base, its head, the standard version it is up to date with, and whether it is closed — the
standard first. `POST /v1/rulesets/{name}/branches` with a branch name and a standard version SHALL
start a branch from that version and answer 201; a name taken in the ruleset is 409, and a version
not on the standard is 400. `PUT /v1/rulesets/{name}` SHALL accept a `branch`, storing on that
branch, and an `upToDateWith`, the standard version the stored document takes in; a closed branch is
409. `POST /v1/rulesets/{name}/branches/{branch}/promote` SHALL promote the branch and answer 201
with the standard's new version, or 409 with a `Problem` naming the standard versions the branch has
not taken in. Every route here that changes something is the operator's. A ruleset or branch the
silo does not hold is 404.

#### Scenario: a branch is started, stored on and promoted
- **WHEN** the operator starts `trial` from `household@7`, puts a document on it, and promotes it
  while the standard's head is 7
- **THEN** the answers are 201, 201 with version 8, and 201 with version 9, and the branch list
  shows `trial` closed

#### Scenario: a promotion that would lose the standard's work
- **WHEN** the standard gained version 9 after `trial` was started from 7, and the operator
  promotes `trial`
- **THEN** the answer is 409 naming version 9, and the standard's head is still 9

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aBranchIsStartedStoredOnAndPromoted`).

### Requirement: The out-of-date presentations of a library are read, and so is a promotion's impact
`GET /v1/libraries/{library}/out-of-date` SHALL answer 200 from the check records: each out-of-date
presentation with its container, item, file and profile, the committed recipe that made it, the stack
it was made by and the stack it was checked against, every stream that would change with what it got
and what it would get, and its binding's sources with their copies; the number of the library's placed
presentations still to be checked; and the number placed without a job. `GET
/v1/rulesets/{name}/branches/{branch}/impact` SHALL answer, in the same shape, the presentations that
promoting the branch would put out of date, resolved on request and recording nothing. Both SHALL be
open, as the queue is, and a copy SHALL be rendered without its secret. A library, ruleset or branch
the silo does not hold is 404.

#### Scenario: a promotion's impact is its outcome
- **WHEN** a branch's impact is read, the branch is then promoted with nothing else changing, and the
  background check finishes
- **THEN** the library's out-of-date presentations are those the impact listed, and none is still to
  be checked

#### Scenario: presentations with no recipe are counted
- **WHEN** a library holds one presentation placed by a job and two placed without one, and the rules
  have changed so that every one of them would be made differently
- **THEN** the report lists the one, and counts two placed without a job

Pinned by: `Tests/SiloTests/CheckTests.swift` (`aPromotionThatChangesADecisionLeavesThePresentationOutOfDate`, `aContainersRulesReachThePresentationsBelowItAndNoOthers`), `Tests/SiloTests/ServerTests.swift` (`theOutOfDateReportAndABranchsImpactAreReadOpenly`).

### Requirement: A rules document is checked as a store would check it, and nothing is stored
`POST /v1/rulesets/{name}/check` with a `RulesetDocument` SHALL check the name as a store checks it and
read the document as a store reads it, and SHALL answer 200 with the reading a `GET` of the stored
document would carry, or 400 with a `Problem` whose detail is the one a store of the same document
under the same name would give. It SHALL store nothing and change nothing, and SHALL be answered
without a token, as the resolver's dry run is.

#### Scenario: a mistyped fact
- **WHEN** a client checks a document testing `<when fact="subtitle.forcd" is="true"/>`
- **THEN** the answer is 400 with the detail a store would give, and no version is added

#### Scenario: a draft that reads
- **WHEN** a client checks a document the reader accepts
- **THEN** the answer is 200 with its reading, and no version is added

Pinned by: `Tests/SiloTests/ServerTests.swift`
(`aRulesetIsReadWholeADraftCheckedAndAStoreBasedOnItsHead`).

### Requirement: A draft's impact on placed presentations is read, and nothing is stored
`POST /v1/rulesets/{name}/impact` with a draft document and the version it is based on SHALL answer
200 with every placed presentation whose committed recipe names a version on the base's branch,
resolved again as the background check resolves it but with the draft in place of the ruleset, the
rest of its stack as it stands, and reported as the out-of-date report reports a presentation — its
container, item and file, the stack that made it, the streams that would change from what to what,
and its binding's sources with their copies, never their secrets — leaving out each the draft would
make as it was made. A document the reader refuses SHALL be 400 as a check answers it, and a ruleset or
base the silo does not hold 404. It SHALL record nothing and change nothing, and SHALL be answered
without a token.

#### Scenario: a draft's impact is what the check finds once it is in force
- **WHEN** a draft's impact is read, the draft is then stored as the head of its base's branch with
  nothing else changing, and the background check finishes
- **THEN** the presentations the check reports out of date are those the impact listed

Pinned by: `Tests/SiloTests/CheckTests.swift` (`aDraftsImpactIsWhatTheCheckFindsOnceItIsInForce`),
`Tests/SiloTests/ServerTests.swift` (`aRulesetIsReadWholeADraftCheckedAndAStoreBasedOnItsHead`).

### Requirement: Trials are listed, served by range, fetched again and deleted
`GET /v1/trials` SHALL answer 200 with every tried trial: its job, its recipe's ruleset, version and
the branch the version is on, its binding, its output's profile, and the encode's result, filtered by
`ruleset` and `branch` when they are given. `GET /v1/trials/{job}/file` SHALL serve the trial's output
as a presentation is served, whole and by range. `POST /v1/trials/{job}/fetch` SHALL fetch an encoded
trial's output again and answer the job, 409 for a trial that is not encoded and 502 when the node
holding the output does not give it. `DELETE /v1/trials/{job}` SHALL delete the output and the job's
record, leaving its recipe committed, and answer 204. Fetching and deleting SHALL be the operator's.
For the file and the deletion a job that is not a tried trial SHALL be 404, and for the fetch a job
that is not a trial.

#### Scenario: a trial served and deleted
- **WHEN** a client asks for a tried trial's file with a range, and the operator then deletes the
  trial
- **THEN** the range is served as 206, and the trial is no longer listed

Pinned by: `Tests/SiloTests/ServerTests.swift` (`yTrialsAreListedServedAndDeletedOverTheAPI`).

### Requirement: An unavailable library is kept, and says so
A library SHALL be unavailable while its folder does not exist, or while its last walk found no
container at its top level where the index holds containers for it. While a library is unavailable
the silo SHALL keep its index rows, SHALL list it with `"available":false`, and SHALL answer its media
route with 503. The silo SHALL log each change of a library's availability once. The boot SHALL NOT
stop for an unavailable library.

#### Scenario: a drive that is not there
- **WHEN** the silo boots with a library's folder missing
- **THEN** it serves every other library, lists that one unavailable, keeps its containers
  browsable, and answers 503 for its presentations

Pinned by: `Tests/SiloTests/LibrariesTests.swift` (`aDriveLateToMountIsUnavailableAndTheRestAreServed`,
`aFolderThatGoesIsUnavailableAndItsIndexKept`), `Tests/SiloTests/ServerTests.swift`
(`aLibraryWhoseFolderGoesIsKeptAndSaysSo`), `Tests/SiloStoreTests/IndexTests.swift`
(`anEmptyMountPointForgetsNothing`). That each change is logged once is pinned by nothing yet.

### Requirement: The last walk of a library is read, never requested
The silo SHALL keep the report of each library's most recent walk and SHALL serve it at
`GET /v1/libraries/{library}/scan`, behind the operator gate, answering 200 with when the walk ran,
whether the library is available, and a `ScanReport` — the counts `read`, `unchanged`, `removed` and
the `findings`, each a `severity` of `error` or `warning` with an optional `path` and its `text`. A
library the silo does not serve SHALL be 404. No route SHALL start a walk on request.

#### Scenario: the last walk and its findings
- **WHEN** the operator reads `/v1/libraries/main/scan` after a walk that found an orphaned sidecar
- **THEN** the 200 answer carries when the walk ran and the warning `a sidecar nothing references`

#### Scenario: a library the silo does not serve
- **WHEN** the operator reads `/v1/libraries/other/scan`
- **THEN** the answer is 404

Pinned by: `Tests/SiloTests/LibrariesTests.swift` (`theLastWalkIsKeptWithItsFindings`),
`Tests/SiloTests/ServerTests.swift` (`aScanIsAnOperatorsToo`).

### Requirement: A library's containers are read within the library
`GET /v1/libraries/{library}/containers` SHALL answer 200 with a
`ContainerSummary` for each container at the top of the library, listed or not.
`GET /v1/libraries/{library}/containers/{id}` SHALL answer 200 with a
`LibraryContainer`: the `library`; the `path` of its sidecar relative to the
library root, as a walk's findings on the sidecar name it; and the `container` as
the library's own sidecar says it, with that library's presentations, in the form
`GET /v1/containers/{id}` answers. `GET /v1/libraries/{library}/containers/{id}/smd`
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

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aLibrarysContainersAreReadWithinIt`).

### Requirement: A container's own fields are edited in one library, on the sidecar the editor read
`PUT /v1/libraries/{library}/containers/{id}` with a JSON `ContainerEdit` — `document`, the
container as its repository XML; `basedOn`, the digest of the sidecar it was made from; and
`dryRun` — SHALL set the container's own fields in that library's sidecar to the document's,
and SHALL change none of the library's facts but the paths of the folders it moves: its
presentations and its rules stay as they stand. A sidecar's digest is the SHA-256 of its bytes as the index read
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
  (`item <id> is a container this library holds`).
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

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aContainersOwnFieldsAreEditedOntoTheSidecarRead`,
`anEditMovesTheFoldersItRenames`).

### Requirement: A container's artwork is read, put and removed by kind
The `LibraryContainer` a library's container route answers SHALL carry `artwork`, the kinds the
container's folder holds, read from the folder when asked rather than from the index.
`GET /v1/libraries/{library}/containers/{id}/artwork/{kind}` SHALL answer 200 with the kind's
image and its content type, or 404 when the folder holds none; it is a read route, and SHALL
answer without a token. `PUT` on the same path SHALL take the image's bytes and SHALL accept a
JPEG or a PNG, told by the bytes' signature rather than the declared type: anything else SHALL be
415, and an image over 25 MB SHALL be 413. It SHALL write the file as `<kind>.jpg` or
`<kind>.png` by writing beside it and renaming, SHALL remove the kind's file in the other format
if there is one, and SHALL answer 200 with the kind and its format. `DELETE` on the same path
SHALL remove the kind's file and answer 204, or 404 when there is none. A kind that is not one of
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

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aContainersArtworkIsPutServedAndRemoved`).

### Requirement: Containers are made in a library without a file
`POST /v1/libraries/{library}/containers` with a JSON `ContainerCreate` — `documents`, one or more
containers as repository XML; `parent`, the id of a container the library holds, or absent; and
`dryRun` — SHALL make each container in that library as a placement would make it, and SHALL place
no file. The documents SHALL form one tree: exactly one of them, the top, is named as a child by
none of the others, and every other is named as a child by a document in the request. With a
`parent`, the top SHALL be filed beneath the parent's folder; without one, at the top of the
library. Each container's sidecar SHALL hold the document's own fields and no presentations, and
each parent's sidecar SHALL record its child's path. The answer SHALL be a `ContainerCreateResult`:
`applied`, the `writes`, each a sidecar's path relative to the library and whether it is new, and
the `findings`.

- A document that cannot be read, or documents that do not form one tree, SHALL be 400, and a
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

Pinned by: `Tests/SiloTests/ServerTests.swift` (`containersAreMadeInALibraryWithoutAFile`).

### Requirement: A library is laid out again on request
`POST /v1/libraries/{library}/layout` with a JSON body of `dryRun` SHALL rename every container
folder in the library whose name is not the one the layout gives its container, from the top of
the library down, recording each new path in the sidecar of the container that holds it, and SHALL
re-read the library into the index under the same lock as the moves, so that a request asked for
while folders move waits for the turn and finds each moved container where it went. It SHALL answer a `LayoutResult`: `applied`, the `moves`, each a
folder's path relative to the library `from` and `to`, and the `findings`. A rename that fails SHALL
leave that folder where it is, SHALL be a warning-severity finding,
`folder "<from>" could not be renamed "<to>": <reason>`, and SHALL NOT stop the rest. A dry run SHALL
answer the moves it would make and move nothing. A library the silo does not serve SHALL be 404, and
an unavailable one SHALL be 503. A presentation's id SHALL be the same after the layout as before
it. The route SHALL require the operator's bearer; a missing or wrong bearer SHALL be 401.

#### Scenario: a library whose folders were renamed by hand
- **WHEN** a library holds a series whose season is in `Season 13` and whose serial is in
  `Season 13/Pyramids of Mars`, and the operator lays the library out
- **THEN** the moves are `Doctor Who (1963)/Season 13` to `Doctor Who (1963)/01 - Season 13` and
  then the serial's folder within it, the sidecars record the new paths, the walk warns of
  nothing, and each presentation has the id it had

#### Scenario: a dry run
- **WHEN** the operator asks for the layout of a library with `dryRun` true
- **THEN** the answer lists the moves and the library is unchanged

Pinned by: `Tests/SiloTests/ServerTests.swift` (`aLibraryIsLaidOutAgain`),
`Tests/SiloLibraryTests/RelayoutTests.swift` (`aLibraryRenamedByHandIsLaidOutFromTheTopDown`),
`Tests/SiloTests/LibrariesTests.swift` (`aRefreshAskedForWhileFoldersMoveFindsWhereTheyWent`).
