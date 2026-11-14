# Input

The input service owns the mod's act key, mouse policy and the act input shield. It runs in
`_input` before the game's desktop input, consumes the act keys, keeps the mouse captured during
an act, shields the act from every other key, routes the debug action wheel, and routes any
hotkey a debug action declares (none today).

It does not own act behavior. It calls the active runtime's typed commands and `main.try_start()`.

## Scope

- The act key: its `unfplap_act` `InputMap` action, start/end and the consumption policy.
- The act input shield: the pass list, the raw-key exclusions and the release injection (a
  documented HACK, below).
- Mouse capture while an act is live, including the menu/alt-tab recapture path.
- The seated-player `Q` guard and the movement hold during an act.
- The debug action wheel: the hold-middle trigger, and modal routing while it is open.
- Any declared debug action hotkey (none today).
- The focus guard: typed chat text is never an act key.

## Ownership

`input/service.gd` is a world-scoped Node created by `main` and added to the tree. It owns no
saved data. Its state is transient:

- `_shield` — the cached `features.act_input_shield`;
- `_suppress_q`, `_old_q` — the seated-player guard;
- `_mouse_recapture_logged` — the one recapture log per act.

`main.gd` owns construction, the service list and world teardown. `runtime.gd` owns act state.
`debug/service.gd` owns the action registry.

## Internal API

The service is a Node; its contract is the Node lifecycle and the input callbacks:

- `_ready()` — sets `PROCESS_MODE_ALWAYS`, the early physics priority and calls `apply_settings()`;
- `_physics_process(delta)` — keeps the mouse captured and the seated guard while an act is live;
- `_input(event)` — routes the debug wheel first (a middle button press opens it and its release
  runs the hovered slot or closes it; while open it owns every event), then consumes act keys,
  routes any declared debug hotkey, starts the hinted act and opens the act chat; while an act is
  live it hands every key press to `_act_key()`;
- `apply_settings()` — rebuilds the `unfplap_act` action from the `act_key` setting and caches the
  shield flag;
- `_act_key(runtime, key, state)` — the act's own keys, then the shield's catch-all;
- `_consume(key)` — marks the key handled and, with the shield on, clears its polled state unless
  it is the act action or one of `RAW_KEYS`;
- `_suppress_raw(key)` — the HACK: injects a matching release event;
- `_exit_tree()` — removes the action.

`apply_settings()` is how a live setting change reaches the `InputMap`; `main._apply_settings_changed()`
calls it. The action is a real `InputMap` action rather than a physical keycode check because the
game's typing guard (`world/ui/typing_guard.gd`) stashes every non-`ui_` action while a text field
has focus. A raw `Input.is_physical_key_pressed()` poll would keep firing in chat.

The action has one `InputEventKey` with a `physical_keycode`; `shared/act_keys.gd` validates the
captured keycode and turns it into its cap label, and the HUD and native prompt read the same
label.

## Data ownership

Nothing is saved. The service reads `main.active_runtime`, `main.player`, `main.debug_wheel_open()`,
`main.menu_panel_open()` and the viewport focus owner, plus the `act_key` and `act_input_shield`
settings. It does not store runtime state.

## Lifecycle

- Scope: world
- Constructed by: `main._ready()`
- Begin: Node `_ready()`
- End: freed with `main` or the world
- Idempotent: yes; the Node lifecycle owns setup and release

## Settings

- `act_key` (General, top row, no section heading): the physical key that starts and ends the act.
  The shipped default lives in `settings/defaults.json`. The declaration is a hidden numeric
  setting; `settings/ui.gd` draws its hand-built **Act Key** capture row because a key capture is
  not one of the declaration widgets.
  Press the row, then press any key; `Esc` cancels. The captured keycode is stored in
  `settings.json` and `main._apply_settings_changed()` rebuilds the action.
- `Y` is not special in the setting: it can be captured, but it is the bundled Dance Mod's key, so
  the mod shows its one-time notice when the act key is not `Y`.
- `act_input_shield` (General, **Block other mods' keys**, no hint, on by default): the act input
  shield. `apply_settings()` caches it; the mechanism and its HACK note are below.

The game's own **Settings → Controls** page is not used. Its `Settings.BINDABLE` and `Settings.TABS`
are game consts, `Settings.bind_key()` saves and resets only `BINDABLE` actions, and the `Settings`
autoload cannot be extended by a mod (`mods/README.md`). A mod-owned capture is the only safe path;
a base-game `register_bindable` API would be needed to put the action on the game page.

A debug action declares its own hotkey in `debug/service.gd` (none today); the action behavior
belongs to the owning service.

## Act input shield (HACK)

While an act is live, the service owns the keyboard. Every key the act does not use is consumed in
`_input`, so the game's `_unhandled_input`, the GUI and any mod on the event pipeline never see
it. That alone does not reach a mod that samples raw key state in `_physics_process` (Pegasus Ride
polls `Input.is_key_pressed(KEY_N/KEY_V/KEY_P)`): `set_input_as_handled()` cannot stop a poll.

**HACK:** for those keys the service also feeds `Input` a matching release through
`Input.parse_input_event()` (`_suppress_raw`). The input flush drains the injected release before
the next physics step, so a raw poller reads the key as up; the player's own release restores the
real state. This is a deliberate, global lie about key state, kept only for the length of an act.

- `PASS_KEYS` stay live: `Enter`/`KP Enter` (typing), `T` (the game's talk turn, scored by the
  act), `Esc` (the pause menu) and `F1`–`F12` (the game's save, settings, weather and debug keys).
  Everything also passes while a `LineEdit`/`TextEdit` has focus, the tree is paused, or
  `main.menu_panel_open()` is true.
- `RAW_KEYS` are consumed but never cleared: `Q W E A S D Z X C F`, the keys the act samples
  every frame (lean, auto layer, caress, kiss), and the act key itself (the hold-to-end poll).
- `features.act_input_shield` turns the shield off; the old per-key consumption lists then run
  unchanged.
- Limits: a mod that handles the press in its own `_input` still sees the event, because
  consumption never stops a sibling `_input` and tree order cannot change that; VR controller
  buttons are not keys; a key held when the act ends reads as released until it is pressed again;
  while typing, keys pass, so a raw poller can still see typed letters; a key the player rebinds
  the act key onto is not cleared, because the hold needs it.

## Controls and debug

The controls table is `docs/runtime.md`. Debug actions and the wheel are in `docs/debug.md`.

- A **middle mouse button press or release** is forwarded to `main.debug_wheel_input()`. The press
  opens the wheel while allowed; the release runs the hovered slot, or closes in the centre. With
  debug off, or while a menu/text field/headset owns the input, the event is not consumed.
- While the wheel is open every event is forwarded to it first. When it consumes the event the
  input service sets it handled and returns, so act keys, smack, recapture, the auto-thrust wheel
  and the skeleton click never see it.
- The input service consumes a key when the act routes it, when an action declares it, or when the
  shield takes it; a text field's focus always passes everything. The rules are in the section
  above.
- The act key starts the hinted act with a tap (`main.try_start()`), and holding it during an act
  is handled by `runtime.gd` (`docs/runtime.md`). The bundled Dance Mod polls raw `Y`; the act
  input shield clears it during an act, and the shipped default act key keeps the collision out
  of idle play too.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | debug | `debug/service.gd` | debug action registry |
| service | settings | `settings/service.gd` | the `act_key` keycode and the shield flag |
| shared | act_keys | `shared/act_keys.gd` | action name, legacy fallback and cap labels |

## Tests

- `tests/test_input.gd` — the legacy fallback, the installed action, a captured rebind, typing
  protection, the start route through `main.try_start()`, the release-injection spike and the
  shield: a foreign key consumed and cleared, an act-polled key kept, `N` still toggling, the
  pass list, typing, a paused tree, an open panel and the setting off.
- The manual lab covers act start, end, smack, auto, chat and the seated-player guard.
- The architecture checker covers the facade-only import rule.

## Related docs

- `docs/runtime.md` — act controls, state and tick order.
- `docs/debug.md` — the action registry and lab keys.
- `docs/settings.md` — settings widgets and the settings panel.
