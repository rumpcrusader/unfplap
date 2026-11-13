extends SceneTree
## Pure proactive-request rules: the timer lock, cooldowns, privacy, wording mode, the prompt
## schedule, pose choice, weighted picks and the closing-phase tables.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/initiation/test_policy.gd

const POLICY := preload("res://mods/unfplap/initiation/policy.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

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
	check(POLICY.COOLDOWN_S == 600.0, "the offer cooldown is ten minutes")
	check(POLICY.HEAT_COOLDOWN == 0.25, "heat cuts the offer cooldown to a quarter")
	check(POLICY.SCAN_INTERVAL_S == 0.5, "the scan runs twice a second")
	check(POLICY.QUIET_CHAT_GAP_S == 45.0, "a recent chat keeps the scan quiet")
	check(POLICY.APPROACH_RADIUS_M == 24.0, "the approach radius is 24 m")
	check(POLICY.APPROACH_GOAL_M == 2.0, "the ask spot is 2 m ahead of Anon")
	check(POLICY.ARRIVE_RANGE_M == 2.8, "she is near enough at 2.8 m")
	check(POLICY.ARRIVE_WAIT_S == 2.0, "the arrival settles for two seconds")
	check(POLICY.APPROACH_TIMEOUT_S == 35.0, "the walk has 35 s")
	check(POLICY.PLAYER_MOVE_CANCEL_M == 5.0, "Anon moving 5 m cancels the walk")
	check(POLICY.ASK_RANGE_CANCEL_M == 8.0, "the ask cancels past 8 m")
	check(POLICY.PRIVACY_RADIUS_M == 30.0, "privacy looks 30 m out")
	check(POLICY.PROMPT_1_S == 12.0, "the first reminder is at twelve seconds")
	check(POLICY.PROMPT_2_S == 24.0, "the second reminder is at twenty-four seconds")
	check(POLICY.GIVE_UP_S == 60.0, "an unanswered offer gives up at sixty seconds")
	check(POLICY.REPLY_GRACE_S == 45.0, "an answer gets 45 s")
	check(POLICY.CLARIFY_GRACE_S == 30.0, "a clarification gets 30 s")
	check(POLICY.INVITE_TIMEOUT_S == 60.0, "the invitation waits 60 s")
	check(POLICY.PRESENT_TURN_TIMEOUT_S == 5.0, "the present turn has a 5 s cap")
	check(POLICY.RETRY_S == 30.0, "a failed walk-over retries after 30 s")
	check(POLICY.BED_SEARCH_M == 10.0, "beds are searched within 10 m")
	check(POLICY.BED_LEAD_TIMEOUT_S == 25.0, "the bed walk has 25 s")
	check(POLICY.BED_WAIT_TIMEOUT_S == 90.0, "the bed wait has 90 s")
	check(POLICY.PHYSICAL_ACCEPT_GRACE_S == 2.5, "lying down counts after 2.5 s")
	check(POLICY.DEADLINE_EXTEND_S == 5.0, "a busy director extends the deadline by 5 s")

	check(POLICY.cooldown_ready(1000.0, 399.0), "the cooldown is over at ten minutes")
	check(not POLICY.cooldown_ready(1000.0, 401.0), "the cooldown blocks inside ten minutes")
	check(POLICY.cooldown_ready(1000.0, 949.0, 50.0), "the cooldown accepts an explicit wait")
	check(not POLICY.cooldown_ready(1000.0, 951.0, 50.0), "an explicit wait still blocks")
	check(POLICY.heat_cooldown(600.0) == 150.0, "heat quarters the cooldown")
	check(POLICY.retry_ready(1000.0, 999.0), "a passed retry is ready")
	check(not POLICY.retry_ready(1000.0, 1001.0), "a future retry still waits")

	check(POLICY.cuddle_private(true, true, false), "an indoor cuddle needs house solitude")
	check(not POLICY.cuddle_private(true, false, false),
		"an indoor cuddle rejects another pony in the house")
	check(POLICY.cuddle_private(false, false, false), "an outdoor cuddle needs nobody near")
	check(not POLICY.cuddle_private(false, false, true),
		"an outdoor cuddle rejects a nearby pony")
	check(POLICY.cuddle_private(false, false, false),
		"an outdoor cuddle ignores the house state")

	check(POLICY.offer_private(true, false, true), "a public offer overrides the reserve")
	check(POLICY.offer_private(false, true, true), "house solitude allows an offer")
	check(POLICY.offer_private(false, false, false), "nobody near allows an offer")
	check(not POLICY.offer_private(false, false, true),
		"a nearby pony blocks an offer without house solitude")

	check(POLICY.wording_mode(true) == POLICY.MODE_FREE, "a private offer words freely")
	check(POLICY.wording_mode(false) == POLICY.MODE_INDIRECT, "a public offer hints")

	check(POLICY.next_prompt_time(0) == 12.0, "the first reminder time")
	check(POLICY.next_prompt_time(1) == 24.0, "the second reminder time")
	check(POLICY.next_prompt_time(2) < 0.0, "there is no third reminder")

	check(POLICY.physical_yes(true, false, false, 3.0, true),
		"a bed offer accepts the physical yes")
	check(not POLICY.physical_yes(false, false, false, 3.0, true),
		"a standing offer has no bed yes")
	check(not POLICY.physical_yes(true, true, false, 3.0, true),
		"a cuddle never counts as a physical yes")
	check(not POLICY.physical_yes(true, false, true, 3.0, true),
		"a pending answer defers the physical yes")
	check(not POLICY.physical_yes(true, false, false, 1.0, true),
		"the physical-yes grace still applies")
	check(not POLICY.physical_yes(true, false, false, 3.0, false),
		"lying down on the offered bed is required")

	check(POLICY.pick_offer_pose(true, true, 0.1) == CATALOG.MISSIONARY,
		"the bed wins the low coin flip")
	check(POLICY.pick_offer_pose(true, true, 0.9) == CATALOG.STANDING,
		"standing wins the high coin flip")
	check(POLICY.pick_offer_pose(true, false, 0.9) == CATALOG.MISSIONARY,
		"the bed is used when standing is unavailable")
	check(POLICY.pick_offer_pose(false, true, 0.1) == CATALOG.STANDING,
		"standing is used when no bed is available")
	check(POLICY.pick_offer_pose(false, false, 0.5) == "",
		"no pose when neither offer fits")

	var weights := [0.7, 0.3]
	check(POLICY.weighted_pick(weights, 0.0) == 0, "a low roll picks the first candidate")
	check(POLICY.weighted_pick(weights, 0.8) == 1, "a high roll picks the second candidate")
	check(POLICY.weighted_pick([0.0], 0.5) == -1, "zero total weight picks nothing")
	check(POLICY.weighted_pick([], 0.5) == -1, "an empty list picks nothing")
	check(POLICY.weighted_pick([1.0, 0.0], 0.99) == 0, "a zero weight is never picked")

	check(POLICY.sets_cooldown(POLICY.PHASE_ASK), "a finished ask sets the cooldown")
	check(POLICY.sets_cooldown(POLICY.PHASE_BED_WAIT), "a finished bed wait sets the cooldown")
	check(not POLICY.sets_cooldown(POLICY.PHASE_APPROACH), "a walk-over sets no cooldown")
	check(POLICY.sets_retry(POLICY.PHASE_APPROACH), "a walk-over sets the short retry")
	check(POLICY.sets_retry(POLICY.PHASE_BED_APPROACH),
		"a failed bed approach sets the short retry")
	check(not POLICY.sets_retry(POLICY.PHASE_NONE), "no phase sets no retry")
	check(POLICY.invite_phase(POLICY.PHASE_BED_WAIT), "a bed wait accepts an invitation")
	check(not POLICY.invite_phase(POLICY.PHASE_ASK), "an ask rejects an invitation")

	print("INITIATION_POLICY_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INITIATION_POLICY_PASS")
	quit(0 if failures == 0 else 1)
