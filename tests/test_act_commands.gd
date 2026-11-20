extends "res://mods/unfplap/tests/support/suite.gd"
## The act command vocabulary: unique lower_snake_case ids, the continuous/discrete partition of
## `ALL`, the pure helpers and the reserved `end`. Run:
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_act_commands.gd

const ACT_COMMANDS := preload("res://mods/unfplap/shared/act_commands.gd")



func run() -> void:
	_check_vocabulary()
	_check_partition()
	_check_helpers()
	if failures == 0:
		print("ACT_COMMANDS_PASS")
	finish()


## The shipped ids are fixed, unique, non-empty and lower_snake_case; the const list matches them.
func _check_vocabulary() -> void:
	var expected := [ACT_COMMANDS.THRUST, ACT_COMMANDS.LEAN, ACT_COMMANDS.CARESS,
		ACT_COMMANDS.KISS, ACT_COMMANDS.ORAL, ACT_COMMANDS.HOLE,
		ACT_COMMANDS.POSE_BACK, ACT_COMMANDS.POSE_FORWARD, ACT_COMMANDS.END]
	check(ACT_COMMANDS.ALL == expected, "the vocabulary is the nine shipped ids")
	var pattern := RegEx.new()
	pattern.compile("^[a-z][a-z0-9_]*$")
	var seen := {}
	for value: Variant in ACT_COMMANDS.ALL:
		var id := str(value)
		check(not id.is_empty(), "a command id is non-empty")
		check(pattern.search(id) != null, "command id %s is lower_snake_case" % id)
		check(not seen.has(id), "command id %s is unique" % id)
		seen[id] = true


## `CONTINUOUS` and `DISCRETE` together cover every id exactly once.
func _check_partition() -> void:
	var seen := {}
	for value: Variant in ACT_COMMANDS.CONTINUOUS:
		var id := str(value)
		check(ACT_COMMANDS.ALL.has(id), "continuous id %s is in ALL" % id)
		check(not seen.has(id), "continuous id %s appears once" % id)
		seen[id] = true
	for value: Variant in ACT_COMMANDS.DISCRETE:
		var id := str(value)
		check(ACT_COMMANDS.ALL.has(id), "discrete id %s is in ALL" % id)
		check(not seen.has(id), "discrete id %s does not repeat a continuous one" % id)
		seen[id] = true
	check(seen.size() == ACT_COMMANDS.ALL.size(), "continuous and discrete partition ALL")
	check(not ACT_COMMANDS.CONTINUOUS.is_empty() and not ACT_COMMANDS.DISCRETE.is_empty(),
		"both halves are declared")


## The helpers agree with the arrays; `end` is the one reserved id.
func _check_helpers() -> void:
	for value: Variant in ACT_COMMANDS.ALL:
		var id := str(value)
		check(ACT_COMMANDS.is_command(id), "%s is a command" % id)
		check(ACT_COMMANDS.is_continuous(id) == ACT_COMMANDS.CONTINUOUS.has(id),
			"%s agrees with CONTINUOUS" % id)
		check(ACT_COMMANDS.is_reserved(id) == (id == ACT_COMMANDS.END),
			"%s is reserved only for end" % id)
	check(not ACT_COMMANDS.is_command(""), "an empty id is not a command")
	check(not ACT_COMMANDS.is_command("nonsense"), "an unknown id is not a command")
	check(not ACT_COMMANDS.is_command("Thrust"), "the ids are case-sensitive")
	check(not ACT_COMMANDS.is_continuous(""), "an empty id is not continuous")
	check(not ACT_COMMANDS.is_reserved(""), "an empty id is not reserved")
	check(not ACT_COMMANDS.is_reserved(ACT_COMMANDS.THRUST), "only end is reserved")
	check(ACT_COMMANDS.is_reserved(ACT_COMMANDS.END), "end is reserved")
