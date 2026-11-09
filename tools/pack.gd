extends SceneTree
## Packs the staged mod at res://mods/<id>/ into a standalone .pck and verifies the result.
##
## build.sh stages the runtime tree selected by .pckignore, runs --import, then copies this
## script into the staging project and calls it. This packer adds the staged tree as-is:
## mod.json, scripts, assets, poses and merge data. Each .import is packed with the data Godot
## generated for it; raw imported assets are not.
##
## The packer rejects development paths, requires the runtime files and the expected anatomy
## set, and writes a .sha256 beside the pack. A failed check removes the pack.
##
##   godot --headless --path <stage> --script res://pack.gd -- --out FILE.pck

const ID_PATTERN := "^[a-z0-9_]{1,40}$"
const REQUIRED := ["mod.json", "mod.built.json", "changelog.txt", "AUDIO_CREDITS.md"]
const FORBIDDEN_DIRS := [".agents", ".claude", ".github", ".opencode", "backups", "scripts", "tests", "tools"]
const FORBIDDEN_FILES := ["release_notes.md", "Thumbs.db", "winking_before_wink.scn"]
const FORBIDDEN_SUFFIXES := [".bak", ".blend", ".blend1", ".log", ".orig", ".pck", ".py", ".pyc", ".sh", ".tmp", ".uid", ".zip"]

var _count := 0
var _failed := false
var _root_key := ""
var _out_path := ""
var _paths := {}
var _anatomy_expected: Array[String] = []
var _anatomy_found := {}
var _anatomy_enabled := false


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var out := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	if out.is_empty():
		fail("missing --out <file.pck>")
		return

	var ids := DirAccess.get_directories_at("res://mods")
	if ids.size() != 1:
		fail("expected exactly one staged mod under res://mods/, found %d" % ids.size())
		return
	var id := ids[0]
	if RegEx.create_from_string(ID_PATTERN).search(id) == null:
		fail("invalid staged mod id: %s" % id)
		return

	var root := "res://mods/%s" % id
	_root_key = "mods/%s" % id
	var manifest_path := root.path_join("mod.json")
	var manifest: Variant = _json(manifest_path)
	if not manifest is Dictionary:
		fail("no readable %s" % manifest_path)
		return
	var data := manifest as Dictionary
	if str(data.get("id", "")) != id:
		fail("mod.json id does not match the staged folder %s" % id)
		return
	var version := str(data.get("version", ""))
	var game_version := str(data.get("game_version", ""))
	if version.is_empty():
		fail("mod.json version is empty")
		return
	if game_version.is_empty():
		fail("mod.json game_version is empty")
		return

	_anatomy_enabled = OS.get_environment("MOD_EXPECT_ANATOMY") == "1"
	_anatomy_expected = _env_list("MOD_ANATOMY_FILES")
	if _anatomy_enabled and _anatomy_expected.is_empty():
		fail("MOD_EXPECT_ANATOMY is set but MOD_ANATOMY_FILES is empty")
		return

	var out_path := ProjectSettings.globalize_path(out) if out.begins_with("res://") else out
	_out_path = out_path
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())

	var packer := PCKPacker.new()
	if packer.pck_start(out_path) != OK:
		fail("cannot write %s" % out_path)
		return

	_add(packer, manifest_path, ProjectSettings.globalize_path(manifest_path))
	if _failed: return
	var absolute_root := ProjectSettings.globalize_path(root)
	for name: String in DirAccess.get_files_at(absolute_root):
		if name == "mod.json" or name.begins_with(".") or name.ends_with(".uid"):
			continue
		if name.ends_with(".import"):
			_add_import(packer, root.path_join(name), absolute_root.path_join(name))
		else:
			_add_file(packer, root.path_join(name), absolute_root.path_join(name))
		if _failed: return
	for name: String in DirAccess.get_directories_at(absolute_root):
		if name.begins_with("."):
			continue
		_add_tree(packer, root.path_join(name), absolute_root.path_join(name))
		if _failed: return

	var stamp := OS.get_temp_dir().path_join("mod_build_%s.json" % id)
	var marker := FileAccess.open(stamp, FileAccess.WRITE)
	if marker == null:
		fail("cannot write %s" % stamp)
		return
	var built := {
		"id": id,
		"version": version,
		"game_version": game_version,
		"godot": Engine.get_version_info().string,
	}
	marker.store_string(JSON.stringify(built, "\t"))
	marker.close()
	_add(packer, root.path_join("mod.built.json"), stamp)
	if _failed: return

	_verify_required()
	if _failed: return
	var entry := str(data.get("entry", "")).trim_prefix("res://")
	if not entry.is_empty() and not _paths.has(entry):
		fail("entry script missing from pack: %s" % entry)
		return
	if packer.flush() != OK:
		fail("cannot finish %s" % out_path)
		return
	DirAccess.remove_absolute(stamp)

	var check := FileAccess.open(out_path, FileAccess.READ)
	if check == null or check.get_buffer(4) != "GDPC".to_ascii_buffer():
		if check != null: check.close()
		fail("%s is not a Godot pack" % out_path)
		return
	check.close()

	var sha := FileAccess.get_sha256(out_path)
	if sha.is_empty():
		fail("cannot hash %s" % out_path)
		return
	var sum_path := out_path + ".sha256"
	var sum := FileAccess.open(sum_path, FileAccess.WRITE)
	if sum == null:
		fail("cannot write %s" % sum_path)
		return
	sum.store_string("%s  %s\n" % [sha, out_path.get_file()])
	sum.close()

	print("[%s] %d files" % [id, _count])
	print("PACK_VERIFY ok files=%d anatomy=%d/%d sha256=%s" % [
		_count, _anatomy_found.size(), _anatomy_expected.size(), sha])
	print("PCK_SHA256 ", sum_path)
	print("MOD_BUILT ", out_path)
	quit(0)


func _env_list(name: String) -> Array[String]:
	var out: Array[String] = []
	for part: String in OS.get_environment(name).split(" ", false):
		if not part.is_empty():
			out.append(part)
	return out


func _verify_required() -> void:
	for name: String in REQUIRED:
		if not _paths.has(_root_key + "/" + name):
			fail("required file missing from pack: %s" % name)
			return
	if not _anatomy_enabled:
		return
	var missing: Array[String] = []
	for name: String in _anatomy_expected:
		if not _anatomy_found.has(name):
			missing.append(name)
	if not missing.is_empty():
		fail("anatomy missing from pack: %s" % ", ".join(PackedStringArray(missing)))


func _verify_path(logical: String) -> String:
	var key := logical.trim_prefix("res://")
	if key.begins_with(".godot/"):
		return ""
	if not key.begins_with(_root_key + "/"):
		return "packed path outside the mod root: %s" % logical
	var relative := key.trim_prefix(_root_key + "/")
	var first := relative.get_slice("/", 0)
	if first in FORBIDDEN_DIRS:
		return "development path in pack: %s" % logical
	var file := relative.get_file()
	if file in FORBIDDEN_FILES:
		return "development file in pack: %s" % logical
	for suffix: String in FORBIDDEN_SUFFIXES:
		if file.ends_with(suffix):
			return "development file in pack: %s" % logical
	if file.ends_with(".md") and file != "AUDIO_CREDITS.md":
		return "documentation file in pack: %s" % logical
	if file.ends_with(".txt") and file != "changelog.txt":
		return "documentation file in pack: %s" % logical
	if relative.begins_with("assets/anatomy/"):
		var name := relative.trim_prefix("assets/anatomy/")
		if name.contains("/"):
			return "nested anatomy path in pack: %s" % logical
		if name.ends_with(".import"):
			if not _anatomy_enabled:
				return "anatomy import in a no-anatomy build: %s" % logical
			var source := name.trim_suffix(".import")
			if source not in _anatomy_expected:
				return "unexpected anatomy import in pack: %s" % logical
			_anatomy_found[source] = true
			return ""
		if not _anatomy_enabled:
			return "anatomy asset in a no-anatomy build: %s" % logical
		if name not in _anatomy_expected:
			return "unexpected anatomy asset in pack: %s" % logical
		_anatomy_found[name] = true
	return ""


func _add_file(packer: PCKPacker, logical: String, absolute: String, import_sidecar := true) -> void:
	if _failed: return
	if import_sidecar and FileAccess.file_exists(absolute + ".import"):
		return   # the .import sidecar carries the imported data
	_add(packer, logical, absolute)


func _add_import(packer: PCKPacker, logical: String, absolute: String) -> void:
	_add(packer, logical, absolute)
	if _failed: return
	var config := ConfigFile.new()
	if config.load(absolute) != OK:
		push_warning("cannot read %s" % absolute)
		return
	var dest: Variant = config.get_value("deps", "dest_files", [])
	if not dest is Array or (dest as Array).is_empty():
		if config.has_section_key("remap", "path"):
			dest = [config.get_value("remap", "path")]
		else:
			dest = []
	for item: Variant in dest:
		var logical_dest := str(item)
		var absolute_dest := ProjectSettings.globalize_path(logical_dest)
		if not FileAccess.file_exists(absolute_dest):
			fail("%s is not imported yet (run build.sh again)" % logical_dest)
			return
		_add(packer, logical_dest, absolute_dest)
		if _failed: return


func _add_tree(packer: PCKPacker, logical_dir: String, absolute_dir: String) -> void:
	if _failed: return
	for name: String in DirAccess.get_files_at(absolute_dir):
		if _failed: return
		if name.begins_with(".") or name.ends_with(".uid"):
			continue
		var logical := logical_dir.path_join(name)
		var absolute := absolute_dir.path_join(name)
		if name.ends_with(".import"):
			_add_import(packer, logical, absolute)
		else:
			_add_file(packer, logical, absolute)
	for name: String in DirAccess.get_directories_at(absolute_dir):
		if _failed: return
		if name.begins_with("."):
			continue
		_add_tree(packer, logical_dir.path_join(name), absolute_dir.path_join(name))


func _add(packer: PCKPacker, logical: String, absolute: String) -> void:
	if _failed: return
	var why := _verify_path(logical)
	if not why.is_empty():
		fail(why)
		return
	if packer.add_file(logical, absolute) != OK:
		fail("cannot add %s" % logical)
		return
	_count += 1
	_paths[logical.trim_prefix("res://")] = true


func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	return json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null


func fail(why: String) -> void:
	_failed = true
	printerr("MOD_BUILD_FAILED ", why)
	if not _out_path.is_empty():
		DirAccess.remove_absolute(_out_path)
		DirAccess.remove_absolute(_out_path + ".sha256")
	quit(1)
