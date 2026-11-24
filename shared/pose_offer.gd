extends RefCounted
## One typed act offer. A trigger (the act key's idle scan, the accepted proactive request, or a
## future auto/dialogue trigger) builds this handle and hands it to the offer service's start
## path; the owner's cleanup and the classifier scope live here too, so the start path never names
## a pose. Plain data only: no tree access, no settings, no file access. Contract:
## `docs/initiation.md`, `docs/offer.md` and `docs/runtime.md`.

## The runtime that owns the act.
var runtime: Node = null
## The mare the act would start with.
var pony: Node3D = null
var pose := ""
var source := ""
## The bed the offer resolved to, or null for the standing fan.
var bed: Variant = null
## The trigger that produced it: "offer" for the accepted proactive request. The idle scan's
## discovered offers leave it empty; future triggers add "cuddle", "dialogue" and "debug".
var trigger := ""
## True when the trigger may start the act without the act key. This handle only stores the flag;
## the trigger owns when to call the start.
var auto := false
## True for the live accepted request offer; a discovery offer is false.
var pending := false
## The blocked policy record `{hint, need, toast}`; empty while the offer is playable.
var blocked: Dictionary = {}
## The owner's cleanup before the gate hands the pony to the act. Invalid means none.
var cancel := Callable()


## Whether the handle names a live runtime, pony and pose. It never reads the act gate.
func valid() -> bool:
	return is_instance_valid(runtime) and is_instance_valid(pony) and not pose.is_empty()


## The blocked hint text, or "" when the offer is playable.
func blocked_hint() -> String:
	return str(blocked.get("hint", ""))
