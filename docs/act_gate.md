# Act gate

The dynamic half of the act gate: the one service that answers "may this mare act right now". It
reads the identity answer from `eligibility`, then the live relationship, romance, willingness,
Promiscuity floor, player form, cycle, act history and per-mare consent. This file is the single
technical contract for the service; the scene rows are `docs/scene_gate.md` and the identity rules
are `docs/eligibility.md`.

The internal API is `act_gate/api.gd`. It stores nothing but its own attach-warm marks, and it
never writes the game, the settings or the history.

## Scope

This contract covers:

- the act-key readiness answer (`ready`) and the Base clearance relationship row;
- the typed verdict every negotiation stage reads;
- per-mare action consent, including the public preference;
- the heat/diestrus note the dialogue prompt appends;
- the fact readers behind those answers.

It does not cover identity, the provider assertion or participation (that is `eligibility`), the
live scene rows (that is `scene_gate`), readiness or tolerance (`docs/readiness.md`).

## Architecture

| File | Role |
|---|---|
| `act_gate/api.gd` | public API and the scene adapter: the typed verdict, the relationship row and consent |
| `act_gate/policy.gd` | pure truth table: facts dictionary plus mode -> verdict dictionary and the Promiscuity floor |
| `act_gate/facts.gd` | pure dynamic fact schema and merge |
| `docs/act_gate.md` | this contract |

The purity boundary is deliberate: `policy.gd` and `facts.gd` have no `Node`, `Time`, `SceneTree`,
`FileAccess`, `SETTINGS` preload or scene preload. The service composes their results from the live
game, the settings and the shared stores. It is a leaf reader of the world and of `eligibility`;
The static gate rejects an anatomy or estrus edge.

## Data ownership

The gate stores no verdict and no setting. Its only state is a set of per-body attach-warm marks,
cleared with the world. Every fact is read per call; the verdict is never cached.

| Data | Stored where | Owner |
|---|---|---|
| Relationship stage, love, willingness, romance, adults | game save (`player_bonds`, impressions) | base game |
| Promiscuity floor | `settings.json` -> `relationship.promiscuity` | `settings/api.gd` |
| Per-mare consent | `characters.json` -> `characters.<id>.consent` | `settings/api.gd` plus `shared/consent.gd` |
| Cycle phase | derived, never saved | `shared/cycle_state.gd` |
| Act history | `Mods.state("unfplap").act_history` | `shared/act_history.gd` |
| Gate facts and verdict | nowhere | `act_gate/api.gd` per call |

Rules:

- `act_gate/api.gd` never calls `SETTINGS.save_*`, `ACT_HISTORY.commit` or
  `Mods.save_changed`.
- `facts.consent` is a snapshot of the resolved consent block. `consent(pony, key)` re-resolves
  live through `SETTINGS.consent(id)`.
- `Facts` is a snapshot, not a cache. `Verdict` is rebuilt per call.

## Facade

`act_gate/api.gd` extends `shared/service.gd`, the world-service base. The entry creates one
instance per world after `eligibility`, calls `wire()`, and binds the gate into the World record,
`initiation`, `negotiation`, `scene_gate` and `debug`. The types are declared in the facade, so a
consumer names them `ACT_GATE.Verdict`, `ACT_GATE.Row`, and so on.

`ready(pony)` is the act key: the identity act target plus `relationship_ok`. `get_verdict()` is the
typed truth table; the mode is recorded and every field is always computed. `consent()` answers one
key of `shared/consent.gd` for a live pony. `cycle_note()` appends the heat or diestrus sentence
while the gate's base holds. `warm(pony)` reads the clearance row once per attached body so the
first offer does not pay the cold bond read. A cleared service answers no to every verb.

## Facts

`Facts` is a typed object on `Verdict.facts`:

```text
id, eligible, adult, participation,
has_relationship, registered_adult, romance_eligible, stage, love_level, willing,
promiscuity, player_young, player_pony,
cycle_phase, cycle_allows, heat, history, consent
```

`adult` is the identity answer from `eligibility` (`Target.CHARACTER`), never re-derived here.
`eligible` and `participation` are the resolved profile blocks for the stable id. `cycle_phase`
comes from `shared/cycle_state.gd`, so the estrus service and this gate agree: the debug override
first, then `features.estrus_cycle` and her relationship bond day. A pony with no relationship
runtime reads normal. `history` is resolved by `shared/act_history.gd`; `consent` by
`SETTINGS.consent(id)`. `registered_adult` follows the provider's tri-state assertion when one is
set, and otherwise the game's `bonds.adults` entry.

Not in facts: the preference profile, poses, prompts, timing values, prompt names, mood, first-time
state or request cooldowns.

## Verdict

```text
mode: Mode
base: bool
show: bool             # the policy's start hint
offer: bool            # proactive offer allowed
offer_weight: float
facts: Facts
actions: Actions       # public, anal, oral
relations: Relations   # id, stage, love_level, willing,
                       # promiscuity, cycle_phase, heat, base
rows: Array[Row]       # key, ok, reason, effect
```

`reasons()` returns the failed rows' reasons; `rows_text()` renders the rows. `Row.effect` is the
`Effect` enum, not a string. The live hotkey reads only `ready()`; `show`, `offer` and
`offer_weight` are the pure policy's hint and offer reads behind the debug line and the truth
table.

## Base clearance

`relationship_ok(pony)` is the Base clearance relationship row: a live relationship runtime,
romance eligibility and the Promiscuity floor. It reads only the relationship runtime, romance
eligibility, the love level and the floor; it never reads willingness, history, cycle, player form
or consent. That narrow read is why the idle hint and the proactive scan do not rebuild her bond
facts every pass.

The love level comes from the game's own ladder cache (`world_context.state.bond_levels`, kept
current by `relationship_runtime._level_check()` on every impression and bond change), with
`relationship_runtime.ladder()` as the fallback for a pony the game has not recorded yet. It cannot
see a player-form change, which empties the game's love row without a signal; romance eligibility is
read live and gates the row first, so a young player still fails clearance.

`shared/clearance.gd` combines `eligible`, `relationship_ok` and `available` into the typed
`Result` with the failed rows in order. The gate never inspects the clearance result.

## Modes and truth table

`base` = adult identity + relationship runtime + registered adult + adult player + romance eligible
+ Promiscuity level pass.

| Condition | `show` | `offer` |
|---|---|---|
| not `base` | no | no |
| `participation.acts` false | no | no |
| `!willing` | no | no |
| `willing`, history withdrawn/stop | yes | no |
| `willing`, history hurt (tier 2) | yes | no |
| diestrus | no | no |

Rules:

- The live routes do not consume `show`, `offer` or `offer_weight`. Base clearance uses `ready()`
  and `relationship_ok()`; Context carries the soft facts.
- `participation.acts` is a block, not a refusal: a player who opts out of acts never gets a buck,
  a history refusal or a mood note. It is a boundary, not a mood beat.

Rows and effects:

| Effect | Meaning |
|---|---|
| `block` | the policy gate refuses a start and an offer; the hotkey hint is scene-only |
| `refuse` | the pure policy's `relation` row fails; no live route bucks |
| `history_refuse` | the pure policy's `history` row fails; no live route speaks a refusal |
| `offer_block` | the policy offer is blocked by history or an active stop |
| `flag` | public/privacy flag; never a failure |

Reason keys: `adult`, `relationship`, `form`, `romance`, `promiscuity`, `participation`, `relation`,
`cycle`, `history`, `history_offers`, `public`.

## Promiscuity

The selected `relationship.promiscuity` is the lowest love level that can start an act. The ladder
is:

```text
Soulmates 4, Head Over Hooves 3, Marefriend/Coltfriend 2, New Couple 1, Crush 0, Any Adult -1
```

An unknown value falls back to Marefriend. `Any Adult` skips only this floor; adulthood, the
relationship runtime and romance eligibility still apply.

## Kiss willingness and history

`bonds.welcomes(id, "kiss")` is the base-game authority; the gate does not reimplement it. The
`relation` row is the willingness row of the pure policy table; it also feeds `show`. There is no
buck or history refusal on a live route: the live act key accepts, and the tolerance strict stop
owns the physical stop and its impression (`docs/readiness.md`, `docs/summary.md`).

`shared/act_history.gd` owns the point math and tiers (`docs/summary.md`). The gate consumes
`blocks_start` (withdrawn tier or an active `stop_until`), `blocks_offers` (hurt tier or higher, or
an active `stop_until`) and `offer_weight` (the history Context weight for Mare Initiation
Reasoning). On every route these are Context, not live gates; the tolerance `stop_until` is the
only hard pre-start gate.

## Per-mare action consent

`settings.consent(id)` resolves deterministic per-id defaults from `shared/consent.gd`, a provider
layer's `consent` block and the player's differences. `consent(pony, key)` reads one resolved key
and never writes it. `public`, `anal` and `oral` are independent:

- **Public** is a soft Context preference for reasoning on the negotiation routes. It is not an
  offer privacy override and never gates an act.
- **Anal** gates `V`; **oral** gates `N`.
- Feature flags (`features.anatomy_holes`, `features.anatomy_oral`) are capability gates, not
  consent.

## Cycle note

`cycle_note(pony)` returns the heat or diestrus sentence for the normal dialogue prompt, during and
outside acts, and is empty while the gate's base would stay shut. The phase itself is the shared
`shared/cycle_state.gd` derivation the estrus service also uses. The debug actions
**Force/Clear heat** and **Force/Clear diestrus** feed the override; none of them bypasses the gate.

## Debug

`runtime.scene.debug_line()` prints the live context, `show`, `offer`, the scene rows, `can_start`
and the reasons; it reads this gate's verdict and does not re-derive it.
`Verdict.rows_text()` returns the same policy view without scene rows. The Debug actions
**Trigger bed offer** and **Trigger standing offer** use the same service.

## Settings

The gate reads the settings live through its owners and declares none of its own:

- `relationship.promiscuity` for the love floor;
- `features.estrus_cycle` for the cycle derivation;
- `features.anatomy_holes` / `features.anatomy_oral` for the anatomy action gates, which the
  anatomy handle reads.

Consent is per mare, not a global setting.
