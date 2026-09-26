<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0004-configuration

Modified: 2026-09-26

# Configuration

This proposes where a silo's configuration lives and who may change it. One environment variable
remains, `SILO_STATE_DIR`, and it only says where the state directory is; absent it, the state
directory is a well-known place on the machine, because a silo is a daemon and one silo per machine
is the expected case. Everything else the silo is told lives in that directory, in two files
divided by one rule — whether an operator route can change the setting. What no route changes is
in `silo.json`, read at startup, and changing it by hand means a restart. What a route changes is
in `settings.json`, managed by the silo and applied while it runs, and it is what SiloAdmin puts in
front of the operator. The operator credential's environment override gives way to the reset file
0002-onboarding already has, and the default port moves off 8080.

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

Keeping the environment alongside a console would cost more than it saves. Every setting the
console could change would need a rule for when the environment disagrees — which wins, how the
silo reports it, how SiloAdmin shows a setting it cannot change and why — and each rule is one more
thing for the operator to learn and the specification to pin. The environment was only ever a
second channel for the machine's owner, and the owner already has a first: the state directory.

The port is a smaller matter with the same root. 8080 is the default of half the development
servers, proxies and admin panels a household machine might already run.

## What this is

**One variable, and a known home.** `SILO_STATE_DIR` names the state directory. Absent it, the
silo takes a platform default: for a process running as root, `/Library/Application Support/Silo`
on macOS and `/var/lib/silo` on Linux; for anyone else, `~/Library/Application Support/Silo` and
`$XDG_STATE_HOME/silo`. The boot logs the path it chose and why. `silo-node` gets the same
resolution under its own folder name, with its `--state-dir` flag in place of the variable.

**Two files, one rule.** Whether an operator route can change a setting decides where it lives.
`silo.json` holds what no route changes — the ServerID, the bind host and port, the library roots —
and is read once, at startup. `settings.json` holds what routes change — the name, the libraries,
the embedded node, advertising — and is applied while the silo runs. The silo writes `silo.json`
only while it starts, to create it or fill in what is missing; it writes `settings.json` whenever a
route changes a setting.

**The credential through the filesystem.** `SILO_OPERATOR_TOKEN` goes. A reset file placed in the
state directory before the first boot already installs a credential without the silo ever entering
bootstrap, which is everything the override was used for.

**Libraries within roots.** A library added over the network must lie within one of the roots in
`silo.json`. Placement writes into library roots, so the roots are what bound where the network
can make the silo write.

**A less common port.** The default port becomes 8742.

## Principles

0001-silo's non-goals and 0002-onboarding's principles stand; the filesystem remains the root of
trust. This proposal adds four of its own.

1. **One rule places every setting.** A setting an operator route can change lives in
   `settings.json`; a setting none can lives in `silo.json`. There is no third place and no second
   rule, so where a setting belongs is never a judgement call.
2. **The filesystem configures; the network operates.** The machine's owner answers what the silo
   is and where it may reach, in a file in the state directory. The operator, over the network,
   changes what the silo does within that. Nothing the network can write widens what the owner
   granted: where the silo listens, and the folders it may write.
3. **One writer at a time.** The silo writes `silo.json` only while it starts, before it serves
   anything, so an owner's edit never races a route. `settings.json` is the silo's while it runs;
   an edit made by hand then may be overwritten, and one made while it is stopped is honoured.
4. **One silo per machine, in a known place.** Where a silo keeps its state is a fact of the
   machine, not of the shell that started it. Two silos on one machine remain possible — a state
   directory and a port each — and are the case that has to say so.

## Vocabulary

- **`silo.json`** — the owner's file: what the silo is and where it may reach. Read at startup;
  written by the silo only then, and only to create it or fill a gap.
- **`settings.json`** — the silo's file: what an operator route may change. Applied while the silo
  runs.
- **Library root** — a folder, named in `silo.json`, within which a library added over the network
  must lie.

## Where the state directory lives

The silo resolves its state directory once, at boot:

1. `SILO_STATE_DIR`, when set and not empty. It keeps its present meaning, relative paths included:
   an explicit answer is the deployment's to give.
2. Otherwise the platform default:

| | Running as root | Running as anyone else |
|---|---|---|
| macOS | `/Library/Application Support/Silo` | `~/Library/Application Support/Silo` |
| Linux | `/var/lib/silo` | `$XDG_STATE_HOME/silo`, the variable defaulting to `~/.local/state` |

Root is decided by the effective user id. A daemon under a dedicated account is not root, and would
land in that account's home — which a service account often lacks — so it is the case the variable
answers. The systemd unit the project ships lets systemd make the folder and names it:

```ini
[Service]
User=silo
StateDirectory=silo
Environment=SILO_STATE_DIR=%S/silo
```

`%S` is `/var/lib` for a system unit; systemd creates `/var/lib/silo` and gives it to `silo`. A
LaunchDaemon under `_silo` sets `SILO_STATE_DIR` in its plist the same way. The paths are spelt out
per platform rather than asked of `FileManager`, whose application-support answer on Linux is not
the Linux convention.

systemd's own `STATE_DIRECTORY` is deliberately not read. It would save the unit one line, and the
unit is the project's; but the name is generic — every unit with `StateDirectory=` sets it, and its
children inherit it — so a silo started from a script some other unit runs would quietly adopt that
unit's folder, which is the start-dependent state directory this proposal exists to remove.

The boot logs `state directory: <path> (<source>)` before anything reads the folder, so the answer
to "where do I drop the reset file" is the first line of the log as well as a row of this table.

`silo-node` resolves its own state directory the same way — `--state-dir`, then `Silo Node` and
`silo-node` in the same places — so a node and a silo on one machine never share a folder. Its
present default, `~/.silo-node`, goes.

There is no migration. Nothing has been released, and a silo or node whose state sits in the old
place is started with an explicit state directory pointing at it; one that is not becomes a new
server, or a new node awaiting approval, which is what those words already mean.

## silo.json

```json
{
  "serverID": "4f0c2a8e-9b1d-4e7a-a3c5-2d6f8b0e1a97",
  "host": "0.0.0.0",
  "port": 8742,
  "libraryRoots": ["/Volumes/Media"]
}
```

| Key | Default |
|---|---|
| `serverID` | minted: a lower-cased UUID |
| `host` | `0.0.0.0` |
| `port` | `8742` |
| `libraryRoots` | none |

At startup the silo reads `silo.json`. When the file does not exist, the silo creates it with every
key at its default, minting the ServerID. When it exists but lacks a key, the silo adds that key at
its default and writes the file back; a complete file is never rewritten, and a file the silo fills
in may come back with its keys in a different order. No route writes the file, and the silo writes
it at no other time: a hand edit takes effect at the next restart, and nothing the silo does can
race it.

Three cases are refused or reported rather than repaired. A `silo.json` that does not parse stops
the boot with the parse error and is left exactly as it was — a mistyped brace must not become a
file of defaults and a new identity. A key the silo does not know is logged by name and kept, so
`"prot": 9000` is caught rather than silently run on the default port, and an older release can run
over a newer file. And a ServerID minted into a state directory that already holds other state — a
credential, nodes, jobs — is logged as a warning a person cannot miss, because deleting `silo.json`
to get back to defaults also makes a new server. That is 0002-onboarding's supported way to make one,
but it should be a decision, not a side effect.

Writing the defaults out fixes them for that silo. A later release that changes a default does not
move a silo that already wrote the old one — which, for a port that nodes and consoles know it by, is
the point.

Each key is here for the reason principle 2 gives. The ServerID is the silo's identity, and no route
may re-mint it. The host and port are needed before the first request, and a network write to either
could strand the client that made it. The library roots are the grant the network works within, so
the network cannot widen them.

The bind host stays `0.0.0.0`. Nodes on other machines, a SiloAdmin on another Mac, and the Bonjour
advertisement all need the silo reachable on the LAN; binding loopback is a deliberate
single-machine choice, which is what an owner's file is for.

## settings.json

```json
{
  "name": "Silo on cupboard-mini",
  "libraries": [{ "id": "films", "path": "/Volumes/Media/Films" }],
  "embeddedNode": true,
  "advertise": true
}
```

| Key | Default |
|---|---|
| `name` | `Silo on <host name>` |
| `libraries` | none |
| `embeddedNode` | off |
| `advertise` | on |

The silo treats `settings.json` at startup as it treats `silo.json` — created when missing, filled
where incomplete, never repaired when malformed — so the name is fixed at first boot rather than
following the host name. After startup the silo holds the settings in memory and writes the file
whole, atomically, whenever a route changes one. An owner may write the file before the first boot
to arrive configured; an edit made while the silo runs will be overwritten by the next change.

The name moves here from `server.json`, which goes: the ServerID moves to `silo.json`, and the name
is a setting a route changes — setup names the silo, and the settings route renames it. `SILO_NAME`
goes with the file.

Libraries written into `settings.json` by hand are not held to the roots; the roots bound what the
network may add, and what the owner wrote is theirs already. A library whose folder is missing at
boot — a drive not yet mounted — is logged and left unscanned, its index rows kept, and the boot
goes on. Today a missing library stops the boot, which suits a server started by hand and does not
suit a daemon whose libraries were chosen from a console.

## The operator credential

`SILO_OPERATOR_TOKEN` goes, and bootstrap becomes the absence of `operator-credential.json` alone.
Its two uses are already covered. Recovery is the reset file 0002-onboarding designed for it. And
arriving configured — a scripted install, a test — is the same file placed before the first boot:
the silo reads it, installs the credential, deletes the file and never enters bootstrap, which is
what the recovery requirement already says of a reset.

## What leaves the environment

| Variable | Becomes |
|---|---|
| `SILO_HOST`, `SILO_PORT` | `silo.json` |
| `SILO_LIBRARIES`, `SILO_EMBEDDED_NODE`, `SILO_ADVERTISE` | `settings.json` |
| `SILO_NAME` | `settings.json`'s `name`, defaulted at first boot |
| `SILO_OPERATOR_TOKEN` | `operator-credential.reset`, placed before the first boot |

The tool locations — `FFMPEG_PATH` and `FFPROBE_PATH` for the encoder, `DNS_SD_PATH` and its
siblings for discovery — are not silo settings and stay as they are. The Encoder and discovery
libraries read them, `silo-ctl` and `silo-node` depend on them as much as the silo does, and they
name binaries the process executes, which no route should choose.

## The settings route

`GET /v1/settings`, behind the operator gate, reports every key of both files, the `silo.json` ones
marked read-only, and the resolved state directory beside them. That the state directory is among
them is deliberate: the console that holds the passkey is the natural place to learn where recovery
would happen, before recovery is needed.

`PATCH /v1/settings` takes any of the name, the embedded node and advertising, and applies all of it
or none; an empty name is 400. The answer is the settings as they now stand.

Each change takes effect at once. Turning the embedded node on starts its loop; turning it off stops
it claiming, and the job in flight, if any, runs to completion — a setting change is not a reason to
throw away an encode. Turning advertising on or off starts or drops the advertisement; renaming
re-advertises under the new name.

## Libraries grow routes

`GET /v1/libraries` stays as it is. Two operator routes join it.

`POST /v1/libraries` adds a library, an id and a path. The path must be absolute, must exist and be a
directory, and once symbolic links are resolved must lie within a library root; the id must be new. A
taken id is 409; a path outside every root, or any path when no roots are configured, is 403; a path
that does not exist is 422. The library is written to `settings.json`, scanned as
`POST /v1/libraries/{library}/scan` would scan it, and returned.

`DELETE /v1/libraries/{library}` removes one. It refuses with 409 while a job not yet in a final
state names the library. The library leaves `settings.json` and its rows leave the index; nothing on
disk is touched — no sidecar, no media file. Moving a library is removing it and adding it again.

With no library roots, no library can be added over the network. That is the safe way round and
deliberately inconvenient: the one thing a console-driven silo needs from someone at the machine is
the answer to "where do your media live", given once, in `silo.json`.

## Applying without a restart

Today `SiloConfig` is an input to the graph, read from the environment, and the libraries are read
from it directly — by the index's first scan, the library, media, operator and job controllers and
services. `SiloConfig` becomes what `silo.json` says, and the settings become a store over
`settings.json`. The libraries move behind one registry, a singleton that holds the current list,
applies adds and removes, and is what every one of those asks instead. The embedded node and the
advertiser stop reading a flag once in `run()` and follow the setting instead, starting and stopping
their work as it changes. Tests build `SiloConfig` directly, as several already do, and install a
credential through the store rather than the environment.

## What this looks like to the operator

A Mac mini is set up for the household. The package installs a LaunchDaemon, and the silo boots with
its state in `/Library/Application Support/Silo`, writing a `silo.json` with a fresh ServerID and
port 8742. Someone at the machine adds `"/Volumes/Media"` to its `libraryRoots` and restarts it once.
SiloAdmin sees a bootstrap silo, sets it up and names it, and the operator opens its settings: no
libraries, the embedded node off, the port and roots shown read-only beside the state directory. They
add `/Volumes/Media/Films` as `films` and turn the embedded node on; the index scans, the loop
starts, and nothing restarted. A year later the drive is late to mount after a power cut: the silo
logs the missing library, boots anyway, and serves the rest.

## What this asks of an implementation

Each step is a pull request, in order, and each carries its spec deltas into `openspec/` per the
corpus README — the deltas are written now, under [`specs/`](Configuration/specs/) beside this
proposal.

### 1. A known home and a new port

The state directory resolution for `silo` and `silo-node`, one resolver shared by both and
parameterised by the folder name; the boot's log line; the default port to 8742; the README brought
up to date. The state directory and node identity deltas apply here.

Tests: each rung of the resolution, with the environment and effective user supplied rather than
read, on both platforms' tables; a relative `SILO_STATE_DIR` keeps its meaning; an inherited
`STATE_DIRECTORY` changes nothing.

### 2. The two files

`silo.json` and `settings.json` created and filled at startup, `server.json` folded into them, and
every variable but `SILO_STATE_DIR` retired from the silo — `SILO_OPERATOR_TOKEN` included, the tests
moving to installing a credential; a missing library no longer stopping the boot. The two files',
onboarding and read-api deltas apply here, and the onboarding and read-api specs' purpose text loses
its account of the environment.

Tests: a fresh directory gets both files at their defaults; a partial file is filled and a complete
one untouched; a malformed file stops the boot and survives it; an unknown key is logged and kept; a
ServerID minted over a directory holding a credential warns; a reset file placed before the first
boot means no bootstrap; a missing library is logged and the boot goes on.

### 3. The settings route

`GET` and `PATCH /v1/settings`, and the embedded node, advertiser and name following their settings
live. The settings, embedded node and advertiser deltas apply here.

Tests: every key reported with the `silo.json` ones read-only; a patch applies whole or not at all and
survives a restart; the embedded node started and stopped by the setting, with a job in flight
completing; renaming re-advertises.

### 4. Libraries within roots

The library registry in place of `SiloConfig.libraries`; `POST` and `DELETE /v1/libraries`. The
libraries delta applies here.

Tests: an added library is scanned and served without a restart; a path outside the roots, through a
symbolic link that leads outside, and with no roots configured are each refused; removal is refused
while a live job names the library, and afterwards leaves every file on disk in place.

### 5. The console's settings

SiloClient and SiloAdminKit learn the settings and library routes; SiloAdmin shows a with-access
silo's settings — the `settings.json` ones editable, the `silo.json` ones and the state directory
read-only — and adds and removes libraries, offering the silo's roots as the places to choose within.
The silo-admin delta applies here; shell-level behaviour stays `Pinned by: nothing yet.` until the
shell grows a test seam.

## Non-goals

- **Configuration through the environment.** Container deployments are used to it, and lose it here:
  they mount the state directory as a volume, which they must do regardless, and edit `silo.json` in
  it. Should that prove a burden, the Configuration library layers an environment provider over a
  file cheaply, and doing it for `silo.json`'s keys alone would bring back none of the disagreements
  this proposal removes, since no route writes them.
- **Changing the port or host from SiloAdmin.** Bonjour carries the port and the registry keys on
  ServerID, so a console-driven port change is possible — but every typed URL breaks, a node given
  `SILO_URL` among them, and principle 3 of 0002-onboarding makes the URL the mechanism. It would also
  mean rebuilding the listener in a running process, for a need — a port conflict — that shows itself
  on the machine, in the log, to the person able to fix it there. A new default makes the conflict
  rarer; that is the proportionate answer.
- **Watching the files.** A change to `silo.json` takes effect at the next restart, and a hand edit to
  `settings.json` while the silo runs is not noticed. Reloading on change would reintroduce the races
  principle 3 rules out.
- **A restart route.** Nothing a route changes needs one, and what `silo.json` holds is the machine's
  to restart.
- **Migration from the old defaults.** Nothing has been released.

## Open questions

1. **Default library roots.** None is safe and unfriendly: a fresh install cannot add a library until
   someone edits `silo.json`. A platform default — `/Volumes` on macOS, `/srv` and `/media` on Linux —
   would remove the step and widen the network's reach by default. The installer asking is a third
   answer, and may be the right one.
2. **The embedded node's default.** One silo per machine suggests that the machine is also the
   household's only encoder more often than not, which argues for on. Off is kept here because the
   encoder tools may be absent and the silo should not start by complaining.
3. **The node's settings.** `silo-node` has its own configuration — its silo's URL, its state directory
   — and nothing a route changes. Whether it should take the same two-file shape, and whether the
   console should reach a node's settings through the silo, are questions for the proposal that makes
   the console approve nodes.
