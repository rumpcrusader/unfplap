extends Node3D
## Dev gallery: every adult mare in the anatomy roster, in a grid, with her anatomy attached and
## her tail seated at the reference dock with the tail-only dock cuff. Tools only; never ships.
##
## Open this scene in the editor and run it (F6). The scene itself is tiny: the mares are built
## from their game scenes at run time, exactly as the game builds them, so the dock/anatomy setup
## is the real one instead of a baked copy.
##
## `mare_ids` empty means the whole `SETTINGS.CHARACTER_ORDER` roster. Set a few ids while
## iterating so the gallery starts fast.

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy.gd")
const TAIL_SEAT := preload("res://mods/unfplap/tail_seat.gd")
const POPULATION := preload("res://world/population/pony_population_config.gd")
const TAIL := preload("res://mods/unfplap/tail_pose.gd")

@export var mare_ids: PackedStringArray = []
@export var columns := 10
@export var spacing := 1.8
@export var row_spacing := 2.6
@export var gallery_scale := 0.0
## `front`, `rear` (the dock side) or `side`: the initial orbit angle.
@export var view := "rear"
## Which mare the camera starts on.
@export var focus_index := 0
## Headless smoke runs build the roster and quit instead of leaving the window open.
@export var quit_when_done := false
## Optional screenshot after the build; empty in normal use.
@export var screenshot_path := ""

var _seat: Node
var _anatomy: Array[Node] = []
var _ponies: Array[Node3D] = []
var _names: Array[String] = []
var _camera: Camera3D
var _label: Label
var _index := 0
var _yaw := PI + 0.55
var _pitch := 0.10
var _distance := 1.8
var _scale := 1.0


func _ready() -> void:
	# Session-only: keep the user's settings.json untouched. The anatomy controller reads these
	# through the flat settings cache, so bump the generation after writing them.
	SETTINGS.data()
	SETTINGS._cache["anatomy"]["anatomy_mode"] = "always"
	SETTINGS._cache["anatomy"]["show_dock"] = true
	SETTINGS._cache["anatomy"]["reseat_tails"] = true
	SETTINGS._cache["anatomy"]["tail_offset_mm"] = 0.0
	SETTINGS._cache["anatomy"]["dock_offset_mm"] = 0.0
	SETTINGS._cache["anatomy"]["anatomy_fluid"] = false
	SETTINGS.generation += 1
	SETTINGS.placement_revision += 1

	var settings: Node = get_node_or_null("/root/Settings")
	var scale := 1.0
	if settings != null and settings.has_method("pony_scale"):
		scale = float(settings.call("pony_scale"))
	if gallery_scale > 0.0:
		scale = gallery_scale

	var ids: Array[String] = []
	var catalogue: Dictionary = POPULATION.catalogue()
	if mare_ids.is_empty():
		for id: String in SETTINGS.CHARACTER_ORDER:
			if catalogue.has(id):
				ids.append(id)
	else:
		for id: String in mare_ids:
			if catalogue.has(id):
				ids.append(id)
			else:
				print("DOCK_GALLERY missing scene for ", id)

	_add_environment()
	_seat = TAIL_SEAT.new()
	_seat.name = "UnfplapTailSeat"
	add_child(_seat)
	var built := 0
	for id: String in ids:
		var path := str(catalogue[id])
		if not ResourceLoader.exists(path):
			print("DOCK_GALLERY missing scene ", id, " ", path)
			continue
		var scene: PackedScene = load(path)
		if scene == null:
			continue
		var pony: Node3D = scene.instantiate() as Node3D
		if pony == null:
			continue
		pony.name = "Mare_%s" % id
		var column := built % maxi(columns, 1)
		var row := built / maxi(columns, 1)
		pony.position = Vector3(column * spacing, 0.0, row * row_spacing)
		pony.rotation.y = PI
		add_child(pony)
		if pony.has_method("set_body_scale"):
			pony.set_body_scale(scale)
		var anatomy: Node = ANATOMY.new()
		anatomy.name = "UnfplapAnatomy"
		add_child(anatomy)
		anatomy.call("setup", pony, null)
		anatomy.call("refresh")
		_anatomy.append(anatomy)
		_seat.call("attach", pony)
		_lift_tail(pony)
		_ponies.append(pony)
		_names.append(str(SETTINGS.CHARACTER_NAMES.get(id, id)))
		built += 1
	print("DOCK_GALLERY built %d mares scale=%.2f" % [built, scale])
	_scale = scale
	_add_camera()
	_add_hud()
	_focus(clampi(focus_index, 0, maxi(_ponies.size() - 1, 0)))
	set_process(_ponies.size() > 0)
	if screenshot_path != "":
		await get_tree().create_timer(1.2).timeout
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png(screenshot_path)
		print("DOCK_GALLERY shot ", screenshot_path, " ", image.get_size())
	if quit_when_done:
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit()


func _add_environment() -> void:
	var light := DirectionalLight3D.new()
	light.name = "GalleryLight"
	light.rotation_degrees = Vector3(-42, 28, 0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)
	var world := WorldEnvironment.new()
	world.name = "GalleryEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.09, 0.11)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.75, 0.85)
	environment.ambient_light_energy = 0.9
	world.environment = environment
	add_child(world)
	var floor := StaticBody3D.new()
	floor.name = "GalleryFloor"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.2, 40.0)
	shape.shape = box
	shape.position.y = -0.1
	floor.add_child(shape)
	add_child(floor)


## Sweep the tail aside so the dock and vulva are visible; the cuff follower carries the dock.
func _lift_tail(pony: Node3D) -> void:
	var hair: Variant = pony.get("hair_skeleton")
	if not hair is Skeleton3D:
		return
	var lift: SkeletonModifier3D = TAIL.new()
	lift.name = "GalleryTail"
	lift.set("mare", pony)
	lift.set("amount", 1.0)
	lift.set("target_amount", 1.0)
	lift.set("aside_angle", 0.95)
	lift.set("lift_angle", 0.75)
	lift.set("aside_sign", 1.0)
	(hair as Skeleton3D).add_child(lift)


func _add_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "GalleryCamera"
	_camera.fov = 42.0
	add_child(_camera)
	_camera.current = true
	match view:
		"front":
			_yaw = 0.0
		"side":
			_yaw = PI * 0.5
		_:
			_yaw = PI + 0.55
func _add_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GalleryHUD"
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24.0, 20.0)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	layer.add_child(_label)


func _focus(index: int) -> void:
	if _ponies.is_empty():
		return
	_index = clampi(index, 0, _ponies.size() - 1)
	_update_camera()


func _process(delta: float) -> void:
	if _ponies.is_empty() or not is_instance_valid(_camera):
		return
	var moved := false
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		_focus(_index - 1)
	elif Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		_focus(_index + 1)
	if Input.is_key_pressed(KEY_Q):
		_yaw += delta * 1.6
		moved = true
	if Input.is_key_pressed(KEY_E):
		_yaw -= delta * 1.6
		moved = true
	if Input.is_key_pressed(KEY_W):
		_distance = maxf(_distance - delta * 2.0, 0.8)
		moved = true
	if Input.is_key_pressed(KEY_S):
		_distance = minf(_distance + delta * 2.0, 8.0)
		moved = true
	if moved:
		_update_camera()


func _update_camera() -> void:
	if not is_instance_valid(_camera) or _ponies.is_empty():
		return
	var pony := _ponies[_index]
	var pivot := pony.global_position + Vector3(0.0, 0.62 * _scale, 0.0)
	var hair: Variant = pony.get("hair_skeleton")
	if hair is Skeleton3D:
		var bone := (hair as Skeleton3D).find_bone("mPelvis")
		if bone >= 0:
			pivot = ((hair as Skeleton3D).global_transform \
				* (hair as Skeleton3D).get_bone_global_pose(bone)).origin
	var offset := Basis.from_euler(Vector3(_pitch, _yaw, 0.0)) * Vector3(0.0, 0.0, _distance * _scale)
	_camera.global_position = pivot + offset
	_camera.look_at(pivot)
	if is_instance_valid(_label):
		_label.text = "%d/%d  %s\nA/D mare   Q/E orbit   W/S zoom   1 front   2 rear   3 side" % [
			_index + 1, _ponies.size(), _names[_index]]


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_1:
			_yaw = 0.0
			_update_camera()
		KEY_2:
			_yaw = PI + 0.55
			_update_camera()
		KEY_3:
			_yaw = PI * 0.5
			_update_camera()
