extends Node
## integration: ported from PonyPussyParadise runtime anatomy attachment. One per adult mare,
## including mares added by other mods, persistent across acts. The mesh and textures are tracked
## assets; if they are missing the controller stays empty and every public method is a no-op.

const CLIMAX_FLUID := preload("res://mods/unfplap/anatomy/fluid.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const IDENTITY := preload("res://mods/unfplap/anatomy/identity.gd")
const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")
const SHAPES := preload("res://mods/unfplap/anatomy/shapes.gd")
const ACT := preload("res://mods/unfplap/anatomy/act.gd")
const COAT := preload("res://mods/unfplap/anatomy/coat.gd")
const PLACEMENT := preload("res://mods/unfplap/anatomy/placement.gd")
const APPEARANCE := preload("res://mods/unfplap/anatomy/appearance.gd")
const HEAT := preload("res://mods/unfplap/anatomy/heat.gd")
const CYCLE := preload("res://mods/unfplap/cycle.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

const ASSET_DIR := "res://mods/unfplap/assets/anatomy/"
const WINKING_PATH := ASSET_DIR + "winking.scn"
const MARE_BITS_V2_PATH := ASSET_DIR + "mare_bits_v2.scn"
const TEATS_PATH := ASSET_DIR + "teats.scn"
const STRIP_PATH := ASSET_DIR + "skin_bridge.scn"

const WINKING_REAR_Y := 0.541
const WINKING_REAR_Z := 0.2961

var pony: Node3D
var runtime: Node
var main: Node

var _mesh: MeshInstance3D
## The rig coat's runtime deform and still-zone debug.
var coat: RefCounted
var _mare_bits_path_loaded := ""
var _fluid: Node3D
var _skeleton: Skeleton3D
var _bone_inverse := Transform3D.IDENTITY
## Saved placement, missionary trims and the debug nudge path.
var placement: RefCounted
## The tail dock mesh; with genitals attached it reads as a stray blob above the ponut.
var _dock: MeshInstance3D
var _dock_was_visible := true
## Persistent shape state: closing/winking, the grip solve, Anon's shaft mask and the V2 anal
## keys. The controller forwards its public shape API.
var shapes: RefCounted
## The current act handle; created here and freed with this controller.
var _act: Node
## Material, skin tones, teats and the skin strip.
var appearance: RefCounted
var _missing_logged := false
var _rig_logged := false
var _attached := false
## integration: visibility is polled, not rewritten every frame, and act-only can hide it.
const VISIBILITY_POLL_S := 0.2
const IDLE_FLUID_COLOR := Color(0.9, 0.93, 1.0, 0.72)
## Idle heat discharge: droplets leave the vulva opening along the ground and fall under the
## fluid node's gravity. Speed and count scale with the Discharge debug setting; the vertical
## speed is the Fluid Y speed setting.
const IDLE_FLUID_SPEED := 0.9
## Ignore the body ellipsoid for this long after a discharge spawn, so a drop leaving the vulva
## flies instead of sticking to the rump and creeping down to the tail.
const IDLE_FLUID_CLEAR_S := 0.2
var _visibility_clock := 0.0
var _visibility_init := false
var _last_shown := false
var _last_teats_shown := false
var _last_strip_shown := false
## Idle heat schedule; the controller supplies state, visibility and the cycle phase.
var heat: RefCounted


static func assets_exist() -> bool:
	return ResourceLoader.exists(WINKING_PATH) and ResourceLoader.exists(TEATS_PATH) \
		and ResourceLoader.exists(STRIP_PATH)


## integration: the V2 model is optional; fall back to the original PPP mesh when absent.
static func selected_mare_bits_path() -> String:
	if SETTINGS.mare_bits.get_choice() == "v2" \
			and ResourceLoader.exists(MARE_BITS_V2_PATH):
		return MARE_BITS_V2_PATH
	return WINKING_PATH


## The pure mesh rebuild and geometry live in `anatomy/geometry.gd`; these forwarders keep the
## static anatomy surface stable while the system is split.
static func refined_winking_mesh(source: ArrayMesh) -> ArrayMesh:
	return GEOMETRY.refined_winking_mesh(source)


## integration: every adult mare gets anatomy, including mares added by other mods. The identity
## filly/stallion flags are the age gate, the player's own pony never gets it, and the pony needs a
## stable id for the per-mare placement. The base-game preference roster is not a whitelist.
static func eligible(pony_node: Node3D) -> bool:
	if not is_instance_valid(pony_node):
		return false
	var player_pony := pony_node.name == "PlayerPony" or is_instance_valid(pony_node.get("rig"))
	return IDENTITY.eligible(pony_node.get("identity"), player_pony, pony_id(pony_node))


## The mod's stable id for a pony: relationship metadata first, then the identity. This mirrors
## `runtime._read_id()` so placement and preferences key off the same value.
static func pony_id(pony_node: Node) -> String:
	if not is_instance_valid(pony_node):
		return ""
	return IDENTITY.id_for(str(pony_node.get_meta("relationship_id", "")),
		pony_node.get("identity"))


## The princess body scale and placement anchor for a known character.
static func body_profile(identity: Variant) -> Array:
	return IDENTITY.body_profile(identity)


## Live adult mares outside the base roster, for the Characters selector. Deduplicated ids out;
## the caller owns the live-pony source and ordering.
static func off_roster_ids(ponies: Array, base_ids: Array) -> Array[String]:
	var ids: Array[String] = []
	for pony: Variant in ponies:
		if pony is Node3D and eligible(pony as Node3D):
			ids.append(pony_id(pony as Node))
	return IDENTITY.off_roster_ids(ids, base_ids)


func _init() -> void:
	shapes = SHAPES.new()
	shapes.setup(null, self)
	coat = COAT.new()
	coat.setup(null, shapes)
	heat = HEAT.new()
	heat.setup(shapes)
	placement = PLACEMENT.new()


func setup(pony_node: Node3D, runtime_node: Node) -> void:
	pony = pony_node
	runtime = runtime_node
	main = runtime.get("main") if is_instance_valid(runtime) else null
	shapes.setup(pony, self)
	coat.setup(pony, shapes)
	placement.setup(pony)
	appearance = APPEARANCE.new()
	appearance.setup(pony, runtime, main, shapes)


## Create the per-act controller for `pose_id`. The controller owns it until `end_act()`.
func begin_act(pose_id: String) -> Node:
	end_act()
	_act = ACT.new()
	_act.name = "UnfplapAnatomyAct"
	add_child(_act)
	_act.call("setup", runtime, main, pony, self, pose_id)
	return _act


func end_act() -> void:
	if is_instance_valid(_act):
		_act.call("end")
		_act.call("teardown")
		_act.queue_free()
	_act = null


func act() -> Node:
	return _act


func refresh() -> void:
	if not _enabled() or not eligible(pony):
		detach()
		return
	if not assets_exist():
		if not _missing_logged:
			_missing_logged = true
			_log("anatomy assets missing under %s; anatomy stays off" % ASSET_DIR)
		return
	_attach()


func _enabled() -> bool:
	return SETTINGS.anatomy_on()


func _attach() -> void:
	if _attached:
		apply_live()
		return
	if not is_instance_valid(pony):
		return
	var skeleton: Variant = pony.get("skeleton")
	if not skeleton is Skeleton3D:
		if not _rig_logged:
			_rig_logged = true
			_log("anatomy skipped for %s: no skeleton" % pony.name)
		return
	_skeleton = skeleton as Skeleton3D
	var bone := _skeleton.find_bone("pony_hips")
	if bone < 0:
		if not _rig_logged:
			_rig_logged = true
			_log("anatomy skipped for %s: no pony_hips bone" % pony.name)
		return
	var selected := selected_mare_bits_path()
	var scene: PackedScene = load(selected)
	if scene == null:
		return
	var instance: Node = scene.instantiate()
	var mesh: MeshInstance3D = instance as MeshInstance3D
	if mesh == null:
		for child: Node in instance.find_children("*", "MeshInstance3D", true, false):
			mesh = child as MeshInstance3D
			break
	if mesh == null:
		instance.queue_free()
		return
	mesh.owner = null
	if mesh.get_parent() != null:
		mesh.get_parent().remove_child(mesh)
	if instance != mesh:
		instance.queue_free()
	mesh.name = "UnfplapAnatomy"
	var anchor := BoneAttachment3D.new()
	anchor.name = "UnfplapAnatomyAnchor"
	anchor.bone_name = "pony_hips"
	_skeleton.add_child(anchor)
	anchor.add_child(mesh)
	_bone_inverse = _skeleton.get_bone_global_rest(bone).affine_inverse()
	_mesh = mesh
	_mare_bits_path_loaded = selected
	var is_v2 := selected == MARE_BITS_V2_PATH
	var refined := refined_winking_mesh(mesh.mesh as ArrayMesh)
	if refined != null:
		mesh.mesh = refined
	var identity: Variant = pony.get("identity")
	placement.set_mesh(mesh, _bone_inverse, body_profile(identity))
	placement.load()
	var dock := pony.find_child("OpenPonyDock", true, false) as MeshInstance3D
	_dock = dock
	if is_instance_valid(dock):
		_dock_was_visible = dock.visible
	placement.apply(_missionary_pose(), _pose_depth(), _bed_frame())
	shapes.set_mesh(_mesh, is_v2)
	coat.set_mesh(_mesh, _skeleton)
	appearance.set_mesh(_mesh, _skeleton)
	appearance.attach_parts()
	appearance.apply_material(_missionary_pose())
	_attached = true
	_visibility_init = false
	if pony.has_signal("physical_reaction") \
			and not pony.physical_reaction.is_connected(_on_physical_reaction):
		pony.physical_reaction.connect(_on_physical_reaction)
	set_process(true)
	_apply_visibility()
	_log("anatomy attached lift=%.3f" % PLACEMENT.LIFT)
	if shapes != null and bool(shapes.v2_anal()) and _mesh.mesh is ArrayMesh:
		var arrays: Array = (_mesh.mesh as ArrayMesh).surface_get_arrays(0)
		var cols: Variant = arrays[Mesh.ARRAY_COLOR]
		var a1 := 0
		var a05 := 0
		if cols != null:
			for c: Color in cols:
				if c.a > 0.9:
					a1 += 1
				elif c.a > 0.4:
					a05 += 1
		_log("V2 colour mask a1=%d a05=%d path=%s" % [a1, a05, _mare_bits_path_loaded])


## A stock flank smack (outside the act) never reaches the runtime's thrust/smack path, and
## FlankTouch does not recognise the mod-owned near-body shader. Re-add the targets when she is
## slapped so the near body and its outline wobble too.
func _on_physical_reaction(kind: String) -> void:
	if kind != "flank_smack":
		return
	if is_instance_valid(runtime) and runtime.has_method("_attach_body_coat_jiggle_target"):
		runtime.call("_attach_body_coat_jiggle_target")


func _process(delta: float) -> void:
	_heat_idle_tick(delta)
	coat.tick_debug()
	placement.tick(_missionary_pose(), _pose_depth(), _bed_frame())
	_visibility_clock -= delta
	if _visibility_clock > 0.0:
		return
	_visibility_clock = VISIBILITY_POLL_S
	_apply_place()
	shapes.refresh_anal()
	_apply_body_coat()
	if appearance != null:
		appearance.apply_strip_scale()
	var started := Time.get_ticks_usec()
	_apply_visibility()
	if is_instance_valid(runtime) and runtime.has_method("perf_note"):
		runtime.call("perf_note", "anatomy_visibility", Time.get_ticks_usec() - started)


## integration: the visibility pill. `act` shows her only during the act's states: POSING_IN,
## ACTIVE, CLIMAX and AFTERGLOW.
func _act_visible() -> bool:
	match SETTINGS.anatomy_mode.get_choice():
		"always":
			return true
		"act":
			if not is_instance_valid(runtime):
				return true
			return int(runtime.get("state")) in [1, 2, 3, 4]
	return false


func _apply_visibility() -> void:
	if not _attached or not is_instance_valid(pony):
		return
	var far := bool(pony.get("_far_mesh_shown")) if pony.get("_far_mesh_shown") != null else false
	var teats_on := SETTINGS.teats.get_bool()
	var strip_on := SETTINGS.skin_strip.get_bool()
	var show := not far and _act_visible()
	var teats_show := show and teats_on
	var strip_show := show and strip_on
	if _visibility_init and show == _last_shown and teats_show == _last_teats_shown \
			and strip_show == _last_strip_shown:
		return
	_visibility_init = true
	_last_shown = show
	_last_teats_shown = teats_show
	_last_strip_shown = strip_show
	if is_instance_valid(_mesh):
		_mesh.visible = show
	_apply_dock(show)
	if appearance != null:
		appearance.apply_visibility(show, teats_on, strip_on)


func _heat_idle_tick(delta: float) -> void:
	if not _attached or not is_instance_valid(runtime) or not is_instance_valid(pony) \
			or heat == null:
		return
	heat.tick(delta, int(runtime.get("state")), _heat_visible(),
		Callable(self, "_cycle_phase_now"), Callable(self, "idle_discharge"))


func _cycle_phase_now() -> String:
	if is_instance_valid(runtime) and runtime.has_method("cycle_phase"):
		return str(runtime.call("cycle_phase"))
	return CYCLE.NORMAL


## How open she rests between winks, from the Heat debug settings.
func _heat_rest_open() -> float:
	return float(heat.rest_open()) if heat != null else 0.0


## True when the mesh is actually shown. Far meshes and act-only hiding both skip idle display.
func _heat_visible() -> bool:
	return _last_shown and is_instance_valid(_mesh) and not bool(
		pony.get("_far_mesh_shown") if pony.get("_far_mesh_shown") != null else false)


## The dock is a skinned mesh, so hiding it is the only reliable way to stop it reading as a
## stray blob above the ponut once the anatomy is visible.
func _apply_dock(anatomy_shown: bool) -> void:
	if not is_instance_valid(_dock):
		return
	if not anatomy_shown:
		_dock.visible = _dock_was_visible
		return
	# A dock the game hid before anatomy attached (the princesses' fitted body hides it) stays
	# hidden: the anatomy must not re-show a dock the body art does not use.
	_dock.visible = _dock_was_visible and SETTINGS.show_dock.get_bool()


## The calibrated lift used by every mare. The dock/tail base is not a reliable reference: some
## tails (Derpy's) sit lower and pulled the whole anatomy into the rump. Keep one value so the
## anatomy's size and position are identical across mares; the Show tail docks switch only hides or
## shows the dock and never moves the anatomy.
func _tail_lift() -> float:
	return PLACEMENT.LIFT


## The act-only placement trim. The lying missionary pose tilts her pelvis, so the rigged vulva can
## sit a little high/low or face the wrong way; these values move only the anatomy mesh.
func _missionary_pose() -> bool:
	return is_instance_valid(runtime) and str(runtime.get("pose_id")) == CATALOG.MISSIONARY


func _pose_depth() -> float:
	if not is_instance_valid(runtime):
		return 0.0
	var value: Variant = runtime.get("depth")
	return clampf(float(value), 0.0, 1.0) if value is float or value is int else 0.0


func _bed_frame() -> Variant:
	return runtime.get("_bed_pose_frame") if is_instance_valid(runtime) else null


func _apply_place() -> void:
	placement.apply(_missionary_pose(), _pose_depth(), _bed_frame())


func _apply_material() -> void:
	if appearance != null:
		appearance.apply_material(_missionary_pose())


static func body_local_point(bind: Transform3D, mesh_transform: Transform3D,
		point: Vector3) -> Vector3:
	return GEOMETRY.body_local_point(bind, mesh_transform, point)


static func body_local_direction(bind: Transform3D, mesh_transform: Transform3D,
		direction: Vector3) -> Vector3:
	return GEOMETRY.body_local_direction(bind, mesh_transform, direction)


## Body-local radius of the visible anal cup's still zone.
static func anal_still_radius_for(lip: float, outer_factor: float, scale: float,
		multiplier: float) -> float:
	return GEOMETRY.anal_still_radius_for(lip, outer_factor, scale, multiplier)


func is_attached() -> bool:
	return _attached


## The visible rig coat and its outline. The runtime uses these to put the runtime-patched
## materials back into FlankTouch's jiggle target list.
func body_coat_mesh() -> MeshInstance3D:
	return coat.body_mesh() if coat != null else null


func body_coat_material() -> ShaderMaterial:
	return coat.body_material() if coat != null else null


func body_outline_material() -> ShaderMaterial:
	return coat.body_outline_material() if coat != null else null


func _apply_body_coat_uniforms() -> void:
	coat.apply()


## integration: the ponut and vulva are on the pony body, not the genitals overlay. The rig
## coat (MareBody) is the visible one; NearBody is only the cutie-mark merge.
func _apply_body_coat() -> void:
	coat.apply()


func _restore_body_coat() -> void:
	coat.restore()


func _debug_zones_tick() -> void:
	coat.tick_debug()


## integration: a mesh modelled on the shared mare body and skinned with her own weights.
func apply_live() -> void:
	if not _attached:
		return
	if selected_mare_bits_path() != _mare_bits_path_loaded:
		_reload_mare_bits_mesh()
	if not placement.dirty() and SETTINGS.placement_revision != placement.revision():
		placement.load()
	_apply_material()
	_apply_place()
	shapes.refresh_anal()
	_apply_body_coat()
	_apply_visibility()


## integration: swap the winking mesh in place when the model choice changes. The anchor,
## material override, placement and current shape values stay with the existing mesh node.
func _reload_mare_bits_mesh() -> void:
	if not is_instance_valid(_mesh):
		return
	var selected := selected_mare_bits_path()
	if selected == _mare_bits_path_loaded:
		return
	var scene: PackedScene = load(selected)
	if scene == null:
		return
	var instance: Node = scene.instantiate()
	var source: MeshInstance3D = instance as MeshInstance3D
	if source == null:
		for child: Node in instance.find_children("*", "MeshInstance3D", true, false):
			source = child as MeshInstance3D
			break
	if source == null or source.mesh == null:
		instance.queue_free()
		return
	var refined := refined_winking_mesh(source.mesh as ArrayMesh)
	if refined == null:
		instance.queue_free()
		return
	_mesh.mesh = refined
	_mare_bits_path_loaded = selected
	shapes.set_mesh(_mesh, selected == MARE_BITS_V2_PATH)
	instance.queue_free()


func detach() -> void:
	end_act()
	_attached = false
	if is_instance_valid(pony) and pony.has_signal("physical_reaction") \
			and pony.physical_reaction.is_connected(_on_physical_reaction):
		pony.physical_reaction.disconnect(_on_physical_reaction)
	if coat != null:
		coat.clear_mesh()
	if placement != null:
		placement.clear_mesh()
	_mare_bits_path_loaded = ""
	_visibility_init = false
	set_process(false)
	if is_instance_valid(_fluid):
		_fluid.queue_free()
	_fluid = null
	if appearance != null:
		appearance.clear()
	if shapes != null:
		shapes.clear_mesh()
	if is_instance_valid(_mesh):
		var anchor := _mesh.get_parent()
		_mesh.queue_free()
		_mesh = null
		if is_instance_valid(anchor):
			anchor.queue_free()
	_skeleton = null
	if is_instance_valid(main) and main.has_method("refresh_dock_color"):
		main.call("refresh_dock_color", pony)


func winking_mesh() -> MeshInstance3D:
	return shapes.winking_mesh()


## integration: one persistent fluid node per pony, reused by every act.
func fluid() -> Node3D:
	if not _enabled() or not is_instance_valid(pony):
		return null
	if not is_instance_valid(_fluid):
		_fluid = CLIMAX_FLUID.new()
		_fluid.name = "UnfplapAnatomyFluid"
		_fluid.set("runtime", runtime)
		pony.add_child(_fluid)
	_fluid.set("runtime", runtime)
	_fluid.set("skeleton", pony.get("skeleton"))
	_fluid.set("body_scale",
		float(pony.get("body_scale")) if pony.get("body_scale") != null else 1.0)
	return _fluid


## Idle heat discharge: one or more droplets are shot out of the vulva opening on each wink
## burst. They leave along the ground and the fluid node's gravity pulls them down, so they read
## as discharged rather than dripping from under the tail. The fluid node is persistent, so the
## drops keep their motion and pool on the ground under her.
func idle_discharge(count: int) -> void:
	if not SETTINGS.anatomy_fluid.get_bool():
		return
	if not is_instance_valid(pony) or not pony.is_inside_tree() or not is_instance_valid(_mesh):
		return
	var amount := maxf(SETTINGS.drip.get_num(), 0.0)
	if amount <= 0.0:
		return
	var node := fluid()
	if not is_instance_valid(node):
		return
	node.set("ground_y", pony.global_position.y)
	var shots := maxi(1, int(round(float(count) * amount)))
	node.call("spray", hole_point(0.0), _discharge_direction(), shots,
		IDLE_FLUID_SPEED * amount, maxf(SETTINGS.fluid_size.get_num(), 0.0001),
		IDLE_FLUID_COLOR, IDLE_FLUID_CLEAR_S, SETTINGS.fluid_y_speed.get_num())


## Horizontal direction away from the body. The anatomy mesh's own rear axis is used unless it
## points back into the body; the vertical speed comes from the Fluid Y speed setting.
func _discharge_direction() -> Vector3:
	var rear := hole_rear()
	var out := Vector3(rear.x, 0.0, rear.z)
	if out.length_squared() < 0.000001:
		out = Vector3.BACK
	out = out.normalized()
	if is_instance_valid(pony):
		var away := hole_point(0.0) - pony.global_position
		away.y = 0.0
		if away.length_squared() > 0.000001 and out.dot(away.normalized()) < 0.0:
			out = -out
	return out


func anal_mesh() -> MeshInstance3D:
	return shapes.anal_mesh()


func hole_local(mix: float) -> Vector3:
	return shapes.hole_local(mix)


func hole_point(mix := 0.0) -> Vector3:
	return shapes.hole_point(mix)


func hole_rear(mix := 0.0) -> Vector3:
	return shapes.hole_rear(mix)


func set_closed(value: float) -> void:
	shapes.set_closed(value)


## Idle heat crossfade: 0 is resting closed, 1 is the authored open shape.
func set_idle_wink(amount: float) -> void:
	shapes.set_idle_wink(amount)


func drive(closed: float) -> void:
	shapes.drive(closed)


func animate(target: float, seconds: float) -> void:
	shapes.animate(target, seconds)


func wink(count := 1, seconds := 0.45) -> void:
	shapes.wink(count, seconds)


## Idle heat wink. The shape module owns the tween; `discharge_count` releases the droplets at
## the first beat's peak.
func wink_burst(count: int, discharge_count := -1) -> void:
	shapes.wink_burst(count, discharge_count, _heat_rest_open(),
		Callable(self, "idle_discharge"))
	_apply_body_coat_uniforms()


## Open the lips to the shaft's actual radius. The shape module converts world metres to mesh
## units and applies the hug padding.
func set_grip(shaft_radius: float) -> void:
	shapes.set_grip(shaft_radius, _missionary_pose())
	_apply_body_coat_uniforms()


func set_shaft(pivot: Vector3, axis: Vector3, length: float, radii: PackedFloat32Array) -> void:
	shapes.set_shaft(pivot, axis, length, radii)


func clear_shaft() -> void:
	shapes.clear_shaft()


## The lip band's mean radius in local units, used by the grip solve and by tuning readouts.
func lip_radius() -> float:
	return shapes.lip_radius()


## The pure stability rule lives in `anatomy/geometry.gd`; this forwarder keeps the static
## anatomy surface stable while the system is split.
static func stable_lip_radius(measured: float) -> float:
	return GEOMETRY.stable_lip_radius(measured)


func set_fill(fill: float) -> void:
	shapes.set_fill(fill)


## Drive the V2 anal blend shapes from the real shaft radius.
func set_anal_grip(shaft_radius: float) -> void:
	shapes.set_anal_grip(shaft_radius)


## Kept for the act's call order; the old cup's cut depth is gone and the shape keys do the work.
func set_anal_shape(_fill: float, _wide := 0.0) -> void:
	pass


func react() -> void:
	shapes.react()


func _clear_part() -> void:
	shapes.clear_part()
	_apply_body_coat_uniforms()


## integration: local placement calibration for the debug actions.
func nudge(axis: String, amount: float) -> void:
	placement.nudge(axis, amount)
	_apply_place()


func place_text() -> String:
	return placement.place_text()


func save_place() -> void:
	placement.save()


## Preview the mare's resolved default. Save writes the preview as her override, or removes it
## when it matches the default.
func reset_place() -> void:
	placement.reset()
	_apply_place()


func _log(text: String) -> void:
	if is_instance_valid(runtime) and runtime.has_method("_log"):
		runtime.call("_log", text)
