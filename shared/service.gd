extends Node
## The world-service base: the four lifecycle hooks have empty bodies, so the entry calls every
## list member directly. Override only what the service needs; the boot check validates the names.
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
