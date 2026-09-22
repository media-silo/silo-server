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
decided and why afterwards.

The model it serves is [SmdKit](https://github.com/project-smd/SmdKit); the tool
that feeds it is the ingestion workflow in smd-tools.

## What is here

One package, in the order its parts arrived:

- `SiloKit` — the facts a rule may test, the ruleset file, and the resolver that
  turns a ruleset and a file's facts into a recipe: one decision per stream and
  the layout the output will have. Pure, and tested on literal values.
- `Encoder` — `ffprobe` and `ffmpeg` as processes: a recipe becomes an argument
  list, progress comes back a report at a time, and the output is probed and
  checked against the layout the recipe promised.
- `silo-ctl` — the operator's command line. `encode` is the part that needs no
  server: give it a ruleset file and a ripped file and it says what it would do,
  does it, and verifies the result.

```sh
swift test
swift run silo-ctl encode --ruleset Examples/household.xml --kind featurette --commentary 2 in.mkv out.mkv
```

`Examples/household.xml` is the ruleset the proposal was written with: an extra
below standard-definition width is re-encoded small, a lossless track that is
not a commentary becomes FLAC, a commentary becomes AAC, and everything else is
copied. `--commentary 2` says the second audio stream is one, which is what the
assignment will say once the ingestion tool makes them; the recipe's `<track>`
index for it is printed renumbered to the output.

Needs `ffmpeg` and `ffprobe` on `PATH`, or `FFMPEG_PATH` and `FFPROBE_PATH` set.
The integration test that runs them skips itself where they are missing; CI
installs them so it does not.

## Licence

Apache 2.0 — see [LICENSE](LICENSE). Every Markdown, Swift and shell file carries
an SPDX header, and `Scripts/check-license-headers.sh` enforces it in CI.
