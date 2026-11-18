# Act scene hold

The scene ownership the act borrows while it runs, and the negotiation hold that reserves the
same mare before the act starts: the navigator lease, the physical affection hold, the player's
movement hold, the face-turn rate, the conversation attention, the carry and the cuddle session.
This is ownership, not eligibility: whether the act may start is `docs/scene_gate.md` and
`docs/eligibility.md`; what the act and the negotiation take over is here.

## Purpose

The act keeps the mare and the player in the scene the act built. The negotiation keeps her with
Anon while an offer or an Agreement lives. Both use one ledger: the negotiation claims a token the
scene gate accepts, keeps Anon as the conversation target, sets the game's physical affection
hold, and hands the same owner to the act at the start. The service is the only place that decides
which ownership is taken, which is held, and in which order it is released.

## Ownership and boundary

`scene_hold/service.gd` is the facade. It owns the ownership flags and the per-flag release. The runtime
owns the act state machine, the one `_end_session` ledger and the call order; the service is
called from the ledger and the tick, and it never touches the runtime's state.

The runtime keeps thin wrappers with their old names (`_claim_nav`, `_keep_nav`, `_release_nav`,
`_lock_player`, `_unlock_player`, `_pause_face_turn`, `_restore_face_turn`,
`_keep_act_attention`, `_release_carry`, `_end_cuddle_session`) and property views over the
service flags for the teardown reports and the suites. The service owns the state, not the
runtime's. It is created in `runtime._init()` and works while the runtime is `IDLE`, because the
negotiation runs before the act.

## Public API

- `bind(host)` — the host context: `pony`, `main`, `pose_family`, `state`.
- `claim_nav(owner_id)` — takes the navigator for the act, records the old wander flag, builds the
  `unfplap:<id>` token and returns whether the lease is owned.
- `claim_negotiation(owner_id)` — claims `unfplap:negotiation:<id>` while the runtime is `IDLE`.
  A missing/reserved navigator, another mod's owner, a routine owner with an active route, or
  another `unfplap:` owner is Occupied.
- `claim_attention()` — takes the attention and physical affection hold without a navigator lease.
  A cuddle session already owns the navigator; the claim leaves that owner alone.
- `transfer_nav(existing_token, old_wander)` — takes over the proactive request's live lease,
  keeping its token and release data.
- `adopt_nav(existing_token, old_wander)` — attaches a second ledger to a live owner without
  touching the navigator.
- `adopt_hold()` — the act start keeps this ledger's negotiation owner instead of claiming a
  second one.
- `holds_negotiation()` — true while this ledger owns the negotiation lease.
- `accepts_hold(pose, source)` — the scene gate's compatibility predicate: the affection hold is
  ours and, when the ledger has a navigator lease, the owner is this ledger's token. An
  attention-only cuddle hold has no lease of its own. It stays true after `adopt_hold()`.
- `keep_nav()` — re-asserts the lease if the owner changed; a negotiation lease also clears a
  route target another system set.
- `keep_target()` — keeps Anon as the conversation target. A cleared target is re-asserted;
  a target under Anon (his rig or body) is still Anon, and any other live target returns false
  (`target_left`).
- `hold_affection()` / `release_affection()` — set and clear the game's `affection_active` meta.
  Any live affection hold is Occupied.
- `release_negotiation()` — releases the whole negotiation hold: affection first, then the
  navigator. Idempotent; every terminal outcome calls it.
- `release_nav()` — gives the owner back and restores the wander flag.
- `pause_face_turn(force)` — holds the standing family face-turn rate at zero.
- `restore_face_turn()` — restores the saved rate.
- `keep_attention()` — clears the conversation target while the act runs.
- `lock_player()` — takes the movement hold and pauses the kisser.
- `unlock_player()` — restores the hold and the kisser.
- `release_carry()` — releases the held carry and returns whether it was released.
- `end_cuddle()` — ends the active cuddle session.

The ledger calls the leaves in this order: cuddle/carry at start, navigator claim before the pose,
then on end the face-turn restore, the player unlock, the carry/stool release, the navigator
release. The negotiation releases the affection hold before the navigator lease. The host is a
plain dictionary of callables; the service never reads the runtime's private fields.

## State and data

The service owns the flags:

- `nav`, `token`, `nav_old_wander`, `negotiation`, `affection_owned`;
- `face_turn_rate_owned`, `face_turn_rate_saved`;
- `locked_player`, `kisser`, `kisser_processing`, `had_kiss_hold`.

The carry and the cuddle are released, not flagged: both are idempotent and read the scene. The
runtime owns the act state, the pose, the serial and the teardown ledger. The service fields stay
cleared on every act end, so a failed start releases the same ownership as a normal end.

## Lifecycle

- Scope: per-pony
- Constructed by: `runtime._init()`
- Begin: `bind()` / `claim_nav()` / `claim_negotiation()`
- End: act teardown or `release_negotiation()`
- Idempotent: yes


## Settings

No settings. The service is a control path, not a tuning surface.

## Controls and debug

No controls. The debug log reports the ownership state on the `debug_line` call and the
`_end_session` teardown. A failed start leaves the same ownership as a failed release today.

## Dependencies

- `pony` — the `Navigator`, `face_turn_rate`, `CuddleSession`, `set_conversation_target`.
- `main` — the `interactor`, `player`, `game.kisser`.
- `main.player` — the `kiss_hold` meta, `seat`, `_q_held` and the conversation target.
- The runtime — the caller, the state and the live pose family.

### Uses
| service | world | `world/service.gd` | Anon's body and reach |

| Kind | Target | Entry point | Purpose |
|---|---|---|---|

## Tests

`tests/scene_hold/` covers the claim/keep/release, the negotiation lease in `IDLE`, the token the
scene gate accepts, the attention-only cuddle hold, keep-target and the attention reassignment,
the affection hold, the transfer/adoption handoff, the idempotent release, the face-turn
ownership, the player lock, the attention clear, the carry release and the cuddle end with fake
navigator, player and cuddle nodes.
The teardown suite (`tests/test_runtime_teardown.gd`) is retargeted to the facade.

## Verification / lab

- Start failure: the navigator, player hold, face turn, attention, carry and cuddle are released in
  the same order as a normal end.
- Normal end: the navigator is released, the wander flag is restored, the player hold is released
  and the kisser is restored.
- Forced stop: the same release, no cuddle rejoin.
- Cuddle start: the cuddle is ended before the act starts and the session is not re-entered.

## Related docs

- `docs/scene_gate.md` — the live scene rows.
- `docs/eligibility.md` — the policy and consent gates.
- `docs/rest.md` — the bed anchor, the cuddle rejoin and the restore posture.
- `docs/runtime.md` — the one teardown ledger and the call order.
