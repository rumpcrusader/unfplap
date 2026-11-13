extends SceneTree
## Pure lover-bond storage: rows, stage refresh, break-up validity and idempotence. The
## Promiscuity ladder and Starting Sex live in the eligibility policy tests.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/bond/test_sex_bond.gd

const SEX_BOND := preload("res://mods/unfplap/bond/service.gd")

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
