<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A search is asked in a language Wikidata takes

## Why
Wikidata's search refuses a language and region it does not know, such as `en-au`, where reading an
item's labels in one only warns. Its API answers a refused request with success and an error in place
of the answer, so a console whose settings name `en-AU` could not search at all, and said only that
the data could not be read because it is missing.

## What Changes
- A search is asked in the settings' language, and while Wikidata refuses it, in the next of the
  languages labels are asked in: its base language, then `mul` and English.
- A request Wikidata's API refuses is thrown as `Wikidata.Unavailable.refused`, with the code and the
  reason it gives, rather than as an answer that cannot be decoded.
- Each way Wikidata cannot be read says why in words, and the console shows that rather than a
  generic failure.
