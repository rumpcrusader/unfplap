extends RefCounted
## Standing oral procedural delta: the movable neck swing that keeps her muzzle along the shaft
## while the standing base holds the stance and the frame. The `standing_oral` row names this file
## as its `delta`; the evaluator runs it after the standing base and before the overlay. The
## values come from the pose turn's style motion on the live config. Contract: `docs/poses.md`.

## The head counters the neck's pitch and yaw so the muzzle does not follow the whole swing.
const ORAL_HEAD_COUNTER := 0.75

var _config: Dictionary = {}


## The delta entry point: two neck bones share the pitch and yaw, and the head counters them and
## takes the roll. A zero key set leaves the normal standing pose untouched. `weight` is the edge
## or base weight; the style values are already eased by the pose turn.
func apply_delta(rig, sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	_config = state.get("config", {})
	if rig.neck.size() < 3:
		return
	var pitch := _value("oral_pitch", 0.0) * weight
	var yaw := _value("oral_yaw", 0.0) * weight
	var roll := _value("oral_roll", 0.0) * weight
	if absf(pitch) + absf(yaw) + absf(roll) < 0.0001:
		return
	var right: Vector3 = rig.right_axis(sk)
	var up: Vector3 = rig.up_axis(sk)
	var forward: Vector3 = rig.forward_axis(sk)
	for i: int in 2:
		rig.rotate(sk, rig.neck[i], right, pitch * 0.5)
		rig.rotate(sk, rig.neck[i], up, yaw * 0.5)
	var head: int = rig.neck[2]
	rig.rotate(sk, head, right, -pitch * ORAL_HEAD_COUNTER)
	rig.rotate(sk, head, up, -yaw * ORAL_HEAD_COUNTER)
	rig.rotate(sk, head, forward, roll)


func _value(key: String, fallback: float) -> float:
	var value: Variant = _config.get(key)
	return float(value) if value != null else fallback
