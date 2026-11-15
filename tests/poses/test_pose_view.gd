extends SceneTree
## The pose read model: the filled identity and profiles, the live mirrors and the reused clear.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_view.gd

const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const REGISTRY := preload("res://mods/unfplap/poses/registry.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

const PROFILES := ["camera", "hands", "controls", "audio", "afterglow", "presentation",
	"contact", "anon", "scene", "modifiers"]

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
	var registry: RefCounted = REGISTRY.new()
	var spec: Variant = registry.spec(CATALOG.STANDING)
	var config: Dictionary = {"gaps": {"canon": 0.3}}
	var view: RefCounted = VIEW.new()
	_check_defaults(view)
	_check_fill(view, spec, config)
	_check_transition(view, spec, config)
	_check_clear(view, spec, config)
	_check_reuse(view, spec, config)
	print("POSE_VIEW_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("POSE_VIEW_PASS")
	quit(0 if failures == 0 else 1)


func _check_defaults(view: RefCounted) -> void:
	check(view.id == "" and view.family == "" and view.frame == "",
		"a fresh view has no identity")
	check(view.pose_state == VIEW.IDLE, "a fresh view is idle")
	check(view.pose_config.is_empty(), "a fresh view has no config")
	check(view.weight == 0.0 and view.edge_id == "" and view.edge_t == 0.0,
		"a fresh view has no transition")
	check(view.contact_kind == "none", "a fresh view names no contact")
	check(view.contact_target == Vector3.INF, "a fresh view has no contact target")
	check(view.facing == Basis.IDENTITY and view.facing_amount == 0.0,
		"a fresh view has no facing")
	check(view.forms.is_empty() and view.views.is_empty(), "a fresh view declares no support")
	check(not view.public_pose and not view.offerable, "a fresh view is not offered")


func _check_fill(view: RefCounted, spec: Variant, config: Dictionary) -> void:
	view.fill(spec, config)
	check(view.id == CATALOG.STANDING, "the view carries the pose id")
	check(view.family == "standing" and view.frame == "ground", "the view carries family and frame")
	check(view.settings_group == "standing", "the view carries the settings group")
	check(view.pose_state == VIEW.STEADY, "a filled view is steady")
	check(is_same(view.pose_config, config), "the view holds the live config object")
	check(is_same(view.from_config, config) and is_same(view.to_config, config),
		"both transition sides alias the live config")
	check(view.weight == 1.0, "a filled view is at full weight")
	check(view.from_id == view.id and view.to_id == view.id,
		"both transition ids are the active id")
	check(view.edge_id == "" and view.edge_t == 0.0, "a filled view has no edge")
	for profile: String in PROFILES:
		check(is_same(view.get(profile), spec.get(profile)),
			"the view shares the %s profile" % profile)
	check(view.forms is Array[String] and view.forms == spec.forms, "the view keeps the forms")
	check(view.views is Array[String] and view.views == spec.views, "the view keeps the views")
	check(view.public_pose and view.offerable, "the view carries the support flags")
	view.contact_kind = "mouth"
	check(view.contact_kind == "mouth", "the contact kind is writable")


## The transition fields the session writes: writable on a filled view and reset by `clear()`.
func _check_transition(view: RefCounted, spec: Variant, config: Dictionary) -> void:
	var target: Dictionary = {"gaps": {"canon": 0.4}}
	view.pose_state = VIEW.TRANSITIONING
	view.from_id = CATALOG.STANDING
	view.to_id = CATALOG.STANDING_TEST
	view.edge_id = "standing__standing_test"
	view.edge_t = 0.25
	view.weight = 0.5
	view.from_config = config
	view.to_config = target
	check(view.pose_state == VIEW.TRANSITIONING, "the transition state is writable")
	check(view.from_id == CATALOG.STANDING and view.to_id == CATALOG.STANDING_TEST,
		"the transition ids are writable")
	check(view.edge_id == "standing__standing_test" and view.edge_t == 0.25,
		"the edge id and clock are writable")
	check(view.weight == 0.5, "the transition weight is writable")
	check(is_same(view.from_config, config) and is_same(view.to_config, target),
		"both transition configs are writable")
	view.clear()
	check(view.pose_state == VIEW.IDLE and view.from_id == "" and view.to_id == ""
		and view.edge_id == "" and view.edge_t == 0.0 and view.weight == 0.0,
		"clear resets the transition fields")
	check(not is_same(view.from_config, config) and not is_same(view.to_config, target),
		"clear drops both transition configs")


func _check_clear(view: RefCounted, spec: Variant, config: Dictionary) -> void:
	view.clear()
	check(config.has("gaps"), "clear leaves the live config contents alone")
	check(view.id == "" and view.family == "" and view.frame == "",
		"clear drops the identity")
	check(view.pose_state == VIEW.IDLE, "clear returns the view to idle")
	check(view.pose_config.is_empty(), "clear drops the config reference")
	check(not is_same(view.pose_config, config), "clear does not keep the live config")
	check(view.weight == 0.0 and view.from_id == "" and view.to_id == "",
		"clear drops the transition")
	check(view.contact_kind == "none", "clear drops the contact kind")
	check(view.contact_target == Vector3.INF, "clear drops the contact target")
	check(view.facing == Basis.IDENTITY and view.facing_amount == 0.0, "clear drops the facing")
	check(view.forms.is_empty() and view.views.is_empty(), "clear empties the support lists")
	check(not view.public_pose and not view.offerable, "clear drops the support flags")
	for profile: String in PROFILES:
		check(view.get(profile).is_empty(), "clear empties the %s profile" % profile)


func _check_reuse(view: RefCounted, spec: Variant, config: Dictionary) -> void:
	var first_config: Dictionary = view.pose_config
	var first_profile: Dictionary = view.camera
	var first_forms: Array[String] = view.forms
	view.fill(spec, config)
	check(is_same(view.pose_config, config), "a second fill points at the live config")
	check(is_same(view.camera, spec.camera), "a second fill points at the spec profile")
	check(is_same(view.forms, first_forms), "a refill reuses the forms array")
	view.clear()
	check(is_same(first_config, view.pose_config), "clear reuses its empty config")
	check(is_same(first_profile, view.camera), "clear reuses its empty profile")
	check(is_same(first_profile, view.presentation), "the empty profile is shared")