# Rest and cuddle rejoin contract

The bed/couch rest the act borrows: where she lies, the return to the stock cuddle, the clear
floor beside the bed and the restore posture.

## Ownership

`rest/service.gd` (RefCounted) owns:

- `place_on_bed` / `place_on_start`: place her on the mattress, wait up to three physics frames
  for support, then request `stand`;
- `bed_anchor`: the guest-seat transform from the game's own bed rest, or the mattress top on
  Anon's side;
- `shared_bed_rest` / `bed_rest_for`: the live couch in the `couches` group that owns this bed;
- `rejoin_bed_cuddle`: the deferred stock recline and guest invite loop;
- `stand_beside_bed`: the safe floor beside the bed via `exit_space.gd`;
- `rejoin_note`: the timeout diagnostic;
- `rejoin_wanted`: the desktop-human, good-act decision;
- `restore_posture`: the missionary scene restore and the `stand` request.

The runtime keeps the act state and the one teardown ledger: the cradle start call, the
`_end_session` restore call, the deferred `_rejoin_bed_cuddle` trigger, `_serial`/`state` and the
`aftercare_min`. It reads `_posture_owned` itself. `rest/control.gd` stays the small static
release helper for a managed bed/couch rest.

The facade binds the scene (`main`, `pony`, the act bed) on every access, and reads the live act
values through one `context` callback (`serial`, `state`, `player_pony`, `headset`, `summary`,
`satisfaction`, `aftercare_min`). The async paths re-read that context after every await, so a new
act, a forced stop or a stood-up player cancels the rejoin instead of acting on stale values.

## Bed anchor

`bed_anchor()` prefers `shared_bed_rest(bed)`: the `couches` node whose `bed_node` matches, with a
`pony_transform(seats[1])` that is finite and within 4 m of the bed. Without it, the anchor is the
mattress top (the drawn bedding via `mattress.visible_top()` or the `mattress_top` meta) shifted
0.25 m toward Anon's side, facing along the bed's `-Z` (or toward Anon when the bed is gone).

## Stock accept path

`SharedBed.accept()` is the game's "her AI chose to join" entry. It sets `_accepting` so a
`social:talk` navigator lease counts as routine, then calls `invite(actor, null)`; `invite()`
ignores its seat argument and lays her spot out at her own `body_scale` (`_lay_mare`). The rejoin
therefore calls `invite(pony, seats[1])` explicitly.

## Placement and restore

- `place_on_start()` is the cradle start: reset her onto the anchor, wait up to three physics
  frames while the state is not `IDLE`, stop on `grounded()`, then request `stand`. The act poses
  her body itself; the placement only puts her in bed space.
- A normal end calls `restore_posture()`. For missionary it restores the pre-act player, pony and
  camera snapshot (`runtime._rest_restore_scene`), then requests `stand`. Standing acts do not
  restore the scene; they keep Anon where the act ended.
- A forced stop never reaches the rejoin. `_end_session()` only captures the bed when the act was
  a normal bed-sourced end that did not go badly and `rejoin_wanted()` is true.

## Cuddle rejoin

`rejoin_bed_cuddle(bed, serial)` runs deferred from `_end_session`:

1. Refuse a missing pony/tree/bed, a stale `serial`, a missing player rest, a bed with no live
   rest, or fewer than two seats. Every exit logs its reason.
2. Seat Anon on the player seat and recline him (`sit_on` + `toggle_couch_sleep`).
3. Move her to the clear floor beside the bed. The act restores her standing on the mattress, and
   the stock bed's front probe rejects a floor more than half a metre below her feet.
4. Wait `CUDDLE_REJOIN_SETTLE_S = 1.5 s` for the recline blend. The stock snuggle support reads
   the reclined avatar's hip targets; inviting earlier leaves the guest at standing height.
5. Retry `open()` + `invite(pony, seats[1])` every `CUDDLE_REJOIN_RETRY_S = 0.5 s` for up to
   `CUDDLE_REJOIN_WINDOW_S = 30 s` (the window covers the 10 s aftercare navigator hold and the
   bed's 20 s guest cooldown). Each attempt re-checks the serial, `state == IDLE` and the player's
   recline. A timeout logs `rejoin_note` and leaves her standing.

The stock closeness rule stays the authority: she must welcome hugs and be at least a friend. A
bad act or an upset mare leaves her standing.

## Host boundary

| Callback | Meaning |
|---|---|
| `context` | the live serial/state/player-form/summary/readiness values |
| `restore_scene` | the missionary pre-act player/pony/camera restore |
| `log` | the one debug gate (`Enable debug`) |

The facade never preloads `runtime.gd` or `main.gd` and never reads their private fields.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| shared | pose_catalog | `shared/pose_catalog.gd` | pose ids and defaults |

## Lifecycle

- Scope: per-act
- Constructed by: `runtime._init()`
- Begin: `bind()`
- End: act teardown
- Idempotent: yes


## Tests

`tests/rest/test_rest.gd` covers the rejoin decision, the bed anchor and shared rest lookup, the
rest lookup, the note, the restore posture, the placement and the early rejoin exits. The lab
covers the live rejoin: a good missionary act returns to the cuddle, a forced stop leaves her
standing and a bad act does not invite.
