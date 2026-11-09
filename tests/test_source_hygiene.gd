extends SceneTree
## Source hygiene for the mod.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_source_hygiene.gd

const ROOT := "res://mods/unfplap"
## Files allowed to create settings widgets. The declaration panel is settings_ui.gd; the
## character preference form in main.gd is the one hand-built exception.
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
	_check_teardown()
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
