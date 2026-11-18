extends SceneTree
## integration: anatomy consent, eligibility and placement checks.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/anatomy/test_anatomy.gd

const CONSENT := preload("res://mods/unfplap/shared/consent.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/controller.gd")
const ANATOMY_SERVICE := preload("res://mods/unfplap/anatomy/service.gd")
const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")
const PLACEMENT := preload("res://mods/unfplap/shared/anatomy_placement.gd")
const ANATOMY_PLACEMENT := preload("res://mods/unfplap/anatomy/placement.gd")
const TAIL_SEAT := preload("res://mods/unfplap/anatomy/tail/seat.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const MARE_REGISTRY := preload("res://mods/unfplap/registry/service.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const ANATOMY_ACT := preload("res://mods/unfplap/anatomy/act.gd")
const PLAYER_PART := preload("res://mods/unfplap/anatomy/player.gd")
const COAT_PATCH := preload("res://mods/unfplap/anatomy/body_coat_patch.gd")
const COAT := preload("res://mods/unfplap/anatomy/coat.gd")
const BODY_COAT_SURFACE := preload("res://mods/unfplap/shared/body_coat.gd")
const STILL_ZONES := preload("res://mods/unfplap/anatomy/still_zone_debug.gd")
const FACTS := preload("res://mods/unfplap/anatomy/facts.gd")
const ATTACH := preload("res://mods/unfplap/anatomy/attach.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")

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


class NearCoatPony extends Node3D:
	var _near: Dictionary = {}


class FakeCoatPony extends Node3D:
	var _model: Node3D


class FakeAnatomy extends Node:
	var calls: Array[String] = []

	func _clear_part() -> void:
		calls.append("clear")

	func fluid() -> Node3D:
		return null


## The face-mode anatomy: records the shape drive and returns a live winking mesh. The opening is
## fixed, so the normal opening path's aim and track calls are observable.
class FakeFaceAnatomy extends Node:
	var calls: Array = []
	var mesh: MeshInstance3D
	var opening := Vector3(0.1, 0.2, 0.3)

	func animate(_closed: float, _seconds: float) -> void:
		calls.append(["animate"])

	func winking_mesh() -> Variant:
		return mesh

	func set_fill(value: float) -> void:
		calls.append(["fill", value])

	func set_grip(value: float) -> void:
		calls.append(["grip", value])

	func set_anal_grip(value: float) -> void:
		calls.append(["anal_grip", value])

	func set_shaft(_pivot: Vector3, _axis: Vector3, _length: float, _radii: Array) -> void:
		calls.append(["shaft"])

	func clear_shaft() -> void:
		calls.append(["clear_shaft"])

	func drive(value: float) -> void:
		calls.append(["drive", value])

	func hole_point(_mix: float) -> Vector3:
		return opening

	func hole_rear(_mix: float) -> Vector3:
		return Vector3(0.0, 0.0, 1.0)

	func fluid() -> Node3D:
		return null


## The player part in the face-mode test: the encounter calls are the park/restore proof, and the
## aim/inset setters count any write the parked path must never make.
class FakeFacePart extends Node:
	var encounters: Array[bool] = []
	var showing_state := false
	var aim_normal_writes := 0
	var aim_opening_writes := 0
	var inset_writes := 0
	var aim_pitch_deg := 0.0
	var aim_normal: Vector3 = Vector3.ZERO:
		set(value):
			aim_normal = value
			aim_normal_writes += 1
	var aim_opening: Vector3 = Vector3.ZERO:
		set(value):
			aim_opening = value
			aim_opening_writes += 1
	var bed_inset_m := 0.0:
		set(value):
			bed_inset_m = value
			inset_writes += 1

	func encounter(on: bool) -> void:
		encounters.append(on)
		showing_state = on

	func showing() -> bool:
		return showing_state

	func girth_at(_point: Vector3) -> float:
		return 0.01

	func root_now() -> Vector3:
		return Vector3.INF

	func tip_world() -> Vector3:
		return Vector3.INF

	func tip_center() -> Vector3:
		return Vector3.INF

	func shaft_radii(_count: int) -> Array:
		return []


class FakeFaceService extends Node:
	var tracks := 0
	var part_node: Variant = null

	func part() -> Variant:
		return part_node

	func player_track(_point: Vector3, _rear: Vector3, _up: Vector3, _detached: bool,
			_shown: float, _delta: float, _parent: Variant, _attached: bool) -> void:
		tracks += 1


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


## The face contact parks the part and the vulva: no player track, no aim/inset write, neutral
## fill/grip/anal and a neutral drive. The first opening tick restores the part once and resumes
## the normal shape and aim path; the hole toggle refuses while the face owns the contact.
func _check_face_contact() -> void:
	var anatomy := FakeFaceAnatomy.new()
	root.add_child(anatomy)
	var host := Node3D.new()
	root.add_child(host)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	host.add_child(mesh)
	anatomy.mesh = mesh
	var pony := _pony("twilight_sparkle")
	root.add_child(pony)
	var sk := Skeleton3D.new()
	sk.add_bone("pony_hips")
	pony.add_child(sk)
	pony.skeleton = sk
	var part := FakeFacePart.new()
	root.add_child(part)
	var service := FakeFaceService.new()
	service.part_node = part
	root.add_child(service)
	var act: Node = ANATOMY_ACT.new()
	root.add_child(act)
	act.setup(service, pony, anatomy)
	var view: RefCounted = VIEW.new()
	view.family = "bed"
	view.frame = "bed"
	view.contact_kind = "face"
	view.contact_target = Vector3(0.4, 0.5, 0.6)
	var facts: RefCounted = FACTS.new()
	facts.state = 2
	facts.pose_view = view
	facts.depth = 0.2
	facts.size_scale = 1.0
	facts.penetration_m = 0.1
	facts.penetration_reach = 0.2
	facts.bed_frame = Transform3D.IDENTITY

	act.tick(0.016, facts)
	check(service.tracks == 0, "the face contact never tracks the part")
	check(part.encounters == [false], "the first face tick parts the part once")
	check(part.aim_normal_writes == 0 and part.aim_opening_writes == 0,
		"the face contact writes no aim")
	check(part.inset_writes == 0 and is_zero_approx(part.bed_inset_m),
		"the face contact writes no bed inset")
	var fill := _last_call(anatomy.calls, "fill")
	var grip := _last_call(anatomy.calls, "grip")
	var drive := _last_call(anatomy.calls, "drive")
	check(not fill.is_empty() and is_zero_approx(float(fill[1])),
		"the face contact zeroes the fill")
	check(not grip.is_empty() and is_zero_approx(float(grip[1])),
		"the face contact zeroes the grip")
	check(not _last_call(anatomy.calls, "clear_shaft").is_empty(),
		"the face contact clears the shaft")
	check(not drive.is_empty()
		and is_equal_approx(float(drive[1]), ANATOMY_ACT.WINKING_REST_OPEN),
		"the face contact holds the neutral closed shape")
	check((act.get("_contact_point") as Vector3).is_equal_approx(view.contact_target),
		"the face contact point is the view's target")
	check((act.get("_contact_normal") as Vector3).is_zero_approx(),
		"the face contact carries no normal")

	act.tick(0.016, facts)
	check(part.encounters == [false], "a second face tick does not part the part again")
	check(service.tracks == 0, "the face contact still never tracks the part")
	var holes_on := SETTINGS.anatomy_holes.get_bool()
	SETTINGS.anatomy_holes.set_bool(true)
	act.call("toggle_hole", 2)
	check(not bool(act.get("_anal")), "the hole toggle refuses in the face contact")
	SETTINGS.anatomy_holes.set_bool(holes_on)

	view.contact_kind = "opening"
	view.contact_target = Vector3.INF
	act.tick(0.016, facts)
	check(part.encounters == [false, true], "the first opening tick restores the part once")
	check(not bool(act.get("_face_parted")), "the face flag clears on the opening contact")
	check(service.tracks == 1, "the opening contact resumes the player track")
	check(part.aim_opening_writes >= 1 and part.aim_normal_writes >= 1,
		"the opening contact resumes the aim writes")
	check(part.inset_writes >= 1, "the bed opening contact restores the bed inset")
	fill = _last_call(anatomy.calls, "fill")
	check(not fill.is_empty() and float(fill[1]) > 0.0,
		"the opening contact resumes the fill drive")

	act.call("teardown")
	act.free()
	root.remove_child(service)
	service.free()
	root.remove_child(part)
	part.free()
	root.remove_child(pony)
	pony.free()
	root.remove_child(anatomy)
	anatomy.free()
	root.remove_child(host)
	host.free()


## The last call recorded for a shape/aim name, or an empty array.
func _last_call(calls: Array, name: String) -> Array:
	for i: int in range(calls.size() - 1, -1, -1):
		var row: Variant = calls[i]
		if row is Array and not (row as Array).is_empty() and str((row as Array)[0]) == name:
			return row as Array
	return []


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
	# Consent defaults are deterministic and per-id, and an override wins.
	var a := CONSENT.defaults("twilight_sparkle")
	var b := CONSENT.defaults("twilight_sparkle")
	check(a == b, "consent defaults are deterministic")
	check(a.has("public") and a.has("anal") and a.has("oral"), "consent has all three keys")
	var over := CONSENT.resolve("twilight_sparkle", {"anal": true, "oral": false})
	check(bool(over.get("anal", false)), "consent anal override wins")
	check(not bool(over.get("oral", true)), "consent oral override wins")
	check(bool(CONSENT.resolve("twilight_sparkle", {}).get("public", false))
		== bool(a.get("public", false)), "empty override keeps defaults")
	check(not bool(a.get("public", true)), "no mare is public by default")

	# Eligibility is capability-scoped: the eligibility service answers the anatomy target, and
	# the base-game roster is not an attachment whitelist.
	var host := FakeMain.new()
	root.add_child(host)
	host.eligibility = ELIGIBILITY.new()
	host.eligibility.setup(host)
	var twilight := _pony("twilight_sparkle")
	check(bool(host.eligibility.eligible(twilight, ELIGIBILITY.Target.ANATOMY)),
		"base adult is eligible")
	var off_roster := _pony("not_a_base_mare")
	check(bool(host.eligibility.eligible(off_roster, ELIGIBILITY.Target.ANATOMY)),
		"off-roster adult is eligible")
	var filly := _pony("not_a_base_mare", true)
	check(not bool(host.eligibility.eligible(filly, ELIGIBILITY.Target.ANATOMY)),
		"identity filly is excluded")
	var stallion := _pony("not_a_base_mare", false, true)
	check(not bool(host.eligibility.eligible(stallion, ELIGIBILITY.Target.ANATOMY)),
		"stallion is excluded")
	var no_id := _pony("")
	check(not bool(host.eligibility.eligible(no_id, ELIGIBILITY.Target.ANATOMY)),
		"empty id is excluded")
	var no_identity := FakePony.new()
	check(not bool(host.eligibility.eligible(no_identity, ELIGIBILITY.Target.ANATOMY)),
		"no identity is excluded")
	var player := _pony("twilight_sparkle")
	player.name = "PlayerPony"
	check(not bool(host.eligibility.eligible(player, ELIGIBILITY.Target.ANATOMY)),
		"player pony is excluded")

	# A provider's `eligible` assertion overrides the identity's age flag; the participation block
	# is the anatomy target's veto, and the character target keeps her editable.
	var registered: Dictionary = MARE_REGISTRY.register(1, {
		"id": "provider_filly", "source": "test",
		"eligible": true, "profile": {"participation": {"anatomy": false}},
	})
	check(bool(registered.get("ok", false)), "the provider registers")
	var provider_filly := _pony("provider_filly", true)
	check(bool(host.eligibility.eligible(provider_filly, ELIGIBILITY.Target.CHARACTER)),
		"a provider's eligible assertion attaches a filly")
	check(not bool(host.eligibility.eligible(provider_filly, ELIGIBILITY.Target.ANATOMY)),
		"a participation opt-out blocks the anatomy target")
	MARE_REGISTRY.unregister(1, "provider_filly")

	# The act calls its consent callback with the key alone, so the facade binds the pony before
	# handing it down; the two-argument lookup stays the world-level API.
	var consent_service: Node = ANATOMY_SERVICE.new()
	root.add_child(consent_service)
	consent_service.call("setup", host)
	var consent_pony := _pony("fluttershy")
	root.add_child(consent_pony)
	var consent_controller: Node = consent_service.call("controller_for", consent_pony, null)
	var consent_call: Callable = consent_controller.get("consent")
	check(consent_call.get_argument_count() == 1,
		"the act's consent callback takes the key alone")
	check(bool(consent_call.call("anal")) == bool(SETTINGS.consent("fluttershy").get("anal", false)),
		"the act's consent callback answers for its own pony")
	check(not bool(consent_call.call("nope")), "an unknown consent key is refused")
	consent_service.call("detach_controller", consent_pony)
	root.remove_child(consent_pony)
	consent_pony.free()
	root.remove_child(consent_service)
	consent_service.free()

	# Placement and preferences use the relationship id first; the identity id is the fallback.
	var meta_first := _pony("visual_id")
	meta_first.set_meta("relationship_id", "relationship_id")
	check(ANATOMY.pony_id(meta_first) == "relationship_id", "relationship id wins")
	var placement_id := ANATOMY.new()
	placement_id.placement.set("pony", meta_first)
	check(str(placement_id.placement.call("_pony_id")) == "relationship_id",
		"anatomy placement uses the relationship id")
	placement_id.free()

	# A modded copy of a princess uses the canon body profile; an ordinary modded mare does not.
	var princess_copy := FakeIdentity.new()
	princess_copy.id = "custom_celestia"
	princess_copy.character_id = "celestia"
	check(ANATOMY.body_profile(princess_copy).size() == 3,
		"a modded Celestia copy uses the princess body profile")
	var ordinary_identity := FakeIdentity.new()
	ordinary_identity.id = "not_a_base_mare"
	check(ANATOMY.body_profile(ordinary_identity).is_empty(),
		"an ordinary modded mare uses the normal body profile")
	check(ANATOMY.body_profile(null).is_empty(), "no identity has no body profile")

	# The Characters selector lists only live off-roster mares.
	var live_ids: Array[String] = ANATOMY.off_roster_ids(
		["not_a_base_mare", "twilight_sparkle"], SETTINGS.CHARACTER_ORDER)
	check(live_ids.size() == 1 and live_ids[0] == "not_a_base_mare",
		"the Characters selector lists live off-roster mares")

	var default_place := SETTINGS.anatomy_placement_default("")
	check(near(float(default_place["offset_x"]), 0.0), "global anatomy X is on the crease")
	check(near(float(default_place["offset_y"]), 0.505), "global anatomy Y")
	check(near(float(default_place["offset_z"]), 0.284), "global anatomy Z")
	check(near(float(default_place["pitch_deg"]), 3.0), "global anatomy pitch")
	check(near(float(default_place["scale"]), 0.682), "global anatomy scale")
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
	var rows: Dictionary = seat.get("_rows")
	var off_row: Dictionary = rows.get(rigged, {})
	check(not off_row.is_empty(), "the seat remembers a pony while it is off")
	check(not bool(off_row.get("seated", true)), "the off row is not measured")
	check(not off_row.has("dock"), "the off row caches no dock")
	check(bool(seat.call("can_seat", rigged)), "the seat still reports the pony as seatable")
	seat.call("refresh_all")
	check(rows.has(rigged), "a settings tick with the seat off keeps the remembered pony")
	check((seat.get("_dirty") as Array).is_empty(), "no dock rebuild is queued while off")
	# The settle queue drains without rebuilding a row that was never measured.
	seat.call("_mark_dirty", off_row)
	check((seat.get("_dirty") as Array).size() == 1, "a placement edit queues one dock rebuild")
	seat.call("_flush_dirty")
	check((seat.get("_dirty") as Array).is_empty(), "the settle pass drains the queue")
	SETTINGS.reseat_tails.set_bool(reseat_before)
	rigged.free()
	seat.free()

	var place_pos := Vector3(
		float(default_place["offset_x"]),
		float(default_place["offset_y"]),
		float(default_place["offset_z"]))
	# Dock style is visibility/colour only. The old placement pinned the mesh top to the dock's
	# buried base ring, which dropped a low-docked mare's anatomy by up to 9 cm.
	var place := ANATOMY.new()
	var place_mesh := MeshInstance3D.new()
	place_mesh.mesh = BoxMesh.new()
	place.add_child(place_mesh)
	place.placement.set_mesh(place_mesh, Transform3D.IDENTITY, [])
	place.placement.set("_pos", place_pos)
	place.placement.set("_pitch", float(default_place["pitch_deg"]))
	place.placement.set("_scale", float(default_place["scale"]))
	var dock_before := SETTINGS.dock_style.get_choice()
	SETTINGS.dock_style.set_choice("coat")
	place.call("_apply_place")
	var dock_on: Transform3D = place_mesh.transform
	SETTINGS.dock_style.set_choice("hide")
	place.call("_apply_place")
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
	check(SETTINGS.by_path("presentation.lean_back_m") == null, "back lean setting removed")
	check(ClassDB.class_has_method("XRBodyTracker", "get_has_tracking_data"),
		"VR body tracker API")
	check(not ClassDB.class_has_method("XRBodyTracker", "get_have_tracking_data"),
		"old VR tracker API absent")
	check(not FileAccess.get_file_as_string("res://mods/unfplap/vr/service.gd").contains(
		"get_have_tracking_data"), "VR source uses the engine method")

	# A profile keeps its custom prompts and poses when consent is merged.
	var base: Dictionary = SETTINGS._filled_default()
	var characters := {"twilight_sparkle": {
		"consent": {"anal": true},
		"event_prompts": {"climax": "custom"},
		"poses": {"missionary": {"rump_drop_deg": 12.0}},
	}}
	var profile: Dictionary = SETTINGS.profile_for(base, characters, "twilight_sparkle")
	check(profile.has("consent"), "profile carries consent")
	check(str((profile.get("event_prompts", {}) as Dictionary).get("climax", "")) == "custom",
		"consent merge preserves event prompts")
	check(absf(float(((profile.get("poses", {}) as Dictionary).get("missionary", {}) as Dictionary)
		.get("rump_drop_deg", 0.0)) - 12.0) < 0.001, "consent merge preserves pose overrides")
	# integration: no act controller means all anatomy action gates are closed.
	var runtime: Node = RUNTIME.new()
	check(not bool(runtime.call("anatomy_hole_ready")), "hole gate closed without an act")
	check(not bool(runtime.call("anatomy_oral_ready")), "oral gate closed without an act")
	check(not bool(runtime.call("anatomy_actions_ready")), "all anatomy gates closed without an act")
	# The refresh binds the reactions facade to her node, which is what the standing offer's rump
	# anchor reads. Without it the act-key hint never appears.
	var rump_pony := Node3D.new()
	get_root().add_child(rump_pony)
	runtime.pony = rump_pony
	check(not runtime.call("rump_anchor").is_finite(),
		"no refresh leaves the rump anchor unbound")
	runtime.call("_anatomy_refresh")
	check(runtime.call("rump_anchor").is_finite(),
		"the anatomy refresh binds the reactions scene for the rump anchor")
	get_root().remove_child(rump_pony)
	rump_pony.free()
	runtime.free()

	# A body that hides every mesh under its model without its own marker names that marker on
	# `anatomy_owned_meta`; the anatomy and its parts ride the same skeleton and must carry it.
	var owner_attach: RefCounted = ATTACH.new()
	var owner_pony := Node3D.new()
	var owner_skeleton := Skeleton3D.new()
	var owner_mesh := MeshInstance3D.new()
	owner_mesh.name = "UnfplapAnatomy"
	var owner_part := MeshInstance3D.new()
	owner_part.name = "UnfplapAnatomySkinStrip"
	var owner_body := MeshInstance3D.new()
	owner_body.name = "MareBody"
	owner_skeleton.add_child(owner_mesh)
	owner_skeleton.add_child(owner_part)
	owner_skeleton.add_child(owner_body)
	owner_pony.add_child(owner_skeleton)
	get_root().add_child(owner_pony)
	owner_attach.setup(owner_pony, owner_pony, FACTS.new())
	owner_attach.attached = true
	owner_attach.skeleton = owner_skeleton
	owner_pony.set_meta("anatomy_owned_meta", "chrysalis_own")
	owner_attach.mark_owned()
	check(owner_mesh.has_meta("chrysalis_own"), "the anatomy mesh carries the body marker")
	check(owner_part.has_meta("chrysalis_own"), "an anatomy part carries the body marker")
	check(not owner_body.has_meta("chrysalis_own"), "the body's own mesh is left alone")
	get_root().remove_child(owner_pony)
	owner_pony.free()

	# Idle heat: active act states suppress the display, idle allows it, and a due timer winks.
	var heat_facts := FACTS.new()
	heat_facts.cycle_phase = "heat"
	var heat_anatomy: Node = ANATOMY.new()
	var heat_pony := Node3D.new()
	var wink_mesh := MeshInstance3D.new()
	wink_mesh.mesh = BoxMesh.new()
	heat_anatomy.add_child(wink_mesh)
	get_root().add_child(heat_anatomy)
	heat_anatomy.set_process(false)
	heat_anatomy.set("pony", heat_pony)
	heat_anatomy.set("facts", heat_facts)
	heat_anatomy.attach.setup(heat_anatomy, heat_pony, heat_facts)
	heat_anatomy.attach.attached = true
	heat_anatomy.attach.mesh = wink_mesh
	heat_anatomy.shapes.set_mesh(wink_mesh)
	heat_anatomy.attach.apply_visibility(true)
	heat_facts.state = 2
	heat_anatomy.call("_heat_idle_tick", 0.1)
	check(heat_anatomy.heat.suppressed(), "active act suppresses idle heat")
	heat_facts.state = 0
	heat_anatomy.heat.set("_phase", CYCLE.HEAT)
	heat_anatomy.heat.set("_phase_clock", 999.0)
	heat_anatomy.heat.set("_wink_clock", 0.001)
	heat_anatomy.call("_heat_idle_tick", 0.01)
	var gap_lo := minf(SETTINGS.wink_min_s.get_num(), SETTINGS.wink_max_s.get_num())
	check(heat_anatomy.heat.wink_clock() >= gap_lo,
		"an idle heat wink resets the interval")
	check(heat_anatomy.shapes.tween_running(), "an idle heat wink builds its tween")
	heat_anatomy.set_idle_wink(0.0)
	check(is_equal_approx(float(heat_anatomy.shapes.wink_amount()), 0.0),
		"the default rest clears the wink shape")
	check(is_equal_approx(float(heat_anatomy.shapes.state().get("closed", -1.0)), 1.0),
		"the default rest is the authored closed shape")
	var rest_open := clampf(SETTINGS.heat_rest_open.get_num(), 0.0, 1.0)
	heat_anatomy.set_idle_wink(rest_open)
	check(is_equal_approx(float(heat_anatomy.shapes.wink_amount()), rest_open),
		"heat rests at the configured share of the open shape")
	check(is_equal_approx(float(heat_anatomy.shapes.state().get("closed", -1.0)),
		1.0 - rest_open), "the heat rest opens the closed lips by the same share")
	check(bool(heat_anatomy.shapes.state().get("idle_wink", false)),
		"the idle rest owns the shapes")
	heat_anatomy.drive(0.5)
	check(is_equal_approx(float(heat_anatomy.shapes.wink_amount()), 0.0),
		"acts clear the idle wink shape")
	check(not bool(heat_anatomy.shapes.state().get("idle_wink", true)),
		"an act clears the idle cut suppression")
	heat_anatomy.free()
	heat_pony.free()

	# The V2 mesh's density walk can collapse to the 4 mm floor; keep the authored band.
	check(is_equal_approx(GEOMETRY.stable_lip_radius(0.004), GEOMETRY.WINKING_LIP_RADIUS),
		"a collapsed lip radius falls back to the authored band")
	check(is_equal_approx(GEOMETRY.stable_lip_radius(GEOMETRY.WINKING_LIP_RADIUS),
		GEOMETRY.WINKING_LIP_RADIUS), "the authored lip radius is kept")
	check(is_equal_approx(GEOMETRY.stable_lip_radius(0.030), 0.030),
		"a nearby measured lip radius is kept")

	# The refined mare bits mesh leaves the default resting mesh alone and masks the anal rim out
	# of the authored `closed` shape.
	var wink_scene: PackedScene = load(ANATOMY.MARE_BITS_PATH)
	var wink_root: Node = wink_scene.instantiate()
	var wink_mi := wink_root as MeshInstance3D
	var source_mesh := wink_mi.mesh as ArrayMesh
	var refined_mesh := GEOMETRY.refined_winking_mesh(source_mesh)
	check(refined_mesh != null, "the winking mesh rebuilds")
	if refined_mesh != null:
		check(refined_mesh.get_blend_shape_count() >= 2, "the wink keeps its shape keys")
		check(str(refined_mesh.get_blend_shape_name(0)) == "closed",
			"the closed shape keeps its name")
		check(wink_mi.find_blend_shape_by_name("wink") >= 0,
			"the mare bits mesh has the clitoris wink key")
		var src_base: PackedVector3Array = source_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var src_closed: PackedVector3Array = source_mesh.surface_get_blend_shape_arrays(0)[0][Mesh.ARRAY_VERTEX]
		var ref_base: PackedVector3Array = refined_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var ref_closed: PackedVector3Array = refined_mesh.surface_get_blend_shape_arrays(0)[0][Mesh.ARRAY_VERTEX]
		check(ref_base == src_base, "the default resting mesh is unchanged")
		var anal_index := -1
		for i in src_base.size():
			if src_base[i].y > 0.06 and (src_closed[i] - src_base[i]).length() > 0.001:
				anal_index = i
				break
		check(anal_index >= 0, "an anal rim vertex moves in the source shape")
		if anal_index >= 0:
			check((ref_closed[anal_index] - ref_base[anal_index]).length() < 0.0001,
				"the anal rim no longer winks")
	wink_root.free()

	# The mare bits mesh owns the anal hole: the cup/ring are gone.
	var v2_scene: PackedScene = load(ANATOMY.MARE_BITS_PATH)
	var v2_root: Node = v2_scene.instantiate()
	var v2_mi := v2_root as MeshInstance3D
	var v2_mesh := v2_mi.mesh as ArrayMesh
	check(v2_mesh.get_blend_shape_count() >= 8, "the mare bits mesh keeps its anal keys")
	check(v2_mi.find_blend_shape_by_name("wink") >= 0,
		"the mesh has the clitoris wink key")
	for shape_name: String in ["anal_open", "anal_stretch", "anal_overstretch",
			"anal_extreme", "ponut_scale"]:
		check(v2_mi.find_blend_shape_by_name(shape_name) >= 0,
			"the mesh has the %s key" % shape_name)
	var v2_arrays: Array = v2_mesh.surface_get_arrays(0)
	var v2_colors: Variant = v2_arrays[Mesh.ARRAY_COLOR]
	check(v2_colors != null and (v2_colors as PackedColorArray).size()
		== (v2_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		"the mare bits colours cover every vertex")
	var folds := 0
	var clits := 0
	if v2_colors != null:
		for c: Color in v2_colors:
			if c.a > 0.9:
				folds += 1
			elif c.a > 0.4:
				clits += 1
	check(folds > 500, "the inner folds keep their mask")
	check(clits > 200, "the clitoris keeps its mask")
	get_root().add_child(v2_mi)
	v2_mi.transform = Transform3D.IDENTITY
	var v2_anatomy: Node = ANATOMY.new()
	v2_anatomy.shapes.set_mesh(v2_mi)
	v2_anatomy.shapes.apply_anal_local(0.030)
	var open_i := v2_mi.find_blend_shape_by_name("anal_open")
	var stretch_i := v2_mi.find_blend_shape_by_name("anal_stretch")
	var over_i := v2_mi.find_blend_shape_by_name("anal_overstretch")
	var extreme_i := v2_mi.find_blend_shape_by_name("anal_extreme")
	check(is_equal_approx(v2_mi.get_blend_shape_value(open_i), 1.0),
		"30 mm opens the V2 anus")
	check(is_equal_approx(v2_mi.get_blend_shape_value(stretch_i), 1.0),
		"30 mm reaches the normal V2 stretch")
	check(is_equal_approx(v2_mi.get_blend_shape_value(over_i), 1.0),
		"30 mm reaches the V2 overstretch")
	check(near(v2_mi.get_blend_shape_value(extreme_i), 0.0714, 0.002),
		"30 mm starts the V2 extreme")
	var mouth: Vector3 = v2_anatomy.shapes.anal_mouth()
	check(mouth.y < 0.062 and mouth.y > 0.041,
		"30 mm tracks the V2 ring down from the old cup point")
	v2_anatomy.shapes.apply_anal_local(0.056)
	mouth = v2_anatomy.shapes.anal_mouth()
	check(near(mouth.y, GEOMETRY.V2_ANAL_RING_EXTREME.y, 0.001),
		"56 mm puts the anal aim on the extreme ring")
	var aim: Vector3 = v2_anatomy.call("hole_point", 1.0)
	var aim_offset: Vector3 = v2_mi.global_transform.basis.y.normalized() \
		* (SETTINGS.anal_aim_mm.get_num() / 1000.0)
	check(aim.distance_to(v2_mi.global_transform * GEOMETRY.V2_ANAL_RING_EXTREME
		+ aim_offset) < 0.0001, "the anal act aims at the deformed V2 ring")
	v2_anatomy.shapes.apply_anal_local(0.080)
	check(v2_mi.get_blend_shape_value(extreme_i) > 1.5,
		"an oversized shaft extrapolates the V2 extreme")
	v2_anatomy.free()
	v2_root.free()

	# Climax clears the shape once and arms the wink pulses; the tick keeps driving the hug so
	# the lips stay on the shaft through the climax instead of closing on nothing.
	var anatomy_act: Node = ANATOMY_ACT.new()
	var fake_anatomy := FakeAnatomy.new()
	anatomy_act.anatomy = fake_anatomy
	anatomy_act.on_climax()
	check(fake_anatomy.calls.size() == 1 and fake_anatomy.calls[0] == "clear",
		"climax clears the shape once")
	check(absf(float(anatomy_act.get("_wink_left")) - ANATOMY_ACT.CLIMAX_WINK_S) < 0.001,
		"climax arms the wink pulses")
	anatomy_act.free()
	fake_anatomy.free()

	# The shaped length and head profile are reported from the same values the shader uses.
	var part: Node = PLAYER_PART.new()
	part.set("_part_length_scale", 1.5)
	part.set("_girth_head", 1.5)
	check(absf(float(part.call("_part_length")) - PLAYER_PART.PART_LENGTH * 1.5) < 0.0001,
		"part length scales")
	check(absf(float(part.call("_head_scale_at", 0.0)) - 1.0) < 0.0001,
		"head scale leaves the base alone")
	check(absf(float(part.call("_head_scale_at", 1.0)) - 1.5) < 0.0001,
		"head scale reaches the full glans value")
	part.set("_ready_amount", 1.0)
	part.set("_throb_gain", 1.0)
	part.set("_throb_clock", 0.099)
	part.call("_throb_tick", 0.001, 1.0)
	check(float(part.get("_throb_amount")) > 0.0, "the heartbeat produces a pulse at its peak")
	# The same beat lifts the visible shaft while it is out of her, and the rise dies at full depth.
	part.set("_throb_depth", 0.0)
	part.call("_throb_tick", 0.001, 0.0)
	check(float(part.get("_throb_lift")) > 0.0, "the heartbeat lifts the shaft while it is outside")
	part.set("_throb_depth", 1.0)
	part.call("_throb_tick", 0.001, 1.0)
	check(is_zero_approx(float(part.get("_throb_lift"))), "the upward beat fades at full thrust")
	check(not (part.call("root_now") as Vector3).is_finite(),
		"the player root is invalid before the part mesh is prepared")
	part.free()

	# A closing world removes the player body, and the part under its Hips, from the tree before
	# `world_closed` reaches the facade. That teardown reset must not read or write world
	# transforms, and it still collects the bed holder.
	var detached_host := Node3D.new()
	root.add_child(detached_host)
	var detached_part: Node = PLAYER_PART.new()
	root.add_child(detached_part)
	var detached_mesh := MeshInstance3D.new()
	detached_mesh.mesh = BoxMesh.new()
	detached_mesh.set_surface_override_material(0, ShaderMaterial.new())
	detached_host.add_child(detached_mesh)
	var detached_holder := Node3D.new()
	detached_host.add_child(detached_holder)
	detached_part.set("_mesh", detached_mesh)
	detached_part.set("_bed_holder", detached_holder)
	detached_part.set("_ready_amount", 1.0)
	var detached_place := detached_mesh.transform
	root.remove_child(detached_host)
	check(not bool(detached_part.call("showing")), "a parted-out mesh is not showing")
	check(not (detached_part.call("root_now") as Vector3).is_finite(),
		"a parted-out part reports no root")
	detached_part.call("reset_state")
	check(detached_part.get("_bed_holder") == null, "a parted-out reset collects the bed holder")
	check(detached_mesh.transform.is_equal_approx(detached_place),
		"a parted-out reset leaves the mesh placement alone")
	detached_part.queue_free()
	detached_host.free()

	# A part built on a body that has left the tree is dropped and rebuilt on the current body,
	# so a following act is not handed a mesh that can never be seen.
	var stale_part: Node = PLAYER_PART.new()
	root.add_child(stale_part)
	var stale_host := Node3D.new()
	var stale_mesh := MeshInstance3D.new()
	stale_mesh.mesh = BoxMesh.new()
	stale_host.add_child(stale_mesh)
	stale_part.set("_mesh", stale_mesh)
	var fake_body := Node3D.new()
	var fake_skeleton := Skeleton3D.new()
	fake_skeleton.add_bone("Hips")
	fake_body.add_child(fake_skeleton)
	root.add_child(fake_body)
	stale_part.set("player_body", fake_body)
	check(bool(stale_part.call("prepare")), "a parted-out part rebuilds on the current body")
	var rebuilt: Variant = stale_part.get("_mesh")
	check(rebuilt is MeshInstance3D and rebuilt != stale_mesh
		and (rebuilt as MeshInstance3D).is_inside_tree(),
		"the rebuilt part is a new in-tree mesh")
	var rebuilt_id := (rebuilt as Node).get_instance_id()
	check(bool(stale_part.call("prepare")), "prepare stays true for a built part")
	check((stale_part.get("_mesh") as Node).get_instance_id() == rebuilt_id,
		"prepare is idempotent and keeps the built mesh")
	stale_host.free()
	stale_part.queue_free()
	fake_body.queue_free()

	# Her act wink: quiet at her lips, frequent once a climax has been pulled out of her.
	check(ANATOMY_ACT.wink_mode(0.6, true, 2) == 0, "a thrusting shaft raises no wink")
	check(ANATOMY_ACT.wink_mode(0.0, true, 0) == 1, "the tip at her lips winks on its own")
	check(ANATOMY_ACT.wink_mode(0.0, false, 0) == 0, "a pulled-out shaft waits before any climax")
	check(ANATOMY_ACT.wink_mode(0.1, false, 1) == 2, "a pulled-out shaft after a climax winks often")
	var wink_act: Node = ANATOMY_ACT.new()
	wink_act.call("_start_wink", ANATOMY_ACT.ACT_WINK_S, 1.0)
	check(absf(float(wink_act.get("_wink_left")) - ANATOMY_ACT.ACT_WINK_S) < 0.001,
		"an act wink arms its countdown")
	check(is_equal_approx(float(wink_act.get("_wink_beats")), 1.0), "an act wink is one beat")
	wink_act.call("reset")
	check(is_zero_approx(float(wink_act.get("_wink_left"))), "reset clears the act wink")
	wink_act.free()

	# The generic bind helper maps anatomy-local points into the body's rest space.
	var bind := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.1, 0.2, 0.3))
	var mesh_xf := Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0.0, 0.55, 0.29))
	var point := Vector3(0.01, -0.02, 0.03)
	var local := GEOMETRY.body_local_point(bind, mesh_xf, point)
	check((mesh_xf.affine_inverse() * (bind * local)).is_equal_approx(point),
		"body-local point round-trips through the bind pose")
	var local_dir := GEOMETRY.body_local_direction(bind, mesh_xf, Vector3.BACK)
	check(absf(local_dir.length() - 1.0) < 0.0001, "body-local direction stays unit length")

	# The rig coat patch only replaces the flank_jiggle include and one call; a shader without
	# those hooks is left alone instead of being half-patched.
	check(bool(SETTINGS.body_coat_deform.default), "body coat deform is on by default")
	check(near(float(SETTINGS.coat_hole.default), 0.7),
		"the coat hole uses 70% of the lip radius across by default")
	check(float(SETTINGS.coat_hole_height.default) > float(SETTINGS.coat_hole.default),
		"the coat hole is a taller-than-wide ellipse by default")
	check(near(float(SETTINGS.coat_hole_depth_mm.default), 30.0),
		"the coat hole reaches 30 mm behind the opening by default")
	check(near(float(SETTINGS.anal_still.default), 0.0), "anal still zone is off by default")
	check(near(float(SETTINGS.still_oval.default), 1.5),
		"still zones are taller than they are wide")
	check(near(float(SETTINGS.still_fade.default), 0.3),
		"still zones fade over 0.3 of their radius")
	check(near(float(SETTINGS.still_height_mm.default), 25.0),
		"the vulva still zone sits 25 mm above the opening by default")
	check(not bool(SETTINGS.draw_still_zones.default), "still-zone debug rings are off by default")
	var zones := STILL_ZONES.new()
	root.add_child(zones)
	zones.call("setup")
	check(zones.get_child_count() == 4, "four debug rings are built")
	zones.call("update", Transform3D.IDENTITY, Vector3.ZERO, Basis.IDENTITY, 0.1,
		Vector3(0.0, 0.1, 0.0), 0.05, 0.7, 0.25, true)
	check(zones.visible, "debug rings show when asked")
	var outer: MeshInstance3D = zones.get_child(0)
	check(outer.global_transform.basis.get_scale().is_equal_approx(Vector3(0.1, 0.07, 0.1)),
		"the outer ring is the oval ellipsoid")
	zones.call("update", Transform3D.IDENTITY, Vector3.ZERO, Basis.IDENTITY, 0.1,
		Vector3(0.0, 0.1, 0.0), 0.05, 0.7, 0.25, false)
	check(not zones.visible, "debug rings hide when asked")
	zones.free()
	var expected_radius := maxf(0.022 * 2.2 * 1.3, 0.045 / 0.742)
	check(near(GEOMETRY.anal_still_radius_for(0.022, 2.2, 0.742, 1.0, 0.0),
		expected_radius), "anal still radius follows the cup's outer ring")
	check(is_zero_approx(GEOMETRY.anal_still_radius_for(0.022, 2.2, 0.742, 0.0, 0.0)),
		"anal still multiplier 0 disables the zone")
	# The controller keeps the coat accessors the runtime uses for the jiggle handoff.
	var coat_owner := ANATOMY.new()
	for method: String in ["is_attached", "body_coat_mesh", "body_coat_material",
			"body_outline_material", "body_coat_targets"]:
		check(coat_owner.has_method(method), "the controller exposes %s" % method)
	check(not bool(coat_owner.call("is_attached")), "a fresh controller is not attached")
	coat_owner.free()

	# A despawned body can already have no surfaces; clearing the coat must not index surface 0.
	var thin_body := MeshInstance3D.new()
	thin_body.mesh = ArrayMesh.new()
	var thin_coat := COAT.new()
	thin_coat.set("_body_mesh", thin_body)
	thin_coat.set("_body_material", ShaderMaterial.new())
	thin_coat.call("clear_mesh")
	check(true, "a surface-less coat clear completes")
	thin_body.free()

	# A normal surface still loses its override on clear.
	var real_body := MeshInstance3D.new()
	real_body.mesh = BoxMesh.new()
	real_body.set_surface_override_material(0, ShaderMaterial.new())
	var real_coat := COAT.new()
	real_coat.set("_body_mesh", real_body)
	real_coat.set("_body_material", ShaderMaterial.new())
	real_coat.call("clear_mesh")
	check(real_body.get_surface_override_material(0) == null,
		"the coat clear removes the surface override")
	real_body.free()

	# The drawn coat: a source body that hides the game MareBody still resolves its visible
	# coat, and the game body wins while it is visible.
	var coat_shader := Shader.new()
	coat_shader.code = "shader_type spatial;\n" \
		+ "#include \"res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc\"\n" \
		+ "void vertex() { VERTEX += flank_jiggle(VERTEX); }\n"
	var coat_material := ShaderMaterial.new()
	coat_material.shader = coat_shader
	var coat_mesh := ArrayMesh.new()
	var coat_arrays := []
	coat_arrays.resize(Mesh.ARRAY_MAX)
	coat_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	coat_arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	coat_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, coat_arrays)
	coat_mesh.surface_set_material(0, coat_material)
	var coat_model := Node3D.new()
	get_root().add_child(coat_model)
	var hidden_game_body := MeshInstance3D.new()
	hidden_game_body.name = "MareBody"
	hidden_game_body.mesh = coat_mesh
	hidden_game_body.visible = false
	coat_model.add_child(hidden_game_body)
	var source_body := MeshInstance3D.new()
	source_body.name = "ChrysalisBody"
	source_body.mesh = coat_mesh
	coat_model.add_child(source_body)
	var coat_pony := FakeCoatPony.new()
	coat_pony._model = coat_model
	var drawn := BODY_COAT_SURFACE.resolve(coat_pony)
	check(drawn.get("mesh") == source_body,
		"a hidden game body falls back to the drawn source coat")
	check(int(drawn.get("surface", -1)) == 0, "the drawn coat surface is found")
	hidden_game_body.visible = true
	var drawn_game := BODY_COAT_SURFACE.resolve(coat_pony)
	check(drawn_game.get("mesh") == hidden_game_body, "a visible game body is the drawn coat")
	coat_pony.free()
	coat_model.queue_free()

	var patch_source := Shader.new()
	patch_source.code = "shader_type spatial;\n" \
		+ "#include \"includes/base-cel-shader.gdshaderinc\"\n" \
		+ "#include \"res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc\"\n" \
		+ "void vertex() { VERTEX += flank_jiggle(VERTEX); }\n" \
		+ "void fragment() { ALBEDO = vec3(1.0); }"
	var patched := COAT_PATCH.patched(patch_source)
	check(patched != null, "the coat shader patch finds its two required hooks")
	if patched != null:
		check(patched.code.contains("body_coat_deform.gdshaderinc"),
			"the patch swaps the include")
		check(patched.code.contains("body_coat_deform(VERTEX)"),
			"the patch swaps the deform call")
		check(patched.code.contains(
			"body_coat_vertex = (body_coat_anatomy_inverse * vec4(VERTEX, 1.0)).xyz;"),
			"the patch records the anatomy-local coat position")
		check(patched.code.contains("body_coat_vulva_cut(body_coat_vertex)"),
			"the patch cuts the coat inside the vulva opening")
		check(patched.code.contains("res://addons/cel-shader/includes/base-cel-shader.gdshaderinc"),
			"the patch makes the cel includes absolute")
	var no_fragment := Shader.new()
	no_fragment.code = "shader_type spatial;\n" \
		+ "#include \"res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc\"\n" \
		+ "void vertex() { VERTEX += flank_jiggle(VERTEX); }"
	var deform_only := COAT_PATCH.patched(no_fragment)
	check(deform_only != null and deform_only.code.contains("body_coat_deform(VERTEX)"),
		"a shader without a fragment hook still gets the coat deform")
	check(deform_only == null or not deform_only.code.contains("body_coat_vulva_cut"),
		"a shader without a fragment hook leaves the vulva cut out")
	var near_source := Shader.new()
	near_source.code = "shader_type spatial;\n" \
		+ "const int ENTRIES = 32;\n" \
		+ "varying flat int pal;\n" \
		+ "#include \"res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc\"\n" \
		+ "uniform float jiggle_entry[ENTRIES];\n" \
		+ "void vertex() { pal = 0; VERTEX += flank_jiggle(VERTEX) * jiggle_entry[pal]; }\n" \
		+ "void fragment() { ALBEDO = vec3(1.0); }"
	var near_patched := COAT_PATCH.patched(near_source)
	check(near_patched != null, "the near palette shader patch finds its hooks")
	if near_patched != null:
		check(near_patched.code.contains("uniform float body_coat_entry[ENTRIES];"),
			"the near patch adds the body entry mask")
		check(near_patched.code.contains("body_coat_deform(body_coat_posed)"),
			"the near patch swaps in the coat deform")
		check(near_patched.code.contains("body_coat_vulva_cut(body_coat_vertex)"),
			"the near patch cuts the body entry")
		check(near_patched.code.contains(
			"body_coat_entry[pal] > 0.5 && body_coat_vulva_cut(body_coat_vertex)"),
			"the near cut is gated on the body palette entry")
	var unpatched := Shader.new()
	unpatched.code = "shader_type spatial;"
	check(COAT_PATCH.patched(unpatched) == null, "a shader without the hooks is left alone")
	var game_body: Shader = load("res://addons/cel-shader/cel-shader-base.gdshader")
	var game_near: Shader = load("res://world/characters/hybrid_mare/near_pony.gdshader")
	var game_near_occlusion: Shader = load(
		"res://world/characters/hybrid_mare/near_pony_occlusion.gdshader")
	var game_near_outline: Shader = load(
		"res://world/characters/hybrid_mare/near_pony_outline.gdshader")
	check(COAT_PATCH.patched(game_body) != null, "the real body shader patches")
	check(COAT_PATCH.patched(game_near) != null, "the real near pony shader patches")
	var compiled := ShaderMaterial.new()
	for source: Shader in [game_body, game_near, game_near_occlusion, game_near_outline]:
		var real_patch := COAT_PATCH.patched(source)
		check(real_patch != null, "the real coat shader compiles")
		if real_patch != null:
			compiled.shader = real_patch
	for setting in [SETTINGS.anal_body_depth_mm, SETTINGS.coat_spread, SETTINGS.coat_hole,
			SETTINGS.coat_hole_height, SETTINGS.coat_hole_depth_mm, SETTINGS.jiggle_still,
			SETTINGS.anal_still, SETTINGS.still_oval, SETTINGS.still_fade,
			SETTINGS.still_height_mm]:
		check(setting.low <= -1000.0 and setting.high >= 1000.0,
			"%s is an unbounded debug row" % setting.name)

	var near_pony := NearCoatPony.new()
	root.add_child(near_pony)
	var near_body := MeshInstance3D.new()
	near_body.name = "MareBody"
	near_pony.add_child(near_body)
	var near_head := MeshInstance3D.new()
	near_head.name = "Head"
	near_pony.add_child(near_head)
	var near_mesh := MeshInstance3D.new()
	near_pony.add_child(near_mesh)
	var near_coat_source := Shader.new()
	near_coat_source.code = "shader_type spatial;\n" \
		+ "const int ENTRIES = 32;\n" \
		+ "varying flat int pal;\n" \
		+ "#include \"res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc\"\n" \
		+ "uniform float jiggle_entry[ENTRIES];\n" \
		+ "void vertex() { pal = 0; VERTEX += flank_jiggle(VERTEX) * jiggle_entry[pal]; }\n" \
		+ "void fragment() { ALBEDO = vec3(1.0); }"
	var palette := ShaderMaterial.new()
	palette.shader = near_coat_source
	var hull := ShaderMaterial.new()
	hull.shader = near_coat_source
	palette.next_pass = hull
	var entries := [[near_pony.get_path_to(near_body), 0],
		[near_pony.get_path_to(near_head), 0]]
	near_pony._near = {"groups": [{"mi": near_mesh,
		"group": {"variants": {"full": {"outputs": [{"entries": entries}]}}},
		"built": {"full": {"materials": [palette]}}}]}
	var near_coat := COAT.new()
	near_coat.setup(near_pony, null)
	near_coat.set("_body_mesh", near_body)
	near_coat.set("_body_patched", true)
	near_coat.call("_refresh_near")
	check(palette.shader != near_coat_source and hull.shader != near_coat_source,
		"the merged near body and outline are patched")
	var near_mask: Variant = palette.get_shader_parameter("body_coat_entry")
	check(near_mask is PackedFloat32Array and (near_mask as PackedFloat32Array).size() == 32,
		"the near palette gets a full body-entry mask")
	if near_mask is PackedFloat32Array:
		var mask := near_mask as PackedFloat32Array
		check(mask[0] > 0.5 and mask[1] < 0.5,
			"only the MareBody palette entry gets the coat deform")
	near_coat.call("restore")
	check(palette.shader == near_coat_source and hull.shader == near_coat_source,
		"the near palette shaders restore exactly")
	near_pony.free()

	_check_face_contact()

	for pony: Node in [twilight, filly, stallion, off_roster, no_id, no_identity, player,
			meta_first]:
		if is_instance_valid(pony):
			pony.free()
	print("ANATOMY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
