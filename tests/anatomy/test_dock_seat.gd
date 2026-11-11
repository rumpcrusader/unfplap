extends SceneTree
## Dock base seat: both the reference fit and the common +40 mm visibility fit must end with every
## base-ring vertex at or inside `rump_z - EMBED`. The outer dock must not move.
##
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_dock_seat.gd

const DOCK_SEAT := preload("res://mods/unfplap/anatomy/tail/dock_seat.gd")
const HYBRID_DOCK := preload("res://world/characters/hybrid_mare/hybrid_dock.gd")
const APPROVED_FIT := "res://world/characters/hybrid_mare/dock_fit.json"

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var fit: Dictionary = HYBRID_DOCK.read_fit(APPROVED_FIT)
	_check_fit(fit, "reference")
	var offset: Dictionary = fit.duplicate(true)
	var position: Array = offset["position"]
	position[2] = float(position[2]) + 0.04
	offset["position"] = position
	_check_fit(offset, "+40 mm visibility")
	print("DOCK_SEAT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("DOCK_SEAT_PASS")
	quit(0 if failures == 0 else 1)


func _check_fit(fit: Dictionary, label: String) -> void:
	var fitted: ArrayMesh = HYBRID_DOCK.fitted_mesh(fit, false)
	var reached: ArrayMesh = HYBRID_DOCK._stretched(fitted, "mare")
	var before := _max_gap(reached)
	check(before > 0.01, "%s starts with a floating base (%.1f mm)" % [label, before * 1000.0])
	var base: Array = reached.surface_get_arrays(0)
	var ring: PackedInt32Array = reached.get_meta("base_indices", PackedInt32Array())
	var tip_index := _tip_index(base, ring)
	var tip_before: Vector3 = (base[Mesh.ARRAY_VERTEX] as PackedVector3Array)[tip_index]
	var snapped: ArrayMesh = DOCK_SEAT.snap_base(reached, "mare")
	check(snapped != null, "%s produces a snapped mesh" % label)
	if snapped == null:
		return
	var after := _max_gap(snapped)
	check(after <= -DOCK_SEAT.EMBED + 0.0005,
		"%s seats every base-ring vertex (%.1f mm)" % [label, after * 1000.0])
	var arrays: Array = snapped.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	check(vertices.size() == (base[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		"%s keeps every vertex" % label)
	var tip_after: Vector3 = vertices[tip_index]
	check(tip_before.distance_to(tip_after) < 0.00001, "%s leaves the outer tip in place" % label)
	var old_arrays: Array = reached.surface_get_arrays(0)
	check((arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size()
		== (old_arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size(),
		"%s keeps the skin bone array" % label)
	check((arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array).size()
		== (old_arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array).size(),
		"%s keeps the skin weight array" % label)
	check(snapped.get_meta("base_indices", PackedInt32Array()) == ring,
		"%s keeps the base-ring metadata" % label)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var finite_normals := normals.size() == vertices.size()
	for normal: Vector3 in normals:
		if not normal.is_finite() or normal.length_squared() < 0.5:
			finite_normals = false
			break
	check(finite_normals, "%s rebuilds finite normals" % label)


func _max_gap(mesh: ArrayMesh) -> float:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ring: PackedInt32Array = mesh.get_meta("base_indices", PackedInt32Array())
	var worst := -INF
	for index: int in ring:
		if index < 0 or index >= vertices.size():
			continue
		var vertex := vertices[index]
		worst = maxf(worst, vertex.z - HYBRID_DOCK.rump_z("mare", vertex.y))
	return worst


func _tip_index(arrays: Array, ring: PackedInt32Array) -> int:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var base := Vector3.ZERO
	for index: int in ring:
		base += vertices[index]
	base /= float(maxi(1, ring.size()))
	var best := 0
	var far := -1.0
	for i in vertices.size():
		var distance := vertices[i].distance_squared_to(base)
		if distance > far:
			far = distance
			best = i
	return best
