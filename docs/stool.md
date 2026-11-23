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
| `stool/service.gd` | facade: the only other systems preload or call; owns the supply child, `new_act()` and the stateless helpers |
| `stool/act.gd` | per-act handle: the live rule, case loans, placed stack, player lift, failed flag and the hotkey pair (`hotkey_pair`, `hint_pair`); the runtime owns one per pony, resets it per act and forwards its queries one line each |
| `stool/measure.gd` | pure reach-gap, threshold and stack-count arithmetic |
| `stool/item.gd` | static `goods:footstool` case-slot, case-count, owned-count and free-slot checks through the world facade's `Inventory` view |
| `stool/prop.gd` | scene adapter: builds the stacked static act stool and its pony collision exception |
| `stool/supply.gd` | scene adapter: finds loaded homes and spawns pickable footstool drops |
| `docs/stool.md` | this contract |
| `tests/stool/` | pure measurement/item tests, prop/stack tests and the facade API test |

The facade is the only non-test file outside `stool/` that may preload `stool/*`. The entry's
service list creates it and the runtime receives it in `act/context.gd` (`stool_service`);
`act/session.gd` creates the per-act handle from it. `stool/measure.gd` stays pure:
no `Node`, tree, time, file or game-scene access. `stool/item.gd` reads the case through the world
facade's `Inventory` view and owns no scene state.

## Facade

`new_act()` creates one per-act handle; the runtime keeps one for its whole lifetime, resets it per
act and drops it with the runtime. `floor_y_at()` is the stateless standing-spot floor probe, with the player capsule
excluded.

`place()` builds the stack under the runtime's standing spot and returns the raised player
target; `release()` frees the prop, lowers the player and returns every case unit. The handle also
owns the hotkey pair: `hotkey_pair(pose)` reads the reach and case counts once and keeps them, and
`hint_pair()` returns that pair for the blocked note. The runtime's stool forwards are
`stool_gap_m()`, `stool_needed_count()`, `stool_case_count()` and `stool_state_text()`, one line
each; `applies()` and `required()` stay on the handle. The handle owns the rule, the case reads
and the failed flag.

`build_prop()` returns a `PROP.Stack` record: its `node`, the height it adds, its stool count and
the step it used.
`ignore` is the partner pony; the stack must not collide with her.

`runtime.gd` supplies the scene values, calls the handle and composes the gate; it does not read
a controller's private state. The live opening comes from the anatomy API's `entrance_point(pony)`:
the deformed resting hole point, cached in local space and mapped by the live mesh transform, so a
scan does not re-run the coat line. The part root and preparation come from
`anatomy.anon().root_now()` and `:prepare()`. The part is normally warmed when the player part
is created, so the first standing offer does not load it (`docs/anatomy.md`); `prepare()` remains
the idempotent fallback. The handle reads the injected world stool facade for the
settings/item/measure calls and the anatomy API for the cover.

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

With `T = presentation.standing.stool_gap_m` and
`S = presentation.standing.stool_height_m`:

```text
if gap <= T:
    needed = 0
else:
    needed = max(1, floor((gap - T) / S) + 1)
```

The first stool is required once the gap passes the threshold. Each stool then covers one step.
The remainder after the last stool is below the threshold, which the existing anatomy hip aim
absorbs.

A missing anatomy controller, an unprepared player part, non-finite values, AnonPony or a headset
rig makes the rule inapplicable, not required. The gate is evaluated at the standing formation, the
idle hint and the act start.

## Gate and hint

- The standing scene gate gets a `stool` row with reason `needs_stool` when the rule needs more
  case footstools than Anon has.
- The scene-only formation rows, the Agreement's placement check and `scene_gate.hotkey_ready()`
  (forwarded by the runtime) use the same row, so a tall mare neither offers nor shows the hint
  when Anon cannot reach.
- `offer/service.gd` shows **Make love** when the start is possible and **Needs a footstool** or
  **Needs N footstools** when the stack is the only missing thing. The blocked note has no act-key
  icon. A one-time toast points at houses.
- The idle hint reads the reach and case pair once per scan (once per second) through
  `hotkey_pair()` and hands it to the scene row. The reach reads `entrance_point()`, the cached
  local resting point, and `AnonBody.root_now()`; the case count is read once. The anatomy
  measurement and the inventory scan are not repeated inside the same scan.
- The blocked hint reads that pair through `hint_pair()` (forwarded by `runtime.start.hint_stool()`); it
  does not repeat the reach or case reads. Before the first hint the accessor falls back to the live
  pair.
- Pressing the act key on the blocked note does not start an act.
- The normal start path takes exactly the required number of case units. A short or unwritable
  case blocks the start.

## Act flow

- The standing state is unchanged when the rule does not apply.
- When it applies, `act/start.gd:run()` asks the handle to check out `needed` case units
  (`take_items()` → `store.take(slot)`); the handle keeps every token and slot.
- `act/frame.gd:begin()` places Anon at her gap, asks the stool handle's `floor_y_at()` for the
  floor and calls its `place()`, which builds a stack of `needed` stools under him and raises his
  player root to `floor + needed * step_height`. The stool floor is a frame input, so a form
  revision re-places him on the same stack. `AnonBody` then plants the feet and hips on the raised floor, so
  the standing pose, camera and anatomy aim use the same body.
- Each stool uses the base-game shop visual (`world/shop/shop_items.gd` → `goods:footstool` →
  `world/props/household/footstool.glb`). The visual is scaled uniformly to the configured step
  height; the collider keeps a minimum `0.46 × 0.40 m` top so Anon's feet are supported. A plain
  box stack is the fallback.
- The stack is one static body with one box collider from the floor to the top. The partner pony
  is added to the body's collision exceptions in both directions, so the stack supports Anon
  without lifting or tilting her; the exceptions are removed with the prop. The player still
  collides with it.
- The act stays on the stack through `AFTERGLOW`. `act/exit.gd:run()` is the one exit path that
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
- The supply retries every `2 s` while no home is loaded, pauses with the tree and during an act
  (the frame comes from the wired act owner, `docs/act_owner.md`), and logs once if no home is
  available or the briefcase is full.

## Settings and debug

- The footstool switch and its two standing values are declarations in `settings/service.gd`,
  each described by its `##` comment. A live reach gap over the shipped gap needs enough
  `goods:footstool` stacks of the shipped step height.
- **Give footstool** adds one to the briefcase.
- **Show data** prints the aimed mare's stool state in its STOOL section: opening, hoof
  and part heights, gap, threshold, step height, required count, case count, owned count, free
  slots and active count.

## Lab and limits

  stack-count cases.
  loans.
  the runtime forwards' live gap, two-step requirement, case count, the hotkey readiness and the
  blocked hint's reuse of the first gate's pair.
  stack placement/release, reset and the missing-stool-only block.
  exceptions.
  floor release.
- The lab covers the full act and supply: Canon and Same Height below the threshold, Celestia and
  Hoers against their live number, with and without enough case stools, early end, forced stop and
  afterglow.
- The step height is a debug setting. A gap larger than the available stack is not bypassed; the
  gate asks for more case stools.
- Step-up is part of the act start and step-down is a cut at session end. There is no step
  animation.
- The generated furniture and the act prop are separate: only the briefcase items enable the act.
