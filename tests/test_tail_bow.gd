extends SceneTree
## Tail bow geometry, placement and the spoken gift rail.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_tail_bow.gd

const BOW := preload("res://mods/unfplap/tail_bow.gd")
const GIFT := preload("res://mods/unfplap/tail_bow_gift.gd")
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
	_test_offer_kind()
	_test_answers()
	_test_placement()
	_test_mesh()
	print("TAIL_BOW_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("TAIL_BOW_PASS")
	quit(0 if failures == 0 else 1)


func _test_offer_kind() -> void:
	check(GIFT.offer_kind("I got you a tail bow.") == "give", "got you a bow is an offer")
	check(GIFT.offer_kind("Here, this satin bow is for you") == "give", "here for you is an offer")
	check(GIFT.offer_kind("want to wear this bow for me?") == "give", "wear this is an offer")
	check(GIFT.offer_kind("take that bow off, please") == "take", "take it off is a removal")
	check(GIFT.offer_kind("let me slip the ribbon off") == "take", "slip it off is a removal")
	check(GIFT.offer_kind("I like your bow") == "", "a comment is not an offer")
	check(GIFT.offer_kind("how are you today?") == "", "unrelated line is not an offer")
	check(GIFT.offer_kind("") == "", "empty line is not an offer")


func _test_answers() -> void:
	check(GIFT.local_answer("Oh, it's lovely!") == "accept", "compliment accepts")
	check(GIFT.local_answer("Yes please") == "accept", "yes please accepts")
	check(GIFT.local_answer("No thank you") == "decline", "no thank you declines")
	check(GIFT.local_answer("Why would I wear that?") == "decline", "why declines")
	check(GIFT.local_answer("What is it?") == "unclear", "a question is unclear")


func _test_placement() -> void:
	var cfg := {
		"size": 1.0, "along_m": 0.03, "tilt_deg": 0.0, "colour": "red",
	}
	var root := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, -0.2))
	var axis := Vector3(0.0, -0.6, 0.8).normalized()
	var radius := 0.06
	var local := BOW.placement(root, axis, Vector3.BACK, Vector3.UP, radius, 0.075, cfg)
	var world := root * local
	var out := (Vector3.BACK - axis * Vector3.BACK.dot(axis)).normalized()
	# The bow sits on the tail's outer surface: face away from her body, loops level with it.
	check(world.basis.z.dot(out) > 0.999, "bow faces away from her body")
	check(world.basis.y.dot(-axis) > 0.999, "loops sit level, up her tail")
	check(absf(world.basis.y.dot(world.basis.z)) < 0.001, "bow frame is square")
	check(world.origin.distance_to(root.origin + out * (0.075 + BOW.TIE_MARGIN)
		+ axis * 0.03) < 0.0001, "the tie point sits on the tail surface")
	check(near(local.basis.determinant(), 1.0, 0.001), "placement basis has no shear")
	var big := BOW.placement(root, axis, Vector3.BACK, Vector3.UP, radius, 0.075,
		{"size": 2.0, "along_m": 0.03})
	check(near(big.basis.get_scale().x, 2.0, 0.001), "size scales the bow")
	var fatter := BOW.placement(root, axis, Vector3.BACK, Vector3.UP, 0.09, 0.075, cfg)
	check(near(fatter.basis.get_scale().x, 1.5, 0.001), "a thicker tail gets a bigger bow")
	var base := BOW.placement(root, axis, Vector3.BACK, Vector3.UP, radius, 0.075,
		{"size": 1.0, "along_m": 0.0})
	var lifted := BOW.placement(root, axis, Vector3.BACK, Vector3.UP, radius, 0.075,
		{"size": 1.0, "along_m": 0.0, "lift_m": 0.10})
	var lift_vec := (root * lifted).origin - (root * base).origin
	check(near(lift_vec.length(), 0.10, 0.001), "lift raises the bow by its value")
	check(lift_vec.normalized().dot(Vector3.UP) > 0.999, "lift runs along her up axis")
	var tilted := BOW.placement(root, axis, Vector3.BACK, Vector3.UP, radius, 0.075,
		{"size": 1.0, "along_m": 0.03, "tilt_deg": 30.0})
	check(not (root * tilted).basis.z.is_equal_approx(world.basis.z), "tilt leans the bow")
	# A raised or sideways tail must not flip the loops.
	var sideways := BOW.placement(root, Vector3.BACK, Vector3.RIGHT, Vector3.UP, radius, 0.075,
		cfg)
	check(absf((root * sideways).basis.z.dot(Vector3.RIGHT)) > 0.999, "tail along her back")
	check(absf((root * sideways).basis.y.dot(Vector3.BACK)) > 0.999, "loops stay upright")


func _test_mesh() -> void:
	var cfg := BOW.config()
	check(BOW.DEFAULT_COLOUR == "red" and BOW.COLOURS.has("red"), "the bow is red")
	check(str(cfg.get("colour", "")) in BOW.COLOURS, "the dye is a known satin colour")
	var mesh := BOW.bow_mesh()
	check(mesh != null and mesh.get_surface_count() >= 1, "the modelled mesh loads")
	var box: AABB = mesh.get_aabb()
	check(box.size.x > 0.10 and box.size.x < 0.25, "the bow is about a hand wide")
	check(box.size.y > 0.12, "the tails hang below the knot")
	check(box.size.z < box.size.x * 0.6, "the bow is a flat piece, not a ball")
	var node := BOW.build(BOW.colour(cfg))
	check(node.name == BOW.NODE_NAME, "bow node name")
	check(node.mesh == mesh, "the bow uses the modelled mesh")
	check(node.material_override is StandardMaterial3D, "the dye overrides the imported material")
	check(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"accessory casts no shadow")
	node.free()
