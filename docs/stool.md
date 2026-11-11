# Footstool

The footstool system handles the one standing-act reach case: a mare whose bits are much higher
than Anon's cannot be reached from the ground, so he stands on a footstool. This file is the single
technical contract; other docs link here.

## Scope

This contract covers:

- the live reach-gap rule and its threshold;
- the base-game `goods:footstool` briefcase item;
- the standing act's static stool prop and the player-root lift;
- the item's return on every exit path;
- the world supply of findable footstools;
- the offer hint, debug actions, tests and limits.

It does not cover eligibility, act readiness, camera, pose, anatomy or inventory rules. Those stay
in `docs/eligibility.md`, `PREFERENCES.md`, `ROTATION.md`, `docs/anatomy.md` and the game's own
inventory contract.

## Architecture

| File | Role |
|---|---|
| `stool.gd` | facade: the only other systems preload or call; owns the supply child and the public helpers |
| `stool/measure.gd` | pure reach-gap and threshold arithmetic |
| `stool/item.gd` | pure `goods:footstool` case-slot, owned-count and free-slot checks |
| `stool/prop.gd` | scene adapter: builds and removes the static act stool |
| `stool/supply.gd` | scene adapter: finds loaded homes and spawns pickable footstool drops |
| `docs/stool.md` | this contract |
| `tests/stool/` | pure measurement/item tests and the facade API test |

The facade is the only non-test file outside `stool/` that may preload `stool/*`. `runtime.gd`
reads it from `main.stool`; `main.gd` creates it. `stool/measure.gd` and `stool/item.gd` stay pure:
no `Node`, tree, time, file or game-scene access.

## Internal API

`main.stool`:

```gdscript
setup(main), shutdown(), on_world(game), on_world_closed()
enabled(), threshold_m()
gap(her_opening_y, her_hoof_y, his_root_y, his_foot_y) -> float
required(gap_m) -> bool
case_slot(store) -> int
owned_count(store) -> int
free_slots(store) -> int
writable(store) -> bool
build_prop(host, at, yaw) -> Dictionary   # {"node": StaticBody3D, "height": float}
free_prop(prop)
```

`runtime.gd` supplies the scene values and composes the gate; it does not read a controller's
private state. The live opening comes from the per-pony anatomy controller, the part root from
`main.anatomy.player_root_now()`, and `main.anatomy.player_prepare()` builds the hidden part first.

## Rule

Only standing, desktop human Anon, with `features.standing_stool` on and the anatomy controller
online:

```text
her_above_hooves = opening.y - pony.global_position.y
his_above_feet   = part_root.y - player.global_position.y
floor_delta      = pony.global_position.y - player.global_position.y
gap              = her_above_hooves - his_above_feet + floor_delta
```

The floor term is zero when both stand on the same floor and makes a step between them explicit.
The expression equals the world vertical gap `opening.y - part_root.y`.

`required = gap > presentation.standing.stool_gap_m`, default `0.30 m`. The setting is debug and
unclamped. A missing anatomy controller, an unprepared player part, non-finite values, AnonPony or
a headset rig makes the rule inapplicable, not required. The gate is evaluated at the standing
offer/start and again on `start()`.

## Gate and hint

- The standing scene gate gets a `stool` row with reason `needs_stool` when the rule applies and
  no unheld `goods:footstool` is in the briefcase.
- `can_offer` uses the same row, so a tall mare does not proactively offer when Anon cannot reach.
- `main._refresh_offer()` shows **Make love** when the start is possible and **Needs a footstool**
  when the footstool is the only missing thing. The blocked note has no Y icon. A one-time toast
  points at houses.
- Pressing Y on the blocked note does not start an act.
- The normal start path takes the first usable case slot. A full or unwritable case blocks the
  start.

## Act flow

- The standing state is unchanged when the rule does not apply.
- When it applies, `runtime.start()` checks out one case unit with `store.take(slot)` and keeps the
  token and slot.
- `_begin_standing_placement()` computes Anon's normal spot, places the static stool under it and
  raises his player root to `floor + stool height`. `AnonBody` then plants the feet and hips on
  the raised floor, so the standing pose, camera and anatomy aim use the same body.
- The prop uses the base-game shop visual (`world/shop/shop_items.gd` → `goods:footstool` →
  `world/props/household/footstool.glb`) with a box collider matching its measured bounds. The
  measured height is about `0.39 m`; a plain box stool is the fallback.
- The act stays on the stool through `AFTERGLOW`. `_end_session()` is the one exit path that
  removes the prop, lowers the player to the saved floor and returns the exact unit to its case
  slot. `_exit_tree()` repeats the release as a last resort.
- If the item cannot be put back, the loan is left without a world transform; the game inventory
  restores it to the case on the next open. A save during the act restores the loan the same way;
  the act itself does not resume, so the player may drop from the stool height on load.

## Supply

- On world load, if `owned_count` is zero and the feature is on, the supply node spawns **3**
  pickable `goods:footstool` drops in random loaded house interiors within `80 m`.
- A home must be in the `house_interiors` group and have `place_id()` and `inside()`. Candidate
  spots start near the inside door and the room centre; a downward ray finds the real floor and a
  box query rejects furniture, walls and bodies.
- Drops use `inventory.spawn_owned_drop()`, so they persist as normal owned world items and can be
  picked up. The generated house footstools are static furniture and do not count.
- `owned_count` includes case units, held items, placed furniture and world drops, so one stool
  anywhere stops the supply. The shop remains a valid way to get one.
- The supply retries every `2 s` while no home is loaded, pauses with the tree and during an act,
  and logs once if no home is available or the briefcase is full.

## Settings and debug

- `features.standing_stool`, default on, label **Use footstool**.
- `presentation.standing.stool_gap_m`, debug, default `0.30`, unit cm, Standing › Motion.
- **Give footstool** adds one to the briefcase.
- **Show stool state** prints the aimed or nearest mare's opening, hoof and part heights, gap,
  threshold, required flag, case slot, owned count and free slots.

## Tests and limits

- `tests/stool/test_measure.gd`: level-ground, raised-floor, negative and threshold cases.
- `tests/stool/test_item.gd`: case slot, owned count, free slots, take/put and placed loans.
- `tests/stool/test_stool_api.gd`: the facade's setting read, threshold, gap and item id.
- `tests/stool/test_gate.gd`: the runtime's live opening/part threshold and case-slot gate.
- `tests/stool/test_prop.gd`: the base-game visual and standable box top.
- `tests/stool/test_placement.gd`: the player-root raise and floor release.
- `tests/test_source_hygiene.gd`: the stool purity and facade boundary, and this contract's
  presence.
- The lab covers the full act and supply: Canon and Same Height below the threshold, Celestia and
  Hoers against their live number, with and without a case stool, early end, forced stop and
  afterglow.
- The stool height is the asset's measured height. A gap larger than it is taken up by the existing
  anatomy hip aim; a second step or scaled stool is out of scope.
- Step-up is part of the act start and step-down is a cut at session end. There is no step
  animation.
- The generated furniture and the act prop are separate: only the briefcase item enables the act.
