<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# silo-server

A server for one household's library of smd-shaped containers: the structure the
[smddb](https://github.com/project-smd/smd-tools) proposals describe, served
directly rather than through Emby, together with the rules that decide how a
ripped file is encoded, the machines on the local network that encode it, and
the step that places the result where the server will find it.

The design is argued before it is built, in [Proposals/Silo.md](Proposals/Silo.md).
That document is the specification until code lands, and the record of what was
decided and why afterwards. Nothing else is here yet.

The model it serves is [SmdKit](https://github.com/project-smd/SmdKit); the tool
that feeds it is the ingestion workflow in smd-tools.

## Licence

Apache 2.0 — see [LICENSE](LICENSE). Every Markdown, Swift and shell file carries
an SPDX header, and `Scripts/check-license-headers.sh` enforces it in CI.
