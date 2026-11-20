extends "res://mods/unfplap/privacy/service.gd"
## Shared privacy fake: the setup no-op and the private offer/cuddle answers the host suites read.

var private := true

func setup() -> void:
	pass

func offer_private(_except: Node = null) -> bool:
	return private

func cuddle_private(_pony: Node) -> bool:
	return private
