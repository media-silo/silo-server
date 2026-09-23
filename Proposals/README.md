<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals

Designs argued before they are built, in the manner of the
[smddb proposals](https://github.com/project-smd/smd-tools/tree/main/Proposals)
this project grows out of. A proposal holds the argument for a change — the
problem, the design, the alternatives weighed and why they lost. What the
change became is in [Specs/](../Specs/): this folder is the record of
decisions, that one the current state they led to.

A change arrives in two pull requests.

**The proposal PR** adds one folder, `Proposals/<name>/`:

- `README.md` — the argument, beginning `**Status:** proposal`.
- `specs/` — the full, final text of every document the change adds to or
  replaces in `Specs/`, written exactly as it will read once the code is the
  way the proposal says. Reviewing the proposal is judging the argument against
  these words, because these words are what will stand as current fact.

**The implementation PR** lands the code and, in the same change, moves each
document from `Proposals/<name>/specs/` into `Specs/` verbatim and flips the
proposal's status line to `landed`. Nothing is summarised or reworded on the
way: the argument was settled when the proposal merged, and the spec texts were
agreed with it. A spec never changes outside such a pair, and when the code's
drift demands a change, that demand is a new proposal.

A landed proposal is history: a record of what was decided and why, kept in
the shape it was decided in. Further changes are new proposals, not edits to
old ones.

## The founding document

- [Silo](Silo.md) — a server for one household's library of smd-shaped
  containers: what it serves, how the files it serves are laid out, the rules
  that decide how a ripped file is encoded, the nodes that do the encoding, and
  how a finished file is placed where the server will find it. Written before
  the two-PR flow above; what it argues that stands today is restated as
  current fact in [Specs/](../Specs/).
