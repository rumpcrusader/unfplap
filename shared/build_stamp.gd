extends RefCounted
## Build stamp: the newest mtime over the mod's source files. A real source file has a non-zero
## mtime; a pack/PCK reports 0, so the entry's one log line proves which build is live.
##
##   const BUILD_STAMP := preload("res://mods/unfplap/shared/build_stamp.gd")
##   BUILD_STAMP.log_stamp()
##
## See `docs/log.md`.

const LOG := preload("res://mods/unfplap/shared/log.gd")

## The files whose newest mtime identifies the build. Kept small: one scan per process start.
const PATHS: Array[String] = [
	"res://mods/unfplap/runtime.gd",
	"res://mods/unfplap/readiness/thrust.gd",
	"res://mods/unfplap/shared/preferences.gd",
	"res://mods/unfplap/dialogue/utterance.gd",
	"res://mods/unfplap/poses/skeleton_pose.gd",
	"res://mods/unfplap/poses/missionary_recipe.gd",
	"res://mods/unfplap/poses/standing_recipe.gd",
]


## The newest mtime in a list. Pure: the unit test feeds values instead of files.
static func newest(mtimes: Array[int]) -> int:
	var newest := 0
	for mtime: int in mtimes:
		newest = maxi(newest, mtime)
	return newest


## The newest mtime over the source files, or 0 in a pack.
static func source_mtime() -> int:
	var mtimes: Array[int] = []
	for path: String in PATHS:
		mtimes.append(FileAccess.get_modified_time(path))
	return newest(mtimes)


## The one line the entry logs after construction.
static func log_stamp() -> void:
	LOG.debug("entry ready (debug logs %s) runtime_mtime=%d" % [
		"ON" if LOG.debug_logs else "OFF", source_mtime()])
