<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0011-extras

Modified: 2026-10-15

# Extras

This proposes that a rule can ask whether the item it is deciding is an **extra**, as a fact of its
own, and that the classification of an extra — a trailer, an interview, a deleted scene — is a
vocabulary SmdKit names rather than one each ruleset spells out. A household can then say what it
wants of extras in rules as plain as the ones it writes for everything else: an extra gets a lower
bitrate, keeps only English subtitles, or keeps only lossy audio, and a trailer is treated apart from
an interview when that matters.

Both halves are already in the data. Whether an item is an extra is where its container holds it —
in `<extras>` rather than a sequence, the `Role` of its entry in smddb — and its classification is
the `type` its entry carries, which smddb's structured containers take from Emby's `ExtraType`. The
silo reads both when it checks a binding and uses only the second. This proposal has it use the
first, and has the console offer the second's values.

## The problem

A rule can test `kind`, the item's type from the binding's lineage. It cannot test whether the item is
an extra. So a rule meant for extras names every type an extra might have, as the example ruleset's
`small-extras` does:

```xml
<when fact="kind" in="featurette,interview,deletedScene,behindTheScenes,trailer,scene,short,clip"/>
```

That is a classification standing in for a position, and the two are not the same thing.

- **An extra need not have an extra's type.** A short film filed among a film's extras is a `short` in
  one container and a `movie` in another. A feature-length documentary on a box set is a `movie` that
  is plainly an extra. A list of types catches neither.
- **A type that is not listed is not an extra.** The vocabulary is open: a new type is a string in a
  container, not a code change. Every ruleset written as a list misses it silently, and nothing
  tells the operator their extras rule stopped catching something.
- **Every ruleset carries its own copy of the list.** The lists drift, and a rule that should read
  "if this is an extra" reads as an inventory.

The console makes the second half worse than it needs to be. `kind` is a bare text field in the form,
so the operator must remember that the vocabulary spells it `deletedScene` and not `deleted scene` or
`deleted`, though SmdKit could say so, and names only three of the types it accepts.

## What this is

**Being an extra is a fact.** `extra` is a file-level flag, true when the binding's item is held in its
container's `<extras>` and false when it is held in a sequence. It comes from the lineage, as `kind`
does, and is visible to a rule of every scope. A binding's item is always one or the other, so the fact
is never absent for a binding. A resolve that names no binding — the dry run, or `silo-ctl encode` —
says it or leaves it out.

**The classification stays `kind`.** `kind` is still the item's type, whether it is an extra or not,
and is still open. What changes is that SmdKit names the types an extra is classified by, so that the
console can offer them and a ruleset can rely on how they are spelled.

**An extra is where it is filed, not what it is called.** The silo already places an item held in
`<extras>` under the library's `extras/` folder by exactly this test. The rule language now asks the
question placement already answers, the same way.

## Principles

1. **Position and classification are separate facts.** `extra` says where the item is filed; `kind`
   says what it is. Neither stands in for the other.
2. **The vocabulary is SmdKit's.** The silo, the console and smddb spell an extra's type the way SmdKit
   names it, which is Emby's `ExtraType`, so a client that already groups extras by type needs no
   translation.
3. **Open stays open.** Naming the types does not close `kind`. A type SmdKit does not name is still a
   valid type, and a rule may still test it.
4. **The silo is told, never guesses.** Whether an item is an extra, and what type it is, come from the
   container that holds it. The silo infers neither from a file's length, title or streams.

## Vocabulary

- **Extra** — an item a container holds in its `<extras>` rather than in a sequence.
- **Classification** — an item's `kind`: for an extra, one of the types SmdKit names for extras, or
  another its container gives.

## What SmdKit adds

`EntryType` names, beside `episode`, `movie` and `featurette`, the rest of Emby's `ExtraType`:
`behindTheScenes`, `deletedScene`, `interview`, `trailer`, `scene`, `short`, `clip`, `themeSong` and
`themeVideo`. `EntryType.extraTypes` lists the ten types an extra is classified by, `featurette`
first, in that order. `EntryType` stays a string wrapper that accepts any raw value but `container`.

## What the silo adds

### The fact

`FactKey` gains `extra`, a file-level flag. `SourceFacts` gains `extra`, derived in the one place the
facts are derived: true when the lineage's last container holds the binding's item in its extras,
false when it holds it in a sequence. The binding check already looks the item up in the sequences and
then the extras; it keeps which of the two it found it in.

A recipe records its facts, so a recipe committed from now on records `extra`. One committed before
records none, and reads it as absent; see the open questions.

### Resolving without a binding

The resolver's dry run takes an optional `extra` beside `kind`, absent when left out, as `kind` is.
`silo-ctl encode` takes `--extra`: given, the fact is true; left out, false, since a file encoded on its
own from the command line is a main item unless it is said to be otherwise.

### The example

`Examples/household.xml`'s `small-extras` tests `extra` instead of listing types:

```xml
<!-- An extra below standard-definition width: small, and never HEVC. -->
<video id="small-extras">
  <when fact="extra" is="true"/>
  <when fact="video.width" lt="576"/>
  <encode codec="libx264" preset="slow" crf="22" pixelFormat="yuv420p">
    <deinterlace mode="auto"/>
  </encode>
</video>
```

## What the console adds

The form offers `extra` as true or false, as it offers any flag. A condition on `kind` offers SmdKit's
named types from the menu beside its field, `episode` and `movie` first and then the extra types, while
the field still takes any type.

## What this looks like to the operator

The operator wants extras to cost less than the films they come with. In the form they add three rules
to their draft, each first in its scope:

```xml
<!-- An extra gets a lower bitrate. -->
<video id="extra-video">
  <when fact="extra" is="true"/>
  <encode codec="libx264" crf="24"/>
</video>

<!-- An extra keeps only English subtitles. -->
<subtitle id="extra-subtitles">
  <when fact="extra" is="true"/>
  <when fact="subtitle.language" ne="en"/>
  <drop/>
</subtitle>

<!-- An extra keeps only lossy audio: a lossless track becomes AAC. -->
<audio id="extra-audio">
  <when fact="extra" is="true"/>
  <when fact="audio.lossless" is="true"/>
  <encode codec="aac" bitrate="160k"/>
</audio>
```

In the form the first reads IF extra is true THEN encode WHERE codec is h264 AND crf is 24. `language`
is the primary language subtag, so `ne en` keeps `en-GB` and `en-US` alike. The audio rule re-encodes
rather than drops: the rule language decides each stream on its own facts, and cannot say "drop a
lossless track when a lossy one is also kept", so dropping would leave an extra whose only track is
lossless with no audio at all.

Later they want trailers smaller still, and add a rule above `extra-video`, choosing `trailer` from the
menu beside `kind`:

```xml
<video id="trailers">
  <when fact="kind" is="trailer"/>
  <encode codec="libx264" crf="28"/>
</video>
```

They commit the draft to a branch and try it on three bindings, among them a box set's feature-length
documentary filed in its extras with the type `movie`. The documentary's trial comes back at CRF 24,
which a list of extra types would have missed.

## What this asks of an implementation

Three steps, one pull request each, each carrying its spec change.

### 1. Extra types in SmdKit

SmdKit names the extra types and lists them in `EntryType.extraTypes`, its container-model spec
changed in the same pull request. It merges first, and the silo's `Package.resolved` moves to it.

### 2. The fact

`FactKey.extra` and `SourceFacts.extra`, derived from the lineage; the resolver's `extra`; `silo-ctl
encode --extra`; and the example's `small-extras` rewritten to test it.

### 3. The console

The form's suggested values for `kind`, from `EntryType`'s named types.

## What comes next

An extra's container says more than that it is an extra: an extra held by a series, a season or an
episode is filed at a different level, and smddb's structured containers render the three differently.
A rule that wants a series' extras treated apart from an episode's would need that level as a fact of
its own. Nothing asks for it yet.

## Non-goals

- **Classifying extras.** What an item is, and whether it is an extra, is its container's to say. The
  silo reads both and infers neither.
- **Closing `kind`.** A type SmdKit does not name stays valid; the console suggests named types and
  takes any.
- **Library layout by type.** Every extra is placed under `extras/`, as it is today. Filing extras into
  per-type folders is a projection of the container, smddb's to make, not the silo's.
- **Rewriting the old proposals.** `Silo.md` and `LayeredRulesets.md` keep their examples as the record
  of what was argued then; the example ruleset and the specification change.

## Open questions

1. **Recipes committed before the fact.** A recipe records its facts, and the background check
   re-resolves those facts against the rules in force. A recipe committed before this lands has no
   `extra`, so a new rule on `extra` never holds for it and the check reports nothing. Re-applying a
   binding makes a recipe that has it. Whether the check should derive a missing fact from the
   binding's current lineage, rather than read it as absent, is a question for every fact added from
   now on, not only this one, and is
   [silo-server#77](https://github.com/media-silo/silo-server/issues/77).
2. **A reclassified item.** For the same reason, an item moved between a sequence and the extras, or
   given another type, after it was placed is not reported out of date: its recipe keeps the facts it
   was committed with. That is true of `kind` today. Noticing it means the check comparing a
   recipe's lineage facts with the lineage as it is now, which #77 also covers.
3. **Theme songs.** `themeSong` names an extra that is audio alone. A source with no video stream
   resolves today, but no one has placed one, and its layout and the sidecar's view of it are untried.
