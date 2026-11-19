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
| `mares()` | the world's live mare list, unchanged |
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

## Internal API

```gdscript
const WORLD := preload("res://mods/unfplap/world/service.gd")

static var game: Node
static var player: Node3D

static func bind_world(host: Node) -> void
static func bind_player(body: Node3D) -> void
static func unbind() -> void
static func camera() -> Camera3D
static func interactor() -> Node
static func desktop() -> Node
static func player_body() -> Node3D
static func mares() -> Array
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

`Bind` runs in this order from the entry: `bind_world()` on world ready (it clears the resolved
handles), `bind_player()` when the player rig arrives, `unbind()` on world close. An unbound
facade answers `null` and `false`; that is the "no world yet" answer, not a rule.

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
  mare reads, the LOD rebuild and the act chat, and the unbound answers.

## Related docs

- `ARCHITECTURE.md` — the layer rules and the host boundary.
- `docs/scene_gate.md` — the live scene rows a gate evaluates through this facade.
- `docs/poses.md` — the bed pose that seats a pony on it.
