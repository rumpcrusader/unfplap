extends SceneTree
## Pure proactive-request rules: the timer lock, the cooldown, the retry, the approach, the bed
## search and the wording mode.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/initiation/test_policy.gd

const POLICY := preload("res://mods/unfplap/initiation/policy.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	# The timings are observable only in play, so a transcription slip must fail here.
	check(POLICY.HEAT_COOLDOWN == 0.25, "heat cuts the offer cooldown to a quarter")
	check(POLICY.SCAN_INTERVAL_S == 0.5, "the scan runs twice a second")
	check(POLICY.QUIET_CHAT_GAP_S == 45.0, "a recent chat keeps the scan quiet")
	check(POLICY.APPROACH_RADIUS_M == 24.0, "the approach radius is 24 m")
	check(POLICY.APPROACH_GOAL_M == 2.0, "the ask spot is 2 m ahead of Anon")
	check(POLICY.ARRIVE_RANGE_M == 2.8, "she is near enough at 2.8 m")
	check(POLICY.ARRIVE_WAIT_S == 2.0, "the arrival settles for two seconds")
	check(POLICY.APPROACH_TIMEOUT_S == 35.0, "the walk has 35 s")
	check(POLICY.PLAYER_MOVE_CANCEL_M == 5.0, "Anon moving 5 m cancels the walk")
	check(POLICY.RETRY_S == 30.0, "a failed walk-over retries after 30 s")
	check(POLICY.BED_SEARCH_M == 7.0, "beds are searched within 7 m")
	check(POLICY.BED_LEAD_TIMEOUT_S == 25.0, "the bed walk has 25 s")

	check(POLICY.cooldown_ready(1000.0, 399.0, 600.0), "the cooldown is over at ten minutes")
	check(not POLICY.cooldown_ready(1000.0, 401.0, 600.0), "the cooldown blocks inside ten minutes")
	check(POLICY.cooldown_ready(1000.0, 949.0, 50.0), "the cooldown accepts an explicit wait")
	check(not POLICY.cooldown_ready(1000.0, 951.0, 50.0), "an explicit wait still blocks")
	check(POLICY.heat_cooldown(600.0) == 150.0, "heat quarters the cooldown")
	check(POLICY.retry_ready(1000.0, 999.0), "a passed retry is ready")
	check(not POLICY.retry_ready(1000.0, 1001.0), "a future retry still waits")

	check(POLICY.wording_mode(true) == POLICY.MODE_FREE, "a private offer words freely")
	check(POLICY.wording_mode(false) == POLICY.MODE_INDIRECT, "a public offer hints")
	check(POLICY.PHASE_APPROACH == "approach" and POLICY.PHASE_ASK == "ask",
		"the phase spellings are stable")
	check(POLICY.PHASE_BED_APPROACH == "bed_approach", "the bed approach phase is named")

	print("INITIATION_POLICY_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INITIATION_POLICY_PASS")
	quit(0 if failures == 0 else 1)
