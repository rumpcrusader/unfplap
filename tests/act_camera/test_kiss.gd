extends "res://mods/unfplap/tests/support/suite.gd"
## The act's kiss module: the stock kiss's own state and the global rows it lifts.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/act_camera/test_kiss.gd

const KISS := preload("res://mods/unfplap/act/kiss.gd")
const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const FACTS := preload("res://mods/unfplap/shared/act_facts.gd")


func run() -> void:
	var kiss: RefCounted = KISS.new()
	var host: RefCounted = ACT_HOST.new()
	var context: RefCounted = ACT_CONTEXT.new()
	kiss.bind(host, context)
	check(not kiss.active(), "the stock kiss starts inactive")
	check(not kiss.start(1.0), "a standing start without her body is refused")
	check(not kiss.active(), "a refused start leaves no stock kiss")
	context.facts = FACTS.new()
	check(not kiss.start(1.0), "a start without the game's kisser is refused")
	check(not kiss.active(), "a refused kisser starts no stock affection")
	kiss.stop()
	kiss.stop()
	check(not kiss.active(), "stopping an idle kiss is a no-op")
	kiss.refresh_rows()
	check(not kiss.active(), "an idle row refresh changes nothing")
	kiss.reset()
	check(not kiss.active(), "a reset leaves the module idle")
	check(is_nan(KISS._saved_rear) and is_nan(KISS._saved_hooves),
		"a reset without a captured row leaves the statics clear")
	KISS.restore_rows()
	KISS.restore_rows()
	check(is_nan(KISS._saved_rear) and is_nan(KISS._saved_hooves),
		"restoring the rows twice is safe")
	if failures == 0:
		print("KISS_PASS")
	finish()
