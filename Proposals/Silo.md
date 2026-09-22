<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Silo

**Status:** proposal. Nothing here is implemented, and nothing here has been
measured; where a claim rests on a number, the number is an estimate and says
so. Depends on `StructuredContainers.md` in the smddb project for the `.smd`
format and its vocabulary, and on `ContainerDatabase.md` for the identities it
keys on. It is the counterpart of `Hosting.md`, not a replacement for it: that
document serves everyone the shared description of what discs hold; this one
serves one household the files that were made from theirs.

A server for a library of smd-shaped containers, the rules that decide how a
ripped file is encoded, the machines that do the encoding, and how a finished
file gets to where the server will find it.

## The problem

Phase 1 of the smddb roadmap ends with a folder of ripped MKVs, each named by
MakeMKV, each filed under the disc it came from. Between that folder and
something a person sits down and watches there are four jobs, and none of them
has a name yet.

**Something has to decide how each file is encoded.** A ripped Blu-ray episode
is twenty gigabytes of video the disc's own codec already compressed once, with
a lossless master mix, a stereo mix, a commentary and three subtitle streams.
The decision for each of those is not the same, and it is not the same for a
featurette at standard definition as for the feature at high, nor for a
commentary as for the main mix. Made by hand, per file, the decision is made
badly on the third disc and inconsistently by the tenth.

**Something has to run that decision**, and the machine that ripped the disc is
the wrong one to run it on: it is a laptop with an optical drive attached, and
an x265 encode of a season is a week of its time. The household has other
machines. They are idle.

**Something has to put the result where it belongs**, in a layout a client can
find it in, next to the `.smd` that says what it is, with the stream indices the
encode produced rather than the ones the disc had.

**And something has to serve it.** Emby was the answer the sidecar format was
designed against, and the format's first principle was to leave Emby a working
library. That principle bought a great deal: it kept the format honest about what
was structure and what was metadata, and it meant the work was never hostage to
an unwritten client. But Emby cannot show a serial as a serial, an omnibus as a
cut, or a commentary as a thing that spans four parts, and every one of those is
what the format exists to say. A server that reads the `.smd` directly does not
need Emby's permission for any of it.

Four jobs, one process to own them. That process is a silo.

## What a silo is

The word is a storage word, not a serving one, and that is the point. A silo
holds what was harvested and hands it out on request; it does not do anything to
it on the way out. Three contrasts fix the meaning.

**Against Emby.** A silo serves the same household the same files, and it serves
containers first: a serial is a serial, an alternative is an alternative, a
feature is a run across the parts that map it. It does not transcode on the way
out, does not scrape providers for cast lists and ratings, and in this version
does not remember what has been watched. It does something Emby does not: it
*makes* the library, holding the encoding rules, the queue of files waiting to
be encoded, and the list of machines allowed to encode them.

**Against the hosted read service.** `Hosting.md` serves the shared database, the
description of what discs hold, to anyone who asks, from a build that bakes a
git repository into a container image. A silo serves one library, the files one
household made from its discs, to that household. Same model, one layer more:
where the shared store stops at "this disc's playlist 4 is part 2 of the
broadcast cut", a library adds "and here is the file". The two are deliberately
alike in shape, so that `GET /v1/containers/{id}` means the same thing on both,
and a client that reads one can read the other.

**Against the `.smd`.** The sidecar is the library-local truth. A silo's index is
derived from a scan of the sidecars and holds nothing they do not; delete the
index and it is rebuilt from disk. This is `Hosting.md`'s "the served database is
a build output" turned to face a mutable library: rebuilt on a scan rather than
on a merge, but with the same one-way arrow.

## Principles

1. **The `.smd` beside the files is the truth.** The index is a cache. Anything
   the silo knows about a library it learned from a sidecar, and anything it
   changes about a library it changes by writing one. A library copied to another
   disk, restored from backup or handed to a different silo loses nothing.

2. **One model.** The smddb proposals already have three expressions of the
   model: the sidecar, the shared store and its API. This proposal adds a
   fourth expression, the library index, and refuses a fifth: the silo's API
   types are the sidecar's elements as JSON, and its routes rhyme with
   `Hosting.md`'s. Every noun this document introduces is about the *work* of
   making a library, never a second name for something the model already names.

3. **Facts are discovered; rules are written.** A rule may test what a file is,
   what its streams are and what it is being made into. It may not invent any
   of that. Where a fact comes from is recorded, so a wrong decision can be
   traced to the wrong fact rather than to the rule that correctly acted on it.

4. **A decision is recorded with what it decided.** The resolved instructions for
   a file are stored with the job that ran them, and a ruleset is immutable once
   a job has named it. "Why is this file FLAC?" is answered by reading, not by
   re-running yesterday's rules against today's file.

5. **Declared write targets.** A placement lists every file it will create or
   change before it changes any, and can be shown without being applied. The
   sidecar is written last, so that a failure half way leaves a file nothing
   references, which is a warning, rather than a reference to a file that is not
   there, which is an error.

6. **Files stay where they are until they are placed.** The machine that ripped a
   file serves it to the machine that encodes it; the machine that encoded it
   serves it to the silo when the silo is ready to place it. Nothing is uploaded
   to a server in order to be downloaded from it again.

7. **Conflicts are shown, never resolved.** A stream no rule matches, a feature
   mapped to a stream the recipe drops, a file already at the destination, a
   ripping machine that is offline when its file is wanted: each is a labelled
   state that a person reads, and none of them is guessed past.

8. **Not a playback engine.** The sidecar format leaves the choice of
   presentation to the player, and so does the silo. It lists every presentation
   an item has; a client asks for one by profile if it wants to, and the silo
   never picks on a client's behalf.

## Vocabulary

Every term the smddb proposals define — container, sequence, item, alternative,
presentation, profile, feature, track, participant, extras, ref, listed,
optional, fingerprint, binding — keeps its meaning here unchanged. The following
are new, and each is argued in one paragraph.

**Silo.** The server process. It serves one or more libraries, holds the
rulesets, runs the job queue and admits nodes. Not "media server", which
promises transcoding and scraping this does not do, and which describes what the
thing does to the files rather than what it is to them.

**Library.** One folder tree the silo owns, named in its configuration. A
household may have several, on different disks. The word is Emby's for the same
thing and there is no reason to have a different one.

**Assignment.** What the Assign stage of the ingestion tool produces: which
container a ripped file belongs to, which item, which alternative, which
profile, and how the container's features map to the file's source tracks. The
stage is already called Assign, and the noun follows the verb. An assignment is
a local fact about a file in a queue; it is not a binding, which is the shared
store's record of what a pressing holds, though a binding is what an assignment
becomes when it is contributed.

**Ruleset.** A named, versioned, ordered list of encoding rules stored on the
silo. "Rules engine" names the mechanism; the ruleset is the thing a person
edits, and a version of it is what a job names. One ruleset document also
carries the extraction policy, the rule the ingestion tool already applies when
it rips, so that the two halves of "what is kept and how" sit in one file.

**Facts.** The typed vocabulary a rule may test: what a file is (its kind, the
disc format it came from, its duration), what each stream is (codec, whether it
is lossless, channels, language, whether it is a commentary), and what the file
is being made into (its profile). Facts are discovered by `ffprobe`, by MakeMKV's
scan, and by the assignment; a rule reads them and never writes them.

**Recipe.** The fully resolved instructions for turning one source file into one
presentation: one decision per stream, and the layout of streams the output will
have. "Plan" was the other candidate and lost twice: it collides with the roadmap
and with planning, and it says nothing about what the thing is for. A recipe is
followed exactly and can be read afterwards to see what was done, which is what
an audit needs.

**Job.** One source file on its way to one presentation: where the source is, its
assignment, the ruleset version and the recipe resolved from it, its state, its
attempts, where the output is, and the placement that put it in the library.

**Node.** A machine that encodes. It has a record on the silo, a state
(`pending`, `approved`, `revoked`), a token once approved, and a list of what its
`ffmpeg` can do. "Worker" describes the loop; "node" describes the machine, which
is what an operator approves. The ingestion tool registers as a node too, not
because it encodes, though it may, but because it holds source files, and a
machine that holds files other machines will fetch needs a record and a name.

**Holder.** The node a file is currently on. A job's source has a holder and so
does its output, and each is a URL on that node, served by it, guarded by a
secret the silo issues per job.

**Placement.** The computed set of writes that puts a finished presentation into
a library: the destination path for the file, the edit to the container's
sidecar, and the findings the validator raised on the way. Principle 5 made
concrete. *Placing* is applying one.

## The library on disk

### What changes from the sidecar proposal

`StructuredContainers.md` was written against Emby, and a good deal of it is
Emby's constraints made explicit: the NFO beside every presentation, the
`{episode stem} - {display name}` filename Emby's version picker shows whole,
the nine folder names that make an extra an extra, the `displayseason` numbers
the projection writes into every NFO of a version group, and the rule that
agreement across that group is an invariant. None of that was wrong; all of it
was the price of a client that could not read the sidecar.

A silo reads the sidecar. So a silo library keeps the container tree, the
sidecar elements and their meanings, and drops the Emby projection whole: no
NFOs, no projected numbering, no version groups, no extras folder vocabulary.
Title and outline live in the `.smd`, where the sidecar proposal already put
them for containers Emby had no item for. What was a special case there is the
only case here.

That is a deliberate break with the sidecar proposal's first principle, and it
should be said plainly. A silo library is not an Emby library and deleting its
sidecars does not leave one behind. The roadmap's phase 1 keeps its promise in
the ingestion tool, which can still file into an Emby layout; a silo library is
the second thing it can file into, and the one this project runs on.

### Layout

Every container that owns files has a folder, named from its display title, and
every such folder holds one file named `container.smd`. Child containers nest as
folders. A library's roots are its top-level folders, and discovery walks them.

```
Doctor Who (1963)/
  container.smd                       type="series"
  Season 13/
    container.smd                     type="season"
    Pyramids of Mars/
      container.smd                   type="serial"
      Part One - Broadcast.mkv
      Part One - Updated special effects.mkv
      Part One - Mobile.mkv
      Part Two - Broadcast.mkv
      …
      Omnibus.mkv
      extras/
        Now and Then.mkv
```

A presentation's file is `{item} - {display name}.mkv`, where the item is its
title or, failing one, its id, and the display name is the alternative's title
for an alternative, the profile's name for a profile, and nothing for the
unqualified presentation of the default alternative. Extras live in `extras/`
inside the container that owns them. A `file=` path is relative to the folder
holding the sidecar that names it, and may not escape that container's folder:
a container's folder is the unit that is moved, backed up and re-pointed.

Two things the sidecar proposal left to the tool are fixed here, because the
silo's routes and the validator depend on them.

**The container id in a sidecar is the minted `ContainerID`**, the sixteen hex
characters the shared store issues, not a slug. The sidecar proposal's examples
use slugs for legibility, and the repository file uses the minted id because
refs, listings and URLs read it. A library sidecar is read by the same code as
the repository file and served under the same routes, so it carries the same id;
item, sequence, alternative and feature ids stay slugs, local to the container,
as before. A hand-authored sidecar with a slug for a container id is read and
reported by the validator, not refused.

**`<track audio="n">` counts from one among the streams of that kind**, the way
a player's audio menu counts and the way the sidecar proposal's own example
reads, where a commentary at `audio="3"` in the full file is `audio="2"` in the
mobile re-encode that dropped the surround mix. Not `ffprobe`'s absolute index,
which counts video and subtitles too and is right for a tool and wrong for a
person reading the file.

### The index

The silo answers requests from an index, never by parsing sidecars on the way.
The index is a SQLite file in the silo's own state directory, one table per
sidecar element plus one recording each sidecar's path, modification time and
size. Boot and a requested scan walk the library and re-parse only the sidecars
whose recorded time or size changed; a placement re-reads the one container it
wrote. Deleting the file rebuilds it from the sidecars on the next boot.

The alternative, an in-memory index rebuilt on every boot, is simpler and would
do for a library on a local disk: an estimate, not a measurement, is that a
thousand small XML files parse in well under a second. On a network share the
per-file round trip dominates and a full walk of a few thousand containers is
seconds to tens of seconds, at every boot, which is the case the modification
time check removes. SQLite also answers the one query the model earns that an
in-memory graph does not, a search across titles, without holding the library
in memory at all. It is a cache, and the file can be thrown away; that is the
whole of its relationship to the truth.

The other alternative, SQLite as the truth with no sidecars, is a legitimate
design for a library nothing else will read. It was not taken because a library
that describes itself survives its server, and because the smddb proposals'
one-model argument is strongest when the same sidecar reader serves the
repository, the ingestion tool and the silo.

## Discovery and playback

The read routes follow `Hosting.md`'s, so that a client reading the shared store
finds a library familiar, and they are versioned under `/v1` and described by an
OpenAPI document that the build checks against the implementation.

| Route | Answers |
| --- | --- |
| `GET /v1/libraries` | The libraries this silo serves |
| `GET /v1/containers` | The listed roots: series, films, collections |
| `GET /v1/containers/{id}` | One container, with its presentations |
| `GET /v1/containers/{id}.smd` | The same container as its sidecar |
| `GET /v1/containers/{id}/companions` | Related containers, listed or not |
| `GET /v1/lookup?provider=&value=` | A provider's id resolved to what it names here |
| `GET /v1/search?q=` | Titles matching, across containers and items |
| `GET /v1/media/{presentation}` | The file, with `Range` |
| `POST /v1/libraries/{id}/scan` | Re-read what changed |

Playback is direct: a presentation is served as bytes, with `Range`, `ETag` and
`Accept-Ranges`, and a client plays what it is given. There is no transcoding
and no per-client selection, by principle 8. A client that wants the mobile
presentation asks for the item, reads its presentations and picks the one with
`profile="mobile"`; `?profile=` on the container route is a filter that removes
the others from the answer, never a decision that substitutes one.

A playback client is out of scope. The ingestion tool's viewer, which already
plays a ripped file through VLCKit and switches its audio tracks, is the obvious
first, and is a later proposal.

## Encoding rules

### Facts

A rule tests facts, and the facts are a closed vocabulary. For the file: its
`kind` (episode, movie, featurette, and the other extra types), the `format` of
the disc it came from, its `duration`, and the `profile` it is being made into.
For the video stream: `codec`, `width`, `height`, `frameRate`, `interlaced`,
`hdr`, `bitDepth`. For each audio stream: `codec`, `lossless`, `channels`,
`language`, `role`, and whether it is the lossy `core` of a lossless track. For
each subtitle stream: `codec`, `language`, `forced`.

Two of these are derived, and each is derived in exactly one place so that every
caller agrees.

`lossless` is a function of codec and profile: TrueHD, MLP, FLAC, PCM, ALAC, and
DTS when its profile is DTS-HD Master Audio. The DTS core inside a DTS-HD track
is the same audio again, lossy, and the ingestion tool already declines to
extract it as a track of its own on those grounds; that decision is carried
here as the `core` fact so that a rule can say so too.

`role` is what a rule means by "is this a commentary", and it has four sources in
order of authority. First, the assignment: if the container declares a
commentary feature and the assignment maps it to this stream, this stream is
that commentary, whatever it calls itself. Second, MakeMKV's stream flags, which
carry the disc's own "director's comments" and "for the visually impaired"
bits. Third, `ffprobe`'s disposition, which says the same thing in the file's
terms. Fourth, and only as a hint reported rather than a fact acted on, a stream
title containing the word "commentary". The first source is the one the sidecar
proposal made possible and the one that makes the rule correct on a disc whose
authoring lied.

Facts come from three places and are merged once: `ffprobe` on the file,
MakeMKV's scan of the title it was ripped from, and the assignment. A fact the
probe and the scan disagree on is reported, not chosen.

### Rules

A ruleset is an ordered list of rules. Each rule has a scope, video, audio or
subtitle; a list of conditions, every one of which must hold; and an action:
copy the stream, drop it, or encode it with the settings given. For the video
stream and for each audio and subtitle stream in turn, the first rule in the
scope whose conditions all hold decides. A stream no rule decides is an error
that names the stream and its facts. A catch-all is a rule with no conditions,
written last.

There is no "or" and there is no nesting. A rule that wants either of two things
is two rules. "Or" is the first thing every rule language grows and the first
thing that makes its order unreadable; the cost of writing a rule twice is paid
by the person writing it, once, and the cost of a nested predicate is paid by
everyone reading it, always.

The three rules the request was made with, in the format proposed:

```xml
<ruleset format="1" name="household" version="7">
  <extraction embeddedAudio="false" subtitles="true" embeddedSubtitles="true"/>

  <!-- An extra below standard-definition width: small, and never HEVC. -->
  <video id="small-extras">
    <when fact="kind" in="featurette,interview,deletedScene,behindTheScenes,trailer,scene,short,clip"/>
    <when fact="video.width" lt="576"/>
    <encode codec="libx264" preset="slow" crf="22" pixelFormat="yuv420p">
      <deinterlace mode="auto"/>
    </encode>
  </video>

  <!-- A lossless source that is not a commentary keeps everything, smaller. -->
  <audio id="lossless-main">
    <when fact="audio.lossless" is="true"/>
    <when fact="audio.role" ne="commentary"/>
    <encode codec="flac"/>
  </audio>

  <!-- A commentary is speech; it does not need what the main mix needs. -->
  <audio id="commentary">
    <when fact="audio.role" is="commentary"/>
    <encode codec="aac" bitrate="160k" channels="2"/>
  </audio>

  <!-- Everything else, as it came. Written last, deliberately. -->
  <video><copy/></video>
  <audio><copy/></audio>
  <subtitle><copy/></subtitle>

  <output container="mkv"/>
</ruleset>
```

`is` is equality, `ne` its negation, `in` a comma-separated set, and `lt`, `le`,
`gt`, `ge` compare numbers and are refused on a fact that is not one. A fact key
carries its scope as a prefix, `video.width`, `audio.role`, and a file-level
fact, `kind`, `profile`, `format`, `duration`, is visible in every scope. An
unknown key, or a scoped key in the wrong scope, is a parse error, not a rule
that never matches.

XML, because the sidecar and the repository file are XML and a ruleset is
hand-edited beside them by the same person; and because the `.smd`'s
"every pointer attribute is named for what it points at" rule reads across
without a second style to learn.

### Extraction as a sibling

The ingestion tool already applies a rule when it rips: every track on the disc,
minus the lossy cores of lossless tracks, minus subtitles if asked, minus the
forced-only streams MakeMKV derives from them if asked. It is expressed twice
today, once as MakeMKV's selection string and once as a per-track predicate for
the engine path, and the two are kept mirrored by hand.

That rule is the `<extraction>` element at the top of the ruleset. It stays a
rule about what is kept at the rip, which is a different question from how what
is kept is encoded, and it lives in the same document because a person deciding
one decides the other. The tool reads it from the silo's active ruleset when it
has one and from its own settings when it does not; the two expressions of it in
the tool become two views of one value.

### Recipes

Resolving a ruleset against a file's facts yields a recipe: one decision per
source stream, each naming the rule that made it, and the output layout, the
list of streams the encoded file will have, in order, each pointing back at the
source stream it came from. The layout is what makes the new presentation's
`<track>` element computable without opening the output: the assignment says the
commentary is source audio 3, the recipe says source audio 3 becomes output
audio 2, and the sidecar says `audio="2"`. The output is then probed and its
actual layout compared to the recipe's; a mismatch fails the job, and is never
placed.

A feature mapped to a stream the recipe drops is a warning the resolver raises
and the tool shows at registration, before anything is encoded. It is not an
error, because a mobile presentation without the isolated score is a reasonable
thing to make; it is not silent, because it changes what the sidecar will say.

A ruleset is stored on the silo under a name, and every store of it is a new
version the silo numbers. A version is immutable. A job records the version it
resolved against and the recipe it resolved, so that re-resolution never happens
by accident and the question "what did this file get, and why" is answered from
the job alone.

## Jobs, nodes and moving files

### Registration

The ingestion tool registers a job the moment a rip finishes, before the file
has been assigned. The job is `unassigned`: it names the file, where the tool is
serving it from, its size, and what MakeMKV recorded about the title it came
from. Registering early costs nothing and means the slow part, moving the file,
can start the moment a node is free rather than the moment a person has decided
what the file is.

When the assignment lands the job becomes `pending`: facts are merged, the
recipe is resolved, and if no rule decides some stream the tool is told so, with
the stream, while the disc is still in the drive. An assignment needs the
container tree, which the tool already authors, and it needs from the person:
the container and item, the alternative, the profile, the map from the
container's features to the file's tracks, and a title if the item is new. It
does not need a binding to the shared store; that is the contribute step, and a
library does not wait for it.

### States

| From | To | On |
| --- | --- | --- |
| — | `unassigned` | the tool registers a rip |
| `unassigned` | `pending` | the assignment lands and a recipe resolves |
| `pending` | `claimed` | an approved node whose `ffmpeg` can do what the recipe needs claims it |
| `claimed` | `encoding` | the first progress report |
| `claimed`, `encoding` | `pending` | the node's lease lapses; the attempt is recorded as lost; the third loss is `failed` |
| `encoding` | `encoded` | the node reports completion with the output's probed layout, and it matches the recipe |
| `encoded` | `placing`, then `placed` | an operator places it, or the library places it itself when told to and the validator raises no error |
| any active | `cancelling`, then `cancelled` | cancellation; the node learns of it in the answer to its next progress report and stops |
| `failed` | `pending` | a retry |

A node claims a job and holds a lease on it; every progress report renews the
lease, so progress doubles as heartbeat and a node that vanishes is noticed by
its silence within the lease's length. A claim prefers a job whose source the
claiming node already holds, so that the machine which ripped a file and can
encode it does not fetch it from itself over the network.

### Files move once

Principle 6 is the design decision that most changes the shape of the thing, so
it gets its argument here.

Every participant serves the files it holds: the ingestion tool serves the rips
in its output folder, a node serves the outputs in its work folder, and the silo
serves a library. A job's source is a URL on its holder; a claiming node fetches
it directly, by `Range`, resuming by offset after an interruption, or opens it
locally if the node is the holder. The output stays on the node that made it.
When the silo places the job it fetches the output from the node into a staging
folder on the library's own filesystem, checks its size and probes its layout,
and renames it into place. Two transfers in the worst case, one in the common
one, and none that exist only to be undone.

The alternative is a central intake: the tool uploads to the silo, the node
downloads from it, the node uploads the result, the silo moves it into place.
Four transfers, two of them of twenty-gigabyte files across a wireless link,
and a server that has to have room for every file in flight. It is simpler to
reason about, and the reasoning is that the ripping machine may go to sleep
before a node gets to its file. That is true, and it is answered by showing it:
a job whose holder does not answer stays `pending` with a note that says so, and
the person who closed the laptop opens it. Parking a source on the silo for a
machine that will be away can be added later without changing the job's shape,
because the silo would simply be another holder.

Each file a holder serves is guarded by a secret minted for the job and handed
by the silo only to the node that claimed it. The threat this defends against is
a guest on the household network, not an adversary; plaintext HTTP on a LAN is
accepted in this version, and TLS is a configuration change when it is wanted.

### Nodes, discovery and approval

A node, on first run, mints an identity and a secret and keeps them. It finds
the silo by Bonjour, or is told its URL, and registers: its name, its platform,
the encoders its `ffmpeg` reports, its cores. The silo records it as `pending`
and gives it nothing. A person approves it, by the operator's command line or,
later, from a list in the ingestion tool, and the node's next poll returns its
token. From then on it claims, reports and completes with that token; revoking
it is one state change, and the node's next request is refused.

Bonjour is convenience, not mechanism: it fills in a URL a person could type,
and nothing depends on it. On macOS the system provides it. On Linux the silo
advertises through Avahi's command-line tools when they are installed and logs
that it did not when they are not; a pure-Swift responder is a project of its
own, and the boundary is drawn so that one could drop in.

The silo may run a node inside itself. Then one machine is the whole pipeline,
which is what makes the first version useful before there is a second machine,
and it is the same loop the standalone node runs, against the same routes, so
that there is one code path to test.

### Why not a cluster

The request named `swift-distributed-actors`, and its attraction is real: nodes
that talk to each other as actors, membership that just happens, no server in
the middle of every message. The design above keeps the part of that which
matters, files that move between the machines that have them, and declines the
rest, for four reasons.

The topology is a star. One silo, some nodes, no node needs to know another
exists; the one thing nodes exchange is files, and they exchange them as HTTP
because that is what files are exchanged as. SWIM-style membership solves
failure detection among peers, and a lease with a heartbeat is the whole of
what a star needs.

One contract. Every interaction a node has with the silo is an operation in the
same OpenAPI document that describes the read routes, tested by the same
in-process harness. An actor transport is a second serialisation, a second
membership system and a second thing to test, in a project whose first
principle after this one is to have one model.

Reach. The ingestion tool is one of the participants, and a URL client runs in
it without the tool binding a cluster port and joining a membership protocol.

Maturity. The library has been a 1.0 beta since 2022 and disabled its own
macOS tests this year. The stack the silo is built on is one this project's
author maintains.

The cost accepted is that a node learns of new work by asking, every few
seconds, rather than by being told, and that progress is polled rather than
pushed. Against encodes measured in hours, neither is a cost anyone will notice.

## Placement

A placement is computed before it is applied. From the assignment and the
container tree it derives the destination folder and filename; from the recipe's
layout and the assignment's feature map it derives the `<presentation>` element,
with its `<track>` children renumbered to the output and its `<chapter>`
children carried from the source; from the validator it collects findings.
An error-severity finding, a destination that already exists, a path that
escapes the container, a track index beyond the probed count, stops it with the
findings shown. Otherwise it is applied in a fixed order: the file is renamed
into place, then the sidecar is rewritten, so that a crash between the two
leaves a file nothing references. The index is then told to re-read that one
container.

A placement can be shown without being applied, and the operator's command line
does so by default. That is principle 5, and it is also the review step the
sidecar proposal asked for when it said container edits should be applied
deliberately rather than behind the user's back.

A sidecar that a person has edited by hand keeps its comments and its order
through a placement, because the edit is made to the document rather than by
regenerating it. A sidecar the silo generated has no comments to keep.

## What this asks of an implementation

One package, on the same stack as the shared store's service will use, with
these parts, in the order they are useful:

- **The rules**, pure and testable: facts, the ruleset file, the resolver, the
  recipe, and the extraction policy the tool reads. With an `ffmpeg` driver and
  a command that encodes one file from one ruleset, it is useful before a server
  exists.
- **The sidecar reader and writer**, which belong to the smddb model package
  because the sidecar is the `.smd`, and **the library layer** here: layout,
  walker, validator, placer. With a command that places a file into a library
  folder, it builds a library by hand.
- **The server's read path**: the index, the discovery routes, the media route,
  the ruleset routes, the OpenAPI document checked in CI.
- **Placement through the server**, then **jobs**, with the embedded node and
  the tool's registration, then **nodes** proper, with discovery and approval,
  then the tool's view of all of it.

Each is a pull request that leaves something usable behind, which is the
roadmap's rule and the only defence against a design this long being built in
the wrong order.

## Non-goals

- **Not a transcoder.** A file is served as it was placed.
- **Not a metadata database.** Cast, ratings, air dates and artwork belong to
  the providers and, where the sidecar proposal put them, to the sidecar.
  The silo indexes what the sidecar says and invents nothing.
- **Not a playback client.** A later proposal.
- **Not internet-facing.** A household network, plaintext, one operator token.
- **Not a scheduler.** First in, first out, among the jobs a node is able to do,
  preferring the one it already holds. Priorities can come when a queue is long
  enough to need them.
- **Not the shared store.** A silo never writes a binding. Contributing what an
  assignment learned is the ingestion tool's step 6, and stays there.

## Open questions

- **Whether the tool should keep filing into an Emby layout as well.** The
  roadmap's phase 1 promised it, and this proposal does not withdraw it, but a
  household running a silo has no Emby to keep working. Decide when the tool's
  Assign stage is built, since that is where the choice is made.
- **Whether a source should ever be parked on the silo.** Argued above as
  unnecessary at first; the job model admits it without change.
- **Resumable uploads at placement.** The silo fetches an output by `Range` and
  can resume; a node's earlier fetch of a source likewise. Neither has been
  exercised across a wireless link that drops.
- **The projection of display order** the sidecar proposal wrote into NFOs has
  no home yet. A silo client derives order from sequences directly, so it may
  need none; if a client wants numbers, they are computed at read time and
  never written.
- **Whether a ruleset may reference another**, for a household with two profiles
  that differ in one rule. Not until there are two.
