extends "res://mods/unfplap/act_gate/service.gd"
## Shared act-gate fake: the readiness, relationship and consent answers a suite sets.

var ready_ok := true
var relationship := true
var consent_ok := true
var ready_calls := 0
var relationship_calls := 0
var consent_calls := 0


func ready(pony: Node) -> bool:
	ready_calls += 1
	return ready_ok and relationship_ok(pony)


func relationship_ok(_pony: Node) -> bool:
	relationship_calls += 1
	return relationship


func consent(_pony: Node, _key: String) -> bool:
	consent_calls += 1
	return consent_ok
