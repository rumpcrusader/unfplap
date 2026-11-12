extends SceneTree
## Pure anatomy helpers: the stable id, the princess body profile and the off-roster list.
## The adult capability is tested with the eligibility service in `tests/eligibility/`.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_identity.gd

const IDENTITY := preload("res://mods/unfplap/anatomy/identity.gd")

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
	# Relationship metadata wins over the identity id.
	check(IDENTITY.id_for("relationship_id", {"id": "identity_id"}) == "relationship_id",
		"relationship id wins")
	check(IDENTITY.id_for("", {"id": "identity_id"}) == "identity_id",
		"the identity id is the fallback")
	check(IDENTITY.id_for("", null) == "", "no identity has no id")

	# A modded copy uses the canon body profile through character_id; an ordinary mare does not.
	check(IDENTITY.body_profile({"id": "custom_celestia", "character_id": "celestia"}).size() == 3,
		"a modded Celestia copy uses the princess body profile")
	check(IDENTITY.body_profile({"id": "luna"}).size() == 3,
		"the canon id selects the body profile")
	check(IDENTITY.body_profile({"id": "not_a_base_mare"}).is_empty(),
		"an ordinary modded mare uses the normal body profile")
	check(IDENTITY.body_profile(null).is_empty(), "no identity has no body profile")

	# Deduplicated off-roster ids, excluding the base roster.
	var ids: Array[String] = ["not_a_base_mare", "twilight_sparkle", "not_a_base_mare", ""]
	var out := IDENTITY.off_roster_ids(ids, ["twilight_sparkle"])
	check(out.size() == 1 and out[0] == "not_a_base_mare",
		"the off-roster list deduplicates and excludes the base roster")

	print("ANATOMY_IDENTITY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
