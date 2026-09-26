<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0004-configuration

Modified: 2026-09-26

# Configuration

This proposes where a silo's configuration lives and who may change it. The state directory
stops defaulting to a folder beside wherever the process happened to start and defaults instead
to a well-known place on the machine, because a silo is a daemon and one silo per machine is the
expected case. The rest of what the silo is told splits in two: the few facts the process must
have before it can answer anyone, or that would let the network reach further than the machine's
owner allowed, stay local — the environment, fixed for the life of the process — while the
household's choices move into the state directory, where operator routes change them while the
silo runs and SiloAdmin puts them in front of the operator. The environment keeps its present
power over those choices, but a setting the environment pins is reported as pinned, never
silently overridden. And the default port moves off 8080.

## The problem

Everything the silo is told, it is told by its environment, once, before the graph exists
([read-api](../openspec/specs/read-api/spec.md)). That was the right first answer — a server run
from a shell by the person who wrote it — and it is the wrong one for the server as it will be
deployed: started by launchd or systemd on a machine in a cupboard, configured from a Mac on the
other side of the house.

The state directory shows it most sharply. It defaults to `silo-state`, relative to the working
directory. A daemon's working directory is `/`, so the default is `/silo-state`: unwritable for a
service account, and the top of the disk for root. Worse, the state directory is the silo's
identity. [0002-onboarding](Onboarding.md) put the ServerID, the operator credential, the node
records and the jobs there, and made the filesystem the root of trust — a lost passkey is regained
by dropping `operator-credential.reset` into the state directory. That recovery is only as good as
the operator's ability to find the directory, and a path that depends on which shell started the
process is not findable. Start the same binary from a different directory and it is a different
silo: a new ServerID, back in bootstrap, a stranger to every SiloAdmin that knew it.

The rest shows it more quietly. The libraries a silo serves, whether it runs an embedded node,
whether it advertises itself — these are household decisions, made after the box is on the shelf,
and today each one is an edit to a service definition and a restart. 0002-onboarding's second open
question already leaned the same way for libraries: rather than the operator typing host paths
into a setup sheet, libraries should grow operator routes of their own, and the console should
drive them. And the name is already half-way there: setup names the silo at runtime, into
`server.json`, but nothing renames it after.

The port is a smaller matter with the same root. 8080 is the default of half the development
servers, proxies and admin panels a household machine might already run.

## What this is

**A state directory with a known home.** Absent an explicit `SILO_STATE_DIR`, the silo takes
systemd's `STATE_DIRECTORY` when a unit provides one, and otherwise a platform default: for a
process running as root, `/Library/Application Support/Silo` on macOS and `/var/lib/silo` on
Linux; for anyone else, `~/Library/Application Support/Silo` and `$XDG_STATE_HOME/silo`. The boot
logs the path it chose and why. `silo-node` gets the same resolution under its own folder name.

**Two kinds of setting.** A *local* setting is read from the environment at boot and fixed for the
life of the process: the state directory, the bind host and port, the operator token override, the
paths to `ffmpeg` and `ffprobe`, and a new one, the library roots. A *stored* setting lives in the
state directory and is changed through operator routes without a restart: the libraries, the
embedded node, advertising, and the name.

**The environment pins, and says so.** Every stored setting keeps its environment variable, and
when the variable is set it wins — the precedent `SILO_OPERATOR_TOKEN` already set. What changes
is that the silo reports it. The settings route names each setting's source; a write to a pinned
setting is refused naming the variable that pins it; SiloAdmin shows it read-only and says why.

**Libraries within roots.** A library added over the network must lie within one of the roots the
machine's owner named in `SILO_LIBRARY_ROOTS`. Placement writes into library roots, so the roots
are what bound where the network can make the silo write.

**A less common port.** The default port becomes 8742.

## Principles

0001-silo's non-goals and 0002-onboarding's principles stand; the filesystem remains the root of
trust. This proposal adds four of its own.

1. **A setting lives where it can safely change.** What the process needs before it can answer a
   request, and what would let the network reach past the machine owner's grant — where the silo
   keeps its state, where it listens, which binaries it executes, which folders it may write —
   is local. Everything else is the household's, and the household changes it from the console.
2. **The environment pins, and says so.** An environment variable is an answer the deployment
   gave, and it wins; but a pin the operator cannot see is a setting that silently ignores them.
   Every setting is reported with its source, and a write to a pinned one is refused by name.
3. **One silo per machine, in a known place.** Where a silo keeps its state is a fact of the
   machine, not of the shell that started it. Two silos on one machine remain possible — an
   explicit state directory and port each — and are the case that has to say so.
4. **Stored settings take effect without a restart.** A setting the console can change is a
   setting the running silo applies. Local settings need a restart by definition; nothing else
   does.

## Vocabulary

- **Local setting** — read from the environment at boot, fixed for the life of the process, never
  writable over the network.
- **Stored setting** — kept in the state directory, changed through operator routes, applied by the
  running silo.
- **Pin** — an environment variable set for a stored setting. A pinned setting takes the
  environment's value and refuses writes.
- **Source** — where a setting's current value came from: `environment`, `stored` or `default`.
- **Library root** — a folder, named locally, within which a library added over the network must
  lie.

## Where the state directory lives

The silo resolves its state directory once, at boot, in this order:

1. `SILO_STATE_DIR`, when set and not empty. It keeps its present meaning, relative paths included:
   an explicit answer is the deployment's to give.
2. `STATE_DIRECTORY`, when set — the variable systemd provides to a unit with `StateDirectory=`,
   having created the folder and given it to the unit's user. It may name several folders,
   colon-separated; the silo takes the first.
3. The platform default:

| | Running as root | Running as anyone else |
|---|---|---|
| macOS | `/Library/Application Support/Silo` | `~/Library/Application Support/Silo` |
| Linux | `/var/lib/silo` | `$XDG_STATE_HOME/silo`, the variable defaulting to `~/.local/state` |

Root is decided by the effective user id. A daemon under a dedicated account without a usable home
— `_silo` under a LaunchDaemon, say — is the case the environment answers: the unit gets
`StateDirectory=silo`, the plist gets `SILO_STATE_DIR`. The paths are spelt out per platform rather
than asked of `FileManager`, whose application-support answer on Linux is not the Linux convention.

The boot logs `state directory: <path> (<source>)` before anything reads the folder, so the answer
to "where do I drop the reset file" is the first line of the log as well as a row of this table.

`silo-node` resolves its own state directory the same way — `--state-dir`, then `STATE_DIRECTORY`,
then `Silo Node` and `silo-node` in the same places — so a node and a silo on one machine never
share a folder. Its present default, `~/.silo-node`, goes.

There is no migration. Nothing has been released, and a silo or node whose state sits in the old
place is started with an explicit state directory pointing at it; one that is not becomes a new
server, or a new node awaiting approval, which is what those words already mean.

## Local and stored

The local settings, with their variables and defaults:

| Setting | Variable | Default |
|---|---|---|
| State directory | `SILO_STATE_DIR` | as above |
| Bind host | `SILO_HOST` | `0.0.0.0` |
| Port | `SILO_PORT` | `8742` |
| Operator token override | `SILO_OPERATOR_TOKEN` | none |
| Encoder tools | `FFMPEG_PATH`, `FFPROBE_PATH` | found on `PATH` and the usual folders |
| Library roots | `SILO_LIBRARY_ROOTS` | none |

Each is local for a reason principle 1 names. The state directory cannot be stored in itself. The
host and port are needed before the first request, and a network write to either could strand the
client that made it. The token override is the escape hatch 0002-onboarding kept, and an escape
hatch the network could close is not one. The tool paths name binaries the silo executes, and a
network route that could choose them would hand the operator's bearer a way to run anything on the
host. The library roots are the grant the network works within, so the network cannot widen them.

The bind host stays `0.0.0.0`. Nodes on other machines, a SiloAdmin on another Mac, and the Bonjour
advertisement all need the silo reachable on the LAN; binding loopback is a deliberate
single-machine choice, which is what a local setting is for.

The stored settings:

| Setting | Pinned by | Default |
|---|---|---|
| Libraries | `SILO_LIBRARIES` | none |
| Embedded node | `SILO_EMBEDDED_NODE` | off |
| Advertising | `SILO_ADVERTISE` | on |
| Name | — | `SILO_NAME`, then `Silo on <host name>`, at minting |

They are kept in `settings.json` in the state directory, written atomically, except the name, which
stays in `server.json` where 0002-onboarding put it. The name is the one stored setting without a
pin: `SILO_NAME` seeds the identity when it is minted and is consulted then only, and this proposal
leaves that meaning alone — a name is part of the identity, and an identity the environment could
rewrite on every boot would not be one.

`SILO_LIBRARIES` pins the list whole. Per-library pinning — some libraries from the environment,
more from the console — would make every list a merge, with an order and a collision rule to learn;
a deployment that names its libraries in its environment has decided to own them there.

## The settings route

`GET /v1/settings`, behind the operator gate, reports every setting: its value, its source, and for
a pinned one the variable that pins it. Local settings are reported the same way, and are never
writable. The state directory being among them is deliberate: the console that holds the passkey is
the natural place to learn where recovery would happen, before recovery is needed.

`PATCH /v1/settings` takes any of the name, the embedded node and advertising, and applies all of
it or none. A pinned setting in the body refuses the whole request with 409, naming the variable; an
empty name is 400. The answer is the settings as they now stand.

Each change takes effect at once. Turning the embedded node on starts its loop; turning it off
stops it claiming, and the job in flight, if any, runs to completion — a setting change is not a
reason to throw away an encode. Turning advertising on or off starts or drops the advertisement;
renaming re-advertises under the new name and writes `server.json`.

## Libraries grow routes

`GET /v1/libraries` stays as it is. Two operator routes join it.

`POST /v1/libraries` adds a library, an id and a path. The path must be absolute, must exist and
be a directory, and once symbolic links are resolved must lie within a library root; the id must be
new. A pinned list refuses with 409, as does a taken id; a path outside every root, or any path when
no roots are configured, is 403; a path that does not exist is 422. The library is recorded, scanned
as `POST /v1/libraries/{library}/scan` would scan it, and returned.

`DELETE /v1/libraries/{library}` removes one. It refuses with 409 while the list is pinned or while
a job not yet in a final state names the library. The library's rows leave the index; nothing on
disk is touched — no sidecar, no media file. Moving a library is removing it and adding it again.

Libraries named in the environment are not held to the roots. The roots bound what the network may
add; what the machine's owner wrote into the environment is theirs already, checked as it is today:
a path that does not exist stops the boot.

With no `SILO_LIBRARY_ROOTS`, no library can be added over the network. That is the safe way round
and deliberately inconvenient: the one piece of local configuration a console-driven silo needs is
the answer to "where do your media live", given once, by someone at the machine.

## Applying without a restart

Today `SiloConfig` is an input to the graph, and the libraries are read from it directly — by the
index's first scan, the library, media, operator and job controllers and services. They move behind
one library registry, a singleton that holds the current list, applies adds and removes, and is
what every one of those asks instead. The embedded node and the advertiser stop reading a flag once
in `run()` and instead follow the setting, starting and stopping their work as it changes.
`SiloConfig` keeps what is local, and the new settings store keeps what is not.

## What this looks like to the operator

A Mac mini is set up for the household. The package installs a LaunchDaemon, and the silo boots
with its state in `/Library/Application Support/Silo`, listening on 8742 and advertising itself; its
plist names one thing, `SILO_LIBRARY_ROOTS=/Volumes/Media`. SiloAdmin sees a bootstrap silo, sets it
up, and the operator opens its settings: no libraries, the embedded node off, the state directory
shown where the reset file would go. They add `/Volumes/Media/Films` as `films` and turn the
embedded node on; the index scans, the loop starts, and nothing restarted. Later, a friend's
compose file names `SILO_LIBRARIES` directly: their SiloAdmin shows the libraries greyed, "set by
`SILO_LIBRARIES` on the server", and an attempt to add one is refused by name rather than lost.

## What this asks of an implementation

Each step is a pull request, in order, and each carries its spec deltas into `openspec/` per the
corpus README — the deltas are written now, under [`specs/`](Configuration/specs/) beside this
proposal.

### 1. A known home and a new port

The state directory resolution for `silo` and `silo-node`, one resolver shared by both and
parameterised by the folder name; the boot's log line; the default port to 8742; the README's
examples and its account of the environment brought up to date. The state directory, node identity
and read-api deltas apply here.

Tests: each rung of the resolution, with the environment and effective user supplied rather than
read, on both platforms' tables; `STATE_DIRECTORY` with several entries takes the first; a relative
`SILO_STATE_DIR` keeps its meaning.

### 2. Stored settings and the settings route

The settings store, `GET` and `PATCH /v1/settings`, pins and their refusals, and the embedded node,
advertiser and name following their settings live. The settings, embedded node and advertiser
deltas apply here.

Tests: sources reported for default, stored and pinned values; a pinned field refuses the whole
patch by name; a patch survives a restart; the embedded node started and stopped by the setting,
with a job in flight completing; renaming re-advertises.

### 3. Libraries within roots

The library registry in place of `SiloConfig.libraries`; `SILO_LIBRARY_ROOTS`; `POST` and
`DELETE /v1/libraries`. The libraries deltas apply here.

Tests: an added library is scanned and served without a restart; a path outside the roots, through
a symbolic link that leads outside, and with no roots configured are each refused; a pinned list
refuses both routes; removal is refused while a live job names the library, and afterwards leaves
every file on disk in place.

### 4. The console's settings

SiloClient and SiloAdminKit learn the settings and library routes; SiloAdmin shows a with-access
silo's settings — the stored ones editable, the pinned ones read-only with the variable named, the
local ones read-only — and adds and removes libraries, offering the configured roots as the places
to choose within. The silo-admin delta applies here; shell-level behaviour stays `Pinned by:
nothing yet.` until the shell grows a test seam.

## Non-goals

- **Changing the port or host from SiloAdmin.** Bonjour carries the port and the registry keys on
  ServerID, so a console-driven port change is possible — but every typed URL breaks, a node given
  `SILO_URL` among them, and principle 3 of 0002-onboarding makes the URL the mechanism. It would
  also mean rebuilding the listener in a running process, for a need — a port conflict — that shows
  itself on the machine, in the log, to the person able to fix it there. A new default makes the
  conflict rarer; that is the proportionate answer.
- **Encoder paths from the network.** Choosing the binary the silo executes is a local decision for
  the reason principle 1 gives.
- **A restart route.** Nothing stored needs one, and what is local is the machine's to restart.
- **Migration from the old defaults.** Nothing has been released.
- **Several operators' views of settings.** One operator, as 0001-silo has it.

## Open questions

1. **A local configuration file.** The environment is the one local source, set through a service
   definition. A `silo.json` beside the state directory — the Configuration library makes another
   provider cheap — would be friendlier to an operator at a shell than editing a plist, at the cost
   of a second place to look. This proposal waits for someone to find the plist a burden.
2. **Default library roots.** None is safe and unfriendly: a fresh LaunchDaemon install cannot add a
   library until someone edits its environment. A platform default — `/Volumes` on macOS, `/srv` and
   `/media` on Linux — would remove the step and widen the network's reach by default. The installer
   asking is a third answer, and may be the right one.
3. **The embedded node's default.** One silo per machine suggests that the machine is also the
   household's only encoder more often than not, which argues for on. Off is kept here because the
   encoder tools may be absent and the silo should not start by complaining.
4. **The node's settings.** `silo-node` has its own local configuration — its silo's URL, its state
   directory — and nothing stored. Whether the console should reach a node's settings through the
   silo is a question for the proposal that makes the console approve nodes.
