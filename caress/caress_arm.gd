extends RefCounted
## Reach plan for a caress hand. It is pure: given the shoulder, arm lengths and wrist target, it
## decides how much shoulder/body shift is needed, how much the arm must stretch, and whether the
## target is reachable. The caller applies the returned frames; the hand is never placed beyond
## the solved/limited wrist.


## `shoulder_limit` and `body_limit` are metres. The body share is the same translation as the
## shoulder share in this first pass; it is reported separately for tuning/logging.
static func plan(shoulder: Vector3, upper_len: float, lower_len: float, target: Vector3,
		max_stretch := 1.25, shoulder_limit := 0.08, body_limit := 0.0) -> Dictionary:
	var axis := target - shoulder
	var distance := axis.length()
	if distance < 0.00001:
		return {
			"shoulder_origin": shoulder, "target": target, "reachable": true,
			"shoulder_shift": 0.0, "body_shift": 0.0, "stretch": 1.0,
			"distance": 0.0, "max_reach": (upper_len + lower_len) * max_stretch,
		}
	var direction := axis / distance
	var max_reach := (upper_len + lower_len) * max_stretch
	var deficit := maxf(0.0, distance - max_reach)
	var shoulder_shift := minf(deficit, maxf(shoulder_limit, 0.0))
	var body_shift := minf(deficit - shoulder_shift, maxf(body_limit, 0.0))
	var shift := shoulder_shift + body_shift
	var origin := shoulder + direction * shift
	var wanted := target
	var reachable := true
	if distance - shift > max_reach:
		wanted = origin + direction * max_reach
		reachable = false
	var solved_distance := wanted.distance_to(origin)
	var native := maxf(upper_len + lower_len, 0.001)
	var stretch := clampf(solved_distance / native, 1.0, maxf(max_stretch, 1.0))
	return {
		"shoulder_origin": origin,
		"target": wanted,
		"reachable": reachable,
		"shoulder_shift": shoulder_shift,
		"body_shift": body_shift,
		"stretch": stretch,
		"distance": solved_distance,
		"max_reach": max_reach,
	}
