# Act gate

The dynamic half of the act gate: the one service that answers "may this mare act right now". It
reads the identity answer from `eligibility`, then the live relationship, romance, willingness,
Promiscuity floor, player form, cycle, act history and per-mare consent. This file is the single
technical contract for the service; the scene rows are `docs/scene_gate.md` and the identity rules
are `docs/eligibility.md`.

The internal API is `act_gate/service.gd`. It stores nothing but its own attach-warm marks, and it
never writes the game, the settings or the history.

## Scope

This contract covers:

- the act-key readiness answer (`ready`) and the Base clearance relationship row;
- the typed verdict every negotiation stage reads;
- per-mare action consent, including the public preference;
- the heat/diestrus note the dialogue prompt appends;
- the fact readers behind those answers.

It does not cover identity and participation (that is `eligibility`), the live scene rows (that is
`scene_gate`), readiness or tolerance (`docs/readiness.md`).

## Public API

```gdscript
enum Mode { START, OFFER }
enum Effect { NONE, BLOCK, REFUSE, HISTORY_REFUSE, OFFER_BLOCK, FLAG }

class History: tier, hurt, comfort, blocks_start, blocks_offers, offer_weight
class Facts: id, eligible, adult, participation, has_relationship, ... (see `## Facts`)
class Actions: public, anal, oral
class Relations: id, stage, love_level, willing, promiscuity, cycle_phase, heat, base
class Row: key, ok, reason, effect
class Verdict: mode, base, show, offer, offer_weight, facts, actions, relations, rows
               reasons() -> PackedStringArray
               rows_text() -> String

func bind_eligibility(service) -> void
func ready(pony: Node) -> bool
func get_verdict(pony: Node, mode: Mode = Mode.START) -> Verdict
func relationship_ok(pony: Node) -> bool
func consent(pony: Node, key: String) -> bool
func cycle_note(pony: Node) -> String
func warm(pony: Node) -> void
```

`ready(pony)` is the act key: the identity act target plus `relationship_ok`. `get_verdict()` is the
typed truth table; the mode is recorded and every field is always computed. `consent()` answers one
key of `shared/consent.gd` for a live pony. `cycle_note()` appends the heat or diestrus sentence
while the gate's base holds. `warm(pony)` reads the clearance row once per attached body so the
first offer does not pay the cold bond read.

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
comes from `shared/cycle_state.gd`, so the estrus service and this gate agree. `history` is
resolved by `shared/act_history.gd`; `consent` by `SETTINGS.consent(id)`.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | eligibility | `eligibility/service.gd` | adult and consent gate |
| service | settings | `settings/service.gd` | settings declarations and live values |
| service | world | `world/game.gd` | service dependency |
| service | world | `world/service.gd` | live scene reads |
| shared | clearance | `shared/clearance.gd` | shared data |
| shared | consent | `shared/consent.gd` | consent defaults |
| shared | cycle | `shared/cycle.gd` | estrus cycle |
| shared | cycle_state | `shared/cycle_state.gd` | shared data |
| shared | participation | `shared/participation.gd` | participation defaults |
| shared | pony_id | `shared/pony_id.gd` | shared data |
| store | act_history | `shared/act_history.gd` | stored history rows |

## Lifecycle

- Scope: world
- Constructed by: the entry's service list
- Begin: `on_world(host)`
- End: `on_world_closed()` on a world enter or close, and `shutdown()` on process exit
- Idempotent: yes

## Tests

- `tests/act_gate/test_act_gate.gd`: the pure truth table, the readiness row, the typed verdict, the
  consent keys, the cycle note and the attach warm.
