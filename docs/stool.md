# Footstool

The footstool system handles the standing-act reach case: a mare whose bits are much higher than
Anon's cannot be reached from the ground, so he stands on one or more stacked footstools. This file
is the single technical contract; other docs link here.

## Scope

This contract covers:

- the live reach-gap rule, its threshold and the stack count;
- the base-game `goods:footstool` briefcase item;
- the standing act's static stool stack, its visual scale and the player-root lift;
- the item return on every exit path;
- the world supply of findable footstools;
- the offer hint, debug actions, tests and limits.

It does not cover eligibility, act readiness, camera, pose, anatomy or inventory rules. Those stay
in `docs/eligibility.md`, `docs/readiness.md`, `docs/poses.md`, `docs/camera.md`,
`docs/anatomy.md` and the game's own inventory contract.

## Architecture

| File | Role |
|---|---|
| `stool.gd` | facade: the only other systems preload or call; owns the supply child, `new_act()` and the stateless helpers |
| `stool/act.gd` | per-act handle: the live rule, case loans, placed stack and player lift; the runtime owns one per act |
| `stool/measure.gd` | pure reach-gap, threshold and stack-count arithmetic |
| `stool/item.gd` | pure `goods:footstool` case-slot, case-count, owned-count and free-slot checks |
| `stool/prop.gd` | scene adapter: builds the stacked static act stool and its pony collision exception |
| `stool/supply.gd` | scene adapter: finds loaded homes and spawns pickable footstool drops |
| `docs/stool.md` | this contract |
| `tests/stool/` | pure measurement/item tests, prop/stack tests and the facade API test |

The facade is the only non-test file outside `stool/` that may preload `stool/*`. `runtime.gd`
reads it from `main.stool`; `main.gd` creates it. `stool/measure.gd` and `stool/item.gd` stay pure:
no `Node`, tree, time, file or game-scene access.

## Internal API

`main.stool`:

```gdscript
setup(main), shutdown(), on_world(game), on_world_closed()
enabled(), threshold_m(), height_m()
gap(her_opening_y, her_hoof_y, his_root_y, his_foot_y) -> float
required(gap_m) -> bool
needed_count(gap_m) -> int
case_slot(store) -> int
case_count(store) -> int
owned_count(store) -> int
free_slots(store) -> int
writable(store) -> bool
build_prop(host, at, yaw, count, step_height, ignore) -> Dictionary
free_prop(prop)
new_act() -> RefCounted
floor_y_at(at, body) -> float
```

`new_act()` creates one per-act handle; the runtime keeps it for the act and drops it with the
runtime. `floor_y_at()` is the stateless standing-spot floor probe, with the player capsule
excluded.

The handle's internal API:

```gdscript
bind(facade, main, pony, player, anatomy_ctl)
applies() -> bool
gap_m() -> float
needed_count() -> int
required() -> bool
case_slot() -> int
case_count() -> int
blocks_start(reasons) -> bool
state_text() -> String
take_items(need) -> bool
place(target, yaw, floor) -> Vector3
release()
reset()
floor_y_at(at, body) -> float
```

`place()` builds the stack under the runtime's standing spot and returns the raised player
target; `release()` frees the prop, lowers the player and returns every case unit.

`build_prop()` returns `{"node": StaticBody3D, "height": float, "count": int, "step": float}`.
`ignore` is the partner pony; the stack must not collide with her.

`runtime.gd` supplies the scene values, calls the handle and composes the gate; it does not read
a controller's private state. The live opening comes from the per-pony anatomy controller, the
part root from `main.anatomy.player_root_now()`, and `main.anatomy.player_prepare()` builds the
hidden part first. The handle reads `main.stool` for the settings/item/measure calls and
`main.anatomy` for the player part.

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

With `T = presentation.standing.stool_gap_m` (default `0.20 m`) and
`S = presentation.standing.stool_height_m` (default `0.20 m`):

```text
if gap <= T:
    needed = 0
else:
    needed = max(1, floor((gap - T) / S) + 1)
```

The first stool is required once the gap passes the threshold. Each stool then covers one step.
With the defaults, 25 cm uses one stool, 40 cm uses two and 60 cm uses three. The remainder after
the last stool is below the threshold, which the existing anatomy hip aim absorbs.

A missing anatomy controller, an unprepared player part, non-finite values, AnonPony or a headset
rig makes the rule inapplicable, not required. The gate is evaluated at the standing offer/start
and again on `start()`.

## Gate and hint

- The standing scene gate gets a `stool` row with reason `needs_stool` when the rule needs more
  case footstools than Anon has.
- `can_offer` uses the same row, so a tall mare does not proactively offer when Anon cannot reach.
- `main._refresh_offer()` shows **Make love** when the start is possible and **Needs a footstool**
  or **Needs N footstools** when the stack is the only missing thing. The blocked note has no Y
  icon. A one-time toast points at houses.
- Pressing Y on the blocked note does not start an act.
- The normal start path takes exactly the required number of case units. A short or unwritable
  case blocks the start.

## Act flow

- The standing state is unchanged when the rule does not apply.
- When it applies, `runtime.start()` asks the handle to check out `needed` case units
  (`take_items()` → `store.take(slot)`); the handle keeps every token and slot.
- `_begin_standing_placement()` computes Anon's normal spot and calls `place()`; the handle builds
  a stack of `needed` stools under it and raises his player root to
  `floor + needed * step_height`. `AnonBody` then plants the feet and hips on the raised floor, so
  the standing pose, camera and anatomy aim use the same body.
- Each stool uses the base-game shop visual (`world/shop/shop_items.gd` → `goods:footstool` →
  `world/props/household/footstool.glb`). The visual is scaled uniformly to the configured step
  height; the collider keeps a minimum `0.46 × 0.40 m` top so Anon's feet are supported. A plain
  box stack is the fallback.
- The stack is one static body with one box collider from the floor to the top. The partner pony
  is added to the body's collision exceptions in both directions, so the stack supports Anon
  without lifting or tilting her; the exceptions are removed with the prop. The player still
  collides with it.
- The act stays on the stack through `AFTERGLOW`. `_end_session()` is the one exit path that
  removes the prop, lowers the player to the saved floor and returns every unit to its case slot.
  `_exit_tree()` repeats the release as a last resort.
- If an item cannot be put back, its loan is left without a world transform; the game inventory
  restores it to the case on the next open. A save during the act restores the loans the same way;
  the act itself does not resume, so the player may drop from the stack height on load.

## Supply

- On world load, if `owned_count` is zero and the feature is on, the supply node spawns **3**
  pickable `goods:footstool` drops in random loaded house interiors within `80 m`.
- A home must be in the `house_interiors` group and have `place_id()` and `inside()`. Candidate
  spots start near the inside door and the room centre; a downward ray finds the real floor and a
  box query rejects furniture, walls and bodies.
- Drops use `inventory.spawn_owned_drop()`, so they persist as normal owned world items and can be
  picked up. The generated house footstools are static furniture and do not count.
- `owned_count` includes case units, held items, placed furniture and world drops, so one stool
  anywhere stops the supply. The shop remains a valid way to get more for a larger stack.
- The supply retries every `2 s` while no home is loaded, pauses with the tree and during an act,
  and logs once if no home is available or the briefcase is full.

## Settings and debug

- `features.standing_stool`, default on, label **Use footstool**.
- `presentation.standing.stool_gap_m`, debug, default `0.20`, unit cm, Standing › Motion.
- `presentation.standing.stool_height_m`, debug, default `0.20`, unit cm, Standing › Motion. Each
  placed stool adds this much height.
- **Give footstool** adds one to the briefcase.
- **Show stool state** prints the aimed or nearest mare's opening, hoof and part heights, gap,
  threshold, step height, required count, case count, owned count, free slots and active count.

## Tests and limits

- `tests/stool/test_measure.gd`: level-ground, raised-floor, negative, threshold and 25/40/60 cm
  stack-count cases.
- `tests/stool/test_item.gd`: case slot, case count, owned count, free slots, take/put and placed
  loans.
- `tests/stool/test_stool_api.gd`: the facade's setting reads, threshold, step height, count, gap
  and item id.
- `tests/stool/test_gate.gd`: the runtime forwards' live gap, two-step requirement and case count.
- `tests/stool/test_act.gd`: the per-act handle's rule, case loans, stack placement/release,
  reset and the missing-stool-only block.
- `tests/stool/test_prop.gd`: the stacked visuals, total height, box top and both pony collision
  exceptions.
- `tests/stool/test_placement.gd`: the player-root raise to the stack top, exception cleanup and
  floor release.
- `tests/test_source_hygiene.gd`: the stool purity and facade boundary, and this contract's
  presence.
- The lab covers the full act and supply: Canon and Same Height below the threshold, Celestia and
  Hoers against their live number, with and without enough case stools, early end, forced stop and
  afterglow.
- The step height is a debug setting. A gap larger than the available stack is not bypassed; the
  gate asks for more case stools.
- Step-up is part of the act start and step-down is a cut at session end. There is no step
  animation.
- The generated furniture and the act prop are separate: only the briefcase items enable the act.
