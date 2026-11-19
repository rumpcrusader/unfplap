# unfplap documentation

This is the index for the mod's documentation. `ARCHITECTURE.md` owns the concepts and rules; each
service owns exactly one contract under `docs/`, and that contract is the single source of truth
for the service's purpose, API, state, settings, controls, debug actions, dependencies and tests.

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
| `tests.md` | the suite layout, conventions and the runner |
| `quality.md` | the static gates: formatting policy, gdlint, complexity and shell-script rules |

## Orchestrators

`main.gd` and `runtime.gd` compose services; they are not services. `main.gd` holds the one ordered
service list, which is the lifecycle order of every broadcast. `runtime.gd` is the per-pony host:
it exists for every non-player pony, idle and in an act, and owns lifetime, the ordered ticks, the
composition, the start and exit entries and the one view call; its own `act/` modules own the
state and the act values, the start recipe, the one teardown, the view and the idle schedule.

| Part | Entry | Contract | Tests |
|---|---|---|---|
| Entry | `main.gd` | `../ARCHITECTURE.md` | `tests/entry/` |
| Per-pony act host | `runtime.gd` | `docs/runtime.md` | `tests/` |
| Per-pony act modules | `act/build.gd`, `act/session.gd`, `act/settings.gd`, `act/start.gd`, `act/setup.gd`, `act/agreement.gd`, `act/gate.gd`, `act/exit.gd`, `act/host.gd`, `act/context.gd`, `act/view.gd`, `act/idle.gd`, `act/input.gd`, `act/swap.gd`, `act/phases.gd`, `act/tick.gd`, `act/consent.gd`, `act/impact.gd` | `docs/runtime.md` | `tests/` |

## Services

| Service | Facade | Contract | Tests |
|---|---|---|---|
| World reads | `world/service.gd` | `docs/world.md` | `tests/world/` |
| Pony runtimes | `ponies/service.gd` | `docs/ponies.md` | `tests/ponies/` |
| Eligibility and consent | `eligibility/service.gd` | `docs/eligibility.md` | `tests/eligibility/` |
| Scene gate and refusal | `scene_gate/service.gd` | `docs/scene_gate.md` | `tests/scene_gate/` |
| Act scene hold | `scene_hold/service.gd` | `docs/scene_hold.md` | `tests/scene_hold/` |
| Privacy | `privacy/service.gd` | `docs/privacy.md` | `tests/privacy/` |
| Act negotiation | `negotiation/service.gd` | `docs/negotiation.md` | `tests/negotiation/` |
| Mod integrations | `integrations/service.gd`, `integrations/pantyhose.gd` | `docs/integrations.md` | `tests/integrations/` |
| Bed rest and rejoin | `rest/service.gd` | `docs/rest.md` | `tests/rest/` |
| Hands | `hands/service.gd` | `docs/hands.md` | `tests/hands/` |
| Anatomy | `anatomy/service.gd` | `docs/anatomy.md` | `tests/anatomy/` |
| Body change | `body_change/service.gd` | `docs/body_change.md` | `tests/body_change/` |
| VR act | `vr/service.gd` | `docs/vr.md` | `tests/test_vr_act.gd` |
| Idle act offer and start | `offer/service.gd` | `docs/offer.md` | `tests/offer/` |
| Proactive requests | `initiation/service.gd` | `docs/initiation.md` | `tests/initiation/` |
| Act memory | `memory/service.gd` | `docs/memory.md` | `tests/memory/` |
| Act dialogue and prompt notes | `dialogue/service.gd` | `docs/dialogue.md` | `tests/dialogue/` |
| Readiness, strength, auto | `readiness/service.gd` | `docs/readiness.md` | `tests/readiness/` |
| Poses and skeleton | `poses/service.gd` | `docs/poses.md` | `tests/poses/` |
| Act camera and shots | `camera/service.gd` | `docs/camera.md` | `tests/act_camera/` |
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

Scope and lifecycle are declared in each contract's `## Lifecycle`. A facade is internal API; the
only stable external surface is `docs/api.md`.

## Shared modules and read models

| Module | Path | Contract | Tests |
|---|---|---|---|
| Act keys | `shared/act_keys.gd` | `docs/input.md` | `tests/test_input.gd` |
| Act state | `shared/act_state.gd` | `docs/runtime.md` | `tests/hud/test_hud_lines.gd`, `tests/act_audio/test_audio.gd` |
| Typed act view | `shared/act_facts.gd` | `docs/act_facts.md` | `tests/act_facts/` |
| Log and perf entry | `shared/log.gd` | `docs/log.md` | `tests/perf/` |
| Settings change notification | `shared/settings_change.gd` | `docs/settings.md` | `tests/test_settings_change.gd` |
| Perf probes | `shared/perf.gd`, `shared/perf_idle.gd`, `shared/perf_tree.gd` | `docs/perf.md` | `tests/perf/` |
| Preferences | `shared/preferences.gd` | `docs/preferences.md` | `tests/readiness/`, `tests/test_character_preferences.gd` |
| Character templates | `shared/character_preferences.gd` | `docs/preferences.md` | `tests/test_character_preferences.gd` |
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
shared store may read `settings`; a read model is refreshed by its owner. The layer rules are in
`../ARCHITECTURE.md`.

## Cross-mod API

| Facade | Contract | Tests |
|---|---|---|
| `api.gd` | `docs/api.md` | `tests/test_api.gd` |

## Doc template

Every service doc uses the same shape. A service may add a section named after its own
responsibility (for example `## Missionary`, `## Standing`, `## Admission`), and it may use
`## Ownership` in place of `## Ownership and boundary`:

```markdown
# <Service>
## Scope
## Ownership
## Internal API
## Data ownership
## Lifecycle
## Settings
## Controls and debug
## Host boundary
## Dependencies
## Tests
## Verification / lab
## Related docs
```

`## Lifecycle` declares the scope and ownership:

```markdown
## Lifecycle

- Scope: world | per-pony | per-act | pure
- Constructed by: ...
- Begin: ...
- End: ...
- Idempotent: yes/no
```

`## Dependencies` has a normative `### Uses` table and an optional `### Used by` table. The
checker parses `Uses` and compares it with the preload graph. `Kind` is one of `service`, `shared`,
`store`, `read model`, `host`, `game`.

```markdown
## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | memory | `memory/service.gd` | cue facts and witness pass |
| shared | preferences | `shared/preferences.gd` | tolerance tier |
| store | act_history | `shared/act_history.gd` | stored history rows |
| read model | act_facts | `runtime.act.facts()` | act state for presentation |
| host | runtime | `bind(SummaryHost)` | clock, idle state, scene callbacks |
| game | pony_director | `res://world/ai/...` | speak one line |
```

`### Used by` is optional; the checker derives the reverse graph and fails if a hand-written table
disagrees. `## Host boundary` has a callback table where the service has a host.

Rules:

- the doc is the single source of truth for the service;
- no other doc restates its API, state, settings, controls, tests or debug actions;
- settings are named and described here, but defaults stay in `settings/defaults.json` and bounds
  in the owning declaration;
- tests are listed by path; do not copy pass counts;
- lab checks are described as steps, not as historical results;
- cross-system facts are links, not copies;
- no historical notes, no "used to be" sections;
- a behaviour, setting, control, debug action or test change updates the doc in the separate
  `docs:` commit after the code commit.

## Verification matrix

| Check | Command / suite |
|---|---|
| Architecture gate (graph, docs, source and test-file rules) | `scripts/architecture.py --check` |
| Parse all scripts | `scripts/check.sh --all` |
| Touched suites | `scripts/test.sh <suite>...` |
| Full headless gate | `scripts/test_all.sh` |
| Source smoke | `scripts/smoke.sh` |
| Settings contract | `tests/test_settings.gd` |
| Manual lab | `./lab.sh`, `./lab-stress.sh`, `./lab-vr.sh` |

## Documentation gate

`scripts/architecture.py --check` enforces this section:

- every doc under `docs/` is linked from this index;
- every service has a facade, a contract and a test path;
- each contract has the headings and sections the template requires;
- every `Uses` edge matches the code, and no service imports another service's private files.

The typed act view boundary is a review rule, not a gate check: `docs/act_facts.md` owns it.

The manual lab is the only check the gate cannot run: it needs a live world and a person at the
keyboard. Record its result in the phase notes instead of assuming it passed.

## Related

- `../ARCHITECTURE.md` — the service model, layers, lifecycle and enforcement.
- `../AGENTS.md` — the path router and the cross-cutting rules.
- `../WORKFLOW.md` — the commands and the release flow.
