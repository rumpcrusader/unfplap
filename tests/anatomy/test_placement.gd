extends SceneTree
## The anatomy placement: the global default, the provider and player layers, the body-fit key,
## the stable id, the saved override and the tail seat integration.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_placement.gd

const ANATOMY := preload("res://mods/unfplap/anatomy/controller.gd")
const ANATOMY_PLACEMENT := preload("res://mods/unfplap/anatomy/placement.gd")
const ANATOMY_SERVICE := preload("res://mods/unfplap/anatomy/service.gd")
const MARE_REGISTRY := preload("res://mods/unfplap/registry/service.gd")
const PLACEMENT := preload("res://mods/unfplap/shared/anatomy_placement.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const TAIL_HIDE := preload("res://mods/unfplap/anatomy/tail/hide.gd")
const TAIL_SEAT := preload("res://mods/unfplap/anatomy/tail/seat.gd")

var failures := 0
var checks := 0

class FakeIdentity extends Resource:
	var id := ""
	var character_id := ""
	var filly := false
	var stallion := false

class FakePony extends Node3D:
	var identity: Resource
	var rig: Node
	var skeleton: Skeleton3D
	var hair_skeleton: Skeleton3D
	var hair_link: Node
	var head_width := 1.0
	var head_width_factor := 1.0
	var _far_mesh_shown := false


class FakeHairLink extends Node:
	var pelvis_offset := Transform3D.IDENTITY


class FakeMain extends Node:
	var eligibility: Variant
	var target: Node
	var refreshed := 0
	var _view: Camera3D

	func camera() -> Camera3D:
		if _view == null:
			_view = Camera3D.new()
			add_child(_view)
		return _view

	func debug_target(_view: Camera3D) -> Node:
		return target

	func nearest_pony(_view: Camera3D) -> Node:
		return null

	func refresh_anatomy() -> void:
		refreshed += 1

	func apply_settings_changed() -> void:
		pass

	func custom_tail_ready(_pony: Node) -> bool:
		return false

	func apply_custom_tail(_pony: Node) -> void:
		pass

	func custom_tail_report() -> String:
		return ""


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func _pony(id: String, filly := false, stallion := false) -> FakePony:
	var pony := FakePony.new()
	var identity := FakeIdentity.new()
	identity.id = id
	identity.filly = filly
	identity.stallion = stallion
	pony.identity = identity
	pony.set_meta("relationship_id", id)
	return pony


## A pony rigged enough for the tail seat's capability check: both skeletons, a hair link and a
## dock. The seat never measures her while the setting is off, so no meshes are needed.
func _rigged_pony(id: String) -> FakePony:
	var pony := _pony(id)
	pony.skeleton = Skeleton3D.new()
	pony.add_child(pony.skeleton)
	pony.hair_skeleton = Skeleton3D.new()
	pony.add_child(pony.hair_skeleton)
	pony.hair_link = FakeHairLink.new()
	pony.add_child(pony.hair_link)
	var dock := MeshInstance3D.new()
	dock.name = "OpenPonyDock"
	dock.mesh = BoxMesh.new()
	pony.add_child(dock)
	return pony


func run() -> void:
	# Placement and preferences use the relationship id first; the identity id is the fallback.
	var meta_first := _pony("visual_id")
	meta_first.set_meta("relationship_id", "relationship_id")
	root.add_child(meta_first)
	check(ANATOMY.pony_id(meta_first) == "relationship_id", "relationship id wins")
	# The placement reads the same stable id: an override saved on the relationship id is the one
	# `load()` applies, not the identity id's row.
	var meta_place := ANATOMY_PLACEMENT.new()
	meta_place.setup(meta_first)
	var meta_mesh := MeshInstance3D.new()
	meta_mesh.mesh = BoxMesh.new()
	meta_place.set_mesh(meta_mesh, Transform3D.IDENTITY, [])
	var rel_override := SETTINGS.anatomy_placement("relationship_id")
	rel_override["offset_x"] = 0.321
	SETTINGS.save_anatomy_placement("relationship_id", rel_override)
	meta_place.load()
	check(near(meta_place.base_place().origin.x, 0.321),
		"anatomy placement uses the relationship id")
	SETTINGS.save_anatomy_placement("relationship_id",
		SETTINGS.anatomy_placement_default("relationship_id", false))
	meta_mesh.free()

	var default_place := SETTINGS.anatomy_placement_default("")
	var modded_place := SETTINGS.anatomy_placement_default("not_a_base_mare")
	check(modded_place == default_place, "an off-roster mare uses the global anatomy placement")

	# A provider placement wins over the catalog/global default; a player's sparse row still wins.
	var placed_id := "provider_placement_mare"
	MARE_REGISTRY.register(2, {"id": placed_id, "source": "anatomy_test",
		"placement": {"tail_y": 0.09}})
	check(near(float(SETTINGS.anatomy_placement(placed_id)["tail_y"]), 0.09),
		"a provider placement beats the global default")
	var placement_override := SETTINGS.anatomy_placement(placed_id)
	placement_override["tail_y"] = 0.11
	SETTINGS.save_anatomy_placement(placed_id, placement_override)
	check(near(float(SETTINGS.anatomy_placement(placed_id)["tail_y"]), 0.11),
		"a player placement beats the provider")
	MARE_REGISTRY.unregister(2, placed_id)
	check(near(float(SETTINGS.anatomy_placement(placed_id)["tail_y"]), 0.11),
		"the player placement survives the provider leaving")
	SETTINGS.save_anatomy_placement(placed_id,
		SETTINGS.anatomy_placement_default(placed_id, false))
	check(not SETTINGS.anatomy_placement_has_override(placed_id),
		"clearing the player placement returns to the global default")

	# A body fit selects the provider/catalog default while the player override stays on the
	# stable pony id. A disguise therefore uses the copied pony's fit, not her own.
	var fit_owner := "chrysalis"
	MARE_REGISTRY.register(3, {"id": fit_owner, "source": "anatomy_test",
		"placement": {"offset_y": 0.51, "offset_z": 0.271, "scale": 0.462}})
	var own_fit := SETTINGS.anatomy_placement(fit_owner, fit_owner)
	check(near(float(own_fit.get("offset_y", 0.0)), 0.51),
		"the body fit resolves the provider placement")
	var disguise_fit := SETTINGS.anatomy_placement(fit_owner, "fluttershy")
	check(disguise_fit == SETTINGS.anatomy_placement("fluttershy"),
		"a copied body uses the target pony's fit")
	check(SETTINGS.anatomy_placement("fluttershy", "fluttershy")
		== SETTINGS.anatomy_placement("fluttershy"),
		"the fit default leaves a base mare unchanged")
	own_fit["offset_y"] = float(own_fit.get("offset_y", 0.0)) + 0.02
	SETTINGS.save_anatomy_placement(fit_owner, own_fit, fit_owner)
	check(near(float(SETTINGS.anatomy_placement(fit_owner, fit_owner).get("offset_y", 0.0)),
		0.53), "the player override follows the stable id")
	check(SETTINGS.anatomy_placement("fluttershy", "fluttershy")
		== SETTINGS.anatomy_placement("fluttershy"),
		"another mare's fit stays unchanged by the override")
	SETTINGS.save_anatomy_placement(fit_owner,
		SETTINGS.anatomy_placement_default(fit_owner, false, fit_owner), fit_owner)
	check(not SETTINGS.anatomy_placement_has_override(fit_owner, fit_owner),
		"clearing the fit override returns to the provider placement")
	MARE_REGISTRY.unregister(3, fit_owner)

	# Tail seat: with Re-seat tails and docks off, attach only remembers her id. A disabled seat
	# must not measure the tail or rebuild the dock, and a settings tick must not write either.
	var seat := TAIL_SEAT.new()
	root.add_child(seat)
	seat.set("eligible", func(_node: Node) -> bool: return true)
	var rigged := _rigged_pony("twilight_sparkle")
	root.add_child(rigged)
	var reseat_before := SETTINGS.reseat_tails.get_bool()
	SETTINGS.reseat_tails.set_bool(false)
	seat.call("attach", rigged)
	var off_row: TAIL_SEAT.SeatRow = seat.row(rigged)
	check(off_row != null, "the seat remembers a pony while it is off")
	check(not off_row.seated, "the off row is not measured")
	check(off_row.dock == null, "the off row caches no dock")
	check(bool(seat.call("can_seat", rigged)), "the seat still reports the pony as seatable")
	seat.call("refresh_all")
	check(seat.row(rigged) != null, "a settings tick with the seat off keeps the remembered pony")
	check(seat.pending_rebuilds() == 0, "no dock rebuild is queued while off")
	off_row.tail_y = 0.01
	off_row.tail_z = -0.02
	check(off_row.target(Vector3(0.1, 0.2, 0.3)).is_equal_approx(Vector3(0.1, 0.21, 0.28)),
		"the row target adds its tail trims to the reference")
	off_row.tail_y = 0.0
	off_row.tail_z = 0.0
	# The settle queue drains without rebuilding a row that was never measured.
	seat.call("_mark_dirty", off_row)
	check(seat.pending_rebuilds() == 1, "a placement edit queues one dock rebuild")
	seat.call("_flush_dirty")
	check(seat.pending_rebuilds() == 0, "the settle pass drains the queue")
	SETTINGS.reseat_tails.set_bool(reseat_before)
	rigged.free()
	seat.free()

	# Dock style is visibility/colour only. The old placement pinned the mesh top to the dock's
	# buried base ring, which dropped a low-docked mare's anatomy by up to 9 cm.
	var place := ANATOMY.new()
	var place_mesh := MeshInstance3D.new()
	place_mesh.mesh = BoxMesh.new()
	place.add_child(place_mesh)
	place.placement.setup(null)
	place.placement.set_mesh(place_mesh, Transform3D.IDENTITY, [])
	place.placement.load()
	var place_pos := Vector3(
		float(default_place["offset_x"]),
		float(default_place["offset_y"]),
		float(default_place["offset_z"]))
	var dock_before := SETTINGS.dock_style.get_choice()
	SETTINGS.dock_style.set_choice("coat")
	place.placement.apply(false, 0.0, null)
	var dock_on: Transform3D = place_mesh.transform
	SETTINGS.dock_style.set_choice("hide")
	place.placement.apply(false, 0.0, null)
	var dock_off: Transform3D = place_mesh.transform
	check(dock_on.is_equal_approx(dock_off), "the dock switch never moves the anatomy")
	check(near(dock_on.origin.y, place_pos.y + float(ANATOMY_PLACEMENT.LIFT)),
		"placement uses the calibrated lift")
	SETTINGS.dock_style.set_choice(dock_before)
	place.free()

	# Saved placements migrate once onto the current default: v0 rows get all three shifts, v1 the
	# lateral and forward steps, v2 the forward step, and a v3 row is left alone.
	var v0 := PLACEMENT.migrate_legacy({"version": 0, "fluttershy": {
		"position": [-0.005, 0.5, 0.281], "pitch": 6.0, "scale": 0.662}})
	check(int(v0.get("version", 0)) == PLACEMENT.LEGACY_VERSION, "v0 placements migrate forward")
	var v0_pos: Array = v0["fluttershy"]["position"]
	check(near(float(v0_pos[0]), 0.0), "v0 row loses the lateral bias")
	check(near(float(v0_pos[2]), 0.289), "v0 row keeps both forward shifts")
	var v1 := PLACEMENT.migrate_legacy({"version": 1, "rarity": {
		"position": [-0.005, 0.5, 0.286], "pitch": 6.0, "scale": 0.662}})
	var v1_pos: Array = v1["rarity"]["position"]
	check(near(float(v1_pos[0]), 0.0), "v1 row loses the lateral bias")
	check(near(float(v1_pos[2]), 0.289), "v1 row gets the current forward step")
	var v2 := PLACEMENT.migrate_legacy({"version": 2, "rarity": {
		"position": [-0.004, 0.5, 0.286]}})
	var v2_pos: Array = v2["rarity"]["position"]
	check(near(float(v2_pos[0]), -0.004), "v2 row keeps its lateral offset")
	check(near(float(v2_pos[2]), 0.289), "v2 row gets the current forward step")
	var v3 := PLACEMENT.migrate_legacy({"version": 3, "rarity": {
		"position": [-0.004, 0.5, 0.289]}})
	var v3_pos: Array = v3["rarity"]["position"]
	check(near(float(v3_pos[2]), 0.289), "current rows are not touched")

	# The facade delegates the Placement actions to the editor; the editor resolves the pointed
	# mare through the scene adapter and never keeps a second target.
	var editor_main := FakeMain.new()
	root.add_child(editor_main)
	var editor_pony := _pony("editor_mare")
	root.add_child(editor_pony)
	editor_main.target = editor_pony
	var service: Node = ANATOMY_SERVICE.new()
	root.add_child(service)
	service.call("setup", editor_main)
	var target_before := SETTINGS.edit_target.get_choice()
	SETTINGS.edit_target.set_choice("mare")
	check(service.placement_editor != null, "the facade owns the placement editor")
	check(str(service.placement_editor.call("placement_id")) == "editor_mare",
		"the editor resolves the pointed mare")
	check(service.call("placement_debug", "text").begins_with("editor_mare"),
		"the facade delegates the placement text")
	SETTINGS.edit_target.set_choice(target_before)
	service.call("shutdown")
	root.remove_child(service)
	service.free()
	root.remove_child(editor_pony)
	editor_pony.free()
	root.remove_child(editor_main)
	editor_main.free()

	# Debug tail collapse: the modifier scales both bones and restores them without moving joints.
	var tail_skeleton := Skeleton3D.new()
	tail_skeleton.add_bone("mTail1")
	tail_skeleton.add_bone("mTail2")
	tail_skeleton.set_bone_parent(1, 0)
	root.add_child(tail_skeleton)
	var tail_modifier := TAIL_HIDE.new()
	tail_modifier.bones = [&"mTail1", &"mTail2"]
	tail_skeleton.add_child(tail_modifier)
	var joint_0 := tail_skeleton.get_bone_pose(0).origin
	var joint_1 := tail_skeleton.get_bone_pose(1).origin
	tail_modifier.call("set_hiding", true)
	tail_modifier.call("_process_modification")
	check(near(tail_skeleton.get_bone_pose_scale(0).x, TAIL_HIDE.HIDE_SCALE),
		"first tail bone collapses")
	check(near(tail_skeleton.get_bone_pose_scale(1).x, TAIL_HIDE.HIDE_SCALE),
		"child tail bone collapses")
	check(tail_skeleton.get_bone_pose(0).origin.is_equal_approx(joint_0)
		and tail_skeleton.get_bone_pose(1).origin.is_equal_approx(joint_1),
		"collapsing the tail leaves both joints in place")
	tail_modifier.call("set_hiding", false)
	check(near(tail_skeleton.get_bone_pose_scale(0).x, 1.0), "first tail bone restores")
	check(near(tail_skeleton.get_bone_pose_scale(1).x, 1.0), "child tail bone restores")
	check(tail_skeleton.get_bone_pose(0).origin.is_equal_approx(joint_0)
		and tail_skeleton.get_bone_pose(1).origin.is_equal_approx(joint_1),
		"restoring the tail leaves both joints in place")
	tail_skeleton.free()

	meta_first.free()
	print("ANATOMY_PLACEMENT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
