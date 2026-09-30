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
  bootstrap mode and the staged, then confirmed, setup pair it allows, the operator's passkey,
  recovery through the filesystem, and SiloAdmin, the macOS console that finds silos and walks
  a fresh one through its first ten minutes.
- [Refresh](Refresh.md) — SiloAdmin keeps itself current: refresh is the app's job rather than
  a manual control, a silo is called unreachable only after two missed sweeps while contact
  heals at once, and a selected silo that has gone quiet — or stopped accepting this Mac's
  passkey — is announced in words.
- [Configuration](Configuration.md) — where a silo's configuration lives and who may change it:
  `SILO_STATE_DIR` as the one variable, the state directory at a known place on the machine, and
  two files inside it divided by one rule — `silo.json` for what no route changes, read at
  startup, and `settings.json` for what routes change, applied while the silo runs — and a
  default port off 8080.
- [Layered rulesets](LayeredRulesets.md) — the rules that decide a file come in layers, nearest
  first: a container's own rules in its `.smd`, then its ancestors', then the library's standard
  ruleset. A ruleset has branches, used on the ingestions the operator chooses and promoted to be
  the standard. Each job records exactly which rules made its file, and the silo reports which
  placed presentations the current rules would make differently, and whether their sources can be
  had.
