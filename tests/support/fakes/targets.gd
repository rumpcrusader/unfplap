extends "res://mods/unfplap/eligibility/service.gd"
## Shared act-target fake: the ponies an offer fixture allows.

var allowed: Array = []

func eligible(pony: Node, _target: Target = Target.ACT) -> bool:
	return allowed.has(pony)

func relationship_ok(_pony: Node) -> bool:
	return true
