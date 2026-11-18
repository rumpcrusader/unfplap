extends SceneTree
## Pure anatomy helpers: the princess body profile and the off-roster list. The stable pony id is
## `shared/pony_id.gd` and the adult capability is the eligibility service.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_identity.gd

const IDENTITY := preload("res://mods/unfplap/anatomy/identity.gd")

var failures := 0
var checks := 0


class FakePony extends Node3D:
	var identity: Variant = null


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	# A modded copy uses the canon body profile through character_id; an ordinary mare does not.
	check(IDENTITY.body_profile({"id": "custom_celestia", "character_id": "celestia"}).size() == 3,
		"a modded Celestia copy uses the princess body profile")
	check(IDENTITY.body_profile({"id": "luna"}).size() == 3,
		"the canon id selects the body profile")
	check(IDENTITY.body_profile({"id": "not_a_base_mare"}).is_empty(),
		"an ordinary modded mare uses the normal body profile")
	check(IDENTITY.body_profile(null).is_empty(), "no identity has no body profile")

	# The body-fit key: an integration's metadata, then character_id, then the identity id.
	var pony := FakePony.new()
	pony.identity = {"id": "chrysalis", "character_id": "celestia"}
	pony.set_meta("body_fit_id", "chrysalis")
	check(IDENTITY.body_fit_id(pony) == "chrysalis", "metadata wins the body fit")
	pony.remove_meta("body_fit_id")
	check(IDENTITY.body_fit_id(pony) == "celestia", "character_id is the body fit fallback")
	pony.identity = {"id": "fluttershy", "character_id": ""}
	check(IDENTITY.body_fit_id(pony) == "fluttershy", "the identity id is the last fallback")
	pony.identity = null
	check(IDENTITY.body_fit_id(pony).is_empty(), "no identity has no body fit")
	check(IDENTITY.body_fit_id(null).is_empty(), "no pony has no body fit")
	pony.free()

	# Deduplicated off-roster ids, excluding the base roster.
	var ids: Array[String] = ["not_a_base_mare", "twilight_sparkle", "not_a_base_mare", ""]
	var out := IDENTITY.off_roster_ids(ids, ["twilight_sparkle"])
	check(out.size() == 1 and out[0] == "not_a_base_mare",
		"the off-roster list deduplicates and excludes the base roster")

	print("ANATOMY_IDENTITY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
