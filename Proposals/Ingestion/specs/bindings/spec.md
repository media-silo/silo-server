<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

## ADDED Requirements

### Requirement: A binding says what one entry is made from, segment by segment
`POST /v1/bindings`, behind the operator's token, SHALL take a binding: the library, the item's
container lineage as repository documents, the item, and its optional alternative; the feature map,
mapping the last container's features to streams by kind and index from one among streams of the
kind; the chapter names the presentation will carry; an optional source reference for the sidecar
to record; the ruleset by name with an optional version; optionally the profiles of the ruleset's
outputs to make, every output when left out; and one or more segments, each a source's id and
optionally a span of its chapters, `from` and `to` inclusive. The silo SHALL mint the binding's id,
keep the binding as one JSON file under its state directory, and never change a binding once made.

#### Scenario: an episode out of a play-all title
- **WHEN** the operator binds part two of a serial to chapter 2 of a source whose chapters are its
  four episodes
- **THEN** the binding is made with one segment, that source spanning chapters 2 to 2

#### Scenario: a film across two discs
- **WHEN** the operator binds a film to two sources, each a whole disc title with the same streams
- **THEN** the binding is made with two segments, in that order

Pinned by: nothing yet.

### Requirement: A binding's segments are joined in order, and must share a stream layout
A binding's media SHALL be its segments' spans joined end to end in order, the way `ffmpeg`'s concat
demuxer presents them, so that a stream's index means the same in every segment and in the joined
media. A segment's span SHALL run from the start of its `from` chapter to the start of the chapter
after its `to`, or to the source's end; a segment without a span is its whole source. The segments'
input specs SHALL describe the same streams — the same kinds and codecs at the same indices — and a
binding whose segments do not SHALL be refused, naming the first stream that differs.

#### Scenario: two sources that cannot be joined
- **WHEN** a binding's first segment has an AC-3 stream at index 1 and its second a DTS stream there
- **THEN** the binding is refused, naming stream 1

Pinned by: nothing yet.

### Requirement: A binding that cannot be made is refused whole
A binding SHALL be refused with 400, naming why, and nothing stored, when its library is unknown to
the silo; a container document cannot be read; the item is not in the last container; the
alternative is not one of that container's; the feature map names a feature the container does not
have, or a stream the joined media does not have; a segment names a source the silo does not have; a
span names a chapter its source does not have, or its `to` comes before its `from`; the segments
cannot be joined; the ruleset or its version does not exist; or a profile it names is not one of the
ruleset's outputs. A binding whose recipes cannot all be resolved SHALL be refused as
[recipes](../recipes/spec.md) describes.

#### Scenario: a span past the end
- **WHEN** a binding's segment spans chapters 3 to 5 of a source with four chapters
- **THEN** the binding is refused with 400, naming chapter 5, and nothing is stored

Pinned by: nothing yet.

### Requirement: Bindings are read openly
`GET /v1/bindings/{id}` SHALL answer the binding with the ids of its recipes, or 404 for an id the
silo does not know, with no token asked.

#### Scenario: a binding and its recipes
- **WHEN** a client reads a binding resolved against a ruleset of two outputs
- **THEN** the answer carries the binding and the ids of its two recipes

Pinned by: nothing yet.
