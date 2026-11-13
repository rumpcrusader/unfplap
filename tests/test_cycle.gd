extends SceneTree
## Pure estrus-cycle rules and the feature flag.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_cycle.gd

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")

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
	check(CYCLE.phase_at(0.0) == CYCLE.HEAT, "cycle starts in heat")
	check(CYCLE.phase_at(6.999) == CYCLE.HEAT, "heat lasts through day six")
	check(CYCLE.phase_at(7.0) == CYCLE.DIESTRUS, "diestrus starts on day seven")
	check(CYCLE.phase_at(8.999) == CYCLE.DIESTRUS, "diestrus lasts two days")
	check(CYCLE.phase_at(9.0) == CYCLE.NORMAL, "normal starts on day nine")
	check(CYCLE.phase_at(29.999) == CYCLE.NORMAL, "normal runs to the end of the month")
	check(CYCLE.phase_at(30.0) == CYCLE.HEAT, "the cycle wraps after thirty days")
	check(CYCLE.phase_at(-1.0) == CYCLE.NORMAL, "negative days wrap into the month")

	check(CYCLE.offset("rarity") == CYCLE.offset("rarity"), "a mare's offset is stable")
	check(CYCLE.phase(12.0, "rarity") == CYCLE.phase(12.0, "rarity"),
		"a mare's phase is stable for the same day")
	check(CYCLE.phase(42.0, "rarity") == CYCLE.phase(12.0, "rarity"),
		"a mare repeats on a thirty-day month")
	check(CYCLE.phase(12.0, "rarity") == CYCLE.phase_at(12.0 + CYCLE.offset("rarity")),
		"phase uses the mare offset")
	check(CYCLE.offset("rarity") >= 0.0 and CYCLE.offset("rarity") < CYCLE.MONTH_DAYS,
		"an offset stays inside the month")

	check(CYCLE.allows_sex(CYCLE.HEAT), "heat allows sex")
	check(CYCLE.allows_sex(CYCLE.NORMAL), "normal allows sex")
	check(not CYCLE.allows_sex(CYCLE.DIESTRUS), "diestrus blocks sex")

	check(CYCLE.prompt_note(CYCLE.HEAT).contains("heat"), "heat has a prompt note")
	check(CYCLE.prompt_note(CYCLE.DIESTRUS).contains("turned off"),
		"diestrus has a prompt note")
	check(CYCLE.prompt_note(CYCLE.NORMAL).is_empty(), "normal has no prompt note")

	var interval_ok := true
	for _i in 200:
		var interval := CYCLE.wink_interval(10.0, 20.0)
		if interval < 10.0 or interval > 20.0:
			interval_ok = false
	check(interval_ok, "idle wink interval respects the configured pair")
	var reversed := CYCLE.wink_interval(20.0, 10.0)
	check(reversed >= 10.0 and reversed <= 20.0, "a reversed wink pair is sorted")
	check(CYCLE.wink_burst_count(0.0) == 3, "the bottom roll is a triple")
	check(CYCLE.wink_burst_count(0.0499) == 3, "triples stop below five percent")
	check(CYCLE.wink_burst_count(0.05) == 2, "doubles start at five percent")
	check(CYCLE.wink_burst_count(0.2999) == 2, "doubles stop below thirty percent")
	check(CYCLE.wink_burst_count(0.30) == 1, "singles start at thirty percent")
	check(CYCLE.wink_burst_count(0.999) == 1, "the top roll is a single")

	check(not bool(SETTINGS.estrus_cycle.default), "estrus is off by default")

	# A pony that has only just spawned has no relationship runtime yet. The anatomy bridge asks
	# for the phase during its bind, so the read must not warn or throw.
	var runtime: Node = RUNTIME.new()
	var pony := Node3D.new()
	pony.set_meta("relationship_id", "rarity")
	root.add_child(pony)
	runtime.pony = pony
	var was_on := SETTINGS.estrus_cycle.get_bool()
	SETTINGS.estrus_cycle.set_bool(true)
	check(str(runtime.call("cycle_phase")) == CYCLE.NORMAL,
		"a pony without a relationship runtime reads a normal phase")
	SETTINGS.estrus_cycle.set_bool(false)
	check(str(runtime.call("cycle_phase")) == CYCLE.NORMAL, "estrus off reads a normal phase")
	SETTINGS.estrus_cycle.set_bool(was_on)
	root.remove_child(pony)
	pony.free()
	runtime.free()

	print("CYCLE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("CYCLE_PASS")
	quit(0 if failures == 0 else 1)
