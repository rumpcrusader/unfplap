extends RefCounted
## One host callable for the VR touch bridge; the typed wrapper keeps the accessor strong.
## `world/game.gd` fires it, so the event name stays in the accessor module.
## Contract: `docs/world.md`.

var run := Callable()
