<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: A sidecar may attribute a field or an artwork kind to a provider
A library sidecar's `<container>` MAY hold `<attribution>` elements, each with a `subject`, a
`provider`, a `value` and `read`, the `yyyy-mm-dd` day the subject was read from the provider. The subject SHALL be `outline`, an alternative's outline as
`alternative/<id>/outline`, or an artwork kind as `artwork/<kind>`, and the provider and value are
the reference the subject came from. An attribution SHALL be a library fact, as a presentation is:
it is not one of the container's own fields, a repository document has no place for it, and the
container read from a sidecar with attributions SHALL be the container read from the same sidecar
without them. A placement SHALL keep a sidecar's attributions, as it keeps every library fact it does
not own. A subject that is none of these, and two attributions of one subject, SHALL be
error-severity findings, and so SHALL an attribution of a field the container does not have
(`<subject> is attributed to <provider> but the container has none`). An attribution of an artwork
kind the container's folder holds no file for SHALL be a warning the walk reports on the sidecar
(`artwork <kind> is attributed to <provider> but the folder has none`). A provider's terms MAY limit how
long content read from it is kept: TMDb's limit it to six months, and the terms of a provider whose
content is CC0, as Wikidata's is, set no limit. An attribution read longer ago than its provider's
limit, reckoned as the same day that many months later or that month's last day when it is shorter,
SHALL be a warning the walk reports on the sidecar each time it walks the library, whether or not
the sidecar has changed (`<subject> was read from <provider> on <read>, more than <n> months ago,
longer than its terms let it be kept`).

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

#### Scenario: an outline kept longer than TMDb's terms allow
- **WHEN** a sidecar attributes its container's outline to provider `tmdb`, read on 5 January 2026, and
  the library is walked on 5 July 2026 and again, unchanged, on 6 July 2026
- **THEN** the first walk reports nothing of the outline's age, and the second warns on the sidecar
  `outline was read from tmdb on 2026-01-05, more than 6 months ago, longer than its terms let it be kept`

#### Scenario: an attribution to a provider whose terms set no limit
- **WHEN** a sidecar attributes an artwork kind to provider `wikidata`, read on 5 January 2026, and the
  library is walked on 6 July 2026
- **THEN** the walk reports nothing of the attribution's age

Pinned by: `Tests/SiloLibraryTests/PlacementTests.swift` (`attributionsAreLibraryFacts`),
`Tests/SiloStoreTests/IndexTests.swift` (`anAttributedKindWithNoFileIsAWarning`,
`anAttributionKeptLongerThanItsTermsIsAWarning`, `aDateMonthsLaterIsTheSameDayOrTheMonthsLast`).
