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
| `api.gd` | `docs/api.md` |
| `tests/**` | `docs/tests.md` |
| `shared/act_facts.gd` | `docs/act_facts.md` |
| `shared/act_keys.gd` | `docs/input.md` |
| `shared/integrations.gd` | `docs/integrations.md` |
| `shared/act_face.gd` | `docs/face.md` |
| `shared/act_history.gd` | `docs/summary.md` |
| `shared/act_motion.gd` | `docs/camera.md` |
| `shared/anatomy_placement.gd` | `docs/anatomy.md` |
| `shared/character_preferences.gd`, `shared/preferences.gd` | `docs/preferences.md` |
| `shared/hands_*.gd` | `docs/hands.md` |
| `shared/perf.gd`, `shared/perf_idle.gd` | `docs/perf.md` |
| `shared/pose_catalog.gd` | `docs/poses.md` |
| `shared/relationship_cue.gd` | `docs/lines.md` |
| `shared/rump_cone.gd` | `docs/scene_gate.md` |
| `afterglow/**` | `docs/afterglow.md` |
| `anatomy/**` | `docs/anatomy.md` |
| `audio/**` | `docs/audio.md` |
| `camera/**` | `docs/camera.md` |
| `debug/**` | `docs/debug.md` |
| `eligibility/**` | `docs/eligibility.md` |
| `face/**` | `docs/face.md` |
| `hands/**` | `docs/hands.md` |
| `hud/**` | `docs/hud.md` |
| `initiation/**` | `docs/initiation.md` |
| `input/**` | `docs/input.md` |
| `integrations/**` | `docs/integrations.md` |
| `kiss/**` | `docs/kiss.md` |
| `lines/**` | `docs/lines.md` |
| `memory/**` | `docs/memory.md` |
| `poses/**` | `docs/poses.md` |
| `reactions/**` | `docs/reactions.md` |
| `readiness/**` | `docs/readiness.md` |
| `registry/**` | `docs/registry.md` |
| `rest/**` | `docs/rest.md` |
| `scene_gate/**` | `docs/scene_gate.md` |
| `scene_hold/**` | `docs/scene_hold.md` |
| `settings/**` | `docs/settings.md` |
| `stool/**` | `docs/stool.md` |
| `summary/**` | `docs/summary.md` |
| `vr/**` | `docs/vr.md` |
| `assets/**`, `scripts/asset_pack*` | `assets/README.md`, `CREDITS.md` |

Non-code tasks: a release is `.opencode/skills/release/SKILL.md`; syncing shipped defaults is
`.opencode/skills/sync-settings/SKILL.md`; a boundary or dependency change starts at
`ARCHITECTURE.md` and `docs/README.md`.

## Identity and scope

- Mod id `unfplap`; the current version and target game are in `mod.json`. Adult mares only; human
  Anon and AnonPony.
- All eligibility, consent and relationship-level gates are in `docs/eligibility.md`. Exactly two
  poses: `missionary` on a bed/couch and `standing` standing.
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

- Settle the design before touching files. Once it is settled, apply every edit first, then check
  the change. Gate once per task, not per commit: `scripts/test.sh <touched>` and
  `scripts/check.sh` before each commit, `scripts/test_all.sh` once when the task is done.
- Use one whole-file write for a file that changes heavily, and send independent edits together in
  one turn. A chain of single-line edits costs a round trip each.
- Plans live outside the repo. Resolve the path with
  `printf '%s\n' "$HOME/.opencode/plan/$OPENCODE_SESSION_ID.md"` and write there; never create a
  plan file in the repository.
- Start a fresh session once the context has grown past a few hundred thousand tokens; carry a
  short plan forward instead of appending to a long conversation.
- **Player-facing settings need the user's approval.** Agree the setting name, hint wording,
  options and placement (tab, section and order) before implementing one. Debug settings are the
  agent's call: choose those details and report them.

## Definition of done

1. The owning doc is updated in the same commit; a new doc is indexed in `docs/README.md`.
2. Suites are added or retargeted, `scripts/test.sh <touched>` passes and `scripts/check.sh --all`
   is clean.
3. `scripts/test_all.sh` passes once, at the end of the task.
4. New `.gd` files are tracked before a build; the pack manifest reads `git ls-files`.
5. `mod.json.version` and `changelog.txt` change only through the release skill.
6. `README.md` was not edited; a needed change is reported with exact replacement text.

## Non-negotiables

- **Order is load-bearing.** `_physics_tick`, `_process_tick` (render-time pose write), the start
  sequence, `_end_session` and the impact fan-out keep their call order until a change deliberately
  moves one call.
- **One teardown.** `_end_session` stays in `runtime.gd` and is the only exit path;
  `tests/test_source_hygiene.gd` enforces it. Do not add a second exit sequence.
- **No reach-ins, no allocation churn.** A system must not preload `runtime.gd` or `main.gd`, must
  not call `runtime.get("_…")` / `runtime.call("_…")`, and reuses `act_facts` and event
  dictionaries instead of allocating per frame. Presentation modules read `shared/act_facts.gd` or
  the owning facade.
- **Settings snapshot.** Values arrive once per act and again on `apply_live_settings()`; no
  per-frame `Settings` reads. One declaration in `settings/service.gd`, one shipped value in
  `settings/defaults.json`, one typed read; the framework is `docs/settings.md`.
- **No game-file edits and no JSON merges.** Everything lives under `res://mods/unfplap/`.
- **No global debug hotkeys.** `debug/service.gd` declares none; a debug action is a button in its
  Debug block and the game's dev keys stay the game's.
- **Tests move with the code.** A change is not done while its suite reads the old private path,
  unless it is explicitly retargeted to the facade.
- **A correct boundary beats a line count.** Report `runtime.gd`'s size as information, not a goal.
- **Performance check.** With **Enable debug** + **Print perf logs**, compare one act and one idle
  window before and after a change that touches the tick, the pose or the camera; see `docs/perf.md`.

## Documentation

- Every service has exactly one doc under `docs/`, indexed by `docs/README.md`, and that doc is the
  single source of truth for its purpose, ownership, API, state, settings, controls, debug actions,
  dependencies and tests; no other doc restates them. Update it in the same commit as the change,
  and remove obsolete claims instead of keeping historical notes.
- A doc names settings and behaviour, not copied numeric defaults; the shipped
  `settings/defaults.json` is the source for the default and the declaration in
  `settings/service.gd` for the bounds.
- `docs/api.md` is the only cross-mod API contract. `README.md` is human-owned: do not edit it;
  report the needed change with exact replacement text.

## Commands

```bash
scripts/test.sh <suite>...   # touched suites; also --list, --all
scripts/test_all.sh          # every suite, once per task
scripts/check.sh             # fast parse check; --all before done
./lab.sh                     # manual lab; also lab-stress.sh, lab-vr.sh
```

Everything else — run from source, the labs, build, bisect and release — is in `WORKFLOW.md`.
