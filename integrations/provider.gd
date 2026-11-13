extends RefCounted
## The pure provider contract for one supported external mod. A provider decides what the act needs
## to write; it never touches a scene, a node, the clock, the filesystem or the settings file. The
## facade resolves bindings, reads the act facts and applies the returned actions.
##
## Providers are private to the integrations service; only `integrations/service.gd` imports them.

## Whether this provider should run for the current act and context.
func available(_context: RefCounted) -> bool:
	return false


## Whether the facade should hold the act's shared excitement Beat while this provider runs.
func holds_excitement() -> bool:
	return false


## Actions applied once when the provider starts.
func start_actions(_context: RefCounted, _out: Array) -> void:
	pass


## Actions applied while the act runs. Reuse action objects instead of allocating every tick.
func tick_actions(_context: RefCounted, _delta: float, _out: Array) -> void:
	pass


## Actions applied once when the act enters afterglow.
func afterglow_actions(_context: RefCounted, _out: Array) -> void:
	pass
