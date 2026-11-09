extends SceneTree
## integration: recover the anatomy assets from a PonyPussyParadise .pck. Run from the
## game project with the pack path as the first user argument. Writes files under
## res://mods/unfplap/assets/anatomy/ and never touches the repository index.

const OUT := "res://mods/unfplap/assets/anatomy"
const BASE := "res://.godot/imported/"
const TEX := {
	"anon_cut_ao.png": "anon_cut_ao.png-2a6fdc775d5365229818523014a72110.ctex",
	"anon_cut_nrm.png": "anon_cut_nrm.png-ebfd700d03e09f8c93a0078a6ae32e39.ctex",
	"anon_cut_light_cut.png": "anon_cut_light_cut.png-14d6156e92fa0a6a1fd5911852ce2716.ctex",
}
const SCENES := {
	"winking": "winking.glb-a97de369059e55e5fe474786ef1f915c.scn",
	"anal": "anal.glb-61f56e58d1203512d5874e5ebe12c707.scn",
	"teats": "teats.glb-1325f6ef0b55ce89323b429107a1ef7b.scn",
	"skin_bridge": "skin_bridge.glb-3248d20c8093ef2ea56e2170ffca7e94.scn",
	"anon_part": "anon_cut.glb-2b8781e8b8f786b6a270a8a243a1e4b5.scn",
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: --script res://mods/unfplap/tools/recover_anatomy_assets.gd -- <pack.pck>")
		quit(1)
		return
	if not ProjectSettings.load_resource_pack(args[0], false):
		print("cannot mount ", args[0])
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# The source scene has an external texture dependency. Satisfy it with a remap to the packed
	# imported texture before loading the scene.
	var dst_png := "res://mods/ponypussyparadise/anon_cut_light_cut.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dst_png.get_base_dir()))
	var ctex := BASE + TEX["anon_cut_light_cut.png"]
	var imp := FileAccess.open(dst_png + ".import", FileAccess.WRITE)
	if imp != null:
		imp.store_string("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\npath=\"%s\"\nuid=\"uid://tlmquy6uspq1\"\n" % (BASE + TEX["anon_cut_light_cut.png"]))
		imp.close()
	for name: String in TEX:
		var texture: Texture2D = load(BASE + TEX[name])
		if texture == null:
			print("missing texture ", name)
			continue
		var image := texture.get_image()
		var target := OUT.path_join(name)
		image.save_png(ProjectSettings.globalize_path(target))
		print("texture ", name, " ", image.get_size())
	for name: String in SCENES:
		var scene: PackedScene = load(BASE + SCENES[name])
		if scene == null:
			print("missing scene ", name)
			continue
		var root: Node = scene.instantiate()
		var source: MeshInstance3D = root as MeshInstance3D
		if source == null:
			for child: Node in root.find_children("*", "MeshInstance3D", true, false):
				source = child as MeshInstance3D
				break
		if source == null or source.mesh == null:
			print("no mesh in ", name)
			root.queue_free()
			continue
		var mesh: Mesh = source.mesh.duplicate(true)
		for surface in mesh.get_surface_count():
			mesh.surface_set_material(surface, null)
		var holder := MeshInstance3D.new()
		holder.name = name.capitalize().replace(" ", "")
		holder.mesh = mesh
		if source.skin != null:
			holder.skin = source.skin
		var packed := PackedScene.new()
		packed.pack(holder)
		var err := ResourceSaver.save(packed, ProjectSettings.globalize_path(OUT.path_join(name + ".scn")))
		print("scene ", name, " err=", err, " skin=", source.skin != null)
		holder.queue_free()
		root.queue_free()
	quit(0)
