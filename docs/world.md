# World

The one place a service reads the live scene. `world/service.gd` (RefCounted, static state) is
bound by the entry on world and player enter and cleared on world close. It answers *where* and
*what* — the world root, Anon's body and the reads derived from them — and never *whether*: every
gate, offer and act rule stays with its caller.

## Scope

This contract covers:

- the live world root and Anon's body, and the handles resolved from them (the view camera, the
  reach interactor, the desktop interactions node);
- the world-owned reads a rule is built on: the mare list, the thinkable bed under a point, the
  real bed behind a mattress hit, the bed a cradle looks at, bed occupancy, Anon's seat beside a
  bed, the menu/panel gates and the headset test;
- the two scene writes a service cannot do itself: the merged LOD rebuild after a shape change and
  the act chat open past the controls lock.

It does not cover an offer, a pose, an act start, a gate verdict or any act state. It preloads no
service facade and no runtime.

## Ownership

The facade is also the mod's one "is there a world" read: a pure guard is
`is_instance_valid(WORLD.game)`. It replaces the entry handle every service used to hold for the
same answer, so a service never names the entry to ask whether the scene is live.


`world/service.gd` owns the bound scene handles:

| Read | Why it is a read, not a rule |
|---|---|
| `game` | the live world root; the caller decides what to do with it |
| `player` | Anon's body; the caller decides whether he may act |
| `camera()` | which camera the eye looks through, with the one-second lookup cache |
| `interactor()` | the player rig's reach node, resolved once per body |
| `desktop()` | the desktop interactions node in the world |
| `player_body()` | the rig body the game shows for Anon |
| `game_player()` | the game's own player property, read defensively; null when absent or not a `Node3D` |
| `mares()` | a typed copy of the world's live mare list |
| `bed_under(point, exclude)` | the bed a downward probe finds under a point |
| `real_bed(node)` | the bed behind a mattress or temporary support hit |
| `bed_for_cradle(pony)` | the bed a cradle looks at, under the pony then ahead of the eye |
| `bed_occupied(bed, target)` | another mare already lying on the mattress top |
| `player_beside_bed(bed)` | Anon's seat is the bed or its couch |
| `menu_panel_open()` | a tree pause or a known UI panel owns the mouse |
| `menu_open()` | the panel test plus "the cursor is visible" |
| `headset_view()` | the eye is in a headset |
| `refresh_body_lod(pony)` | drop the merged LOD caches and re-arm the near mesh |
| `open_act_chat()` | open the chat box past the act's controls lock |

## Base-game access

`world/game.gd` is the base-game accessor module: static functions with explicit arguments, no
bound state and no service preload. `world/service.gd` delegates its raw reads to it, and the act
calls it directly for the eye line and the blush sustainer. Every accessor answers with a typed
zero when the member is absent or renamed — `null` for a handle, `false` for a flag, `NAN` for a
measurement. An argument that is not a live node is answered the same way, so a caller that holds a
freed handle gets the absent answer instead of a crash.

The private game members below are quirks of this game version: the accessor mirrors their
behaviour exactly, and a game update that renames one is a change here rather than in a caller.

| Accessor | Game member | Returns | Absent answer |
|---|---|---|---|
| `GAME.headset_view(game)` | `headset_view` | `bool` | `false` |
| `GAME.game_player(game)` | `player` | `Node3D` | `null` |
| `GAME.mares(game)` | `mares` | `Array[Node3D]`, a copy | empty |
| `GAME.player_camera(player)` | the rig's `camera` | `Camera3D` | `null` |
| `GAME.find_camera(game, player)` | `_find_camera` (private) | `Camera3D` | `null` |
| `GAME.player_avatar(player)` | the rig's `form_driver.avatar` | `Node3D` | `null` |
| `GAME.player_body_node(player)` | the rig's `Body` child | `Node3D` | `null` |
| `GAME.seat_of(player)` | the rig's `seat` | `Node` | `null` |
| `GAME.controls_locked(player)` | the rig's `controls_locked` | `bool` | `false` |
| `GAME.set_controls_locked(player, locked)` | the rig's `controls_locked` | — | no write |
| `GAME.menu_panel(game, key)` | `save_menu`, `settings_menu`, `pause_menu` | `Node` | `null` |
| `GAME.inventory(game)` | `inventory` | `Node` | `null` |
| `GAME.map_open(inventory)` | `_map_open` (private) | `bool` | `false` |
| `GAME.case_visible(inventory)` | `case.visible` | `bool` | `false` |
| `GAME.customizer_opened(inventory)` | `customizer.opened` | `bool` | `false` |
| `GAME.inspector_active(inventory)` | `inspector.active` | `bool` | `false` |
| `GAME.chat_box(game)` | the `ChatBox` child | `Node` | `null` |
| `GAME.open_chat(game, player)` | `_open`, `_lock_owned` (private), and the rig's `controls_locked` | `bool` | `false` |
| `GAME.identity_of(pony)` | `identity` | `Resource` | `null` |
| `GAME.boop_of(pony)` | `boop_node` | `Node` | `null` |
| `GAME.sustain_blush(boop, amount)` | `sustain_blush` | — | no call |
| `GAME.eye_height(player)` | `eye_height` | `float` | `NAN` |
| `GAME.set_eye_y(body, y)` | `_set_eye_y` (private) | — | no write |
| `GAME.pitch(body)` | the rig's `_pitch` | `float` | `NAN` |
| `GAME.set_pitch(body, pitch)` | the rig's `_pitch` | — | no write |
| `GAME.form_of(player)` | the rig's `form_driver` | `Node` | `null` |
| `GAME.clamp_view(form)` | `clamp_view` | — | no call |
| `GAME.clear_face_point(pony)` | the navigator's `face_point` | — | no write |
| `GAME.clear_conversation_target(pony)` | the navigator's `set_conversation_target` | — | no call |
| `GAME.look_toward(secondary, angles, weight)` | `look_toward` | `bool` | `false` |
| `GAME.aim_eyes(eye_motion, target)` | `target_world`, `target_weight` | — | no write |
| `GAME.listen_point(pony)` | `listen_point` | `Vector3` | her root plus `UP` |
| `GAME.eye_transform(body)` | `eye_transform` | `Transform3D` | infinite origin |
| `GAME.skull_world(boop)` | `skull_world` | `Vector3` | `Vector3.INF` |
| `GAME.nose_world(boop)` | `nose_world` | `Vector3` | `Vector3.INF` |
| `GAME.muzzle_world(boop)` | `muzzle_world` | `Vector3` | `Vector3.INF` |
| `GAME.set_head_back(pose, value)` | the act pose node's `head_back` | — | no write |
| `GAME.refresh_body_lod(pony)` | the hybrid near and far LOD caches, `set_near_mesh` | — | no rebuild |
| `GAME.bed_of(collider)` | the mattress `bed_of` lookup | `Node3D` | `null` |

Only `GAME.mares` and `GAME.refresh_body_lod` allocate, and both are scan-cadence calls; the
per-frame accessors copy nothing. `GAME` writes the rig's control hold, its eye line and its look
pitch, the chat lock, her navigator's face point and conversation aim, her gaze and pupils, and the
act pose's head throw-back. `GAME.set_head_back` is the one row that writes a mod-owned node: the
camera's glance needs it, and the view carries no string dispatch of its own.

## Internal API

```gdscript
const WORLD := preload("res://mods/unfplap/world/service.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")

static var game: Node
static var player: Node3D

static func bind_world(host: Node) -> void
static func bind_player(body: Node3D) -> void
static func unbind() -> void
static func camera() -> Camera3D
static func interactor() -> Node
static func desktop() -> Node
static func player_body() -> Node3D
static func game_player() -> Node3D
static func mares() -> Array[Node3D]
static func bed_under(point: Vector3, exclude: RID = RID()) -> Node3D
static func real_bed(node: Node) -> Node3D
static func bed_for_cradle(pony: Node3D) -> Node3D
static func bed_occupied(bed: Node3D, target: Node) -> bool
static func player_beside_bed(bed: Node3D) -> bool
static func menu_panel_open() -> bool
static func menu_open() -> bool
static func headset_view() -> bool
static func refresh_body_lod(pony: Node) -> void
static func open_act_chat() -> bool
```

`WORLD.mares()` answers a typed copy of the game's live list, so a caller may keep it across a
scan but never expects the game's own array. `GAME` is the raw layer: every function takes the
scene handle it needs and answers the typed zero, so a consumer that already holds `game` or
`player` calls it directly instead of reaching through the facade.

`Bind` runs in this order from the entry: `bind_world()` on world ready (it clears the resolved
handles), `bind_player()` when the player rig arrives, `unbind()` on world close. An unbound
facade answers `null` and `false`; that is the "no world yet" answer, not a rule. `game_player()`
reads the game's own `player` property through `GAME`, so a renamed or missing property is null
instead of a crash.

## Data ownership

The facade stores no saved data. It holds the two bound handles and three resolved ones, all
cleared on every bind and on unbind. Nothing is written to the settings file or `Mods.state`.

## Lifecycle

- Scope: world
- Constructed by: static initialization
- Begin: `bind_world()`/`bind_player()`
- End: `unbind()`/world close
- Idempotent: yes

## Settings

No setting is declared or read here.

## Controls and debug

No control and no debug action. The debug tooling reads the scene through this facade like any
other consumer.

## Host boundary

The entry is the only writer: it calls `bind_world(host)`, `bind_player(body)` and `unbind()`. The
facade never calls back into the entry.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|

## Tests

- `tests/world/test_world.gd`: the camera cache and its fallback, the bed resolution and the
  real-bed walk, bed occupancy and Anon's seat, the menu/paused/headset gates, the player body and
  mare reads, the LOD rebuild and the act chat, the unbound and freed-handle answers, and every
  `GAME` accessor's live and absent answer, including the chat hold's save and restore.

## Related docs

- `ARCHITECTURE.md` — the layer rules and the host boundary.
- `docs/scene_gate.md` — the live scene rows a gate evaluates through this facade.
- `docs/poses.md` — the bed pose that seats a pony on it.
