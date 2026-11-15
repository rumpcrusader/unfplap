extends SceneTree
## The kiss facade's pose-change retarget: the live config and the base kiss profile follow the
## view without ending a running kiss.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/act_camera/test_kiss.gd

const KISS := preload("res://mods/unfplap/kiss/service.gd")
const FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")

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
	var facts: RefCounted = FACTS.new()
	var view: RefCounted = VIEW.new()
	view.family = "bed"
	view.presentation = {"kiss": "missionary"}
	var live := {"kiss_speed": 1.0}
	view.from_config = live
	view.pose_config = live
	facts.pose_view = view
	var kiss: RefCounted = KISS.new(facts)
	kiss._kiss_amount = 0.32
	kiss._base_kiss_active = true
	kiss.pose_changed(view)
	check(str(kiss._hook_profile) == "missionary", "the hook caches the missionary kiss profile")
	check(is_same(kiss._pose_cfg, live), "the hook follows the live pose config")
	check(kiss.amount() > 0.3 and kiss.base_active(),
		"a pose change does not end the running kiss")

	view.family = "standing"
	view.presentation = {"kiss": "standing"}
	var target := {"kiss_speed": 2.0}
	view.from_config = target
	view.pose_config = target
	kiss.pose_changed(view)
	check(str(kiss._hook_profile) == "standing", "the hook retargets the standing profile")
	check(is_same(kiss._pose_cfg, target), "the hook retargets the live config")
	check(kiss.amount() > 0.3 and kiss.base_active(),
		"the retarget keeps the kiss state")

	# The service's own tick reads the same live config from the view.
	view.from_config = live
	view.pose_config = live
	kiss._sync()
	check(is_same(kiss._pose_cfg, live), "the kiss sync follows the view's live config")
	check(str(kiss._kiss_profile()) == "standing", "the kiss profile is the view's presentation")

	kiss._base_kiss_active = false
	kiss._kiss_amount = 0.0
	print("KISS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("KISS_PASS")
	quit(0 if failures == 0 else 1)
