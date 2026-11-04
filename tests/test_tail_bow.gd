extends SceneTree
## Tail bow geometry and placement.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_tail_bow.gd

const BOW := preload("res://mods/unfplap/tail_bow.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	_test_placement()
	_test_mesh()
	print("TAIL_BOW_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("TAIL_BOW_PASS")
	quit(0 if failures == 0 else 1)


func _test_placement() -> void:
	var cfg := {
		"size": 1.0, "outward_m": 0.05, "along_m": 0.03, "outward_up": 0.65,
		"tilt_deg": 0.0, "yaw_deg": 0.0, "roll_deg": 0.0, "band_radius": 0.042,
	}
	var root := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, -0.2))
	var local := BOW.placement(root, Vector3.BACK, Vector3.UP, 1.0, cfg)
	var world := root * local
	check(world.basis.z.dot(Vector3.BACK) < -0.5, "bow faces back off the rump")
	check(world.basis.y.dot(Vector3.UP) > 0.5, "bow stands up her body")
	check(world.origin.z > root.origin.z + 0.02, "bow sits behind the tail root")
	var lower := BOW.placement(root, Vector3.BACK, Vector3.UP, 1.0,
		{"size": 1.0, "outward_m": 0.05, "along_m": 0.0, "outward_up": 0.65})
	check((root * lower).origin.y > world.origin.y, "along moves down her body")
	check(near(local.basis.determinant(), 1.0, 0.001), "placement basis has no shear")
	var big := BOW.placement(root, Vector3.BACK, Vector3.UP, 1.5, cfg)
	check(near(big.basis.get_scale().x, 1.5, 0.001), "size scales the bow")
	var half := BOW.placement(root, Vector3.BACK, Vector3.UP, 0.5, cfg)
	check(near(half.basis.get_scale().x, 0.5, 0.001), "bow size scales the placement")
	var sideways := BOW.placement(root, Vector3.BACK, Vector3.UP, 1.0,
		{"size": 1.0, "outward_m": 0.05, "along_m": 0.0, "outward_up": 0.65, "yaw_deg": 90.0})
	check(not (root * sideways).basis.z.is_equal_approx(world.basis.z),
		"yaw turns the bow about its outward axis")


func _test_mesh() -> void:
	var cfg := BOW.config()
	check(not str(cfg.get("colour", "")).is_empty(), "bow reads a dye")
	var node := BOW.build(BOW.colour(cfg), cfg)
	check(node.name == BOW.NODE_NAME, "bow node name")
	check(node.mesh != null and node.mesh.get_surface_count() >= 3,
		"bow carries loops, tails and knot")
	var box: AABB = node.mesh.get_aabb()
	check(box.size.x > 0.1 and box.size.x < 0.35, "bow width is a bow, not a pony")
	check(box.size.y > 0.08, "bow hangs down the tail")
	check(box.size.z < 0.25, "bow stays shallow against the tail")
	var bigger := BOW.build(BOW.colour(cfg), {"size": 2.0, "along_m": 0.03, "outward_m": 0.05,
		"band_radius": 0.042}).mesh.get_aabb()
	check(near(bigger.size.x, box.size.x * 2.0, 0.01), "bow size scales the mesh")
	check(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"accessory casts no shadow")
	node.free()
