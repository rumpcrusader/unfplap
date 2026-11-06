extends SceneTree
## Pure admission-policy tests for act lines.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_utterance_scheduler.gd

const SCHED := preload("res://mods/unfplap/utterance_scheduler.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func fresh() -> RefCounted:
	var scheduler: RefCounted = SCHED.new()
	scheduler.reset(0.0, 12.0)
	return scheduler


func run() -> void:
	var base: RefCounted = fresh()
	var cue := "She wants you to keep going."
	base.observe_cue(0.0, cue)
	check(not base.admit_cue(1.9, cue, false), "base cue needs 2 s of stability")
	check(base.admit_cue(2.0, cue, false), "base cue admits at 2 s")
	base.note_cue_queued(2.0, "cue:1", cue, false)
	check(not base.channel_free(), "queued line owns the slot")
	check(base.pending_key() == "cue:1", "pending key is stored")
	check(base.pending_kind() == "cue", "pending kind is stored")
	check(not base.admit_cue(3.0, "She is close.", false), "a second line cannot take the slot")
	base.note_finished(10.0, "cue:1")
	check(not base.release_ready(10.9), "release waits 1 s after speech stops")
	check(base.release_ready(11.0), "release is ready after the hold")
	base.note_finished(12.0, "cue:1")
	check(base.release_ready(12.5), "a repeated delivered tick keeps the first finish time")
	base.release()
	check(base.channel_free(), "release frees the slot")

	base.observe_cue(11.0, "She is close.")
	check(not base.admit_cue(13.0, "She is close.", false), "cue gap blocks before 12 s")
	check(not base.admit_cue(19.9, "She is close.", false), "shared gap blocks before 18 s")
	check(base.admit_cue(20.0, "She is close.", false), "cue admits when both gaps clear")
	base.note_cue_queued(20.0, "cue:2", "She is close.", false)
	check(base.pending_until() == 40.0, "cue stores its 20 s max age")
	check(base.expired_key(40.0) == "", "not expired at the boundary")
	check(base.expired_key(40.1) == "cue:2", "expiry reports the pending key")

	var override: RefCounted = fresh()
	override.observe_cue(0.0, "She likes that.")
	check(not override.admit_cue(0.4, "She likes that.", true),
		"override cue settles for 0.5 s")
	check(override.admit_cue(0.5, "She likes that.", true), "override cue admits at 0.5 s")

	var demand: RefCounted = fresh()
	var want := "She wants it harder."
	demand.observe_cue(0.0, want)
	check(demand.admit_cue(2.0, want, false), "demand cue admits like any cue")
	demand.note_cue_queued(2.0, "cue:1", want, true)
	demand.note_finished(2.5, "cue:1")
	demand.release()
	check(not demand.demand_blocked("She is close.", 3.0), "non-demand is outside the budget")
	check(demand.demand_blocked(want, 10.0), "demand budget blocks inside 28 s")
	check(demand.demand_blocked(want, 40.0), "same demand text repeats only after 45 s")
	check(not demand.demand_blocked(want, 47.1), "same demand text clears after 45 s")

	var repeat: RefCounted = fresh()
	repeat.observe_cue(0.0, "A")
	check(repeat.admit_cue(2.0, "A", false), "first text admits")
	repeat.note_cue_queued(2.0, "k1", "A", false)
	repeat.note_finished(3.0, "k1")
	repeat.release()
	repeat.observe_cue(20.0, "A")
	check(not repeat.admit_cue(40.0, "A", false), "the last queued text does not repeat")
	repeat.observe_cue(40.0, "B")
	check(repeat.admit_cue(60.0, "B", false), "a different text admits")
	repeat.note_cue_queued(60.0, "k2", "B", false)
	repeat.note_finished(61.0, "k2")
	repeat.release()
	repeat.observe_cue(80.0, "A")
	check(repeat.admit_cue(100.0, "A", false), "the first text may return after another")

	var reaction: RefCounted = fresh()
	reaction.observe_cue(0.0, "A")
	check(reaction.admit_cue(2.0, "A", false), "cue admits before the reaction")
	reaction.note_reaction_queued(2.0, "reaction:1", "", 32.0)
	check(not reaction.channel_free(), "reaction takes the slot")
	check(reaction.pending_kind() == "reaction", "reaction kind is stored")
	check(not reaction.admit_cue(30.0, "B", false), "a cue cannot follow a pending reaction")
	reaction.note_finished(3.0, "reaction:1")
	check(not reaction.release_ready(3.9), "reaction release waits 1 s")
	check(reaction.release_ready(4.0), "reaction release is ready")
	reaction.release()
	check(reaction.channel_free(), "reaction release frees the slot")

	var reset_test: RefCounted = fresh()
	reset_test.note_reaction_queued(1.0, "orphan", "", 10.0)
	reset_test.reset(2.0, 12.0)
	check(reset_test.channel_free(), "reset clears the slot")
	check(reset_test.expired_key(100.0) == "", "reset clears the age")

	check(SCHED.mood_for(0.0, 0.0) == "warming", "mood warming")
	check(SCHED.mood_for(40.0, 0.0) == "wanting", "mood wanting")
	check(SCHED.mood_for(65.0, 0.0) == "close", "mood close")
	check(SCHED.mood_for(100.0, 1.0) == "overwhelmed", "overwhelmed overrides the band")

	var taste := {"intensity": "firm", "pattern": "steady"}
	check(SCHED.base_cue(taste, 0.0, 10.0, "soft", "") == "She wants it firmer.",
		"soft gives firmer")
	check(SCHED.base_cue(taste, 0.0, 10.0, "rough", "") == "She wants it softer.",
		"rough gives softer")
	var rough_taste := {"intensity": "rough", "pattern": "steady"}
	check(SCHED.base_cue(rough_taste, 0.0, 10.0, "firm", "") == "She wants it harder.",
		"rough taste gives harder")
	var soft_taste := {"intensity": "soft", "pattern": "steady"}
	check(SCHED.base_cue(soft_taste, 0.0, 10.0, "firm", "") == "She wants it softer.",
		"soft taste gives softer")
	check(SCHED.base_cue({"intensity": "firm", "pattern": "quick"}, 0.0, 10.0, "", "steady")
		== "She wants it quicker.", "quick pattern cue")
	check(SCHED.base_cue({"intensity": "firm", "pattern": "teasing"}, 0.0, 10.0, "", "steady")
		== "She wants to be teased.", "teasing pattern cue")
	check(SCHED.base_cue(taste, 0.0, 10.0, "firm", "steady") == "She likes that.",
		"both axes match")
	check(SCHED.base_cue(taste, 0.0, 10.0, "", "") == "She wants you to keep going.",
		"no axes is warming up")
	check(SCHED.base_cue(taste, 0.0, 65.0, "soft", "quick") == "She is close.",
		"close beats the axes")
	check(SCHED.base_cue(taste, 1.0, 10.0, "firm", "steady") == "She's overwhelmed.",
		"overwhelmed beats everything")

	print("UTTERANCE_SCHEDULER_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("UTTERANCE_SCHEDULER_PASS")
	quit(0 if failures == 0 else 1)
