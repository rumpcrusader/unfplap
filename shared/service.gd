extends Node
## The world-service base: the four lifecycle hooks as no-ops, so the entry calls every service
## directly. A service that needs a hook overrides it; the entry validates the names once at boot.
##
## See `ARCHITECTURE.md` (`## Composition`).


func on_world(_host: Node) -> void:
	pass


func on_world_closed() -> void:
	pass


func on_player(_body: Node) -> void:
	pass


func shutdown() -> void:
	pass
