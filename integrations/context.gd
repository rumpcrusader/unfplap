extends RefCounted
## The plain values a pure provider may read. The facade refreshes one context per provider in
## place; nothing here is a node handle or a scene reach-in.

## Runtime state enum, pose id and the act clock.
var state := 0
var pose_id := ""
var satisfaction := 0.0
var act_seconds := 0.0
## True once the act has entered afterglow.
var afterglow := false
## The game's Affection kind: "", "kiss" or "hug".
var affection_kind := ""
## The runtime's per-act feature snapshot.
var features: Dictionary = {}
## Binding id -> whether the binding currently resolves to a live node.
var bindings: Dictionary = {}


## A feature flag from the act snapshot; unknown flags read as `fallback`.
func feature(name: String, fallback := false) -> bool:
	return bool(features.get(name, fallback))


## Whether a provider binding currently exists.
func binding(name: String) -> bool:
	return bool(bindings.get(name, false))
