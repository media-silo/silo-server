<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Specifications

This directory holds the behavioural specification of this package: what the code does today,
stated as requirements with scenarios, each pinned to the test that measures it. It follows the
[OpenSpec](https://github.com/Fission-AI/OpenSpec) layout, one capability per
`specs/<capability>/spec.md`, so the OpenSpec tooling validates it unchanged:

```sh
npx -y @fission-ai/openspec validate --specs --strict
```

Two documents already exist here and this one does not replace them. [Proposals/Silo.md](../Proposals/Silo.md)
argues the design and stays the record of what was decided and why. The repository
[README](../README.md) says how to run what was built. A spec says what the code does now. Where
a spec and the proposal disagree, the spec is the checked claim and the proposal is the
historical record.

A contract another repository builds on — the shape of a library on disk, the routes a node or
the ingestion tool speaks — is specified here once. Consumers link to it by URL rather than
restating it.

## Conventions

Each requirement ends with `Pinned by:` naming the test that measures it; `Pinned by: nothing
yet.` marks a claim that is true of the source but not yet under test.

Specs change through proposals, using OpenSpec's own change layout. A proposal argues its case in
a document under [Proposals/](../Proposals/README.md) and carries its spec deltas in
`openspec/changes/<change-name>/`, using the OpenSpec `## ADDED Requirements`, `## MODIFIED
Requirements`, `## REMOVED Requirements` and `## RENAMED Requirements` headings;
[changes/README.md](changes/README.md) describes the shape. A proposal implemented over several
pull requests carries one change per pull request, named in order, so that each applies its own. The
implementing pull request applies its change with `openspec archive`, which updates `specs/` and
moves the change into `changes/archive/`. A bug fix that changes a recorded requirement edits the
spec in the same pull request.

CI checks all of it in the `Specifications` workflow:

```sh
npx -y @fission-ai/openspec@1.13.2 validate --all --strict
python3 Scripts/spec-pins-gate.py
python3 Scripts/spec-deltas-gate.py
```

The second checks that every path a spec pins to exists and that every test it names occurs in the
file named, reading each `Pinned by:` paragraph whole. The third applies every active change to a
scratch copy of the specs and fails if one does not apply.

`changes/archive/` holds the deltas of the proposals that have landed, dated the day the last of
their pull requests merged. The design in [Proposals/Silo.md](../Proposals/Silo.md) predates the
corpus and has no archive: the corpus was written from the code it produced.
