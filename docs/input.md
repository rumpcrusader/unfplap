# Input

The input service owns the mod's act key and mouse policy. It runs in `_input` before the game's
desktop input, consumes the act keys, keeps the mouse captured during an act, routes the debug
action wheel, and routes any hotkey a debug action declares (none today).

It does not own act behavior. It calls the active runtime's typed commands and `main.try_start()`.

## Scope

- `Y` start/end and the act key consumption policy.
- Mouse capture while an act is live, including the menu/alt-tab recapture path.
- The seated-player `Q` guard and the movement hold during an act.
- The debug action wheel: the middle-click trigger, and modal routing while it is open.
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

- `_ready()` — sets `PROCESS_MODE_ALWAYS` and the early physics priority;
- `_physics_process(delta)` — keeps the mouse captured and the seated guard while an act is live;
- `_input(event)` — routes the debug wheel first (a middle click opens it; while open it owns
  every event), then consumes act keys, routes any declared debug hotkey, starts the hinted act
  and opens the act chat.

There is no public method other than the Node callbacks.

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

No settings. A debug action declares its own hotkey in `debug/service.gd` (none today); the action
behavior belongs to the owning service.

## Controls and debug

The controls table is `docs/runtime.md`. Debug actions and the wheel are in `docs/debug.md`.

- A **middle mouse click** is forwarded to `main.debug_wheel_input()`. The wheel decides whether
  it may open; with debug off, or while a menu/text field/headset owns the input, the event is
  not consumed.
- While the wheel is open every event is forwarded to it first. When it consumes the event the
  input service sets it handled and returns, so act keys, smack, recapture, the auto-thrust wheel
  and the skeleton click never see it.
- The input service consumes a key only when an action declares it and the focus is not a text
  field.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | debug | `debug/service.gd` | debug action registry |

## Tests

No dedicated headless suite. The manual lab covers act start, end, smack, auto, chat and the
seated-player guard. The architecture checker covers the facade-only import rule.

## Related docs

- `docs/runtime.md` — act controls, state and tick order.
- `docs/debug.md` — the action registry and lab keys.
- `docs/settings.md` — settings widgets and the settings panel.
