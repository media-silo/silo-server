<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## MODIFIED Requirements

### Requirement: Wikidata is read without a key, as its policy asks
SiloAdminKit's `WikidataClient`, a `WikidataSource`, SHALL read items' own statements through
Wikidata's API, `wbgetentities`, at most fifty items to a request, and what points at an item and who
people are through Wikidata's query service, by SPARQL. Every request SHALL carry the User-Agent
`Wikidata.userAgent`, naming SiloAdmin and its repository, and no key. Labels and descriptions SHALL be
asked in the language the settings name, then its base language, then `mul` and English, and read in
the first of them that has one. A search SHALL be asked in the first of those languages Wikidata's
search does not refuse. A request Wikidata's API answers with an error in place of an answer SHALL
throw `refused`, with the code and the reason the error gives. A request answered 429 SHALL be asked again after the wait its
`Retry-After` names, or a second, at most three times, and one whose wait is longer than thirty
seconds SHALL not be waited, the 429 being thrown as `Wikidata.Unavailable.answered`. Reading an item
as a kind it is not an instance of, or of a subclass of, SHALL throw `notA`, and one Wikidata does not
hold `notThere`. Each of these SHALL say why in words, which the console shows in place of the error.

#### Scenario: a film read in the settings' language
- **WHEN** the settings name `en-GB` and a film is read
- **THEN** each request carries SiloAdmin's User-Agent and no `Authorization`, and asks its labels in
  `en-gb`, `en` and `mul`

#### Scenario: a search in a language Wikidata's search refuses
- **WHEN** the settings name a language and region Wikidata's search does not know, and a title is
  searched
- **THEN** the search is asked again in the base language, and what it finds is answered

#### Scenario: a request Wikidata's API refuses
- **WHEN** Wikidata's API answers a request with an error
- **THEN** the request throws `refused`, with the error's code and reason

#### Scenario: too many at once
- **WHEN** every request is answered 429 with `Retry-After: 0`
- **THEN** the request is asked four times, and the 429 is thrown

#### Scenario: a wait too long to keep
- **WHEN** a request is answered 429 with `Retry-After: 600`
- **THEN** it is asked once, and the 429 is thrown

#### Scenario: a series read as a film
- **WHEN** a television series is read as a film
- **THEN** reading throws `notA` naming `film` and the series' id

Pinned by: `Tests/SiloAdminKitTests/WikidataClientTests.swift` (`everyRequestNamesSiloAdminAndAsksInTheSettingsLanguage`,
`aSearchInALanguageWikidataRefusesIsAskedInTheNext`, `tooManyAtOnceIsAskedAgainAfterAWaitThatIsNotTooLong`,
`anItemOfAnotherKindOrNoneIsRefused`).
