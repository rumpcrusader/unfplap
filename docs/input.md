# Input

The input service owns the mod's act key and mouse policy. It runs in `_input` before the game's
desktop input, consumes the act keys, keeps the mouse captured during an act, routes the debug
action wheel, and routes any hotkey a debug action declares (none today).

It does not own act behavior. It calls the active runtime's typed commands and `main.try_start()`.

## Scope

- The act key: its `unfplap_act` `InputMap` action, start/end and the consumption policy.
- Mouse capture while an act is live, including the menu/alt-tab recapture path.
- The seated-player `Q` guard and the movement hold during an act.
- The debug action wheel: the hold-middle trigger, and modal routing while it is open.
- Any declared debug action hotkey (none today).
- The focus guard: typed chat text is never an act key.

## Ownership

`input/service.gd` is a world-scoped Node created by `main` and added to the tree. It owns no
saved data. Its state is transient:

- `_suppress_q`, `_old_q` — the seated-player guard;
- `_mouse_recapture_logged` — the one recapture log per act.

`main.gd` owns construction, the service list and world teardown. `runtime.gd` owns act state.
`debug/service.gd` owns the action registry.

## Internal API

The service is a Node; its contract is the Node lifecycle and the input callbacks:

- `_ready()` — sets `PROCESS_MODE_ALWAYS`, the early physics priority and the initial act action;
- `_physics_process(delta)` — keeps the mouse captured and the seated guard while an act is live;
- `_input(event)` — routes the debug wheel first (a middle button press opens it and its release
  runs the hovered slot or closes it; while open it owns every event), then consumes act keys,
  routes any declared debug hotkey, starts the hinted act and opens the act chat;
- `apply_act_key()` — rebuilds the `unfplap_act` action from the `act_key` setting;
- `_exit_tree()` — removes the action.

`apply_act_key()` is how a live setting change reaches the `InputMap`; `main._apply_settings_changed()`
calls it. The action is a real `InputMap` action rather than a physical keycode check because the
game's typing guard (`world/ui/typing_guard.gd`) stashes every non-`ui_` action while a text field
has focus. A raw `Input.is_physical_key_pressed()` poll would keep firing in chat.

The action has one `InputEventKey` with a `physical_keycode`; `shared/act_keys.gd` validates the
captured keycode and turns it into its cap label, and the HUD and native prompt read the same
label.

## Data ownership

Nothing is saved. The service reads `main.active_runtime`, `main.player`, `main.debug_wheel_open()`
and the viewport focus owner. It does not store runtime state.

## Lifecycle

- Scope: world
- Constructed by: `main._ready()`
- Begin: Node `_ready()`
- End: freed with `main` or the world
- Idempotent: yes; the Node lifecycle owns setup and release

## Settings

- `act_key` (General, top row, no section heading): the physical key that starts and ends the act.
  The default is `6`. The declaration is a hidden numeric setting; `settings/ui.gd` draws its
  hand-built **Act Key** capture row because a key capture is not one of the declaration widgets.
  Press the row, then press any key; `Esc` cancels. The captured keycode is stored in
  `settings.json` and `main._apply_settings_changed()` rebuilds the action.
- `Y` is not special in the setting: it can be captured, but it is the bundled Dance Mod's key, so
  the mod shows its one-time notice when the act key is not `Y`.

The game's own **Settings → Controls** page is not used. Its `Settings.BINDABLE` and `Settings.TABS`
are game consts, `Settings.bind_key()` saves and resets only `BINDABLE` actions, and the `Settings`
autoload cannot be extended by a mod (`mods/README.md`). A mod-owned capture is the only safe path;
a base-game `register_bindable` API would be needed to put the action on the game page.

A debug action declares its own hotkey in `debug/service.gd` (none today); the action behavior
belongs to the owning service.

## Controls and debug

The controls table is `docs/runtime.md`. Debug actions and the wheel are in `docs/debug.md`.

- A **middle mouse button press or release** is forwarded to `main.debug_wheel_input()`. The press
  opens the wheel while allowed; the release runs the hovered slot, or closes in the centre. With
  debug off, or while a menu/text field/headset owns the input, the event is not consumed.
- While the wheel is open every event is forwarded to it first. When it consumes the event the
  input service sets it handled and returns, so act keys, smack, recapture, the auto-thrust wheel
  and the skeleton click never see it.
- The input service consumes a key only when an action declares it and the focus is not a text
  field.
- The act key starts the hinted act with a tap (`main.try_start()`), and holding it during an act
  is handled by `runtime.gd` (`docs/runtime.md`). The bundled Dance Mod still polls raw `Y`; the
  default `6` removes the accidental collision, but a deliberate `Y` during an act is that mod's
  own check to add.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | debug | `debug/service.gd` | debug action registry |
| service | settings | `settings/service.gd` | the `act_key` keycode |
| shared | act_keys | `shared/act_keys.gd` | action name, default and cap labels |

## Tests

- `tests/test_input.gd` — the default, the installed action, a captured rebind, typing protection
  and the start route through `main.try_start()`.
- The manual lab covers act start, end, smack, auto, chat and the seated-player guard.
- The architecture checker covers the facade-only import rule.

## Related docs

- `docs/runtime.md` — act controls, state and tick order.
- `docs/debug.md` — the action registry and lab keys.
- `docs/settings.md` — settings widgets and the settings panel.
