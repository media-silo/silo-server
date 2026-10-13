<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A ruleset's document is edited element by element, and what an edit does not touch stays as written
SiloKit SHALL read a ruleset's document keeping the range in its text of each rule and each output,
with the comments immediately before it, and SHALL edit the document by splicing: adding a rule after
its scope's last rule, or an output after the last output, written in the indentation of its
neighbours; replacing one; moving a rule within its scope, its comments with it; and deleting one, its
comments with it. An edit SHALL change only the
characters of the ranges it touches and the text it puts in their place, and the document SHALL then
read as the ruleset with that change made. An edit SHALL NOT be offered on a document the reader
refuses.

#### Scenario: a move leaves everything else as it was
- **WHEN** a document's commentary rule, with a comment above it, is moved before the lossless rule
- **THEN** the document reads with the two rules swapped, the comment above the commentary rule still,
  and every other character as it was

#### Scenario: an edit beside a comment
- **WHEN** a rule's bitrate is changed in a document with a comment between that rule and the next
- **THEN** the comment, and the blank lines around it, are as they were

Pinned by: `Tests/SiloKitTests/RulesetTextTests.swift` (`everyRuleAndOutputIsFoundWithItsComments`,
`aMoveLeavesEverythingElseAsItWas`, `anEditBesideACommentLeavesTheCommentAsItWas`,
`anAddedRuleTakesItsNeighboursIndentation`, `aDeletionTakesItsCommentsWithIt`,
`aDocumentTheReaderRefusesOffersNoEdit`).
