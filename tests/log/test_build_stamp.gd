extends SceneTree
## The build stamp's max logic and its source scan.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/log/test_build_stamp.gd

const BUILD_STAMP := preload("res://mods/unfplap/shared/build_stamp.gd")

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
	check(BUILD_STAMP.newest([0, 0, 0]) == 0, "an empty build has no stamp")
	check(BUILD_STAMP.newest([1, 7, 3]) == 7, "the newest mtime wins")
	check(BUILD_STAMP.newest([9, 9, 9]) == 9, "equal mtimes keep the stamp")
	check(BUILD_STAMP.newest([]) == 0, "no files means no stamp")
	check(BUILD_STAMP.source_mtime() >= 0, "the source scan returns a non-negative mtime")
	check(BUILD_STAMP.PATHS.size() == 7, "the stamp scans seven source files")

	print("BUILD_STAMP_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("BUILD_STAMP_PASS")
	quit(0 if failures == 0 else 1)
