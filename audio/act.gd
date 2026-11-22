extends RefCounted
## One runtime's act audio. It owns the lazy audio node, the act's bind/open/close, the generated
## vocal cooldown, the voice policy, the breath and the shared excitement Beat holds. The runtime
## only parents the node and calls in; every act call is a no-op before the node exists.
##
## See `docs/audio.md`.

const AUDIO := preload("res://mods/unfplap/audio/service.gd")

## The live audio node, or null before the first act. It is created lazily so both audio flags
## off keep the node out of the scene.
var node: Variant = null
## The runtime node: the one parent of the audio node.
var host: Node = null
## Named holds on the game's excitement Beat, one per owner that asked for it.
var _holders: Array[String] = []
var _beat: Timer = null
var _beat_saved := false
var _beat_paused := false


func bind(host_node: Node) -> void:
	host = host_node


## The audio node, created on the first act that needs it.
func service() -> Variant:
	if is_instance_valid(node):
		return node
	node = AUDIO.new()
	node.name = "UnfplapActAudio"
	if is_instance_valid(host):
		host.add_child(node)
	return node


## The new presented body's identity: the audio facade reads her snout, the bed point and the
## director's vocal-cache key from its bind, so a body swap rebinds without restarting the layer.
func bind_identity(pony: Variant, id: String, bed: Variant) -> void:
	if is_instance_valid(node):
		node.bind(pony, id, bed)


## Open the act's audio layer for this body and bed.
func start(pony: Variant, id: String, bed: Variant) -> void:
	stop()
	var audio: Variant = service()
	if audio != null:
		audio.bind(pony, id, bed)
		audio.begin()


func stop() -> void:
	if is_instance_valid(node):
		node.end()


## The pre-act scene's voice volume, and the act's mute policy. A live Ponese mute edit runs the
## pair again: restore first, then apply the new policy.
func restore_voice_policy() -> void:
	if is_instance_valid(node):
		node.restore_voice_policy()


func apply_voice_policy(mute: bool, pony: Variant, id: String) -> void:
	if is_instance_valid(node):
		node.apply_voice_policy(mute, pony, id)


func stop_breath() -> void:
	if is_instance_valid(node):
		node.stop_breath()


func play_climax() -> void:
	if is_instance_valid(node):
		node.climax()


func play_vocal() -> void:
	if is_instance_valid(node):
		node.play_vocal()


func tick_vocal(delta: float) -> void:
	if is_instance_valid(node):
		node.tick_vocal(delta)


func oral_kiss() -> void:
	if is_instance_valid(node):
		node.oral_kiss()


func play_mouth_kiss() -> void:
	if is_instance_valid(node):
		node.play_mouth_kiss()


## One rendered frame: the breath loop follows the state and the live thrust rate.
func tick(delta: float, state: int, rate: float) -> void:
	if is_instance_valid(node):
		node.tick(delta, node.phase_for_state(state), rate)


## The stroke's presentation calls. A missing node keeps the act quiet.
func impact(tier: String, strength: float, point: Vector3, gap: float, contact_gap: float,
		plap: bool) -> void:
	if is_instance_valid(node):
		node.impact(tier, strength, point, gap, contact_gap, plap)


func crossed(before: float, now: float) -> bool:
	return is_instance_valid(node) and bool(node.crossed(before, now))


func withdraw(before: float, now: float, strength: float, point: Vector3) -> void:
	if is_instance_valid(node):
		node.withdraw(before, now, strength, point)


## Acquire a named hold on the game's excitement Beat. The first successful holder saves the
## current pause state; every holder keeps the Beat paused. Repeating an owner is idempotent.
func hold_excitement(owner: String) -> void:
	if owner.is_empty() or _holders.has(owner):
		return
	if not is_instance_valid(_beat):
		_beat = null
		_beat_saved = false
	if not _beat_saved:
		_resolve_beat()
	_holders.append(owner)
	if is_instance_valid(_beat):
		_beat.paused = true


## Release a named hold. The saved state comes back only when the last holder has released.
func release_excitement(owner: String) -> void:
	var index := _holders.find(owner)
	if index >= 0:
		_holders.remove_at(index)
	if not _holders.is_empty():
		return
	_restore_beat()


## Act teardown fallback: drop every hold and restore the Beat once.
func reset_excitement_hold() -> void:
	_holders.clear()
	_restore_beat()


func _resolve_beat() -> void:
	var pony: Variant = host.get("pony") if is_instance_valid(host) else null
	if not is_instance_valid(pony):
		return
	var excitement: Variant = pony.get("excitement")
	if not excitement is Node:
		return
	var beat: Variant = (excitement as Node).get_node_or_null("Beat")
	if not beat is Timer:
		return
	_beat = beat as Timer
	_beat_paused = _beat.paused
	_beat_saved = true


func _restore_beat() -> void:
	if _beat_saved and is_instance_valid(_beat):
		_beat.paused = _beat_paused
	_beat = null
	_beat_saved = false
	_beat_paused = false
