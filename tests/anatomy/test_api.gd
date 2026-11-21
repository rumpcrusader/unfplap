extends "res://mods/unfplap/tests/support/suite.gd"
## The anatomy API surface: the caller-owned read models, the absent handles and the act target
## gates. Internal attachment behavior stays in its own suite.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_api.gd

const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const ACT := preload("res://mods/unfplap/anatomy/act.gd")
const CONTROLLER := preload("res://mods/unfplap/anatomy/controller.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")


class FakeController extends "res://mods/unfplap/anatomy/controller.gd":
	var view: Variant = null
	var stage: Variant = null
	var endings := 0

	func set_act_view(view_node: Variant, stage_node: Variant, _bed: Variant = null) -> void:
		view = view_node
		stage = stage_node

	func end_act() -> void:
		endings += 1


func run() -> void:
	# The caller owns the two read models; their defaults are the planning and settling values.
	var view := ANATOMY.PoseView.new()
	check(view.family.is_empty() and view.frame.is_empty(), "a fresh view has no pose family")
	check(view.contact_target == Vector3.INF, "a fresh view carries no contact target")
	var stage := ANATOMY.ActStage.new()
	check(stage.phase == ANATOMY.Phase.POSING_IN, "a fresh stage starts posing in")
	check(is_zero_approx(stage.depth), "a fresh stage has no depth")

	# An API node with no world still answers every verb as a safe no-op.
	var api: ANATOMY = ANATOMY.new()
	var handle := api.anon(null)
	check(not handle.prepare() and not handle.showing(), "an absent part prepares and shows false")
	check(handle.root_now() == Vector3.INF, "an absent part has no root")
	check(is_zero_approx(handle.shaft_length_m()), "an absent part has no shaft")
	handle.encounter(true)
	handle.drive_hip(null)
	check(api.entrance_point(null) == Vector3.INF, "an absent anatomy has no entrance")
	check(api.debug_anon_scale(null) == Vector3.INF, "an absent part has no debug scale")
	check(api.garment(null).hull() == null, "an absent garment has no hull")
	check(api.begin_act(null, view, null) == null, "no presented pony begins no act")
	api.free()

	# The target gates read the stage, the view and the feature switches; consent is not here.
	var controller := FakeController.new()
	var act: ACT = ACT.new()
	var presentation := ANATOMY.ActPresentation.new(controller, act, view, null, Callable())
	var holes := SETTINGS.anatomy_holes.get_bool()
	var oral := SETTINGS.anatomy_oral.get_bool()
	SETTINGS.anatomy_holes.set_bool(true)
	SETTINGS.anatomy_oral.set_bool(true)
	view.family = "standing"
	view.contact_kind = "opening"
	stage.phase = ANATOMY.Phase.ACTIVE
	presentation.stage(0.0, stage)
	check(presentation.can_target_vulva(), "an active opening can turn the vulva")
	check(presentation.can_target_anus(), "an active opening can turn the anus")
	check(presentation.can_target_mouth(), "an active standing pose can target the mouth")
	presentation.target_anus()
	check(presentation.target() == ANATOMY.Target.ANUS, "the target follows the anal choice")
	view.contact_kind = "mouth"
	presentation.pose(view)
	check(presentation.target() == ANATOMY.Target.ANUS, "a non-mouth pose keeps the target")
	presentation.target_mouth()
	check(presentation.target() == ANATOMY.Target.MOUTH, "the mouth target needs the mouth contact")
	view.contact_kind = "opening"
	presentation.pose(view)
	check(presentation.target() == ANATOMY.Target.VULVA,
		"leaving the mouth contact clears the mouth target")
	view.contact_kind = "face"
	check(not presentation.can_target_vulva(), "a face contact blocks the openings")
	check(not presentation.can_target_mouth(), "a face contact blocks the mouth target")
	SETTINGS.anatomy_holes.set_bool(holes)
	SETTINGS.anatomy_oral.set_bool(oral)

	presentation.end()
	check(controller.endings == 1, "the handle owns the one act teardown")
	check(presentation.target() == ANATOMY.Target.VULVA, "target survives the teardown")
	check(presentation.frame_point() == Vector3.INF, "a closed handle has no frame point")
	controller.free()
	act.free()
	finish()
