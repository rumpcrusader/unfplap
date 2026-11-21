extends SceneTree
## Loads every script named on the command line in one engine boot and reports the ones that fail.
##
## A boot per file pays the project start and the same shared preload closure again for every file.
## Loading only compiles: no scene is built and no autoload singleton is read.
##
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tools/parse_all.gd
##   ... -- res://mods/unfplap/main.gd res://mods/unfplap/tests/test_api.gd
##
## Prints `FAIL <path>` for each script that does not load, then `PARSED <files> <failed>`.

func _initialize() -> void:
	var paths := OS.get_cmdline_user_args()
	var failed := 0
	for path in paths:
		print("CHECK ", path)
		var script := ResourceLoader.load(path) as Script
		if script == null or not script.can_instantiate():
			print("FAIL ", path)
			failed += 1
	print("PARSED %d %d" % [paths.size(), failed])
	quit(1 if failed > 0 else 0)
