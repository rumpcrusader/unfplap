# unfplap — mod-specific agent guide

Read `res://mods/AGENTS.md` first and follow its general Home: Equestria mod rules. This file adds
the working knowledge for `unfplap` only. It holds the project rules and the path router; the
concepts are in `ARCHITECTURE.md`, the commands in `WORKFLOW.md`, the service index in
`docs/README.md`, and the per-service contracts under `docs/`.

## Required reading by path

Do not start implementation until you have read the owning doc for the files you will touch. The
table is the router: a doc not listed here is reached from `docs/README.md`, and this file does not
restate a contract.

| Paths | Read |
|---|---|
| `main.gd` | `ARCHITECTURE.md`, `docs/runtime.md` |
| `runtime.gd` | `docs/runtime.md` |
| `act/**` | `docs/runtime.md` |
| `world/api.gd` | `docs/world.md` |
| `world/game.gd` | `docs/world.md` |
| `settings/game.gd` | `docs/settings.md` |
| `offer/service.gd` | `docs/offer.md` |
| `api.gd` | `docs/api.md` |
| `tests/**` | `docs/tests.md` |
| `tests/body_change/**` | `docs/tests.md`, `docs/body_change.md` |
| `tests/offer/**` | `docs/tests.md`, `docs/offer.md` |
| `*.sh`, `.gdlintrc`, `scripts/requirements-lint.txt`, `scripts/pack_report.py` | `docs/quality.md` |
| `shared/act_facts.gd` | `docs/act_facts.md` |
| `shared/act_state.gd` | `docs/runtime.md` |
| `shared/act_keys.gd` | `docs/input.md` |
| `shared/integrations.gd` | `docs/integrations.md` |
| `shared/act_face.gd` | `docs/face.md` |
| `shared/act_history.gd` | `docs/summary.md` |
| `shared/act_motion.gd` | `docs/camera.md` |
| `shared/anatomy_placement.gd` | `docs/anatomy.md` |
| `shared/body_form.gd`, `shared/body_change.gd`, `shared/body_binding.gd`, `shared/body_change_policy.gd`, `shared/body_profile.gd` | `docs/body_change.md` (`shared/body_profile.gd` also `docs/anatomy.md`, `docs/camera.md`) |
| `shared/character_preferences.gd`, `shared/preferences.gd` | `docs/preferences.md` |
| `shared/defaults_data.gd` | `docs/settings.md` |
| `shared/prompt_text.gd` | `docs/prompts.md` |
| `shared/hands_*.gd` | `docs/hands.md` |
| `shared/log.gd`, `shared/perf.gd` | no doc: the frozen file header is the contract |
| `shared/build_stamp.gd` | its file header |
| `shared/pose_catalog.gd` | `docs/poses.md` |
| `shared/settings_change.gd` | `docs/settings.md` |
| `shared/smack_cues.gd` | `docs/audio.md`, `docs/stock_smack.md` |
| `shared/voice_status.gd` | `docs/audio.md` |
| `shared/relationship_cue.gd` | `docs/dialogue.md` |
| `shared/bond_record.gd`, `shared/touch_bridge.gd`, `shared/dock_fit.gd` | `docs/world.md` |
| `shared/rump_cone.gd` | `docs/scene_gate.md` |
| `afterglow/**` | `docs/afterglow.md` |
| `anatomy/**` | `docs/anatomy.md` |
| `audio/**` | `docs/audio.md` |
| `stock_smack/**` | `docs/stock_smack.md` |
| `body_change/**` | `docs/body_change.md` |
| `camera/**` | `docs/camera.md` |
| `debug/game.gd` | `docs/debug.md` |
| `debug/**` | `docs/debug.md` |
| `dialogue/**` | `docs/dialogue.md` |
| `eligibility/**` | `docs/eligibility.md` |
| `face/**` | `docs/face.md` |
| `hands/**` | `docs/hands.md` |
| `hud/game.gd` | `docs/hud.md` |
| `hud/**` | `docs/hud.md` |
| `initiation/**` | `docs/initiation.md` |
| `input/**` | `docs/input.md` |
| `integrations/**` | `docs/integrations.md` |
| `integrations/changelings.gd`, `integrations/changelings_policy.gd` | `docs/integrations.md`, `docs/body_change.md` (`## Source extension point`, `## Provider policy`) |
| `kiss/**` | `docs/kiss.md` |
| `memory/**` | `docs/memory.md` |
| `negotiation/**` | `docs/negotiation.md` |
| `poses/**` | `docs/poses.md` |
| `reactions/**` | `docs/reactions.md` |
| `readiness/**` | `docs/readiness.md` |
| `registry/**` | `docs/registry.md` |
| `rest/**` | `docs/rest.md` |
| `scene_gate/**` | `docs/scene_gate.md` |
| `scene_hold/**` | `docs/scene_hold.md` |
| `settings/**` | `docs/settings.md` |
| `settings/prompts.json` | `docs/prompts.md` |
| `stool/**` | `docs/stool.md` |
| `summary/**` | `docs/summary.md` |
| `vr/**` | `docs/vr.md` |
| `offer/**` | `docs/offer.md` |
| `ponies/**` | `docs/ponies.md` |
| `world/**` | `docs/world.md` |
| `assets/**`, `scripts/asset_pack*` | `assets/README.md`, `CREDITS.md` |

Non-code tasks: a release is `.opencode/skills/release/SKILL.md`; syncing shipped defaults is
`.opencode/skills/sync-settings/SKILL.md`; a boundary or dependency change starts at
`ARCHITECTURE.md` and `docs/README.md`.

## Identity and scope

- Mod id `unfplap`; the current version and target game are in `mod.json`. Adult mares only; human
  Anon and AnonPony.
- All eligibility, consent and relationship-level gates are in `docs/eligibility.md`. Two
  **offerable** poses: `missionary` on a bed/couch and `standing` standing; internal poses are not
  offers.
- No pregnancy, conception, content warning, new character or body models. Estrus is an optional,
  off-by-default cycle (`features.estrus_cycle`) that changes timing, willingness and dialogue
  only. The anatomy is an optional, feature-gated addition that never replaces a pony's body or
  rig; its meshes, textures and the act audio come from one external resource pack fetched before
  a build, are not tracked, and the mod does not run without them. The act stays off-camera by
  framing; modelled accessories are allowed.
- Anatomy attaches to every adult identity with `pony_hips`, including mares added by other mods;
  the base-game roster is not an attachment whitelist, and tail seating follows the same rule.
  Acts still need the game's relationship runtime and adult bond.
- Desktop first: VR and seated VR are deferred except the optional standing VR act behind the
  anatomy master.
- The user-facing summary is `README.md`; the per-system contracts are under `docs/`.

## How to work

Read `WORKFLOW.md` before any task. Commit in small, testable units; never push.

- **Docs follow the code, same commit.** Land the behavior, its tests and the sentences the change
  makes false in one commit. A standalone `docs:` commit is only for docs no code change touched: a
  new contract, an index row, a sweep.
- Settle the design before touching files. Once it is settled, apply every code edit first, then
  check the change. Before each commit run `scripts/test.sh <touched>`, `scripts/check.sh --parse`
  and `scripts/lint.sh`; run `scripts/check.sh` and `scripts/test.sh` once when the code phase is
  done.
- Use one whole-file write for a file that changes heavily, and send independent edits together in
  one turn. A chain of single-line edits costs a round trip each.
- **The shell already runs in the mod directory.** Never prefix a command with `cd`; pass
  `workdir` for the game project root (`../..`) or another checkout.
- Plans live outside the repo. Resolve the path with
  `printf '%s\n' "$HOME/.opencode/plan/$OPENCODE_SESSION_ID.md"` and write there; never create a
  plan file in the repository.
- Start a fresh session once the context has grown past a few hundred thousand tokens; carry a
  short plan forward instead of appending to a long conversation.
- **Player-facing settings need the user's approval.** Agree the setting name, hint wording,
  options and placement (tab, section and order) before implementing one. Debug settings are the
  agent's call: choose those details and report them.

## Definition of done

1. The code, its tests and the doc text the change makes false are one code commit. A standalone
   `docs:` commit is only for docs no code change touched.
2. A new doc is indexed in `docs/README.md` in the same commit.
3. Suites are added or retargeted; `scripts/test.sh <touched>` passes, `scripts/check.sh` is
   clean and `scripts/lint.sh` is clean before the commit.
4. `scripts/test.sh` passes once, at the end of the code phase.
5. A standalone `docs:` commit passes `scripts/check.sh`, `scripts/lint.sh` and every suite
   that reads an edited doc.
6. New `.gd` files are tracked before a build; the pack manifest reads `git ls-files`.
7. `mod.json.version` and `changelog.txt` change only through the release skill.
8. `README.md` was not edited; a needed change is reported with exact replacement text.

## Service API

Every service facade — `<service>/api.gd` preferred, `<service>/service.gd` legacy — and every
public handle it returns follows these. The mechanics — facade, typing, state and reach-in rules —
are in `ARCHITECTURE.md` (`## The service contract`).

- **The surface is defined by the consumer, and the service adapts to it.** A member exists only
  because a caller's job needs it and is traceable to that caller; when a consumer needs something,
  the service changes, not the consumer's workaround. *Test: name the caller and the job it is
  trying to do at the business-logic level.*
- **The interface lives at the level of the business need.** A consumer asks for the action, query
  or handle it actually needs; the API never exposes internal steps, state or data structures. It
  need not be a command — a query is right when that is what the consumer really needs.
  *Test: would the consumer otherwise have to reimplement business logic or reach inside?*
- **Internals stay internal.** State, wiring and composition are private; the boundary exposes only
  typed handles that behave like views of the service. No public fields, no reach-ins, no “just this
  once” access. *Test: can the internal representation change without touching a consumer?*
- **The contract is typed.** Every public member carries explicit parameter and return types; the
  compiler and the architecture gate enforce it. Weak types and typing debt are defects, not
  concessions. *Test: would a wrong call fail at parse time rather than at runtime?*
- **Every public surface change needs explicit approval.** Adding, removing, renaming or re-signing
  a public member is proposed with its justification and the list of consumers; an unapproved
  surface change is a defect, however small.

## Non-negotiables

- **Order is load-bearing.** `act/tick.gd:tick` and its `render` (render-time pose write), the
  start sequence, `act/exit.gd:run` and the impact fan-out keep their call order until a change
  deliberately moves one call.
- **One teardown.** `act/exit.gd:run` is the only exit path and its own routes plus the consent stop
  are its only callers; the static gate enforces it. Do not add a second exit
  sequence.
- **No reach-ins, no allocation churn.** A system must not preload `runtime.gd` or `main.gd`, must
  not call `runtime.get("_…")` / `runtime.call("_…")`, and reuses `act_facts` and event
  dictionaries instead of allocating per frame. The entry constructs and binds; it never dispatches
  by string or assigns a service's fields. Presentation modules read `shared/act_facts.gd` or the
  owning facade.
- **The entry is not a locator.** A service that needs another service preloads its facade; a
  service that needs the scene reads `WORLD`; nothing but `main.gd` names `main`
  (the static gate fails on any other shipped file, `tests/` excepted). A new
  long-running service joins the lifecycle with `on_world(host)`, `on_world_closed()`,
  `on_player(body)` and `shutdown()`, and one line in the entry's service list.
- **One game boundary.** A base-game import lives only in `<service>/game.gd`; a `game.gd` exists
  only in a game-layer service directory; only that service's own files import it. Every other file
  reads the game through a facade, and the `/root/Settings` and `/root/Mods` literals obey the same
  rule. The static gate fails a new base-game import outside one.
- **No preload re-exports.** A file uses only the preload consts it declares. Reaching another
  module's `const … := preload(...)` fails the gate; enums, nested classes and plain constants stay
  reachable, and `GAME.X` is the one allowed re-export.
- **The top preload block is the dependency manifest.** Every script dependency is a top-level
  `const … := preload(...)` in the contiguous block directly below the doc header, in every `.gd`
  including `tests/` and `tools/`. A late or nested preload and a `load()` of a script are gate
  failures; a runtime asset `load(path)` stays allowed.
- **Settings reads.** A service may read its typed handles at use, hot or cold; a bulk block uses
  `SETTINGS.act_snapshot(group)`. No default copies, no private settings module, no per-service
  cache; if a hot path regresses, improve the settings service. One declaration in
  `settings/service.gd`, one shipped value in `settings/settings.json`, one typed read; the
  framework is `docs/settings.md`.
- **No game-file edits and no JSON merges.** Everything lives under `res://mods/unfplap/`.
- **The cross-mod API is frozen.** `api.gd`, `docs/api.md` and `tests/test_api.gd` are edited only
  with the user's explicit approval; that approval starts the task and the edit follows the
  same-commit rule.
- **No global debug hotkeys.** `debug/service.gd` declares none; a debug action is a button in its
  Debug block and the game's dev keys stay the game's.
- **Tests move with the code.** A change is not done while its suite reads the old private path,
  unless it is explicitly retargeted to the facade.
- **A correct boundary beats a line count.** Report `runtime.gd`'s size as information, not a goal.
- **One sink, one profiler.** `shared/log.gd` is the only file that prints, warns, errors or
  builds the mod prefix, and `shared/perf.gd` the only one that reads a clock, an engine
  monitor or the rendering info. Every other script calls `LOG` and `PERF`;
  the static gate fails on a second one.
- **Both modules are frozen.** `shared/log.gd` and `shared/perf.gd` are edited only with the
  user's explicit approval; their header is the contract and no `docs/` entry restates it.
- **A timed chunk is one unconditional pair.** `PERF.begin("chunk")` and `PERF.end("chunk")`
  wrap a self-contained block and are never separated by an early `return`: an open frame at
  the frame's end is a bug the profiler reports and drops, not a shape to work around.
- **Performance check.** With **Enable debug** + **Print perf logs**, read one `perf` block in
  an act and one outside it before and after a change that touches the tick, the pose, the
  camera or a service's composition. A chunk that moved into another chunk's row, or a row
  that grew without a matching change, is the signal; record the rows, never a claim.

## Documentation

- Every service has exactly one doc under `docs/`, indexed by exactly one row in `docs/README.md`.
  A doc owns its responsibility and boundary, the decisions behind that boundary, invariants,
  ordering constraints, traps and extension points. It never enumerates what a script, a
  declaration or the index already carries: no API signature dumps, no dependency edges, no
  setting rows, no debug-action rosters, no test lists, no numeric defaults, no call counts. Point
  at the owner instead. A doc names another system in at most one clause; anything more is a link.
- The index row owns the facade and the test paths; a contract does not repeat them.
- A facade's non-underscore members are its surface; `_` marks internals. A `##` note above a
  facade's public type, and above every public member of `api.gd` that is not a preload const,
  states the rule the signature cannot. Public facade functions without a note stay advisory:
  `--audit-surface` prints them, and it is not a gate.
- **Docs follow the code, same commit.** Documentation means both `.md` files and code comments. A
  claim a change makes false is fixed in the commit that makes it false. A standalone `docs:`
  commit is only for docs no code change touched: a new contract, an index row, a sweep. Fix only
  the claims that became false; a claim that is still true is never reworded.
- **Comments state what the code cannot.** A `##` block is at most two lines: the promise, then one
  clause of why when the reason is not visible. A file header is at most five lines — the
  `Service:`/`Scope:`/`Contract:` fields plus one purpose sentence; the owning doc carries
  the rest. A `#` block is at most three lines and only for an invariant, an order constraint, a
  game quirk or a workaround. Do not restate a doc sentence, a member name, a count, an ordinal or a
  numeric value the code owns; a rename must never force a comment edit. The comment gate
  enforces the shape in `scripts/lint.sh`.
- A doc names settings and behaviour, not copied numeric defaults; the shipped
  `settings/settings.json` is the source for the default and the declaration in
  `settings/service.gd` for the bounds.
- `docs/api.md` is the only cross-mod API contract. `README.md` is human-owned: do not edit it;
  report the needed change with exact replacement text.

## Commands

```bash
scripts/test.sh [<suite>...]  # no argument runs every suite; also --list, --smoke (failures only)
scripts/check.sh [--parse]    # no argument parses every script and runs the static gate
scripts/lint.sh               # gdlint over the shipped scripts
./lab.sh                      # manual lab; also lab-stress.sh, lab-vr.sh
```

Everything else — run from source, the labs, build, bisect and release — is in `WORKFLOW.md`.
