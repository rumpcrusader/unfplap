# unfplap documentation

This is the index for the mod's documentation. `ARCHITECTURE.md` owns the concepts and rules; each
service owns exactly one contract under `docs/`, and that contract is the single source of truth
for the service's responsibility and boundary, its decisions, invariants, ordering constraints,
traps and extension points.

`AGENTS.md` holds the project-wide agent rules and links here.

## Project docs

| Doc | Owns |
|---|---|
| `../ARCHITECTURE.md` | the service model, layers, lifecycle, dependency policy and enforcement |
| `../README.md` | the player-facing summary; human-owned, do not edit |
| `../AGENTS.md` | project-wide agent rules and the path router |
| `../WORKFLOW.md` | commands, the lab scripts and the release flow |
| `../assets/README.md` | the resource pack layout and the asset-change workflow |
| `../CREDITS.md` | external credits: anatomy and act audio |
| `api.md` | the stable cross-mod API |
| `prompts.md` | the shipped prompt document, its part/slot graph and the one renderer |
| `tests.md` | the suite layout, conventions and the runner |
| `quality.md` | the static gates: formatting policy, gdlint, complexity and shell-script rules |
| `vr.md` | the optional standing VR act handle: what it binds, what it leaves to the act |

## Orchestrators

`main.gd` and `runtime.gd` compose services; they are not services. `main.gd` owns two build roots:
`_build_process()`, the one process Node, and `_build_world()`, the one ordered World service list
that is the lifecycle order of every broadcast. `runtime.gd` is the per-pony Node host: it exists
for every non-player pony, idle and in an act, and owns lifetime, parenting, the two engine-frame
forwards, the reparent across a body swap and the world-close release. Its own `act/` modules own
the act state and values, the start recipe, the one teardown, the schedule, the view and the idle
block; its `_compose()` constructs and binds them once per pony and attaches the Pony services.

| Part | Entry | Contract | Tests |
|---|---|---|---|
| Entry | `main.gd` | `../ARCHITECTURE.md` | `tests/entry/` |
| Per-pony Node host and composition | `runtime.gd` | `docs/runtime.md` | `tests/`, `tests/act/`, `tests/test_runtime_teardown.gd` |
| Act session | `act/session.gd` | `docs/runtime.md` | `tests/act/test_session.gd` |
| Act ledgers | `act/start.gd`, `act/exit.gd` | `docs/runtime.md` | `tests/poses/test_start_setup.gd`, `tests/test_runtime_teardown.gd` |
| Act modules | `act/tick.gd`, `act/view.gd`, `act/idle.gd`, `act/input.gd`, `act/phases.gd`, `act/agreement.gd`, `act/consent.gd`, `act/impact.gd`, `act/swap.gd`, `act/setup.gd`, `act/settings.gd`, `act/host.gd`, `act/host_live.gd`, `act/context.gd` | `docs/runtime.md` | `tests/` |

## Services

| Service | Facade | Contract | Tests | Scope |
|---|---|---|---|---|
| World reads | `world/api.gd` | `docs/world.md` | `tests/world/` | `world` |
| Pony runtimes | `ponies/api.gd` | `docs/ponies.md` | `tests/ponies/` | `world` |
| Act frame | `act_owner/api.gd` | `docs/act_owner.md` | `tests/act_owner/` | `world` |
| Identity eligibility | `eligibility/api.gd` | `docs/eligibility.md` | `tests/eligibility/` | `world` |
| Act gate | `act_gate/api.gd` | `docs/act_gate.md` | `tests/act_gate/` | `world` |
| Estrus cycle | `estrus/api.gd` | `docs/estrus.md` | `tests/estrus/` | `world` |
| Scene gate and refusal | `scene_gate/api.gd` | `docs/scene_gate.md` | `tests/scene_gate/` | `pony` |
| Act scene hold | `scene_hold/api.gd` | `docs/scene_hold.md` | `tests/scene_hold/` | `pony` |
| Privacy | `privacy/api.gd` | `docs/privacy.md` | `tests/privacy/` | `world` |
| Act negotiation | `negotiation/api.gd` | `docs/negotiation.md` | `tests/negotiation/` | `world` |
| Conversation director | `director/api.gd` | `docs/director.md` | `tests/director/` | `world` |
| Model classifiers | `classifier/api.gd` | `docs/classifier.md` | `tests/classifier/` | `world` |
| Mod integrations | `integrations/api.gd` | `docs/integrations.md` | `tests/integrations/` | `world` |
| Bed rest and rejoin | `rest/api.gd` | `docs/rest.md` | `tests/rest/` | `pony` |
| Hands | `hands/api.gd` | `docs/hands.md` | `tests/hands/` | `pony` |
| Anatomy | `anatomy/api.gd` | `docs/anatomy.md` | `tests/anatomy/` | `world` |
| Body change | `body_change/api.gd` | `docs/body_change.md` | `tests/body_change/` | `world` |
| Idle act offer and start | `offer/api.gd` | `docs/offer.md` | `tests/offer/` | `world` |
| Proactive requests | `initiation/api.gd` | `docs/initiation.md` | `tests/initiation/` | `world` |
| Act memory | `memory/api.gd` | `docs/memory.md` | `tests/memory/` | `world` |
| Act dialogue and prompt notes | `dialogue/api.gd` | `docs/dialogue.md` | `tests/dialogue/` | `pony` |
| Readiness, strength, auto | `readiness/api.gd` | `docs/readiness.md` | `tests/readiness/` | `pony` |
| Poses and skeleton | `poses/api.gd` | `docs/poses.md` | `tests/poses/` | `pony` |
| Act camera and live view | `camera/api.gd` | `docs/camera.md` | `tests/act_camera/` | `pony` |
| Kiss | `kiss/api.gd` | `docs/kiss.md` | `tests/act_camera/`, `tests/face/`, `tests/hands/` | `pony` |
| Act summary | `summary/api.gd` | `docs/summary.md` | `tests/summary/` | `pony` |
| Afterglow | `afterglow/api.gd` | `docs/afterglow.md` | `tests/afterglow/` | `pony` |
| Face and mood | `face/api.gd` | `docs/face.md` | `tests/face/` | `pony` |
| Reactions | `reactions/api.gd` | `docs/reactions.md` | `tests/reactions/` | `pony` |
| Stool | `stool/api.gd` | `docs/stool.md` | `tests/stool/` | `world` |
| Audio and voice | `audio/api.gd` | `docs/audio.md` | `tests/act_audio/` | `world` |
| Outside-act smack | `stock_smack/api.gd` | `docs/stock_smack.md` | `tests/stock_smack/` | `world` |
| HUD | `hud/api.gd` | `docs/hud.md` | `tests/hud/` | `world` |
| Settings | `settings/api.gd` | `docs/settings.md` | `tests/test_settings.gd` | `process` |
| Mare registry | `registry/api.gd` | `docs/registry.md` | `tests/test_api.gd` | `process` |
| Input | `input/api.gd` | `docs/input.md` | `tests/test_input.gd` | `world` |
| Debug tooling | `debug/api.gd` | `docs/debug.md` | `tests/test_debug_wheel.gd`, `tests/test_settings.gd` | `process` |
| Debug actions executor | `debug_actions/api.gd` | `docs/debug_actions.md` | `tests/test_debug_pony.gd`, `tests/test_deep_stretch.gd`, `tests/test_face_sit_action.gd` | `world` |

The facade header declares the service scope; each contract owns the service's responsibility and
boundary. A facade is internal API; the only stable external surface is `docs/api.md`.

## Shared modules and public service modules

A service-directory file is listed here only when another service or an orchestrator may preload it
(the public list in `scripts/checks/graph.py`, or the runtime's own); a service-private module stays
with its service's contract.

| Module | Path | Contract | Tests |
|---|---|---|---|
| Act keys | `shared/act_keys.gd` | `docs/input.md` | `tests/test_input.gd` |
| Act report | `shared/act_report.gd` | `docs/api.md` | `tests/act/test_session.gd`, `tests/test_api.gd` |
| Act state | `shared/act_state.gd` | `docs/runtime.md` | `tests/hud/test_hud_lines.gd`, `tests/act_audio/test_audio.gd` |
| Typed act view | `shared/act_facts.gd` | `docs/act_facts.md` | `tests/act_facts/` |
| Settings change notification | `shared/settings_change.gd` | `docs/settings.md` | `tests/test_settings_change.gd` |
| Service base | `shared/service.gd` | `../ARCHITECTURE.md` | `tests/entry/` |
| Start handle | `shared/start_port.gd` | `docs/runtime.md` | `tests/offer/`, `tests/negotiation/` |
| Presentation handle | `shared/presentation_port.gd` | `docs/runtime.md` | `tests/stool/` |
| Preferences | `shared/preferences.gd` | `docs/preferences.md` | `tests/readiness/`, `tests/test_character_preferences.gd` |
| Character templates | `shared/character_preferences.gd` | `docs/preferences.md` | `tests/test_character_preferences.gd` |
| Prompt text | `shared/prompt_text.gd` | `docs/prompts.md` | `tests/test_prompts.gd` |
| Cycle | `shared/cycle.gd` | `docs/estrus.md` | `tests/test_cycle.gd` |
| Participation | `shared/participation.gd` | `docs/eligibility.md` | `tests/test_participation.gd` |
| Consent defaults | `shared/consent.gd` | `docs/eligibility.md` | `tests/eligibility/` |
| Pony id | `shared/pony_id.gd` | `docs/eligibility.md` | `tests/test_pony_id.gd` |
| History store | `shared/act_history.gd` | `docs/summary.md` | `tests/summary/` |
| Face data | `shared/act_face.gd` | `docs/face.md` | `tests/face/` |
| Relationship cue | `shared/relationship_cue.gd` | `docs/dialogue.md` | `tests/test_relationship_cue.gd` |
| Pose catalog | `shared/pose_catalog.gd` | `docs/poses.md` | `tests/poses/` |
| Pose options | `shared/pose_options.gd` | `docs/poses.md`, `docs/scene_gate.md` | `tests/pose_options/` |
| Pose placement | `shared/pose_placement.gd` | `docs/scene_gate.md` | `tests/pose_placement/` |
| Base clearance | `shared/clearance.gd` | `docs/act_gate.md` | `tests/clearance/` |
| Negotiation context | `shared/context.gd` | `docs/negotiation.md` | `tests/context/` |
| Privacy rules | `shared/privacy_rules.gd` | `docs/initiation.md` | `tests/privacy/` |
| Anatomy placement | `shared/anatomy_placement.gd` | `docs/anatomy.md` | `tests/anatomy/` |
| Body form | `shared/body_form.gd` | `docs/body_change.md` | `tests/body_change/` |
| Body change | `shared/body_change.gd` | `docs/body_change.md` | `tests/body_change/`, `tests/handover/` |
| Body binding | `shared/body_binding.gd` | `docs/body_change.md` | `tests/body_change/`, `tests/anatomy/` |
| Body change policy | `shared/body_change_policy.gd` | `docs/body_change.md` | `tests/body_change/`, `tests/integrations/` |
| Body profile | `shared/body_profile.gd` | `docs/anatomy.md`, `docs/camera.md`, `docs/body_change.md` | `tests/anatomy/`, `tests/act_camera/`, `tests/body_change/` |
| Mod integration catalog | `shared/integrations.gd` | `docs/integrations.md` | `tests/integrations/` |
| Lean/travel math | `shared/act_motion.gd` | `docs/camera.md` | `tests/act_camera/` |
| Palm scale | `shared/hands_scale.gd` | `docs/hands.md` | `tests/hands/` |
| Reach plan | `shared/hands_reach_plan.gd` | `docs/hands.md` | `tests/hands/` |
| Standing offer cone | `shared/rump_cone.gd` | `docs/scene_gate.md` | `tests/test_rump_cone.gd` |
| Smack cue table | `shared/smack_cues.gd` | `docs/audio.md`, `docs/stock_smack.md` | `tests/act_audio/`, `tests/stock_smack/` |
| Voice routing | `shared/voice_status.gd` | `docs/audio.md` | `tests/test_voice.gd`, `tests/act_audio/` |
| Bond record | `shared/bond_record.gd` | `docs/world.md` | `tests/world/`, `tests/test_debug_pony.gd` |
| VR touch bridge | `shared/touch_bridge.gd` | `docs/world.md` | `tests/test_vr_act.gd` |
| Dock fit | `shared/dock_fit.gd` | `docs/world.md` | `tests/anatomy/`, `tests/world/` |
| Body-change provider base | `body_change/source.gd` | `docs/body_change.md` | `tests/body_change/`, `tests/integrations/` |
| Per-pony integration adapter | `integrations/act.gd` | `docs/integrations.md` | `tests/integrations/` |
| World handles | `world/handles.gd` | `docs/world.md` | `tests/act/` |

Shared modules are not services. Pure modules have no scene, lifecycle or service dependency. A
shared store may read `settings`; a read model is refreshed by its owner. `shared/service.gd` is
the lifecycle base every world-list service extends, not a service. The layer rules are in
`../ARCHITECTURE.md`.

## Cross-mod API

| Facade | Contract | Tests |
|---|---|---|
| `api.gd` | `docs/api.md` | `tests/test_api.gd` |

## Doc template

Every service doc uses the same shape. A service may add a section named after its own
responsibility (for example `## Missionary`, `## Standing`, `## Admission`), and it may use
`## Ownership` in place of `## Scope`:

```markdown
# <Service>
## Scope
## Ownership
## Data ownership
## <behaviour sections>
## Settings
## Verification / lab
```

`## Data ownership` is the save-schema and single-writer map; `## Settings` names settings and
behaviour without copying defaults or bounds. Every other section is a behaviour section named
after its responsibility. The preload graph is the dependency record; do not mirror it in a table.
`## Host boundary` has a callback table where the service has a host.

Rules:

- the doc owns the service's responsibility and boundary, its decisions, invariants, ordering
  constraints, traps and extension points;
- it never enumerates what a script, a declaration or the index already carries: no API signature
  dumps, no dependency edges, no setting rows, no debug-action rosters, no test lists, no numeric
  defaults, no call counts;
- settings are named and described here, but defaults stay in `settings/settings.json` and bounds
  in the owning declaration;
- a doc names another system in at most one clause; anything more is a link;
- no historical notes; remove an obsolete claim instead of keeping it;
- a behaviour, setting, control or debug change updates the doc in the same commit as the code.

## Verification matrix

| Check | Command / suite |
|---|---|
| Architecture gate (graph, docs, source and test-file rules) | `scripts/check.sh --static` |
| Comment shape and rename-safety | `scripts/lint.sh` |
| Parse all scripts | `scripts/check.sh` |
| Touched suites | `scripts/test.sh <suite>...` |
| Full headless gate | `scripts/test.sh` |
| Source smoke | `scripts/test.sh --smoke` |
| Settings contract | `tests/test_settings.gd` |
| Manual lab | `./lab.sh`, `./lab-stress.sh`, `./lab-vr.sh` |

## Documentation gate

The static gate enforces this section:

- every doc under `docs/` is linked from this index;
- every service has a facade, a contract and exactly one index row whose contract and tests resolve;
- each contract has an ownership heading and names its facade;
- every facade's public type carries a `##` note; `api.gd`'s public surface carries one and every
  public `api.gd` function is named in `docs/api.md`;
- no service imports another service's private files or its `game.gd`, no module preloads a
  base-game module except a game-layer service's `game.gd`, and no module reaches another module's
  preload const.

The typed act view boundary is a review rule, not a gate check: `docs/act_facts.md` owns it.

The manual lab is the only check the gate cannot run: it needs a live world and a person at the
keyboard. Record its result in the phase notes instead of assuming it passed.
