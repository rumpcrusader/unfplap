extends SceneTree
## Packs the staged mod at res://mods/<id>/ into a standalone .pck and verifies the result.
##
## build.sh stages the tracked runtime tree, writes the expected file list from
## scripts/build_manifest.py, runs --import, then copies this script into the staging project.
## The packer requires the packed runtime files to equal that list plus mod.built.json, rejects
## broken import sidecars, and writes a .sha256 beside the pack. A failed check removes the pack.
##
##   godot --headless --path <stage> --script res://pack.gd -- --out FILE.pck

const ID_PATTERN := "^[a-z0-9_]{1,40}$"

var _count := 0
var _failed := false
var _root_key := ""
var _out_path := ""
var _expected := {}
var _packed := {}


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

	var expected_path := OS.get_environment("MOD_EXPECTED_FILES")
	if expected_path.is_empty() or not FileAccess.file_exists(expected_path):
		fail("MOD_EXPECTED_FILES is missing or not readable")
		return
	for line: String in FileAccess.get_file_as_string(expected_path).split("\n"):
		var rel := line.strip_edges()
		if not rel.is_empty():
			_expected[rel] = true
	if _expected.is_empty():
		fail("the expected file manifest is empty")
		return
	_expected["mod.built.json"] = true

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
	var entry := str(data.get("entry", ""))
	var entry_prefix := "res://mods/%s/" % id
	if not entry.begins_with(entry_prefix):
		fail("mod.json entry is not under %s" % entry_prefix)
		return
	var entry_rel := entry.trim_prefix(entry_prefix)
	if entry_rel.is_empty():
		fail("mod.json entry is empty")
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

	var marker_path := ProjectSettings.globalize_path(root.path_join("mod.built.json"))
	var marker := FileAccess.open(marker_path, FileAccess.WRITE)
	if marker == null:
		fail("cannot write %s" % marker_path)
		return
	var built := {
		"id": id,
		"version": version,
		"game_version": game_version,
		"godot": Engine.get_version_info().string,
	}
	marker.store_string(JSON.stringify(built, "\t"))
	marker.close()
	_add(packer, root.path_join("mod.built.json"), marker_path)
	if _failed: return

	_verify_manifest()
	if _failed: return
	if not _packed.has(entry_rel):
		fail("entry script missing from pack: %s" % entry_rel)
		return
	if packer.flush() != OK:
		fail("cannot finish %s" % out_path)
		return

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
	print("PACK_VERIFY ok files=%d expected=%d sha256=%s" % [_count, _expected.size(), sha])
	print("PCK_SHA256 ", sum_path)
	print("MOD_BUILT ", out_path)
	quit(0)


func _verify_manifest() -> void:
	for rel: String in _expected:
		if not _packed.has(rel):
			fail("required file missing from pack: %s" % rel)
			return
	for rel: String in _packed:
		if not _expected.has(rel):
			fail("unexpected file in pack: %s" % rel)
			return


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
		fail("cannot read import sidecar: %s" % logical)
		return
	var dest: Variant = config.get_value("deps", "dest_files", [])
	if not dest is Array or (dest as Array).is_empty():
		if config.has_section_key("remap", "path"):
			dest = [config.get_value("remap", "path")]
		else:
			dest = []
	if not dest is Array or (dest as Array).is_empty():
		fail("import sidecar has no destination: %s" % logical)
		return
	for item: Variant in dest:
		var logical_dest := str(item)
		var absolute_dest := ProjectSettings.globalize_path(logical_dest)
		if not FileAccess.file_exists(absolute_dest):
			fail("imported data is missing for %s: %s" % [logical, logical_dest])
			return
		var imported := FileAccess.open(absolute_dest, FileAccess.READ)
		if imported == null or imported.get_length() <= 0:
			if imported != null: imported.close()
			fail("imported data is empty for %s: %s" % [logical, logical_dest])
			return
		imported.close()
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
	var key := logical.trim_prefix("res://")
	if key.begins_with(".godot/"):
		pass
	elif key.begins_with(_root_key + "/"):
		_packed[key.trim_prefix(_root_key + "/")] = true
	else:
		fail("packed path outside the mod root: %s" % logical)
		return
	if packer.add_file(logical, absolute) != OK:
		fail("cannot add %s" % logical)
		return
	_count += 1


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
