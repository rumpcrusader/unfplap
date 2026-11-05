extends SceneTree
## Pure lover-bond policy: Promiscuity levels, stored bond, break-up validity and the Starting
## Sex bypass. No world or user:// file is touched.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_sex_bond.gd

const SEX_BOND := preload("res://mods/unfplap/sex_bond.gd")

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
	check(SEX_BOND.level_ok("soulmates", 4), "Soulmates accepts level 4")
	check(not SEX_BOND.level_ok("soulmates", 3), "Soulmates rejects level 3")
	check(SEX_BOND.level_ok("head_over_hooves", 3), "Head Over Hooves accepts level 3")
	check(not SEX_BOND.level_ok("head_over_hooves", 2), "Head Over Hooves rejects level 2")
	check(SEX_BOND.level_ok("marefriend", 2), "Marefriend accepts level 2")
	check(not SEX_BOND.level_ok("marefriend", 1), "Marefriend rejects level 1")
	check(SEX_BOND.level_ok("new_couple", 1), "New Couple accepts level 1")
	check(not SEX_BOND.level_ok("new_couple", 0), "New Couple rejects level 0")
	check(SEX_BOND.level_ok("crush", 0), "Crush accepts level 0")
	check(not SEX_BOND.level_ok("crush", -1), "Crush rejects no crush")
	check(SEX_BOND.level_ok("any", -1), "Any Adult skips the love level")
	check(SEX_BOND.level_ok("", 2), "unknown Promiscuity falls back to Marefriend")
	check(not SEX_BOND.level_ok("", 1), "fallback still has a floor")

	check(SEX_BOND.bypasses_bond("try_luck"), "Try Your Luck bypasses the bond")
	check(not SEX_BOND.bypasses_bond("default"), "Default requires the bond")
	check(not SEX_BOND.bypasses_bond(""), "unknown Starting Sex is not a bypass")

	check(SEX_BOND.romantic_stage("dating"), "dating is romantic")
	check(SEX_BOND.romantic_stage("engaged"), "engaged is romantic")
	check(SEX_BOND.romantic_stage("married"), "married is romantic")
	check(not SEX_BOND.romantic_stage("close_friend"), "close friend is not romantic")
	check(not SEX_BOND.romantic_stage(""), "empty stage is not romantic")

	var section: Dictionary = {}
	check(not SEX_BOND.bonded(section, "rarity"), "no stored bond")
	check(SEX_BOND.grant(section, "rarity", "dating", 2, "test", "I would like that."),
		"grant writes a bond")
	check(SEX_BOND.bonded(section, "rarity"), "granted bond reads back")
	check(SEX_BOND.grant(section, "rarity", "dating", 2, "test", "again"),
		"grant is idempotent")
	var row: Dictionary = SEX_BOND.row(section, "rarity")
	check(str(row.get("stage", "")) == "dating", "row keeps the stage")
	check(int(row.get("love_level", -1)) == 2, "row keeps the love level")
	check(SEX_BOND.set_stage(section, "rarity", "engaged"), "stage refresh works")
	check(str(SEX_BOND.row(section, "rarity").get("stage", "")) == "engaged",
		"stage refresh is stored")
	check(SEX_BOND.clear(section, "rarity", "test"), "clear removes the bond")
	check(not SEX_BOND.bonded(section, "rarity"), "cleared bond is gone")
	check(not SEX_BOND.clear(section, "rarity", "test"), "second clear is a no-op")

	section["sex_bonds"] = {"rarity": {"stage": "dating"}}
	check(not SEX_BOND.bonded(section, "rarity"), "malformed row without a timestamp is ignored")

	print("SEX_BOND_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("SEX_BOND_PASS")
	quit(0 if failures == 0 else 1)
