extends Node
## integration: ported from PonyPussyParadise runtime anatomy attachment. One per adult mare,
## including mares added by other mods, persistent across acts. The mesh and textures are tracked
## assets; if they are missing the controller stays empty and every public method is a no-op.

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const IDENTITY := preload("res://mods/unfplap/anatomy/identity.gd")
const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")
const SHAPES := preload("res://mods/unfplap/anatomy/shapes.gd")
const ACT := preload("res://mods/unfplap/anatomy/act.gd")
const COAT := preload("res://mods/unfplap/anatomy/coat.gd")
const PLACEMENT := preload("res://mods/unfplap/anatomy/placement.gd")
const APPEARANCE := preload("res://mods/unfplap/anatomy/appearance.gd")
const HEAT := preload("res://mods/unfplap/anatomy/heat.gd")
const FACTS := preload("res://mods/unfplap/anatomy/facts.gd")
const ATTACH := preload("res://mods/unfplap/anatomy/attach.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

const ASSET_DIR := "res://mods/unfplap/assets/anatomy/"
const WINKING_PATH := ASSET_DIR + "winking.scn"
const MARE_BITS_V2_PATH := ASSET_DIR + "mare_bits_v2.scn"
const TEATS_PATH := ASSET_DIR + "teats.scn"
const STRIP_PATH := ASSET_DIR + "skin_bridge.scn"

var pony: Node3D
## The typed runtime context. The controller never reads the runtime node.
var facts: RefCounted
## The anatomy facade's dock-colour refresh. Called after attach/detach/tone changes.
var dock_refresh := Callable()
## The anatomy facade and its host callbacks for the act handle.
var service: Node
var consent := Callable()
var status := Callable()

## The persistent mesh/anchor/dock/fluid/visibility attachment.
var attach: RefCounted
## The rig coat's runtime deform and still-zone debug.
var coat: RefCounted
## Saved placement, missionary trims and the debug nudge path.
var placement: RefCounted
## Persistent shape state: closing/winking, the grip solve, Anon's shaft mask and the V2 anal
## keys. The controller forwards its public shape API.
var shapes: RefCounted
## The current act handle; created here and freed with this controller.
var _act: Node
## Material, skin tones, teats and the skin strip.
var appearance: RefCounted
var _missing_logged := false
var _rig_logged := false
## integration: visibility is polled, not rewritten every frame, and act-only can hide it.
var _visibility_clock := 0.0
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
	facts = FACTS.new()
	attach = ATTACH.new()
	attach.setup(self, null, facts)
	shapes = SHAPES.new()
	shapes.setup(null, self)
	coat = COAT.new()
	coat.setup(null, shapes)
	heat = HEAT.new()
	heat.setup(shapes)
	placement = PLACEMENT.new()


func setup(pony_node: Node3D, facts_node: RefCounted, service_node: Node = null,
		consent_callable := Callable(), status_callable := Callable(),
		dock_refresh_callable := Callable()) -> void:
	pony = pony_node
	set_facts(facts_node)
	service = service_node
	consent = consent_callable
	status = status_callable
	dock_refresh = dock_refresh_callable
	attach.setup(self, pony, facts)
	shapes.setup(pony, self)
	coat.setup(pony, shapes)
	placement.setup(pony)
	appearance = APPEARANCE.new()
	appearance.setup(pony, shapes, dock_refresh, facts.perf_note)


## Replace the runtime context. The facade calls this when the controller is created; tests can
## build a bare context without a runtime.
func set_facts(facts_node: RefCounted) -> void:
	facts = facts_node if facts_node != null else FACTS.new()
	if attach != null:
		attach.facts = facts
	if appearance != null:
		appearance.set_perf(facts.perf_note)


## Create the per-act controller for `pose_id`. The controller owns it until `end_act()`.
func begin_act(pose_id: String) -> Node:
	end_act()
	_act = ACT.new()
	_act.name = "UnfplapAnatomyAct"
	add_child(_act)
	_act.call("setup", service, pony, self, pose_id, consent, status)
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
	if is_attached():
		apply_live()
		return
	if not is_instance_valid(pony):
		return
	var selected := selected_mare_bits_path()
	if not attach.attach(selected):
		if not _rig_logged:
			_rig_logged = true
			_log("anatomy skipped for %s: %s" % [pony.name, attach.last_error])
		return
	var mesh: MeshInstance3D = attach.mesh
	var refined := refined_winking_mesh(mesh.mesh as ArrayMesh)
	if refined != null:
		mesh.mesh = refined
	var is_v2 := selected == MARE_BITS_V2_PATH
	var identity: Variant = pony.get("identity")
	placement.set_mesh(mesh, attach.bone_inverse, body_profile(identity))
	placement.load()
	placement.apply(_missionary_pose(), _pose_depth(), _bed_frame())
	shapes.set_mesh(mesh, is_v2)
	coat.set_mesh(mesh, attach.skeleton)
	appearance.set_mesh(mesh, attach.skeleton)
	appearance.attach_parts()
	appearance.apply_material(_missionary_pose())
	set_process(true)
	attach.apply_visibility(_act_visible())
	_log("anatomy attached lift=%.3f" % PLACEMENT.LIFT)
	if shapes != null and bool(shapes.v2_anal()) and mesh.mesh is ArrayMesh:
		var arrays: Array = (mesh.mesh as ArrayMesh).surface_get_arrays(0)
		var cols: Variant = arrays[Mesh.ARRAY_COLOR]
		var a1 := 0
		var a05 := 0
		if cols != null:
			for c: Color in cols:
				if c.a > 0.9:
					a1 += 1
				elif c.a > 0.4:
					a05 += 1
		_log("V2 colour mask a1=%d a05=%d path=%s" % [a1, a05, attach.mare_bits_path])


func _process(delta: float) -> void:
	_heat_idle_tick(delta)
	coat.tick_debug()
	placement.tick(_missionary_pose(), _pose_depth(), _bed_frame())
	_visibility_clock -= delta
	if _visibility_clock > 0.0:
		return
	_visibility_clock = ATTACH.VISIBILITY_POLL_S
	_apply_place()
	shapes.refresh_anal()
	_apply_body_coat()
	if appearance != null:
		appearance.apply_strip_scale()
	var started := Time.get_ticks_usec()
	attach.apply_visibility(_act_visible())
	facts.perf("anatomy_visibility", Time.get_ticks_usec() - started)


## integration: the visibility pill. `act` shows her only during the act's states: POSING_IN,
## ACTIVE, CLIMAX and AFTERGLOW.
func _act_visible() -> bool:
	match SETTINGS.anatomy_mode.get_choice():
		"always":
			return true
		"act":
			return facts.state in [1, 2, 3, 4]
	return false


func _heat_idle_tick(delta: float) -> void:
	if not attach.is_attached() or not is_instance_valid(pony) or heat == null:
		return
	heat.tick(delta, facts.state, attach.visible(),
		Callable(self, "_cycle_phase_now"), Callable(self, "idle_discharge"))


func _cycle_phase_now() -> String:
	return facts.cycle_phase


## How open she rests between winks, from the Heat debug settings.
func _heat_rest_open() -> float:
	return float(heat.rest_open()) if heat != null else 0.0


## The calibrated lift used by every mare. The dock/tail base is not a reliable reference: some
## tails (Derpy's) sit lower and pulled the whole anatomy into the rump. Keep one value so the
## anatomy's size and position are identical across mares; the Show tail docks switch only hides or
## shows the dock and never moves the anatomy.
func _tail_lift() -> float:
	return PLACEMENT.LIFT


## The act-only placement trim. The lying missionary pose tilts her pelvis, so the rigged vulva can
## sit a little high/low or face the wrong way; these values move only the anatomy mesh.
func _missionary_pose() -> bool:
	return facts.pose_id == CATALOG.MISSIONARY


func _pose_depth() -> float:
	return clampf(float(facts.depth), 0.0, 1.0)


func _bed_frame() -> Variant:
	return facts.bed_frame


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


## The attach module computes the mesh/dock visibility; the controller owns the teats and strip
## parts, which live in the appearance module.
func apply_part_visibility(show: bool, teats_on: bool, strip_on: bool) -> void:
	if appearance != null:
		appearance.apply_visibility(show, teats_on, strip_on)


func is_attached() -> bool:
	return attach.is_attached()


func body_coat_mesh() -> MeshInstance3D:
	return coat.body_mesh() if coat != null else null


func body_coat_material() -> ShaderMaterial:
	return coat.body_material() if coat != null else null


func body_outline_material() -> ShaderMaterial:
	return coat.body_outline_material() if coat != null else null


## Public coat refresh for the runtime's jiggle fallback. The private `_apply_body_coat` stays
## the implementation; the runtime no longer calls a private method.
func body_coat_refresh() -> void:
	_apply_body_coat()


func _apply_body_coat_uniforms() -> void:
	coat.apply()


## integration: the ponut and vulva are on the pony body, not the genitals overlay. The rig
## coat (MareBody) is the visible one; NearBody is only the cutie-mark merge.
func _apply_body_coat() -> void:
	coat.apply()


## integration: a mesh modelled on the shared mare body and skinned with her own weights.
func apply_live() -> void:
	if not is_attached():
		return
	var selected := selected_mare_bits_path()
	if selected != attach.mare_bits_path and attach.reload_mare_bits(selected):
		shapes.set_mesh(attach.mesh, selected == MARE_BITS_V2_PATH)
	if not placement.dirty() and SETTINGS.placement_revision != placement.revision():
		placement.load()
	_apply_material()
	_apply_place()
	shapes.refresh_anal()
	_apply_body_coat()
	attach.apply_visibility(_act_visible())


func detach() -> void:
	end_act()
	if coat != null:
		coat.clear_mesh()
	if placement != null:
		placement.clear_mesh()
	if appearance != null:
		appearance.clear()
	if shapes != null:
		shapes.clear_mesh()
	if attach != null:
		attach.detach()
	set_process(false)
	if dock_refresh.is_valid():
		dock_refresh.call(pony)


func winking_mesh() -> MeshInstance3D:
	return shapes.winking_mesh()


## integration: one persistent fluid node per pony, reused by every act.
func fluid() -> Node3D:
	return attach.fluid() if attach != null else null


## Idle heat discharge: one or more droplets are shot out of the vulva opening on each wink
## burst. The persistent fluid node keeps their motion and pools them on the ground under her.
func idle_discharge(count: int) -> void:
	if attach != null:
		attach.idle_discharge(count)


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
	facts.write_log(text)
