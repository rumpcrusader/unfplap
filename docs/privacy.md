# Privacy

The one live privacy provider. It exposes the existing offer and cuddle privacy rules to the
proactive, negotiation and act stages; it does not invent a new rule. Contract owner of the
`offer_private`/`cuddle_private` result for a target.

## Scope

This contract covers:

- the live privacy state for a target: the house, other mares, Anon, the radius and the target
  exclusion;
- the offer predicate (bed and standing) and the cuddle predicate;
- the debug report;
- the world house lookup the bed scan shares.

It does not cover an offer decision, a pose, a scene row or an act start. Visibility is derived
by the consumer from this state; there is no public override, no third-pony answer rule and no
negotiation face here.

## Ownership

`privacy/service.gd` (RefCounted) owns the scene reads for privacy:

- Anon from `WORLD.player`;
- the mares from `WORLD.game.mares`;
- the house from `res://world/buildings/house_interior.gd` (`HOUSE.at`) and
  `privacy.RADIUS_M` (30 m);
- the target exclusion: the offered mare never counts as another mare.

The rule itself is `shared/privacy_rules.gd`:

```text
offer_private  = house_alone or not others_near
cuddle_private = house_alone if indoors else not others_near
```

"House alone" excludes the target and counts every other mare in the same house. `others_near`
counts every other mare within the radius. `State` carries the facts and the two resolved
predicates; `private_for(cuddle)` picks the predicate for the offer kind.

## Internal API

`main.privacy`:

```gdscript
class State:  player, house, indoors, house_alone, others_near, offer_private, cuddle_private,
              in_house, nearby
              private_for(cuddle: bool) -> bool

setup(main_node: Node) -> void
reset() -> void
state_for(target: Node) -> State
private_for(target: Node, cuddle := false) -> bool
offer_private(target: Node) -> bool
cuddle_private(target: Node) -> bool
report(target: Node) -> String
house_at(at: Vector3) -> Node3D
```

`offer_private()` is the bed/standing offer rule; `cuddle_private()` is the stricter cuddle rule.
Both exclude the target. A missing main fails closed to not-private.

## Data ownership

The provider stores no data. Everything is sampled from the live scene per call. `State` is a
fresh value; a caller reads it immediately and never stores it.

## Lifecycle

- Scope: world
- Constructed by: `main._ready()`
- Begin: `setup()`
- End: `reset()`/world close
- Idempotent: yes

## Settings

No setting changes privacy. `features.act_public_offer` and `consent.public` no longer override
the reserve; the retired setting is removed from the declaration in the settings retirement
phase.

## Controls and debug

- The proactive service logs `request privacy <report>` at most once per second while an episode
  lives.
- The report names Anon's position, the house and its position, the mares in the house, the mares
  within the radius, the target id, and both resolved predicates.
- No privacy hotkey.

## Host boundary

`setup(main_node)` stores the entry node. The provider calls only plain values:
`WORLD.player` and `WORLD.game`. It never calls a service or a runtime.

## Dependencies

### Uses
| service | world | `world/service.gd` | player and mares |

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| shared | pony_id | `shared/pony_id.gd` | target label |
| shared | privacy_rules | `shared/privacy_rules.gd` | offer and cuddle formulas |

## Tests

- `tests/privacy/test_privacy.gd`: the house/outdoors states, target exclusion, the 30 m radius
  boundary, the offer vs. cuddle difference, the pure formulas and the unbound provider.

## Related docs

- `docs/initiation.md` — the proactive offer's use of the provider.
- `docs/eligibility.md` — public consent and heat as Context, not visibility.
- `docs/scene_gate.md` — the live scene rows the act start evaluates.
