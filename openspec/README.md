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

Specs change through the proposals process. A proposal that changes behaviour carries its spec
deltas under `Proposals/<Name>/specs/<capability>/spec.md` using the OpenSpec `## ADDED
Requirements`, `## MODIFIED Requirements` and `## REMOVED Requirements` headings, and the
implementing pull request applies them here.

`changes/archive/` is the one exception, and it is retrospective: the design in
[Proposals/Silo.md](../Proposals/Silo.md) was implemented over seven pull requests before this
corpus existed, and each archive there records one of them — a proposal, its task list and the
spec deltas that pull request would have carried, dated the day it merged. They explain how the
baseline came to be; they are not the format for new work.
