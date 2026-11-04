extends SceneTree
## Source hygiene for the mod.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_source_hygiene.gd

const ROOT := "res://mods/unfplap"
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
	var manifest := FileAccess.get_file_as_string(ROOT.path_join("mod.json"))
	check(manifest.contains("\"id\": \"unfplap\""), "mod id")
	check(manifest.contains("\"version\": \"0.1.1\""), "mod version")
	check(manifest.contains("\"game_version\": \"0.3.0\""), "target game version")
	check(not manifest.contains("\"extends\""), "entry script only")
	check(manifest.contains("res://mods/unfplap/"), "entry/extension paths")
	for path: String in ["build.sh", "tools/pack.gd", ".github/workflows/build.yml"]:
		check(not FileAccess.get_file_as_string(ROOT.path_join(path)).contains("--no-extends"),
			"no obsolete extension flag in %s" % path)
	_check_preloads(files)
	print("SOURCE_HYGIENE_RESULT checks=%d failures=%d files=%d" % [checks, failures, files.size()])
	if failures == 0:
		print("SOURCE_HYGIENE_PASS")
	quit(0 if failures == 0 else 1)


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
		regex.compile("res://mods/unfplap/[A-Za-z0-9_./-]+\\.(gd|json|md)")
		for match: RegExMatch in regex.search_all(text):
			var target := match.get_string()
			if seen.has(target):
				continue
			seen[target] = true
			check(FileAccess.file_exists(target), "resolved preload %s" % target)
