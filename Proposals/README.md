<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals

Designs argued before they are built, in the manner of the
[smddb proposals](https://github.com/project-smd/smd-tools/tree/main/Proposals) this project
grows out of. When a proposal lands, its content becomes the specification and the code, and the
document stays as the record of what was decided and why. The specification the proposals become
lives in [openspec/](../openspec/README.md); a proposal that changes behaviour carries its spec
deltas under `Proposals/<Name>/specs/`, as that README describes.

- [Silo](Silo.md) — a server for one household's library of smd-shaped containers: what it
  serves, how the files it serves are laid out, the rules that decide how a ripped file is
  encoded, the nodes that do the encoding, and how a finished file is placed where the server
  will find it.
- [Onboarding](Onboarding.md) — how a silo with no configuration becomes a working server:
  bootstrap mode and the one setup call it allows, the operator's passkey, recovery through the
  filesystem, and SiloAdmin, the macOS console that finds silos and walks a fresh one through
  its first ten minutes.
