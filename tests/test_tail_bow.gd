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
		"size": 1.0, "along_m": 0.02, "margin_m": 0.004, "loop_scale": 1.0,
		"splay_deg": 14.0, "tilt_deg": 0.0, "colour": "red",
	}
	var root := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, -0.2))
	var axis := Vector3(0.0, -0.6, 0.8).normalized()
	var local := BOW.placement(root, axis, Vector3.BACK, Vector3.UP, 1.0, cfg)
	var world := root * local
	# Square to the tail: the bow's own normal runs down her tail, so the loops hang around it.
	check(world.basis.z.dot(axis) > 0.999, "bow plane is square to the tail")
	check(absf(world.basis.y.dot(axis)) < 0.001 and world.basis.y.y > 0.3,
		"loops stay upright and square to the tail")
	check(world.origin.distance_to(root.origin + axis * 0.02) < 0.0001,
		"tie point moves down the tail")
	check(near(local.basis.determinant(), 1.0, 0.001), "placement basis has no shear")
	var big := BOW.placement(root, axis, Vector3.BACK, Vector3.UP, 1.5, cfg)
	check(near(big.basis.get_scale().x, 1.5, 0.001), "size scales the bow")
	check((root * big).origin.distance_to(root.origin + axis * 0.03) < 0.001,
		"the tie point scales with the bow")
	var tilted := BOW.placement(root, axis, Vector3.BACK, Vector3.UP, 1.0,
		{"size": 1.0, "along_m": 0.02, "tilt_deg": 30.0})
	check(not (root * tilted).basis.z.is_equal_approx(world.basis.z), "tilt leans the bow")
	# A raised or sideways tail must not flip the loops.
	var sideways := BOW.placement(root, Vector3.BACK, Vector3.BACK, Vector3.UP, 1.0, cfg)
	check(absf((root * sideways).basis.z.dot(Vector3.BACK)) > 0.999, "tail along her back")
	check(absf((root * sideways).basis.y.dot(Vector3.UP)) > 0.5, "loops stay upright")


func _test_mesh() -> void:
	var cfg := BOW.config()
	check(BOW.DEFAULT_COLOUR == "red" and BOW.COLOURS.has("red"), "the bow is red")
	check(str(cfg.get("colour", "")) in BOW.COLOURS, "the dye is a known satin colour")
	var radius := 0.045
	var node := BOW.build(BOW.colour(cfg), cfg, radius)
	check(node.name == BOW.NODE_NAME, "bow node name")
	check(node.mesh != null and node.mesh.get_surface_count() >= 3,
		"bow carries the loops, the wrap and the knot")
	var box: AABB = node.mesh.get_aabb()
	check(box.size.x > radius * 2.0 and box.size.x < radius * 5.0,
		"two loops spread wider than the tail")
	check(box.size.y > radius * 2.0, "loops reach above and below the tie point")
	check(box.size.z < radius * 2.0, "the bow stays shallow along the tail")
	# The wrap must sit on the measured tail, not float off it.
	check(box.has_point(Vector3(0.0, 0.0, box.position.z + box.size.z * 0.5)),
		"the winding wraps the tail axis")
	var thicker := BOW.build(BOW.colour(cfg), cfg, 0.09).mesh.get_aabb()
	check(thicker.size.x > box.size.x * 1.6, "a thicker tail gets a bigger bow")
	var small := BOW.build(BOW.colour(cfg), {"size": 1.0, "along_m": 0.02, "margin_m": 0.004,
		"loop_scale": 0.5}, radius).mesh.get_aabb()
	check(small.size.x < box.size.x, "loop size shrinks the bow")
	check(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"accessory casts no shadow")
	node.free()
