extends "res://mods/unfplap/privacy/api.gd"
## Shared privacy fake: the setup no-op and the one private answer the host suites read.

var private := true

func setup() -> void:
	pass

func is_private(_target: Node, _kind: Kind = Kind.OFFER) -> bool:
	return private