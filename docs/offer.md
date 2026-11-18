# Idle act offer

`offer/service.gd` (Node, world scope) owns the idle act offer: the one-second scan, the standing
gate behind it, the typed offer the act key would start, and the "Make love" hint beside the game's
prompt row. It never starts anything. Contract stub; the prose lands in the documentation commit.

## Scope

This contract covers:

- the idle scan cadence and the standing cone target;
- the standing gate's reuse window and its footstool block;
- the typed playable offer, the blocked variant and the `offer_target()` query;
- the hint unit in the game's prompt row, its HUD fallback and the blocked toasts;
- the live Agreement as the act key's own offer.

## Ownership

`offer/service.gd` owns the scan result, the standing gate verdict, the hint row and the blocked
toasts.

## Lifecycle

- Scope: world
- Constructed by: `main._ready()`
- Begin: `on_world()`
- End: `reset()`/world close
- Idempotent: yes

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | hud | `hud/service.gd` | the prompt row unit and the HUD fallback |
| service | negotiation | `negotiation/service.gd` | the live Agreement offer |
| service | poses | `poses/service.gd` | the warmed authored pose assets |
| service | settings | `settings/service.gd` | the act key's cap label |
| service | world | `world/service.gd` | player, camera, mares, headset and pause |
| shared | act_keys | `shared/act_keys.gd` | the act key's key cap label |
| shared | log | `shared/log.gd` | the offer lines and the idle offer chunks |
| shared | pose_catalog | `shared/pose_catalog.gd` | the two offerable pose ids |
| shared | pose_offer | `shared/pose_offer.gd` | the typed act offer |
| shared | pose_specs | `shared/pose_specs.gd` | the two offerable assets |
| shared | rump_cone | `shared/rump_cone.gd` | the standing offer zone |
| service | hud | `hud/service.gd` | act HUD card |
| service | negotiation | `negotiation/service.gd` | service dependency |
| service | poses | `poses/service.gd` | pose and skeleton |
| service | settings | `settings/service.gd` | settings declarations and live values |
| service | world | `world/service.gd` | live scene reads |
| shared | act_keys | `shared/act_keys.gd` | shared data |
| shared | log | `shared/log.gd` | log sink and perf entry |
| shared | pose_catalog | `shared/pose_catalog.gd` | pose ids and schema |
| shared | pose_offer | `shared/pose_offer.gd` | typed act offer |
| shared | pose_specs | `shared/pose_specs.gd` | pose capability table |
| shared | rump_cone | `shared/rump_cone.gd` | standing offer zone |

## Tests

- `tests/offer/test_offer.gd`: the scan cadence, the cone target choice, the standing gate's reuse
  window, the footstool block and its one toast, the hint row and the HUD fallback, the live
  Agreement offer and the offer cleared while an act is live.
