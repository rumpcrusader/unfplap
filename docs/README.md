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
| `../AGENTS.md` | project-wide agent rules and the reading table |
| `../WORKFLOW.md` | commands, the lab scripts and the release flow |
| `../assets/README.md` | the resource pack layout and the asset-change workflow |
| `../AUDIO_CREDITS.md` | audio credits |
| `api.md` | the stable cross-mod API |

## Orchestrators

`main.gd` and `runtime.gd` compose services; they are not services.

| Part | Entry | Contract | Tests |
|---|---|---|---|
| Entry | `main.gd` | `../ARCHITECTURE.md` | `tests/` |
| Act runtime | `runtime.gd` | `docs/runtime.md` | `tests/` |

## Services

| Service | Facade | Contract | Tests |
|---|---|---|---|
| Eligibility and consent | `eligibility/service.gd` | `docs/eligibility.md` | `tests/eligibility/` |
| Scene gate and refusal | `scene_gate/service.gd` | `docs/scene_gate.md` | `tests/scene_gate/` |
| Act scene hold | `scene_hold/service.gd` | `docs/scene_hold.md` | `tests/scene_hold/` |
| Bed rest and rejoin | `rest/service.gd` | `docs/rest.md` | `tests/rest/` |
| Hands | `hands/service.gd` | `docs/hands.md` | `tests/hands/` |
| Anatomy | `anatomy/service.gd` | `docs/anatomy.md` | `tests/anatomy/` |
| VR act | `vr/service.gd` | `docs/vr.md` | `tests/test_vr_act.gd` |
| Proactive requests | `initiation/service.gd` | `docs/initiation.md` | `tests/initiation/` |
| Act memory | `memory/service.gd` | `docs/memory.md` | `tests/memory/` |
| Act lines and prompt notes | `lines/service.gd` | `docs/lines.md` | `tests/lines/` |
| Readiness, strength, auto | `readiness/service.gd` | `docs/readiness.md` | `tests/readiness/` |
| Poses and skeleton | `poses/service.gd` | `docs/poses.md` | `tests/poses/` |
| Act camera and shots | `camera/service.gd` | `docs/camera.md` | `tests/act_camera/` |
| Kiss | `kiss/service.gd` | `docs/kiss.md` | `tests/act_camera/`, `tests/face/`, `tests/hands/` |
| Act summary | `summary/service.gd` | `docs/summary.md` | `tests/summary/` |
| Afterglow | `afterglow/service.gd` | `docs/afterglow.md` | `tests/afterglow/` |
| Face and mood | `face/service.gd` | `docs/face.md` | `tests/face/` |
| Reactions | `reactions/service.gd` | `docs/reactions.md` | `tests/reactions/` |
| Stool | `stool/service.gd` | `docs/stool.md` | `tests/stool/` |
| Audio and voice | `audio/service.gd` | `docs/audio.md` | `tests/act_audio/` |
| HUD | `hud/service.gd` | `docs/hud.md` | `tests/hud/` |
| Settings | `settings/service.gd` | `docs/settings.md` | `tests/test_settings.gd` |
| Mare registry | `registry/service.gd` | `docs/registry.md` | `tests/test_api.gd` |
| Input | `input/service.gd` | `docs/input.md` | manual |
| Debug tooling | `debug/service.gd` | `docs/debug.md` | manual |

Scope and lifecycle are declared in each contract's `## Lifecycle`. A facade is internal API; the
only stable external surface is `docs/api.md`.

## Shared modules and read models

| Module | Path | Contract | Tests |
|---|---|---|---|
| Typed act view | `shared/act_facts.gd` | `docs/act_facts.md` | `tests/act_facts/` |
| Perf probes | `shared/perf.gd`, `shared/perf_idle.gd` | `docs/perf.md` | `tests/perf/` |
| Preferences | `shared/preferences.gd` | `docs/preferences.md` | `tests/readiness/`, `tests/test_character_preferences.gd` |
| Character templates | `shared/character_preferences.gd` | `docs/preferences.md` | `tests/test_character_preferences.gd` |
| Cycle | `shared/cycle.gd` | `docs/eligibility.md` | `tests/test_cycle.gd` |
| Participation | `shared/participation.gd` | `docs/eligibility.md` | `tests/test_participation.gd` |
| Consent defaults | `shared/consent.gd` | `docs/eligibility.md` | `tests/eligibility/` |
| History store | `shared/act_history.gd` | `docs/summary.md` | `tests/summary/` |
| Face data | `shared/act_face.gd` | `docs/face.md` | `tests/face/` |
| Relationship cue | `shared/relationship_cue.gd` | `docs/lines.md` | `tests/test_relationship_cue.gd` |
| Pose catalog | `shared/pose_catalog.gd` | `docs/poses.md` | `tests/test_catalog.gd` |
| Anatomy placement | `shared/anatomy_placement.gd` | `docs/anatomy.md` | `tests/anatomy/` |
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
| read model | act_view | `shared/act_facts.gd` | act state for presentation |
| host | runtime | `bind(SummaryHost)` | clock, idle state, scene callbacks |
| game | pony_director | `res://world/ai/...` | speak one line |
```

`### Used by` is optional; the checker derives the reverse graph and fails if a hand-written table
disagrees. `## Host boundary` has a callback table where the service has a host.

Rules:

- the doc is the single source of truth for the service;
- no other doc restates its API, state, settings, controls, tests or debug actions;
- settings are named and described here, but defaults and bounds stay in the owning declaration;
- tests are listed by path; do not copy pass counts;
- lab checks are described as steps, not as historical results;
- cross-system facts are links, not copies;
- no historical notes, no "used to be" sections;
- a behaviour, setting, control, debug action or test change updates the doc in the same commit.

## Verification matrix

| Check | Command / suite |
|---|---|
| Architecture gate | `scripts/architecture.py --check` |
| Parse all scripts | `scripts/check.sh --all` |
| Full headless gate | `scripts/test_all.sh` |
| Source smoke | `scripts/smoke.sh` |
| Source hygiene | `tests/test_source_hygiene.gd` |
| Settings contract | `tests/test_settings.gd` |
| Manual lab | `./lab.sh`, `./lab-stress.sh`, `./lab-vr.sh` |

## Documentation gate

`tests/test_source_hygiene.gd` and `scripts/architecture.py --check` enforce this section:

- every doc under `docs/` is linked from this index;
- every service has a facade, a contract and a test path;
- no root service contract remains, and no doc names a removed root path;
- no presentation module reaches into `runtime.gd` for state: the typed act view is the boundary;
- each contract has the headings and sections the template requires;
- every `Uses` edge matches the code, and no service imports another service's private files.

The manual lab is the only check the gate cannot run: it needs a live world and a person at the
keyboard. Record its result in the phase notes instead of assuming it passed.

## Related

- `../ARCHITECTURE.md` — the service model, layers, lifecycle and enforcement.
- `../AGENTS.md` — the required reading table and the cross-cutting rules.
- `../WORKFLOW.md` — the commands and the release flow.
