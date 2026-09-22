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
- `SiloLibrary` — a library on disk: the layout (a folder per container named
  from its title, `container.smd` inside, `{item} - {display name}.mkv` beside
  it), the walk that finds every sidecar from the roots down and reports the
  ones nothing references, the validator, and the placement that puts a
  finished file in and records it — computed and shown before it is applied,
  refused whole when a finding is an error, and written sidecar-last.
- `SiloStore` — the silo's own state: the index, a SQLite file derived from the
  sidecars that a scan brings up to date by re-reading only what changed, and
  the rulesets, kept as the documents they were given under
  `rulesets/<name>/<version>.xml`, a version never rewritten.
- `SiloAPI`, `SiloApp` and `silo` — the server: an OpenAPI document under `/v1`
  for what a client reads (libraries, containers with their presentations,
  lookup by a provider's id, search, rulesets and a dry run of the resolver)
  and what an operator changes (a scan, a stored ruleset), on the swift-wire
  stack; and beside the document, two routes that stream, the file a
  presentation is with `Range`, and the container as its sidecar.
- `FileServing`, `SiloClient` and `SiloWorker` — the parts every participant
  shares: a file served by range to the node that needs it, guarded by a
  secret the silo hands out per job; the silo's API from a client's side over
  nothing but Foundation; and the node's loop, which claims a job, opens or
  fetches its source, encodes it as the recipe says, probes the result, checks
  its layout and tells the silo where the output is. The silo runs that loop
  inside itself when `SILO_EMBEDDED_NODE=true`, so one machine is the whole
  pipeline: the tool registers a rip, assigns it, the embedded node encodes it,
  and `silo-ctl jobs place` has the silo move the result into the library.
- `SiloDiscovery` and `silo-node` — a node on another machine. It finds the
  silo by Bonjour (through `dns-sd` on macOS or Avahi's tools on Linux, as a
  process, so nothing Apple-only is linked) or is given its URL, registers
  itself and is given nothing, waits for a person to approve it with
  `silo-ctl nodes approve`, takes its token once, and then runs the same loop
  the embedded node runs, serving what it makes for the silo to fetch at
  placement. Revoking it is one command and its token stops at once. The silo
  advertises itself the same way unless `SILO_ADVERTISE=false`.
- `silo-ctl` — the operator's command line. `encode` and `place` are the parts
  that need no server: the first takes a ruleset file and a ripped file and
  says what it would do, does it, and verifies the result; the second takes a
  finished file and a clone of the data repository and files it into a library.

```sh
swift test
SILO_LIBRARIES=main=~/Library SILO_STATE_DIR=~/silo-state SILO_OPERATOR_TOKEN=secret SILO_EMBEDDED_NODE=true swift run silo
SILO_URL=http://localhost:8080 SILO_TOKEN=secret swift run silo-ctl jobs list
swift run silo-node                       # on another machine; finds the silo, waits to be approved
SILO_URL=http://localhost:8080 SILO_TOKEN=secret swift run silo-ctl nodes approve <id>
swift run silo-ctl encode --ruleset Examples/household.xml --kind featurette --commentary 2 in.mkv out.mkv
swift run silo-ctl place --library ~/Library --repository ~/data --container 0123456789abcdef --item part1 \
    --track commentary1=audio:2 --chapter "1=Opening titles" --dry-run out.mkv
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
