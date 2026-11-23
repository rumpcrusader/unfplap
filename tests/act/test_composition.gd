extends "res://mods/unfplap/tests/support/suite.gd"
## The runtime's Pony services: attached by construction, named in the fixed order, grouped and
## free of engine-frame work.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/act/test_composition.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")

const PONY_GROUP := "unfplap_pony_service"
const PONY_NAMES := [
	"UnfplapPoses", "UnfplapCamera", "UnfplapHands", "UnfplapKiss", "UnfplapFace",
	"UnfplapAfterglow", "UnfplapRest", "UnfplapSceneGate", "UnfplapSceneHold",
	"UnfplapReadiness", "UnfplapReactions", "UnfplapSummary", "UnfplapDialogue",
]
const FRAME_HOOKS := ["_process", "_physics_process", "_exit_tree"]


func run() -> void:
	var runtime: Node = RUNTIME.new()
	var attached: Array[String] = []
	for child: Node in runtime.get_children():
		attached.append(str(child.name))
		check(child.is_in_group(PONY_GROUP), "%s joins the Pony service group" % child.name)
		for hook: String in FRAME_HOOKS:
			check(not child.has_method(hook), "%s declares no %s" % [child.name, hook])
	check(attached == PONY_NAMES, "the 13 Pony services are attached once, in their fixed order")
	check(runtime.get_node_or_null("UnfplapPoses") == runtime._bundle.pose,
		"the named child is the constructed pose session")
	check(runtime.get_node_or_null("UnfplapDialogue") == runtime._bundle.dialogue,
		"the named child is the constructed dialogue facade")
	runtime.free()
	finish()
