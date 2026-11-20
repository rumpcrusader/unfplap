extends "res://mods/unfplap/tests/support/suite.gd"
## The build stamp's max logic and its source scan.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/log/test_build_stamp.gd

const BUILD_STAMP := preload("res://mods/unfplap/shared/build_stamp.gd")



func run() -> void:
	check(BUILD_STAMP.newest([0, 0, 0]) == 0, "an empty build has no stamp")
	check(BUILD_STAMP.newest([1, 7, 3]) == 7, "the newest mtime wins")
	check(BUILD_STAMP.newest([9, 9, 9]) == 9, "equal mtimes keep the stamp")
	check(BUILD_STAMP.newest([]) == 0, "no files means no stamp")
	check(BUILD_STAMP.source_mtime() >= 0, "the source scan returns a non-negative mtime")
	check(BUILD_STAMP.PATHS.size() == 7, "the stamp scans seven source files")

	if failures == 0:
		print("BUILD_STAMP_PASS")
	finish()
