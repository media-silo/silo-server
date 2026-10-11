<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Rulesets without an extraction policy

## Why
The extraction policy spoke only to a producer, and only to one kind of producer: the silo stored it,
read it and showed it, and applied none of it. What a source keeps is a producer's to decide, and
everything the policy said can be said as drop rules, which a producer that can leave streams out
reads through the resolver's dry run like any other client. Decided in review of the console's
rulesets, without a proposal document of its own: there is nothing to migrate, since no silo holds a
ruleset yet.

## What Changes
- `<extraction>` is no longer an element of a ruleset, and a document holding one is refused.
- The reading, the console and the starter draft carry no extraction policy.
