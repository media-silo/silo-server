<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Specs

The system as the code is today: one document per capability, each named
`Specs/<capability>.md`. This corpus describes; it does not argue. The argument
for why a thing is shaped as it is — the problem met, the alternatives weighed
and refused — belongs to the proposal that made it, in
[Proposals/](../Proposals/). A reader who wants to know what the silo is starts
here; one who wants to know why reads there.

Every document here carries the project's SPDX header and its one status:

```
**Status:** current
```

A spec is `current` because of how it changes, which is never casually. A
proposal writes the spec text it intends as part of its case, under
`Proposals/<name>/specs/`; the pull request that implements the proposal moves
that text here verbatim — word for word, not summarised, not smoothed — and
flips the proposal to `landed`. A spec changes in no other pull request: not
for a refactor that keeps the stated behaviour, not for wording, not for a fix
the spec never spoke of. When the code and a spec disagree, the spec is wrong
and owed a proposal, not an edit.
