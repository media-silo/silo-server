<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A sidecar may attribute a field or an artwork kind to a provider
A library sidecar's `<container>` MAY hold `<attribution>` elements, each with a `subject`, a
`provider` and a `value`. The subject SHALL be `outline`, an alternative's outline as
`alternative/<id>/outline`, or an artwork kind as `artwork/<kind>`, and the provider and value are
the reference the subject came from. An attribution SHALL be a library fact, as a presentation is:
it is not one of the container's own fields, a repository document has no place for it, and the
container read from a sidecar with attributions SHALL be the container read from the same sidecar
without them. A placement SHALL keep a sidecar's attributions, as it keeps every library fact it does
not own. A subject that is none of these, and two attributions of one subject, SHALL be
error-severity findings, and so SHALL an attribution of a field the container does not have
(`<subject> is attributed to <provider> but the container has none`). An attribution of an artwork
kind the container's folder holds no file for SHALL be a warning the walk reports on the sidecar
(`artwork <kind> is attributed to <provider> but the folder has none`).

#### Scenario: an attributed outline kept through a placement
- **WHEN** a container's sidecar attributes its outline to a provider, and a presentation is then
  placed into the container
- **THEN** the sidecar holds the presentation, and the outline's attribution as it was

#### Scenario: an attribution of an outline the container lacks
- **WHEN** a sidecar attributes its container's outline to provider `tmdb`, and the container has no
  outline
- **THEN** the validator reports the error `outline is attributed to tmdb but the container has none`

#### Scenario: an attributed poster that is not there
- **WHEN** a sidecar attributes its container's `poster` to provider `tmdb`, and the folder holds no
  poster
- **THEN** the walk warns on the sidecar `artwork poster is attributed to tmdb but the folder has none`

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`attributionsAreLibraryFacts`),
`Tests/SiloStoreTests/IndexTests.swift` (`anAttributedKindWithNoFileIsAWarning`).

### Requirement: A sidecar may record the refs the operator declined
A library sidecar's `<container>` MAY hold `<declined>` elements, each with a `provider` and a
`value`: a reference a provider lists for the container that the operator chose not to hold, such as a
trailer among a series' specials. A declined ref SHALL be a library fact, as an attribution is: it is
not one of the container's own fields, another library holding the same container may decline
differently, and the container read from a sidecar with declined refs SHALL be the container read from
the same sidecar without them. A placement SHALL keep a sidecar's declined refs. The same ref declined
twice SHALL be an error-severity finding, and so SHALL a declined ref that an entry of the container
carries (`<provider> <value> is declined but item <id> carries it`), since one thing cannot be both
held and declined.

#### Scenario: a declined ref kept through a placement
- **WHEN** a series' sidecar declines a ref of provider `tmdb`, and a presentation is then placed into
  the series
- **THEN** the sidecar holds the presentation, and the declined ref as it was

#### Scenario: a ref both held and declined
- **WHEN** a sidecar declines a ref of provider `tmdb`, and an entry of its container carries the same
  ref
- **THEN** the validator reports an error naming the ref and the entry

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`declinedRefsAreLibraryFacts`).

## MODIFIED Requirements

### Requirement: A container's artwork is found beside its sidecar by name
A container's artwork SHALL be the files in its folder, beside `container.smd`, named
`<kind>.jpg` or `<kind>.png` for the kinds `poster`, `fanart`, `banner`, `logo` and `thumb`.
The sidecar SHALL list none of it, though it MAY attribute a kind to a provider, and a placement or an edit SHALL leave it as it stands. A kind
held as both a `.jpg` and a `.png` beside one sidecar SHALL be a warning the walk reports on
the sidecar (`<kind> is both <kind>.jpg and <kind>.png`), and the `.jpg` is the one that counts.

#### Scenario: a poster in two formats
- **WHEN** a container's folder holds both `poster.jpg` and `poster.png`
- **THEN** the walk warns on its sidecar that `poster` is both, and the container's poster is
  `poster.jpg`

Pinned by: `Tests/SiloStoreTests/IndexTests.swift` (`artworkInTwoFormatsIsAWarning`).
