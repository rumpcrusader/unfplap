# Act scene hold

The scene ownership the act borrows while it runs, and the negotiation hold that reserves the
same mare before the act starts: the navigator lease, the physical affection hold, the player's
movement hold, the face-turn rate, the conversation attention, the carry, the cuddle session and
the game's shared excitement Beat. This is ownership, not eligibility: whether the act may start is
`docs/scene_gate.md` and `docs/eligibility.md`; what the act and the negotiation take over is here.

## Purpose

The act keeps the mare and the player in the scene the act built. The negotiation keeps her with
Anon while an offer or an Agreement lives. Both use one ledger: the negotiation claims a token the
scene gate accepts, keeps Anon as the conversation target, sets the game's physical affection
hold, and hands the same owner to the act at the start. The service is the only place that decides
which ownership is taken, which is held, and in which order it is released.

## Ownership and boundary

`scene_hold/api.gd` is the facade. It owns the ownership flags and the per-flag release. The
act exit ledger (`act/exit.gd`), the start ledger, the frame schedule (`act/tick.gd`) and the
body-swap seams (`act/swap.gd`) call it; the service never touches the act's state.

The game's excitement Beat is held by owner name: the first holder saves the Beat's pause state,
every holder keeps it paused, and only the last release restores the saved state. The
mod-integration bridge and the kiss take their holds through the act's facts, so a service never
writes `Beat.paused` itself. The act teardown drops every hold and restores the Beat once.

The act modules read `context.hold` directly for the ordered steps (`keep_nav`, `keep_attention`,
`pause_face_turn`, `release_nav`, `restore_face_turn`, `release_carry`), and the start ledger
claims the lease. The session keeps `hold_handle()` for the Negotiation bridge and property views
over the service flags for the teardown reports and the suites. The service owns the state, not
the runtime's. It is created by the runtime's composition and works while the runtime is `IDLE`,
because the negotiation runs before the act.

## Order

The ledger calls the leaves in this order: cuddle/carry at start, navigator claim before the pose,
then on end the face-turn restore, the player unlock, the carry/stool release, the navigator
release. The negotiation releases the affection hold before the navigator lease. The keep and the
release work from the navigator handle the claim recorded, so a teardown that has already lost the
pony still gives the lease back. The host is a typed `Host` record with the `pony`, `state` and
`pose_family` reads; the service never reads the runtime's private fields.

## State and data

The service owns the flags:

- `nav`, `token`, `nav_old_wander`, `negotiation`, `affection_owned`;
- `face_turn_rate_owned`, `face_turn_rate_saved`;
- `locked_player`, `kisser`, `kisser_processing`, `had_kiss_hold`;
- the Beat holders and the saved pause state.

The carry and the cuddle are released, not flagged: both are idempotent and read the scene. The
`act/session.gd` owns the act state, the pose, the serial and the teardown ledger. The service fields stay
cleared on every act end, so a failed start releases the same ownership as a normal end.

## Settings

No settings. The service is a control path, not a tuning surface.

## Controls and debug

No controls. The debug log reports the ownership state on the `debug_line` call and the act exit
teardown. A failed start leaves the same ownership as a failed release today.

## Verification / lab

- Start failure: the navigator, player hold, face turn, attention, carry and cuddle are released in
  the same order as a normal end.
- Normal end: the navigator is released, the wander flag is restored, the player hold is released
  and the kisser is restored.
- Forced stop: the same release, no cuddle rejoin.
- Cuddle start: the cuddle is ended before the act starts and the session is not re-entered.
- Beat: a repeated owner releases once, the last of several restores, an already-paused Beat stays
  paused, and the act teardown restores it with owners left.
