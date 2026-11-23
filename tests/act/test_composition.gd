extends "res://mods/unfplap/tests/support/suite.gd"
## The runtime's Pony services: attached by construction, named in the fixed order, grouped and
## free of engine-frame work.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/act/test_composition.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const HANDLES := preload("res://mods/unfplap/world/handles.gd")
const ACT_GATE := preload("res://mods/unfplap/act_gate/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const PONY_GROUP := "unfplap_pony_service"
const PONY_NAMES := [
	"UnfplapPoses", "UnfplapCamera", "UnfplapHands", "UnfplapKiss", "UnfplapFace",
	"UnfplapAfterglow", "UnfplapRest", "UnfplapSceneGate", "UnfplapSceneHold",
	"UnfplapReadiness", "UnfplapReactions", "UnfplapSummary", "UnfplapDialogue",
]
const FRAME_HOOKS := ["_process", "_physics_process", "_exit_tree"]


func run() -> void:
	var world := HANDLES.new()
	var gate := ACT_GATE.new()
	world.act_gate = gate
	var runtime: Node = RUNTIME.new(null, world)
	var attached: Array[String] = []
	for child: Node in runtime.get_children():
		attached.append(str(child.name))
		check(child.is_in_group(PONY_GROUP), "%s joins the Pony service group" % child.name)
		for hook: String in FRAME_HOOKS:
			check(not child.has_method(hook), "%s declares no %s" % [child.name, hook])
	check(attached == PONY_NAMES, "the 13 Pony services are attached once, in their fixed order")
	check(runtime.get_node_or_null("UnfplapPoses") == runtime.act.context.pose,
		"the named child is the constructed pose session")
	check(runtime.get_node_or_null("UnfplapDialogue") == runtime.act.context.dialogue,
		"the named child is the constructed dialogue facade")
	check(runtime.act.context.world == world, "the runtime hands its World record to the act context")
	check(runtime.scene.gate_service == gate, "the scene gate reads the record's act gate")
	var other_world := HANDLES.new()
	var other: Node = RUNTIME.new(null, other_world)
	check(other.act.context.world == other_world and other.scene.gate_service == null,
		"each runtime reads its own record, never a shared one")
	root.add_child(other)
	other.free()
	_check_scope_children()
	_check_frames()
	# The composition releases from the runtime's real world-close exit, its one release path.
	root.add_child(runtime)
	root.remove_child(runtime)
	check_null(runtime.act.context, "the world-close exit releases the act record")
	runtime.free()
	gate.free()
	finish()


## The engine frames follow the body: the suite fixture state runs none, a bound runtime runs both.
func _check_frames() -> void:
	var bodyless: Node = RUNTIME.new()
	root.add_child(bodyless)
	check(not bodyless.is_processing() and not bodyless.is_physics_processing(),
		"a bodyless runtime runs no act frame")
	bodyless.free()
	var body := Node3D.new()
	root.add_child(body)
	var bound: Node = RUNTIME.new()
	bound.pony = body
	root.add_child(bound)
	check(bound.is_processing() and bound.is_physics_processing(),
		"a runtime given a body runs both act frames")
	bound.free()
	body.free()


## `_assert_children`: the composed set passes; a hand-built stray child is reported.
func _check_scope_children() -> void:
	var runtime: Node = RUNTIME.new()
	var quiet: bool = LOG.enabled
	LOG.enabled = true
	check(int(runtime.call("_assert_children")) == 0,
		"the composed Pony services pass the scope check")
	var stray := Node.new()
	stray.name = "Stray"
	runtime.add_child(stray)
	check(int(runtime.call("_assert_children")) == 1,
		"a child outside the Pony service group is reported")
	LOG.enabled = quiet
	root.add_child(runtime)
	runtime.free()
