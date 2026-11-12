# unfplap documentation

This is the index for the mod's documentation. Each service owns exactly one doc here; that doc is
the single source of truth for the service's purpose, API, state, settings, controls, debug
actions, tests and lab check. `AGENTS.md` holds project-wide rules and links here.

## Project docs

| Doc | Owns |
|---|---|
| `../README.md` | the player-facing summary, CONTROLS and FEATURES |
| `../AGENTS.md` | project-wide agent rules, the reading table, the service index and the workflow |
| `../WORKFLOW.md` | commands, the lab scripts and the release flow |
| `../assets/README.md` | the resource pack layout and the asset-change workflow |
| `../AUDIO_CREDITS.md` | audio credits |
| `api.md` | the stable cross-mod API |

## Services

| Service | Facade | Contract | Tests |
|---|---|---|---|
| Eligibility and consent | `eligibility.gd` | `docs/eligibility.md` | `tests/eligibility/` |
| Scene gate and refusal | `scene_gate.gd` | `docs/scene_gate.md` | `tests/scene_gate/` |
| Act scene hold | `scene_hold.gd` | `docs/scene_hold.md` | `tests/scene_hold/` |
| Bed rest and rejoin | `rest_rejoin.gd` | `docs/rest.md` | `tests/rest/` |
| Hands | `hand_control.gd` | `docs/hands.md` | `tests/hands/` |
| Anatomy | `anatomy.gd` + `anatomy/act_bridge.gd` | `docs/anatomy.md` | `tests/anatomy/` |
| VR act | `vr_act.gd` | `docs/vr.md` | `tests/test_vr_act.gd` |
| Proactive requests | `initiation.gd` | `docs/initiation.md` | `tests/initiation/` |
| Act memory | `memory.gd` | `docs/memory.md` | `tests/memory/` |
| Act lines and prompt notes | `act_lines.gd` + `act_lines/prompts.gd` | `docs/lines.md` | `tests/act_lines/` |
| Readiness, strength, auto | `readiness.gd` | `docs/readiness.md` | `tests/readiness/` |
| Preferences | `preferences.gd`, `character_preferences.gd` | `docs/preferences.md` | `tests/readiness/`, `tests/test_character_preferences.gd` |
| Poses and skeleton | `poses/session.gd` | `docs/poses.md` | `tests/poses/` |
| Act camera and shots | `act_camera.gd` | `docs/camera.md` | `tests/act_camera/` |
| Kiss | `kiss_control.gd` | `docs/kiss.md` | `tests/act_camera/`, `tests/face/`, `tests/hands/` |
| History and tolerance | `history.gd` | `docs/history.md` | `tests/history/` |
| Afterglow | `afterglow.gd` | `docs/afterglow.md` | `tests/afterglow/` |
| Face and mood | `face_session.gd` | `docs/face.md` | `tests/face/` |
| Reactions | `act_reactions.gd` | `docs/reactions.md` | `tests/reactions/` |
| Stool | `stool.gd` + `stool/act.gd` | `docs/stool.md` | `tests/stool/` |
| Audio and voice | `act_audio.gd` + `act_sound.gd` | `docs/audio.md` | `tests/act_audio/` |
| HUD | `hud.gd` + `hud_lines.gd` | `docs/hud.md` | `tests/hud/` |
| Settings | `settings.gd` + `settings_ui.gd` | `docs/settings.md` | `tests/test_settings.gd` |
| Lover bond | `sex_bond.gd` | `docs/bond.md` | `tests/bond/` |
| Perf probe | `perf.gd` | `docs/perf.md` | `tests/perf/` |
| Typed act view | `act_facts.gd` | `docs/act_facts.md` | `tests/act_facts/` |
| Debug tooling | `debug_actions.gd`, `debug_skeleton.gd` | `docs/debug.md` | manual |
| Act runtime | `runtime.gd` | `docs/runtime.md` | `tests/` |

`act_summary.gd`, `act_history.gd` and `act_tolerance.gd` are internals of the history system and
are documented in `history.md`. `utterance.gd`, `utterance_scheduler.gd` and
`relationship_cue.gd` are internals of act lines and are documented in `lines.md`.
`auto_thrust.gd`, `auto_panel.gd` and `thrust.gd` are internals of readiness and are documented in
`readiness.md`. `missionary_anon.gd`, `standing_anon.gd`, `missionary_camera.gd` and
`standing_camera.gd` are shot/body implementations of the pose and camera systems and are
documented in `camera.md` and `poses.md`.

## Doc template

Every service doc uses the same shape. A service may add a section named after its own
responsibility (for example `## Missionary`, `## Standing`, `## Admission`), and it may use
`## Ownership` in place of `## Ownership and boundary`:

```
# <Service>
## Scope
## Ownership
## Internal API
## Data ownership
## Settings
## Controls and debug
## Dependencies
## Tests
## Verification / lab
## Related docs
```

Rules:

- the doc is the single source of truth for the service;
- no other doc restates its API, state, settings, controls, tests or debug actions;
- settings are named and described here, but defaults and bounds stay in `settings.gd`; do not copy
  numbers that can drift;
- tests are listed by path; do not copy pass counts;
- lab checks are described as steps, not as historical results;
- cross-system facts are links, not copies;
- no historical notes, no "used to be" sections;
- a behaviour, setting, control, debug action or test change updates the doc in the same commit.

## Verification matrix

| Check | Command / suite |
|---|---|
| Parse all scripts | `scripts/check.sh --all` |
| Full headless gate | `scripts/test_all.sh` |
| Source smoke | `scripts/smoke.sh` |
| Service boundaries and doc coverage | `tests/test_source_hygiene.gd` |
| Settings contract | `tests/test_settings.gd` |
| Manual lab | `./lab.sh`, `./lab-stress.sh`, `./lab-vr.sh` |

## Related

- `../AGENTS.md` — the required reading table and the cross-cutting rules.
- `../WORKFLOW.md` — the commands and the release flow.
