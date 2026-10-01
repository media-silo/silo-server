<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposed spec changes

A proposal that changes behaviour carries its spec deltas here, one directory per change, named in
kebab-case after the proposal — and, for a proposal implemented over several pull requests, after
the step, numbered in order, as `ingestion-1-sources` is:

```
openspec/changes/<change-name>/
├── proposal.md                    why, in a few lines, linking the proposal document
└── specs/<capability>/spec.md     the deltas against openspec/specs/<capability>/spec.md
```

`proposal.md` is short, because the argument lives in the proposal document:

```markdown
<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# <Change title>

## Why
<One paragraph.> Proposal: <link to the proposal document>.

## What Changes
- <One line per behavioural change.>
```

Each delta file uses the OpenSpec headings `## ADDED Requirements`, `## MODIFIED Requirements`,
`## REMOVED Requirements` and `## RENAMED Requirements`. A MODIFIED requirement is restated in
full, under its exact existing heading, with every scenario the existing requirement has — OpenSpec
matches scenarios by name and refuses to drop one, so a requirement whose scenarios change their
names is REMOVED and ADDED instead. Requirements follow the same rules as the specs themselves,
including the `Pinned by:` line. Every Markdown file here carries the SPDX header, as everywhere in
the repository.

There is no `tasks.md`: the pull requests that implement a proposal say what is done.

The implementing pull request applies the deltas and moves the change into `archive/`:

```sh
npx -y @fission-ai/openspec@1.13.2 archive <change-name> --yes
```

A change that introduces a new capability is written as ADDED requirements in
`specs/<new-capability>/spec.md`. Archiving creates the spec with a placeholder Purpose, and the
implementing pull request replaces it with a real one; strict validation fails until it does.

`archive/` is the record of what each change did. CI validates every active change and checks that
it applies to the current specs (`Scripts/spec-deltas-gate.py`).
