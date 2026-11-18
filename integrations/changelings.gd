extends Node
## Queen Chrysalis, by changelings: the world-side adapter for the installed-mare profile, the
## body-fit id and her own spring tail.
##
## The pack's own body script extends the game's pony, so unfplap already attaches its runtime and
## anatomy controller. This adapter adds only what the generic core cannot know: her approved
## profile as a provider layer, her body-fit and custom tail-root metadata on the bodies she
## brings, and the installed list entry while the pack is active. It reads the pack's public
## nodes and state; it never edits the pack and never requires a rebuild.
##
## Scope: world. `main.gd` constructs it once. It never preloads `main.gd` or `runtime.gd`.
##
## See `docs/integrations.md` and `docs/anatomy.md` (`## Placement`, `## Tail seating`).

const MOD_ID := "changelings"
const GROUP := "changelings_mod"
const ID := "chrysalis"
## Her own mane and tail script, built under the body: the visible tail root is its chain.
const TAIL_ROOT := "ChrysalisHair/Hair_tail/Chain"
## A disguise marks its body with this geometry variant (`changeling=<pony id>` in 0.2.12).
const SHAPE_PREFIX := "changeling="

## The approved provider profile. No `eligible` assertion: her identity decides age, so a young
## disguised shape still fails the act gate.
const DESCRIPTOR := {
	"schema": 1,
	"id": ID,
	"source": MOD_ID,
	"name": "Queen Chrysalis",
	"preferences": {
		"intensity": "firm",
		"pattern": "teasing",
		"touch": ["caress", "kiss"],
		"dislikes": ["smack"],
		"talk": ["praise", "playful"],
		"warmth": "slow",
		"tolerance": "normal",
		"notes": "You are proud, theatrical and possessive, and you enjoy an audience. Kindness that asks nothing unsettles you, though you would never admit it. You show affection more in staying than in saying, and you remember who stayed.",
	},
	"placement": {"offset_y": 0.51, "offset_z": 0.271, "scale": 0.462},
}

var main: Node
## Test seam for the pack-active check. Production sets it in `setup()`.
var mod_active := Callable()

var _registered := false
## The generic shape-change source state. The runtime reads it through the source methods below;
## it never sees the pack's own fields.
var _changing := false
var _change_old: Node = null
var _change_new: Node = null
var _change_target := ""
var _change_by_player := false


func setup(main_node: Node) -> void:
	main = main_node
	if mod_active.is_null():
		mod_active = Callable(self, "_mod_active")


func _ready() -> void:
	if mod_active.is_null():
		mod_active = Callable(self, "_mod_active")
	set_process(false)
	refresh()


## True while the Queen Chrysalis pack is loaded this launch.
func active() -> bool:
	return not mod_active.is_null() and bool(mod_active.call())


## Mares this source installs even while they are away. The generic listing merges this with the
## live off-roster mares.
func installed_character_ids() -> Array[String]:
	var out: Array[String] = []
	if active() and _registered:
		out.append(ID)
	return out


# --------------------------------------------------------------------------- shape-change source
#
# The generic contract is documented in `integrations/shape_change.gd`. Only this adapter reads
# the pack's own `busy`, `actor` and `disguised_as` fields and calls `reveal()` / `disguise()`.

## True when this installed body may be changed through the pack.
func handles_pony(pony: Node) -> bool:
	if not active() or not is_instance_valid(pony):
		return false
	if _is_disguise(pony) or _is_own_body(pony):
		return true
	var identity: Variant = pony.get("identity")
	return identity != null and str(identity.get("id")) == ID


## The body a new change should claim, so the act is adopted before the pack finishes settling.
func claims_body(pony: Node) -> bool:
	if not _changing or not is_instance_valid(pony):
		return false
	if _change_target.is_empty():
		if _is_disguise(pony):
			return false
		if _is_own_body(pony):
			return true
		var identity: Variant = pony.get("identity")
		return identity != null and str(identity.get("id")) == ID
	return _shape_of(pony) == _change_target


func is_active() -> bool:
	return active()


func is_changing() -> bool:
	return _changing


func old_actor() -> Node:
	return _change_old if is_instance_valid(_change_old) else null


func new_actor() -> Node:
	return _change_new if is_instance_valid(_change_new) else null


## The requested shape id; empty while she returns to her own form.
func target() -> String:
	return _change_target


func requested_by_player() -> bool:
	return _change_by_player


## Start a change back to her own form. The pack plays the flame and replaces the body.
func request_true_form() -> bool:
	var mod := _source_mod()
	if not active() or _changing or mod == null:
		return false
	var current: Variant = mod.get("actor")
	if not current is Node3D or not is_instance_valid(current):
		return false
	if str(mod.get("disguised_as")).is_empty():
		return false
	_begin_change(current as Node, "", false)
	mod.call("reveal")
	return true


## Start a change to `shape_id`. The pack owns whether that shape is available.
func request_shape(shape_id: String) -> bool:
	var shape := shape_id.strip_edges()
	var mod := _source_mod()
	if not active() or _changing or mod == null or shape.is_empty():
		return false
	var current: Variant = mod.get("actor")
	if not current is Node3D or not is_instance_valid(current):
		return false
	_begin_change(current as Node, shape, false)
	mod.call("disguise", shape)
	return true


## The idle debug helper: bring her out as she is. It is not a shape change.
func request_appear() -> bool:
	var mod := _source_mod()
	if not active() or _changing or mod == null:
		return false
	var current: Variant = mod.get("actor")
	if current is Node3D and is_instance_valid(current):
		return true
	mod.call("bring_out")
	return true


## Read the pack's completion state. The runtime also calls this, so a change started from the
## Settings tab completes when no act is watching it.
func poll() -> void:
	if not _changing:
		set_process(false)
		return
	var mod := _source_mod()
	if mod == null:
		_end_change()
		return
	var current: Variant = mod.get("actor")
	if current is Node3D and is_instance_valid(current) and current != _change_old:
		_change_new = current as Node
	if not bool(mod.get("busy")):
		_end_change()


func source_name() -> String:
	return MOD_ID


## Phase 3 owns the player's own words. The source contract keeps the hooks in one place.
func asks_form_change(_text: String) -> bool:
	return false


func named_form(_text: String) -> String:
	return ""


## Register or drop the provider layer after a pack check. Idempotent.
func refresh() -> void:
	if active():
		_register()
	else:
		_unregister()


## Put the generic body-fit and custom-tail metadata on a body she brings. Her own body uses her
## approved placement and spring tail; a disguise uses the copied pony's fit and the normal hair
## path. A missing node is a quiet no-op, so a pack update can change the shape without a crash.
func prepare_pony(pony: Node) -> void:
	if not active() or not is_instance_valid(pony):
		return
	if _is_disguise(pony):
		var shape := _shape_of(pony)
		if not shape.is_empty():
			_apply_fit(pony, shape, null)
		return
	if _is_own_body(pony):
		var root := pony.get_node_or_null(TAIL_ROOT) as Node3D
		_apply_fit(pony, ID, root)
		return
	var identity: Variant = pony.get("identity")
	if identity == null or str(identity.get("id")) != ID:
		return
	# A form whose variant marker is missing: the copied body's own identity names its fit.
	var fit := ""
	var character: Variant = identity.get("character_id")
	if character != null:
		fit = str(character).strip_edges()
	_apply_fit(pony, fit if not fit.is_empty() else ID, null)


## The entry node's teardown. Idempotent.
func shutdown() -> void:
	_end_change()
	_unregister()
	main = null


func _exit_tree() -> void:
	_end_change()
	_unregister()


func _apply_fit(pony: Node, fit: String, tail_root: Node3D) -> void:
	pony.set_meta("body_fit_id", fit)
	if is_instance_valid(tail_root):
		pony.set_meta("tail_pose_root", tail_root)
	elif pony.has_meta("tail_pose_root"):
		pony.remove_meta("tail_pose_root")


func _is_disguise(pony: Node) -> bool:
	return str(pony.get_meta("geometry_variant", "")).begins_with(SHAPE_PREFIX)


## The copied pony's id from the pack's own geometry variant, or "".
func _shape_of(pony: Node) -> String:
	var variant := str(pony.get_meta("geometry_variant", ""))
	return variant.trim_prefix(SHAPE_PREFIX).strip_edges() if variant.begins_with(SHAPE_PREFIX) else ""


## One change, one old body. A second request while it runs is refused by the caller's gate.
func _begin_change(old: Node, shape_id: String, by_player: bool) -> void:
	_changing = true
	_change_old = old
	_change_new = null
	_change_target = shape_id
	_change_by_player = by_player
	set_process(true)


## The pack has finished (or vanished). The old/new handles stay readable for the act watcher.
func _end_change() -> void:
	_changing = false
	set_process(false)


## The pack's world node. The pack registers this group in its own `_ready`.
func _source_mod() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(GROUP)


func _process(_delta: float) -> void:
	poll()


## Her own body: the pack's own meshes, or its spring-tail script. A copied pony has neither.
func _is_own_body(pony: Node) -> bool:
	if pony.get_node_or_null(TAIL_ROOT) is Node3D:
		return true
	var meshes: Variant = pony.get("own_meshes")
	return meshes is Array and not (meshes as Array).is_empty()


func _register() -> void:
	if _registered:
		return
	var api := _api()
	if api == null or not api.has_method("register_mare"):
		return
	var result: Variant = api.call("register_mare", self, DESCRIPTOR.duplicate(true))
	_registered = result is Dictionary and bool((result as Dictionary).get("ok", false))
	if not _registered:
		_log("provider registration failed")


func _unregister() -> void:
	if not _registered:
		return
	_registered = false
	var api := _api()
	if api == null or not api.has_method("unregister_mare"):
		return
	api.call("unregister_mare", self, ID)


func _api() -> Node:
	if not is_instance_valid(main):
		return null
	var value: Variant = main.get("api")
	return value as Node if value is Node else null


func _mod_active() -> bool:
	var mods := get_node_or_null("/root/Mods")
	if mods == null or not mods.has_method("is_active"):
		return false
	return bool(mods.call("is_active", MOD_ID))


func _log(text: String) -> void:
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", "[changelings] " + text)
