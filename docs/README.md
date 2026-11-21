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

## Orchestrators

`main.gd` and `runtime.gd` compose services; they are not services. `main.gd` holds the one ordered
service list, which is the lifecycle order of every broadcast. `runtime.gd` is the per-pony Node
host: it exists for every non-player pony, idle and in an act, and owns lifetime, parenting, the two
engine-frame forwards, the reparent across a body swap and the world-close release. Its own `act/`
modules own the act state and values, the start recipe, the one teardown, the schedule, the view and
the idle block; `act/build.gd` constructs and binds them once per pony.

| Part | Entry | Contract | Tests |
|---|---|---|---|
| Entry | `main.gd` | `../ARCHITECTURE.md` | `tests/entry/` |
| Per-pony Node host | `runtime.gd` | `docs/runtime.md` | `tests/` |
| Per-pony composition | `act/build.gd` | `docs/runtime.md` | `tests/act/`, `tests/test_runtime_teardown.gd` |
| Act session | `act/session.gd` | `docs/runtime.md` | `tests/act/test_session.gd` |
| Act ledgers | `act/start.gd`, `act/exit.gd` | `docs/runtime.md` | `tests/poses/test_start_setup.gd`, `tests/test_runtime_teardown.gd` |
| Act modules | `act/tick.gd`, `act/view.gd`, `act/idle.gd`, `act/input.gd`, `act/phases.gd`, `act/agreement.gd`, `act/consent.gd`, `act/impact.gd`, `act/swap.gd`, `act/setup.gd`, `act/settings.gd`, `act/host.gd`, `act/context.gd` | `docs/runtime.md` | `tests/` |

## Services

| Service | Facade | Contract | Tests |
|---|---|---|---|
| World reads | `world/service.gd`, `world/game.gd` | `docs/world.md` | `tests/world/` |
| Pony runtimes | `ponies/service.gd` | `docs/ponies.md` | `tests/ponies/` |
| Identity eligibility | `eligibility/service.gd` | `docs/eligibility.md` | `tests/eligibility/` |
| Act gate | `act_gate/service.gd` | `docs/act_gate.md` | `tests/act_gate/` |
| Estrus cycle | `estrus/service.gd` | `docs/estrus.md` | `tests/estrus/` |
| Scene gate and refusal | `scene_gate/service.gd` | `docs/scene_gate.md` | `tests/scene_gate/` |
| Act scene hold | `scene_hold/service.gd` | `docs/scene_hold.md` | `tests/scene_hold/` |
| Privacy | `privacy/service.gd` | `docs/privacy.md` | `tests/privacy/` |
| Act negotiation | `negotiation/service.gd` | `docs/negotiation.md` | `tests/negotiation/` |
| Mod integrations | `integrations/service.gd`, `integrations/pantyhose.gd` | `docs/integrations.md` | `tests/integrations/` |
| Bed rest and rejoin | `rest/service.gd` | `docs/rest.md` | `tests/rest/` |
| Hands | `hands/service.gd` | `docs/hands.md` | `tests/hands/` |
| Anatomy | `anatomy/api.gd` | `docs/anatomy.md` | `tests/anatomy/` |
| Body change | `body_change/service.gd` | `docs/body_change.md` | `tests/body_change/` |
| VR act | `vr/service.gd` | `docs/vr.md` | `tests/test_vr_act.gd` |
| Idle act offer and start | `offer/service.gd` | `docs/offer.md` | `tests/offer/` |
| Proactive requests | `initiation/service.gd` | `docs/initiation.md` | `tests/initiation/` |
| Act memory | `memory/service.gd` | `docs/memory.md` | `tests/memory/` |
| Act dialogue and prompt notes | `dialogue/service.gd` | `docs/dialogue.md` | `tests/dialogue/` |
| Readiness, strength, auto | `readiness/service.gd` | `docs/readiness.md` | `tests/readiness/` |
| Poses and skeleton | `poses/service.gd` | `docs/poses.md` | `tests/poses/` |
| Act camera and live view | `camera/service.gd`, `camera/view.gd` | `docs/camera.md` | `tests/act_camera/` |
| Kiss | `kiss/service.gd` | `docs/kiss.md` | `tests/act_camera/`, `tests/face/`, `tests/hands/` |
| Act summary | `summary/service.gd` | `docs/summary.md` | `tests/summary/` |
| Afterglow | `afterglow/service.gd` | `docs/afterglow.md` | `tests/afterglow/` |
| Face and mood | `face/service.gd` | `docs/face.md` | `tests/face/` |
| Reactions | `reactions/service.gd` | `docs/reactions.md` | `tests/reactions/` |
| Stool | `stool/service.gd` | `docs/stool.md` | `tests/stool/` |
| Audio and voice | `audio/service.gd`, `audio/stock_smack.gd` | `docs/audio.md` | `tests/act_audio/` |
| HUD | `hud/service.gd` | `docs/hud.md` | `tests/hud/` |
| Settings | `settings/service.gd` | `docs/settings.md` | `tests/test_settings.gd` |
| Mare registry | `registry/service.gd` | `docs/registry.md` | `tests/test_api.gd` |
| Input | `input/service.gd` | `docs/input.md` | `tests/test_input.gd` |
| Debug tooling | `debug/service.gd`, `debug/actions.gd` | `docs/debug.md` | `tests/test_debug_wheel.gd`, `tests/test_debug_pony.gd`, `tests/test_deep_stretch.gd` |

Scope and ownership are declared in each contract's `## Scope` or `## Ownership` heading. A facade
is internal API; the only stable external surface is `docs/api.md`.

## Shared modules and read models

| Module | Path | Contract | Tests |
|---|---|---|---|
| Act keys | `shared/act_keys.gd` | `docs/input.md` | `tests/test_input.gd` |
| Act state | `shared/act_state.gd` | `docs/runtime.md` | `tests/hud/test_hud_lines.gd`, `tests/act_audio/test_audio.gd` |
| Typed act view | `shared/act_facts.gd` | `docs/act_facts.md` | `tests/act_facts/` |
| Settings change notification | `shared/settings_change.gd` | `docs/settings.md` | `tests/test_settings_change.gd` |
| Service base | `shared/service.gd` | `../ARCHITECTURE.md` | `tests/entry/` |
| Start handle | `shared/start_port.gd` | `docs/runtime.md` | `tests/offer/`, `tests/negotiation/` |
| Presentation handle | `shared/presentation_port.gd` | `docs/runtime.md` | `tests/stool/` |
| Preferences | `shared/preferences.gd` | `docs/preferences.md` | `tests/readiness/`, `tests/test_character_preferences.gd` |
| Character templates | `shared/character_preferences.gd` | `docs/preferences.md` | `tests/test_character_preferences.gd` |
| Prompt text | `shared/prompt_text.gd` | `docs/prompts.md` | `tests/test_prompts.gd` |
| Cycle | `shared/cycle.gd` | `docs/eligibility.md` | `tests/test_cycle.gd` |
| Participation | `shared/participation.gd` | `docs/eligibility.md` | `tests/test_participation.gd` |
| Consent defaults | `shared/consent.gd` | `docs/eligibility.md` | `tests/eligibility/` |
| Pony id | `shared/pony_id.gd` | `docs/eligibility.md` | `tests/test_pony_id.gd` |
| History store | `shared/act_history.gd` | `docs/summary.md` | `tests/summary/` |
| Face data | `shared/act_face.gd` | `docs/face.md` | `tests/face/` |
| Relationship cue | `shared/relationship_cue.gd` | `docs/dialogue.md` | `tests/test_relationship_cue.gd` |
| Pose catalog | `shared/pose_catalog.gd` | `docs/poses.md` | `tests/poses/` |
| Pose options | `shared/pose_options.gd` | `docs/poses.md`, `docs/scene_gate.md` | `tests/pose_options/` |
| Pose placement | `shared/pose_placement.gd` | `docs/scene_gate.md` | `tests/pose_placement/` |
| Base clearance | `shared/clearance.gd` | `docs/eligibility.md` | `tests/clearance/` |
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
| Architecture gate (graph, docs, source and test-file rules) | `scripts/architecture.py --check` |
| Comment shape and rename-safety | `scripts/comments.py --check` |
| Parse all scripts | `scripts/check.sh --all` |
| Touched suites | `scripts/test.sh <suite>...` |
| Full headless gate | `scripts/test_all.sh` |
| Source smoke | `scripts/smoke.sh` |
| Settings contract | `tests/test_settings.gd` |
| Manual lab | `./lab.sh`, `./lab-stress.sh`, `./lab-vr.sh` |

## Documentation gate

`scripts/architecture.py --check` enforces this section:

- every doc under `docs/` is linked from this index;
- every service has a facade, a contract and exactly one index row whose contract and tests resolve;
- each contract has an ownership heading and names its facade;
- every facade's public type carries a `##` note; `api.gd`'s public surface carries one and every
  public `api.gd` function is named in `docs/api.md`;
- no service imports another service's private files, no module preloads a base-game module except
  `world/game.gd`, and no module reaches another module's preload const except `GAME`.

The typed act view boundary is a review rule, not a gate check: `docs/act_facts.md` owns it.

The manual lab is the only check the gate cannot run: it needs a live world and a person at the
keyboard. Record its result in the phase notes instead of assuming it passed.
