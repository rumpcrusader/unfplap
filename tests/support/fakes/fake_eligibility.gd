extends "res://mods/unfplap/eligibility/api.gd"
## Shared eligibility fake: counts the act-target and relationship calls a gate suite makes.

var eligible_calls := 0
var relationship_calls := 0

func eligible(_pony: Node, _target: Target) -> bool:
	eligible_calls += 1
	return true

func relationship_ok(_pony: Node) -> bool:
	relationship_calls += 1
	return true
