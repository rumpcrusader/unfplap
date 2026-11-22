extends RefCounted
## Service: hands
## Contract: docs/hands.md
## Scope: pure
## Import: hands/path_base.gd only
## Base for a pose-specific caress path: ordered contacts, preferred first.

const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const MODEL := preload("res://mods/unfplap/hands/model.gd")


var pony: Node3D = null
## The typed act view: a path reads the camera and the scene handles from it.
var facts: ACT_FACTS = null


func setup(pony_node: Node3D, facts_context: ACT_FACTS = null) -> void:
	pony = pony_node
	facts = facts_context


func candidates(_side: MODEL.Side, _context: MODEL.CaressContext) -> Array[MODEL.Candidate]:
	return []


func debug_world(_side: MODEL.Side) -> Array[MODEL.AnchorWorld]:
	return []


func reset() -> void:
	pass
