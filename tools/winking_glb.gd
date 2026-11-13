extends SceneTree
## Round-trip the winking anatomy mesh between the packed scene and a Blender GLB.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tools/winking_glb.gd -- export <out.glb>
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tools/winking_glb.gd -- import <in.glb>
## Import writes res://mods/unfplap/assets/anatomy/mare/winking.scn and keeps a
## winking_before_wink.scn backup under sources/work/ on the first import.

const SCN := "res://mods/unfplap/assets/anatomy/mare/winking.scn"
const BACKUP := "res://mods/unfplap/sources/work/winking_before_wink.scn"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- export <out.glb> | -- import <in.glb>")
		quit(1)
		return
	match args[0]:
		"export":
			quit(_export(args[1]))
		"import":
			quit(_import(args[1]))
		_:
			print("usage: -- export <out.glb> | -- import <in.glb>")
			quit(1)


func _export(path: String) -> int:
	var scene: PackedScene = load(SCN)
	if scene == null:
		print("WINKING_EXPORT_FAIL missing ", SCN)
		return 1
	var root: Node = scene.instantiate()
	var source: MeshInstance3D = _mesh_in(root)
	if source == null or source.mesh == null:
		print("WINKING_EXPORT_FAIL no mesh")
		root.free()
		return 1
	var holder := MeshInstance3D.new()
	holder.name = "Winking"
	holder.mesh = source.mesh.duplicate(true)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(holder, state)
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(path))
	holder.free()
	root.free()
	print("WINKING_EXPORTED ", path, " err=", err)
	return 0 if err == OK else 1


func _import(path: String) -> int:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(path), state)
	if err != OK:
		print("WINKING_IMPORT_FAIL parse err=", err)
		return 1
	var root: Node = doc.generate_scene(state)
	var source: MeshInstance3D = _mesh_in(root)
	if source == null or source.mesh == null:
		print("WINKING_IMPORT_FAIL no mesh in ", path)
		root.free()
		return 1
	var mesh: Mesh = source.mesh.duplicate(true)
	for surface in mesh.get_surface_count():
		mesh.surface_set_material(surface, null)
	var holder := MeshInstance3D.new()
	holder.name = "Winking"
	holder.mesh = mesh
	if source.skin != null:
		holder.skin = source.skin
	var packed := PackedScene.new()
	packed.pack(holder)
	if not FileAccess.file_exists(BACKUP) and FileAccess.file_exists(SCN):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SCN),
			ProjectSettings.globalize_path(BACKUP))
	var save_err := ResourceSaver.save(packed, SCN)
	var names: PackedStringArray = []
	if mesh is ArrayMesh:
		for i in (mesh as ArrayMesh).get_blend_shape_count():
			names.append(str((mesh as ArrayMesh).get_blend_shape_name(i)))
	print("WINKING_IMPORTED ", ProjectSettings.globalize_path(SCN), " err=", save_err,
		" shapes=", ",".join(names))
	holder.free()
	root.free()
	return 0 if save_err == OK else 1


func _mesh_in(root: Node) -> MeshInstance3D:
	var mesh := root as MeshInstance3D
	if mesh != null:
		return mesh
	for child: Node in root.find_children("*", "MeshInstance3D", true, false):
		return child as MeshInstance3D
	return null
