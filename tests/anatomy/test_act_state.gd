extends SceneTree
## Pure act-anatomy decisions: the hole/oral mix, the shared shape drive and the wink scheduler.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_act_state.gd

const STATE := preload("res://mods/unfplap/anatomy/act/state.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	# The non-anal, non-oral share is 1 at rest and 0 when either turn owns the mesh.
	check(near(STATE.front(0.0, 0.0), 1.0), "the vulva owns the shape at rest")
	check(near(STATE.front(1.0, 0.0), 0.0), "the anal mix removes the vulva share")
	check(near(STATE.front(0.0, 1.0), 0.0), "the oral mix removes the vulva share")
	check(near(STATE.front(1.0, 1.0), 0.0), "a full anal and oral mix leaves no front share")

	# The hole swap eases over its seconds and settles at the selected side.
	check(near(STATE.hole_mix_step(0.0, true, 0.9, 0.45), 0.5),
		"the hole swap moves halfway in half its time")
	check(near(STATE.hole_mix_step(0.9, true, 0.9, 0.9), 1.0),
		"the anal side settles at 1")
	check(near(STATE.hole_mix_step(0.1, false, 0.9, 0.9), 0.0),
		"the vulva side settles at 0")
	check(near(STATE.hole_mix_step(0.0, true, 0.0, 0.016), 1.0),
		"a zero swap time is guarded")

	# The closed value keeps the grip through the climax and follows the oral/anal turn.
	check(near(STATE.closed_for(0.0, 0.0, 0.0, 0.6), 0.6),
		"the resting shape opens to the configured heat rest")
	check(near(STATE.closed_for(1.0, 0.0, 0.0, 0.6), 0.0),
		"a full fill opens the lips")
	check(near(STATE.closed_for(0.0, 0.0, 1.0, 0.6), 1.0),
		"the oral turn closes the vulva drive")

	# The climax wink is one open/close pulse from the remaining beat time.
	check(near(STATE.wink_beat(1.0, 1.0, 1.0), 0.0), "the beat starts closed")
	check(near(STATE.wink_beat(0.5, 1.0, 1.0), 1.0), "the beat peaks halfway")
	check(near(STATE.wink_beat(0.0, 1.0, 1.0), 0.0), "the beat ends closed")
	check(near(STATE.wink_beat(0.0, 0.0, 1.0), 0.0), "a zero-length beat is guarded")

	# The act wink decision: 0 nothing, 1 touching, 2 pulled out after a climax.
	check(STATE.wink_mode(0.6, true, 2) == 0, "a thrusting shaft raises no wink")
	check(STATE.wink_mode(0.0, true, 0) == 1, "the tip at her lips winks on its own")
	check(STATE.wink_mode(0.0, false, 0) == 0,
		"a pulled-out shaft waits before any climax")
	check(STATE.wink_mode(0.1, false, 1) == 2,
		"a pulled-out shaft after a climax winks often")
	check(STATE.wink_mode(STATE.PULLED_OUT_PHASE, false, 1) == 0,
		"the pulled-out threshold is exclusive")

	# The oral anchor: the opening holds through the turn, then eases to the live mouth, and the
	# release blends back to the opening as the mix falls.
	var opening := Vector3(1.0, 0.5, 2.0)
	var mouth := Vector3(1.4, 0.5, 2.3)
	check(STATE.oral_anchor_step(Vector3.INF, mouth, opening, 0.5, true, 0.8, 0.25) \
		.is_equal_approx(opening),
		"an unfinished turn holds the opening")
	check(STATE.oral_anchor_step(Vector3.INF, mouth, opening, 1.0, true, 0.8, 0.25) \
		.is_equal_approx(mouth),
		"a settled first tick starts at the live mouth")
	var eased: Vector3 = STATE.oral_anchor_step(opening, mouth, opening, 1.0, true, 0.8, 0.25)
	check(eased.distance_to(mouth) < opening.distance_to(mouth),
		"a settled turn eases toward the live mouth")
	var settled: Vector3 = STATE.oral_anchor_step(opening, mouth, opening, 1.0, true, 0.8, 100.0)
	check(settled.distance_to(mouth) < 0.001, "a long settled tick reaches the live mouth")
	check(STATE.oral_anchor_step(mouth, mouth, opening, 1.0, false, 0.8, 0.25) \
		.is_equal_approx(mouth),
		"a full release mix keeps the last anchor")
	check(STATE.oral_anchor_step(mouth, mouth, opening, 0.0, false, 0.8, 0.25) \
		.is_equal_approx(opening),
		"a finished release is exactly the opening")
	check(STATE.oral_anchor_step(opening.lerp(mouth, 0.5), mouth, opening, 0.5, false, 0.8, 0.25) \
		.is_equal_approx(opening.lerp(opening.lerp(mouth, 0.5), 0.5)),
		"a half release mix halves the anchor's distance to the opening")
	check(STATE.oral_anchor_step(opening, Vector3.INF, opening, 1.0, true, 0.8, 0.25) \
		.is_equal_approx(opening),
		"a non-finite mouth falls back to the opening")
	check(STATE.oral_anchor_step(mouth, mouth, Vector3.INF, 1.0, true, 0.8, 0.25) \
		.is_equal_approx(mouth),
		"a non-finite opening leaves the anchor alone")

	print("ANATOMY_ACT_STATE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
