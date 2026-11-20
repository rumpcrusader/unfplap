extends SceneTree
## Pure anatomy helpers: the princess body profile and the off-roster list. The stable pony id is
## `shared/pony_id.gd` and the adult capability is the eligibility service.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_identity.gd

const IDENTITY := preload("res://mods/unfplap/anatomy/identity.gd")

var failures := 0
var checks := 0


class FakeIdentity extends Resource:
	var id := ""
	var character_id := ""


class FakePony extends Node3D:
	var identity: Resource = null


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _identity(id: String, character_id := "") -> FakeIdentity:
	var identity := FakeIdentity.new()
	identity.id = id
	identity.character_id = character_id
	return identity


func run() -> void:
	# A modded copy uses the canon body profile through character_id; an ordinary mare does not.
	var copy: Array[float] = IDENTITY.body_profile(_identity("custom_celestia", "celestia"))
	check(copy.size() == 3, "a modded Celestia copy uses the princess body profile")
	check(IDENTITY.body_profile(_identity("luna")).size() == 3,
		"the canon id selects the body profile")
	check(IDENTITY.body_profile(_identity("not_a_base_mare")).is_empty(),
		"an ordinary modded mare uses the normal body profile")
	check(IDENTITY.body_profile(null).is_empty(), "no identity has no body profile")

	# The body-fit key: an integration's metadata, then character_id, then the identity id.
	var pony := FakePony.new()
	pony.identity = _identity("chrysalis", "celestia")
	pony.set_meta("body_fit_id", "chrysalis")
	check(IDENTITY.body_fit_id(pony) == "chrysalis", "metadata wins the body fit")
	pony.remove_meta("body_fit_id")
	check(IDENTITY.body_fit_id(pony) == "celestia", "character_id is the body fit fallback")
	pony.identity = _identity("fluttershy")
	check(IDENTITY.body_fit_id(pony) == "fluttershy", "the identity id is the last fallback")
	pony.identity = null
	check(IDENTITY.body_fit_id(pony).is_empty(), "no identity has no body fit")
	check(IDENTITY.body_fit_id(null).is_empty(), "no pony has no body fit")

	# The profile follows the body she is wearing now, so a copy on a princess body fits that body
	# and a princess wearing an ordinary body does not.
	pony.identity = _identity("celestia")
	check(IDENTITY.body_profile_for(pony).size() == 3,
		"her own princess body names the profile")
	pony.set_meta("body_fit_id", "chrysalis")
	check(IDENTITY.body_profile_for(pony).is_empty(),
		"a princess wearing an ordinary body drops the princess profile")
	pony.remove_meta("body_fit_id")
	pony.identity = _identity("chrysalis", "celestia")
	check(IDENTITY.body_profile_for(pony).size() == 3,
		"a copied princess body names the profile")
	check(IDENTITY.body_profile(pony.identity).size() == 3,
		"the identity path keeps the copied body profile")
	pony.set_meta("body_fit_id", "chrysalis")
	check(IDENTITY.body_profile_for(pony).is_empty(),
		"the body-fit metadata wins over the identity profile")
	pony.remove_meta("body_fit_id")
	pony.identity = null
	check(IDENTITY.body_profile_for(pony).is_empty(), "no identity has no worn body profile")
	check(IDENTITY.body_profile_for(null).is_empty(), "no pony has no worn body profile")
	pony.free()

	# Deduplicated off-roster ids, excluding the base roster.
	var ids: Array[String] = ["not_a_base_mare", "twilight_sparkle", "not_a_base_mare", ""]
	var roster: Array[String] = ["twilight_sparkle"]
	var out := IDENTITY.off_roster_ids(ids, roster)
	check(out.size() == 1 and out[0] == "not_a_base_mare",
		"the off-roster list deduplicates and excludes the base roster")

	print("ANATOMY_IDENTITY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
