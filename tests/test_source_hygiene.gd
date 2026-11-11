extends SceneTree
## Source hygiene for the mod.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_source_hygiene.gd

const ROOT := "res://mods/unfplap"
## Files allowed to create settings widgets. The declaration panel is settings_ui.gd; the
## character preference form in main.gd is the one hand-built exception. The tools are never
## shipped and are not settings UI.
const WIDGET_FILES := ["res://mods/unfplap/settings_ui.gd", "res://mods/unfplap/main.gd"]
const WIDGETS := ["SpinBox.new(", "CheckButton.new(", "OptionButton.new(", "ColorPickerButton.new("]
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
	var files: Array[String] = []
	_collect(ROOT, files)
	check(files.size() > 10, "source files found")
	var manifest_text := FileAccess.get_file_as_string(ROOT.path_join("mod.json"))
	var manifest: Variant = JSON.parse_string(manifest_text)
	check(manifest is Dictionary, "mod.json parses")
	if manifest is Dictionary:
		var data := manifest as Dictionary
		var semver := RegEx.new()
		semver.compile("^\\d+\\.\\d+\\.\\d+$")
		var version := str(data.get("version", ""))
		var game_version := str(data.get("game_version", ""))
		check(str(data.get("id", "")) == "unfplap", "mod id")
		check(semver.search(version) != null, "mod version is MAJOR.MINOR.PATCH")
		check(game_version == str(ProjectSettings.get_setting("application/config/version", "")),
			"target game version matches the project")
		check(not data.has("extends"), "entry script only")
		check(str(data.get("entry", "")) == "res://mods/unfplap/main.gd", "entry path")
	for path: String in [
		".opencode/skills/release/SKILL.md",
		".opencode/commands/release.md",
		"scripts/prepare_release.sh",
		"scripts/check_release.sh",
		"scripts/check_release_metadata.py",
		"scripts/build_manifest.py",
		"scripts/asset_pack.py",
		"scripts/pack_assets.sh",
		"scripts/fetch_assets.sh",
		"scripts/asset_pack.json",
		"assets/README.md",
	]:
		check(FileAccess.file_exists(ROOT.path_join(path)), "release file %s" % path)
	for path: String in ["build.sh", "tools/pack.gd", ".github/workflows/build.yml"]:
		check(not FileAccess.get_file_as_string(ROOT.path_join(path)).contains("--no-extends"),
			"no obsolete extension flag in %s" % path)
	_check_preloads(files)
	_check_settings_module(files)
	_check_sync_snapshot()
	_check_teardown()
	_check_hands_isolation()
	_check_hands_docs()
	_check_eligibility_isolation(files)
	_check_eligibility_docs()
	_check_anatomy_isolation(files)
	_check_anatomy_docs()
	print("SOURCE_HYGIENE_RESULT checks=%d failures=%d files=%d" % [checks, failures, files.size()])
	if failures == 0:
		print("SOURCE_HYGIENE_PASS")
	quit(0 if failures == 0 else 1)


## The settings live in one module with one declaration per setting; settings widgets may only
## live in the declaration panel and the preference form.
func _check_settings_module(files: Array[String]) -> void:
	# The settings live in one module. These checks keep that true as the mod grows.
	var module := FileAccess.get_file_as_string(ROOT.path_join("settings.gd"))
	check(module.contains("static func all_settings() -> Array"), "settings module present")
	var stale: Array = []
	var widget_ok := true
	for path: String in files:
		if not path.ends_with(".gd") or path.begins_with(ROOT.path_join("tests/")):
			continue
		if path.begins_with(ROOT.path_join("tools/")):
			continue
		var text := FileAccess.get_file_as_string(path)
		if text.contains("tunables_schema.gd") or text.contains("unfplap/tunables.gd"):
			stale.append(path)
		if path.begins_with(ROOT.path_join("tests/")):
			continue
		if not WIDGET_FILES.has(path):
			for widget: String in WIDGETS:
				if text.contains(widget):
					widget_ok = false
					print("settings widget %s outside settings_ui.gd: %s" % [widget, path])
	check(stale.is_empty(), "no file imports the removed tunable shims: %s" % str(stale))
	check(widget_ok, "only settings_ui.gd (and the preference form) create settings widgets")


## The sync-settings snapshot must keep the full shipped character templates even though the
## player's settings file stores only differences.
func _check_sync_snapshot() -> void:
	var tool := FileAccess.get_file_as_string(ROOT.path_join("tools/settings_snapshot.gd"))
	check(tool.contains("SETTINGS.CHARACTER_TEMPLATES"),
		"the settings snapshot carries the shipped character templates")


## The hands engine must not know a pose. Pose geometry belongs in the path providers; the
## engine only sees the body surface, a contact path and the palm frame.
func _check_hands_isolation() -> void:
	var engine := FileAccess.get_file_as_string(
		ROOT.path_join("hands/placement.gd"))
	check(engine.contains("func frame("), "hands engine is present")
	for token: String in ["pose_id", "CATALOG", "missionary", "standing",
			"desktop_pose_driver", "missionary_anon"]:
		check(not engine.contains(token), "hands engine has no pose reference: %s" % token)
	var path_base := FileAccess.get_file_as_string(
		ROOT.path_join("hands/path_base.gd"))
	check(path_base.contains("func candidates("), "hands path contract is present")
	var contact := FileAccess.get_file_as_string(ROOT.path_join("hands/contact.gd"))
	check(contact.contains("static func contact("), "hands contact query is present")
	for name: String in ["hands/session.gd", "hands/path_base.gd", "hands/contact.gd",
			"hands/surface.gd", "hands/palm.gd", "hands/reach_plan.gd", "hands/scale.gd",
			"hands/smack.gd"]:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		for token: String in ["pose_id", "CATALOG", "desktop_pose_driver",
				"missionary_anon"]:
			check(not text.contains(token),
				"%s has no pose reference: %s" % [name, token])


## The hands contract lives in one file; every other doc points to it.
func _check_hands_docs() -> void:
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/hands.md"))
	check(not contract.is_empty(), "docs/hands.md exists")
	check(contract.contains("## Controls") and contract.contains("## Contact engine"),
		"docs/hands.md has the controls and contact contract")
	for name: String in ["AGENTS.md", "ROTATION.md", "PREFERENCES.md", "HISTORY.md",
			"README.md"]:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		check(text.contains("docs/hands.md"), "%s links to docs/hands.md" % name)


## One ordered teardown owns act exit. If a new exit path or a copied restore sequence appears,
## this fails before a leak reaches a save.
func _check_teardown() -> void:
	var runtime := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	check(_count(runtime, "func _end_session(") == 1, "one act teardown")
	for name: String in ["_abort_start", "_finish_restore", "_restore_now"]:
		check(_func_body(runtime, name).contains("_end_session("),
			"%s ends through _end_session" % name)
	var force := _func_body(runtime, "force_stop")
	check(force.contains("_end_session(") and force.contains("_restore_now()"),
		"force_stop ends through the same teardown")
	for name: String in ["_abort_start", "_finish_restore", "_restore_now", "force_stop"]:
		var body := _func_body(runtime, name)
		for call: String in ["_restore_camera(", "_restore_look(", "_release_nav(",
				"_free_pose(", "_unlock_player("]:
			check(not body.contains(call), "%s does not call %s directly" % [name, call])
	# `cancel()` queues the early-stop reaction after `_restore_begin()`; the timed finish must
	# not cancel director rows or that line never speaks.
	var finish := _func_body(runtime, "_finish_restore")
	check(not finish.contains("_end_act_lines"), "normal restore keeps the early-stop line")
	check(not finish.contains("MEMORY.cancel_act_lines"), "normal restore cancels no director rows")


## The eligibility rules are pure and only the adapter reads the gate sources. The docs contract
## lives in one file; other docs link to it instead of restating the rules.
func _check_eligibility_isolation(files: Array[String]) -> void:
	var pure_files := [
		"eligibility/policy.gd", "eligibility/facts.gd", "eligibility/verdict.gd",
	]
	for name: String in pure_files:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		for token: String in ["extends Node", "get_tree(", "Time.", "FileAccess", "SETTINGS",
				"preload(\"res://world/", "preload(\"res://mods/unfplap/settings.gd\")"]:
			check(not text.contains(token), "%s stays pure: %s" % [name, token])
	var shell := FileAccess.get_file_as_string(ROOT.path_join("eligibility.gd"))
	for token: String in ["save_changed", "save_consent", "save_preferences", "SEX_BOND.save",
			"ACT_HISTORY.commit", "ACT_HISTORY.save", "FileAccess"]:
		check(not shell.contains(token), "eligibility shell is read-only: %s" % token)
	var readers := {
		"bonds.welcomes(": ["eligibility.gd"],
		"bonds.eligible_for_romance(": ["eligibility.gd"],
		"bonds.adults": ["eligibility.gd"],
		"SETTINGS.promiscuity": ["eligibility.gd", "settings.gd"],
		"SETTINGS.sex_start": ["eligibility.gd", "settings.gd"],
		"CYCLE.allows_sex(": ["eligibility.gd", "cycle.gd"],
		"ACT_HISTORY.blocks_start(": ["eligibility.gd", "act_history.gd"],
		"ACT_HISTORY.blocks_offers(": ["eligibility.gd", "act_history.gd"],
		"ACT_HISTORY.offer_weight(": ["eligibility.gd", "act_history.gd"],
	}
	for path: String in files:
		if not path.ends_with(".gd") or path.begins_with(ROOT.path_join("tests/")):
			continue
		var relative := path.trim_prefix(ROOT.path_join(""))
		var text := FileAccess.get_file_as_string(path)
		for token: String in readers.keys():
			if not text.contains(token):
				continue
			var allowed: Array = readers[token]
			check(relative in allowed, "%s does not read %s outside the eligibility API" % [
				relative, token])


func _check_eligibility_docs() -> void:
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/eligibility.md"))
	check(not contract.is_empty(), "docs/eligibility.md exists")
	for heading: String in ["## Data ownership", "## Public API", "## Modes and truth table",
			"## Tests"]:
		check(contract.contains(heading), "docs/eligibility.md has %s" % heading)
	for name: String in ["AGENTS.md", "PREFERENCES.md", "HISTORY.md", "TUNING.md", "README.md"]:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		check(text.contains("docs/eligibility.md"), "%s links to docs/eligibility.md" % name)


## The pure anatomy core is scene-free, and the system internals never preload the two hosts.
## The facade is the only file another system should call.
func _check_anatomy_isolation(files: Array[String]) -> void:
	var pure_files := [
		"anatomy/identity.gd", "anatomy/geometry.gd", "anatomy/act/state.gd",
	]
	for name: String in pure_files:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		for token: String in ["extends Node", "get_tree(", "Time.", "FileAccess", "SETTINGS",
				"preload(\"res://world/", "preload(\"res://mods/unfplap/runtime.gd\")",
				"preload(\"res://mods/unfplap/main.gd\")"]:
			check(not text.contains(token), "%s stays pure: %s" % [name, token])
	var act := FileAccess.get_file_as_string(ROOT.path_join("anatomy_act.gd"))
	check(not act.contains("runtime.get("), "the anatomy act does not read runtime fields")
	check(not act.contains("runtime.call(\"_"), "the anatomy act does not call runtime private helpers")
	for path: String in files:
		if not path.ends_with(".gd") or path.begins_with(ROOT.path_join("tests/")):
			continue
		var relative := path.trim_prefix(ROOT.path_join(""))
		if not relative.begins_with("anatomy/"):
			continue
		var text := FileAccess.get_file_as_string(path)
		for token: String in ["preload(\"res://mods/unfplap/runtime.gd\")",
				"preload(\"res://mods/unfplap/main.gd\")"]:
			check(not text.contains(token), "%s does not preload the host: %s" % [relative, token])


## The anatomy contract owns the anatomy and tail-seating rules. It is one file; AGENTS and the
## settings/pose docs link to it instead of restating them.
func _check_anatomy_docs() -> void:
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/anatomy.md"))
	check(not contract.is_empty(), "docs/anatomy.md exists")
	for heading: String in ["## Scope", "## Architecture", "## Controls", "## Act anatomy",
			"## Tail seating", "## Tests", "## Migration target"]:
		check(contract.contains(heading), "docs/anatomy.md has %s" % heading)
	for name: String in ["AGENTS.md", "README.md", "ROTATION.md", "PREFERENCES.md", "TUNING.md"]:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		check(text.contains("docs/anatomy.md"), "%s links to docs/anatomy.md" % name)


func _func_body(text: String, name: String) -> String:
	var needle := "func " + name + "("
	var start := text.find(needle)
	if start < 0:
		return ""
	var next := text.find("\nfunc ", start + needle.length())
	if next < 0:
		next = text.length()
	return text.substr(start, next - start)


func _count(text: String, needle: String) -> int:
	var total := 0
	var at := text.find(needle)
	while at >= 0:
		total += 1
		at = text.find(needle, at + needle.length())
	return total


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file: String in dir.get_files():
		if file.ends_with(".gd") or file.ends_with(".md") or file.ends_with(".json"):
			out.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)


func _check_preloads(files: Array[String]) -> void:
	var seen := {}
	for path: String in files:
		if not path.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string(path)
		var regex := RegEx.new()
		regex.compile("res://mods/unfplap/[A-Za-z0-9_./-]+\\.(gdshaderinc|gdshader|gd|json|md)")
		for match: RegExMatch in regex.search_all(text):
			var target := match.get_string()
			if seen.has(target):
				continue
			seen[target] = true
			check(FileAccess.file_exists(target), "resolved preload %s" % target)
