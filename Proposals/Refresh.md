<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0003-refresh

Modified: 2026-09-25

# Refresh

This proposes that SiloAdmin keep itself current without being asked. The console refreshes on
its own — on a steady cadence, and whenever it returns to the fore — and its manual refresh
controls go away; a silo is called unreachable only after two consecutive sweeps find no
contact, while contact heals at once; and when the silo the operator is looking at cannot be
used — gone quiet, or no longer accepting the passkey this Mac holds — the console says so in
words, dimming what cannot be clicked and naming what changed. The four classes, the registry
and the setup, claim and forget flows of [0002-onboarding](Onboarding.md) all stand. This is
about how often the truth is asked, how carefully it is called, and how plainly it is said.

## The problem

Freshness is, today, partly the operator's job. The window polls every thirty seconds and on
appear, and then hedges with three manual controls — the ⌘R menu item, the toolbar button, the
empty-state button — as if polling were advisory and the truth arrived when summoned. Either
the cadence is trusted, in which case the controls are noise, or it is not, in which case the
fix is a better cadence. An operator who just replugged the silo does wait out a stale half
minute — the gap the controls pretend to cover — but the honest answer to "I was away and
things changed" is to ask again when the console returns to the fore, which costs the operator
nothing, rather than a button they must remember exists.

Deciding is faster than it should be. One missed poll — a dropped Bonjour announce, a slow
reply, a laptop waking mid-sweep — flips a silo from has-access to gone-quiet for up to thirty
seconds and back. Each classification reads as a verdict the console stands behind, and a
verdict that flickers teaches the operator to ignore all of them, precisely at the moment the
vocabulary is being learnt.

And saying is quieter than it should be. A selected silo that has gone quiet renders its detail
much as a live one does, with "gone quiet" doing all the work; a passkey that has stopped
fitting renders identically to a silo never entered. The registry already keeps everything
needed to say more — last-known-ness is row data by design — but the console does not say it
where the operator is looking.

## What this is

**Refresh becomes the app's job.** The window refreshes on appear and on a thirty-second tick,
as it does today, and additionally whenever the app returns to the fore — the moment an
operator who changed something looks back. The manual refresh controls — ⌘R menu item, toolbar
button, empty-state button — are removed. One sweep never overlaps another: a refresh requested
in flight joins the one under way, so the network is asked once however many voices asked.

**The fall to unreachable is damped; healing is not.** A silo is called unreachable only after
two consecutive sweeps find no contact. A single miss changes nothing the operator can see —
the row keeps the last classification the console verified, and only its last-seen time stands
still, the honest early signal — and the first sweep that reaches the silo renders the probe's
verdict immediately, whatever it is. Hysteresis damps deterioration and never delays good news.

**A silo that cannot be used is announced, and why.** When the selected silo is unreachable,
its detail dims and goes non-interactive under a "currently unreachable" banner; the sidebar
and the rows' acts stay live — forgetting a dead silo being the very act that moment exists
for — and the dim and banner lift themselves when the silo answers again. When the probe
refuses a passkey this Mac holds, the console names the refusal — the stored passkey is no
longer accepted — on the row and, for the selected silo, in a banner of its own, with claim
still on offer. Held-then-refused stops posing as never-met.

## Principles

0002-onboarding's principles stand — discovery as convenience, a URL as the mechanism, the
passkey rarely travelling. This proposal adds three of its own.

1. **The console is read, not operated.** Freshness is a property of the app. If the operator
   has to do something to see the truth, the app is broken in a way a button cannot fix.
2. **Deterioration is damped, healing is instant.** A classification should be a fact the
   console is prepared to stand behind: slow to call a silo dead — two clean sweeps — and
   immediate in calling it back. One dropped packet must never move the interface.
3. **The verbs stay live.** A banner may dim a pane; it never disables an act. The operator's
   vocabulary of moves — set up, claim, forget — is available at every moment it is meaningful,
   and forget is never more meaningful than when the silo is quiet.

## Vocabulary

- **Sweep** — one pass of refresh: the Bonjour browse, the typed-address resolutions, and the
  probes of what answered.
- **Miss** — a sweep that reaches no contact with a silo the registry knows.
- **Held class** — the classification a silo keeps through its first miss: the last one the
  console verified, or, just launched, the one its recorded verdicts imply. A held class is a
  pause, not a reading; only the last-seen clock admits the silence.

## The engine learns patience

The miss ledger is SiloAdminKit's: session state keyed by ServerID, a count and the last
verified class. A contact resets the count and renders the probe's truth. A miss with a clean
count renders the held class and advances the count; a miss with a spent count renders
unreachable. A silo that no sweep has ever reached and no registry records still does not
appear at all, and nothing about forget, claim or setup moves.

The ledger is deliberately not in the registry. Hysteresis is a property of this console's
vantage — what it has verified lately — not of the silo, and the registry already holds
everything durable. Launching the console seeds each known silo's held class from the recorded
verdicts — with-access where the registry kept an access verdict, without-access for a kept
refusal, nothing where there is no verdict — so one miss after launch reads exactly as one
miss mid-session. Persisting the miss count itself would punish a week's absence the console
was not running to witness.

Coalescing joins the ledger in the kit: a refresh arriving while one is in flight awaits it and
shares its rows. Appear, tick and activation may then fire in any combination without stacking
sweeps on the actor, and a slow network stretches the interval rather than queuing debt.

Recovery after a miss deserves one sentence of its own: healing reveals truth, not comfort. A
silo missed once and refused on return renders without-access, named as refused — the damping
applies to silence alone.

## The console's new shape

The cadence stands at thirty seconds, on appear and on returning to the fore. The manual
refresh controls come out: the ⌘R menu item, the toolbar button, and the empty-state button —
the empty state keeps Add Manually, since Bonjour is browsing regardless and a typed address is
the mechanism that survives discovery failing. Coalescing is what makes removal safe: the three
sources can land in the same instant and the silos are still asked once.

The treatments are functions of the row the engine already hands over — no new state crosses
from kit to shell. An unreachable selected silo: the detail dims and takes no input behind a
banner saying the silo is currently unreachable, restored on the sweep that finds it again.
The banner and dim exist only where a detail exists — one selected silo — and the sidebar is
never part of the dim: selecting away, and forgetting the dead, stay one click. A without-access
row whose last-known access is a refused verdict reads as refused rather than no access, on the
row and, when selected, in a banner of its own; claim is on offer exactly where it always was.

A sweep may reclassify a row beneath an open setup or claim sheet. That is kept: the flow
renders its own verdict on completion — the refusal alerts already exist — and the row's
honesty underneath is worth more than the coincidence is confusing.

## What this looks like to the operator

A silo is unplugged while the operator is elsewhere in the house. At the next tick its row does
nothing but let "seen …" stale; a tick later it reads gone quiet — had access when last seen —
and if it was selected, the detail is dim behind the unreachable banner, Forget still one
click away. The silo comes back; the following tick clears the banner and the dim before the
operator thought to reach for a button that is no longer there. Months later a credential is
rotated on the server: the sweep asks, the silo refuses, and the console says the stored
passkey is no longer accepted, with Claim on offer where it always was. At no point did anyone
press refresh.

## What this asks of an implementation

Each step is a pull request, in order, and each carries its spec deltas into `openspec/` per the
corpus README — the deltas are written now, under [`specs/`](Refresh/specs/) beside this
proposal.

### 1. The engine learns patience

SiloAdminKit: the miss ledger with its launch seeding from the registry's verdicts, and sweep
coalescing. The classification spec deltas apply here.

Tests: one miss holds the class with last-seen frozen; two misses render unreachable with
last-known intact; contact after one miss renders that sweep's verdict at once; a silo dead
since before launch seeds from the registry and then obeys the same two-miss rule; concurrent
refreshes ask the network once.

### 2. The console refreshes itself

SiloAdmin: refresh on application activation joins appear and the tick; the ⌘R menu item, the
toolbar button and the empty-state button are removed. No engine change; the auto-refresh spec
delta applies here.

### 3. The console announces what cannot be used

SiloAdmin: the dimmed, non-interactive detail and unreachable banner for the selected quiet
silo, restored on return; refused-verdict naming on rows and its own banner for held-then-
refused. All of it derived from the classification and last-known fields the engine already
hands over. The announcement spec delta applies here; shell-level behaviour stays `Pinned by:
nothing yet.` until the shell grows a test seam.

## Non-goals

- **Any server change, push, or instant signalling.** The console polls; a minute of worst-case
  damping is affordable on a household LAN, and no route or TXT record moves.
- **A configurable cadence.** Thirty seconds is a decision, not a default waiting for a settings
  pane.
- **Reachability history.** Uptime graphs, flap counts, a log of comings and goings: `last-seen`
  remains all the console remembers.
- **A first-miss indicator.** The frozen last-seen line is signal enough; a fifth visual state
  would blur the four-class invariant the spec pins.

## Open questions

1. **The numbers.** Thirty seconds plus one confirming miss puts the worst case at about a
   minute from silence to banner. A faster tick, or an adaptive one that sweeps again sooner
   right after a miss, would trade network noise for speed; this proposal ships the steady
   cadence and waits for the pain to argue otherwise.
2. **What a sweep may move under an open sheet.** A setup or claim sheet can be up while its
   silo goes quiet mid-flow; the position here is that the flow renders its own verdict and the
   row moves underneath, but the first operator confusion it causes is evidence to revisit.
3. **Speaking while the console is away.** Gone-quiet while the app is backgrounded could ring
   a macOS notification. This proposal says the console speaks when looked at and is silent
   otherwise, but it is the kind of affordance someone will ask for, and the answer should be
   chosen rather than drifted into.
