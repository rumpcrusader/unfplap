# Act scene hold

The scene ownership the act borrows while it runs: the navigator lease, the player's movement
hold, the face-turn rate, the conversation attention, the carry and the cuddle session. This is
ownership, not eligibility: whether the act may start is `docs/scene_gate.md` and
`docs/eligibility.md`; what the act takes over while it runs is here.

## Purpose

The act keeps the mare and the player in the scene the act built. It takes the navigator, the
player's movement hold, the face-turn rate and the conversation attention, and gives back the
carry and the cuddle the act started from. The service is the only place that decides which
ownership is taken, which is held, and in which order it is released.

## Ownership and boundary

`scene_hold.gd` is the facade. It owns the ownership flags and the per-flag release. The runtime
owns the act state machine, the one `_end_session` ledger and the call order; the service is
called from the ledger and the tick, and it never touches the runtime's state.

The runtime keeps thin wrappers with their old names (`_claim_nav`, `_keep_nav`, `_release_nav`,
`_lock_player`, `_unlock_player`, `_pause_face_turn`, `_restore_face_turn`,
`_keep_act_attention`, `_release_carry`, `_end_cuddle_session`) and property views over the
service flags for the teardown reports and the suites. The service owns the state, not the
runtime's.

## Public API

- `bind(host)` — the host context: `pony`, `main`, `pose_id`, `state`.
- `claim_nav(owner_id)` — takes the navigator, records the old wander flag, builds the
  `unfplap:<id>` token and returns whether the lease is owned.
- `keep_nav()` — re-asserts the lease if the owner changed.
- `release_nav()` — gives the owner back and restores the wander flag.
- `pause_face_turn(force)` — holds the standing face-turn rate at zero.
- `restore_face_turn()` — restores the saved rate.
- `keep_attention()` — clears the conversation target while the act runs.
- `lock_player()` — takes the movement hold and pauses the kisser.
- `unlock_player()` — restores the hold and the kisser.
- `release_carry()` — releases the held carry and returns whether it was released.
- `end_cuddle()` — ends the active cuddle session.

The ledger calls the leaves in this order: cuddle/carry at start, navigator claim before the pose,
then on end the face-turn restore, the player unlock, the carry/stool release, the navigator
release. The host is a plain dictionary of callables; the service never reads the runtime's
private fields.

## State and data

The service owns the flags:

- `nav`, `token`, `nav_old_wander`;
- `face_turn_rate_owned`, `face_turn_rate_saved`;
- `locked_player`, `kisser`, `kisser_processing`, `had_kiss_hold`.

The carry and the cuddle are released, not flagged: both are idempotent and read the scene. The
runtime owns the act state, the pose, the serial and the teardown ledger. The service fields stay
cleared on every act end, so a failed start releases the same ownership as a normal end.

## Settings

No settings. The service is a control path, not a tuning surface.

## Controls and debug

No controls. The debug log reports the ownership state on the `debug_line` call and the
`_end_session` teardown. A failed start leaves the same ownership as a failed release today.

## Dependencies

- `pony` — the `Navigator`, `face_turn_rate`, `CuddleSession`, `set_conversation_target`.
- `main` — the `interactor`, `player`, `game.kisser`.
- `main.player` — the `kiss_hold` meta, `seat` and `_q_held`.
- The runtime — the caller and the state.
- `poses/catalog.gd` — the standing pose id for the face-turn gate.

## Tests

`tests/scene_hold/` covers the claim/keep/release, the face-turn ownership, the player lock, the
attention clear, the carry release and the cuddle end with fake navigator, player and cuddle nodes.
The teardown suite (`tests/test_runtime_teardown.gd`) is retargeted to the facade.

## Verification / lab

- Start failure: the navigator, player hold, face turn, attention, carry and cuddle are released in
  the same order as a normal end.
- Normal end: the navigator is released, the wander flag is restored, the player hold is released
  and the kisser is restored.
- Forced stop: the same release, no cuddle rejoin.
- Cuddle start: the cuddle is ended before the act starts and the session is not re-entered.

## Related docs

- `docs/scene_gate.md` — the live scene rows and the refusal executor.
- `docs/eligibility.md` — the policy and consent gates.
- `docs/rest.md` — the bed anchor, the cuddle rejoin and the restore posture.
- `docs/runtime.md` — the one teardown ledger and the call order.
