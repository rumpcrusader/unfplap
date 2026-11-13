extends SceneTree
## Trigger the settings migration against the real profile. `/sync-settings` backs up the profile
## and runs this before reading it. The game must be closed. Loading `SETTINGS.data()` is what runs
## `_migrate()`, the legacy placement import and the write.
##
##   godot --headless --xr-mode off --path <project> \
##       --script res://mods/unfplap/tools/settings_migrate.gd

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")


func _initialize() -> void:
	var data := SETTINGS.data()
	print("SETTINGS_MIGRATED path=%s schema=%d" % [
		SETTINGS._path(), int(data.get("version", 0))])
	quit(0)
