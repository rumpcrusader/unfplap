extends "res://mods/unfplap/tests/support/suite.gd"
## Self-test fixture: one real check, then run() never returns, so the base watchdog must fail it.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/support/fixtures/watchdog_hang.gd


func before() -> void:
	watchdog_seconds = 0.3


func run() -> void:
	check_size("abc", 3, "the fixture reports one real check before the hang")
	await create_timer(30.0).timeout
