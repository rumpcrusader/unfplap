extends RefCounted
## A satin tail bow worn at the base of a mare's tail. The piece is a modelled mesh
## (`assets/tail_bow/tail_bow.glb`, built by `tools/tail_bow/build_bow.py`), attached to the hair
## rig's `mTail2` through a BoneAttachment3D and registered in her `identity.accessories` like the
## game's own show pieces (Braeburn's hat, Vinyl's glasses).
##
## The bow is authored facing +Z with +Y up her tail, sitting on the tail's outer surface: the
## knot rests against the fur, the loops spread to her left and right, and the two tails hang down
## the tail. It is one unskinned mesh, so the merged near mesh leaves it alone and the far mesh
## carries it rigidly.
##
## The game's wardrobe (`pony_wardrobe.gd`) owns its own `KINDS` and slots; a mod cannot add one
## there without editing a game script, so this file owns the piece and its worn state instead.
## The state lives in `Mods.state("unfplap").tail_bows`, keyed by pony id.

const TUNABLES := preload("res://mods/unfplap/tunables.gd")
const BOW_SCENE := preload("res://mods/unfplap/assets/tail_bow/tail_bow.glb")

const NODE_NAME := "TailBow"
const ATTACHMENT_NAME := "TailBowAttachment"
const TAIL_BONE := "mTail2"
const NEXT_BONE := "mTail2"
const VARIANT_TAG := "|tail-bow"
const STATE_KEY := "tail_bows"
## Tail radius the mesh was modelled around; used when her identity has no tail radii.
const AUTHORED_RADIUS := 0.060
## Clearance between the fur surface and the knot, in metres.
const TIE_MARGIN := 0.002
## The fur drawn around her tail springs is thicker than the springs themselves
## (`identity.tail_segment_radii`), so the knot stands off by this share of the tail radius.
const FUR_SCALE := 1.9

## Satin dyes. The key is stored in settings; the bow keeps its colour for every pony.
const COLOURS := {
	"red": Color("c8102e"),
	"rose": Color("d94b8a"),
	"pink": Color("ffa8c7"),
	"cream": Color("f4e8d6"),
	"purple": Color("8d6bd1"),
	"midnight": Color("2f3559"),
}
const DEFAULT_COLOUR := "red"

static var _mesh: Mesh


static func feature_on() -> bool:
	return TUNABLES.get_bool("features.tail_bow")


# --- Worn state -----------------------------------------------------------------------------

## Every pony id wearing a bow: `{id: {}}`.
static func worn() -> Dictionary:
	var mods := _mods()
	if mods == null or not mods.has_method("state"):
		return {}
	var state: Variant = mods.call("state", "unfplap")
	if not state is Dictionary:
		return {}
	var rows: Variant = (state as Dictionary).get(STATE_KEY)
	if not rows is Dictionary:
		rows = {}
		(state as Dictionary)[STATE_KEY] = rows
	return rows


static func worn_id(pony: Node) -> String:
	if not is_instance_valid(pony):
		return ""
	var id := str(pony.get_meta("relationship_id", ""))
	if id.is_empty():
		var identity: Variant = pony.get("identity")
		if identity != null:
			id = str(identity.get("id"))
	return id


static func wears_id(id: String) -> bool:
	return not id.is_empty() and worn().has(id)


static func wears(pony: Node) -> bool:
	return wears_id(worn_id(pony))


## Put a bow on a pony's worn record or take it off, then save the world.
static func set_worn(id: String, on: bool) -> void:
	if id.is_empty():
		return
	var rows := worn()
	if on:
		rows[id] = {}
	else:
		rows.erase(id)
	var mods := _mods()
	if mods != null and mods.has_method("save_changed"):
		mods.call("save_changed")


## The satin dye: `presentation.tail_bow.colour` names one key of `COLOURS`.
static func colour(cfg: Dictionary) -> Color:
	return COLOURS.get(str(cfg.get("colour", DEFAULT_COLOUR)), COLOURS[DEFAULT_COLOUR])


# --- Attach ---------------------------------------------------------------------------------

## The bow currently on this pony, or null.
static func piece(pony: Node) -> MeshInstance3D:
	if not is_instance_valid(pony):
		return null
	var found := pony.find_child(NODE_NAME, true, false)
	return found as MeshInstance3D if found is MeshInstance3D else null


## Attach the bow to `pony`'s tail root and register it as one of her accessories.
## Returns the mesh, or null when her hair rig is not ready yet.
static func attach(pony: Node3D) -> MeshInstance3D:
	if not is_instance_valid(pony):
		return null
	var existing := piece(pony)
	if is_instance_valid(existing):
		return existing
	var sk := hair_skeleton(pony)
	if sk == null or sk.find_bone(TAIL_BONE) < 0:
		return null
	var cfg := config()
	var node := build(colour(cfg))
	var attachment := BoneAttachment3D.new()
	attachment.name = ATTACHMENT_NAME
	attachment.bone_name = TAIL_BONE
	sk.add_child(attachment)
	attachment.add_child(node)
	node.transform = local_transform(sk, pony, cfg)
	_register_accessory(pony, true)
	return node


## Remove the bow and forget the accessory entry. The worn record is the caller's business.
static func detach(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	var node := piece(pony)
	if is_instance_valid(node):
		var attachment := node.get_parent()
		if attachment != null:
			attachment.free()
		else:
			node.free()
	_register_accessory(pony, false)


## Re-colour and re-place in place after a settings edit. The accessory registration and the
## merged meshes are left alone: they only depend on the piece existing.
static func refresh(pony: Node) -> void:
	var node := piece(pony)
	if not is_instance_valid(node):
		attach(pony)
		return
	var sk := hair_skeleton(pony)
	if sk == null:
		return
	var cfg := config()
	node.material_override = satin(colour(cfg))
	node.transform = local_transform(sk, pony, cfg)


static func hair_skeleton(pony: Node) -> Skeleton3D:
	if not is_instance_valid(pony):
		return null
	var rig: Variant = pony.get("hair_skeleton")
	return rig as Skeleton3D if rig is Skeleton3D else null


## The bow's placement settings, read once per rebuild.
static func config() -> Dictionary:
	return {
		"size": TUNABLES.get_float("presentation.tail_bow.size"),
		"along_m": TUNABLES.get_float("presentation.tail_bow.along_m"),
		"tilt_deg": TUNABLES.get_float("presentation.tail_bow.tilt_deg"),
		"colour": TUNABLES.get_string("presentation.tail_bow.colour"),
	}


## Her tail's radius at the base: the hair spring radii her own tail is built from. Falls back
## to the radius the mesh was modelled around.
static func tail_radius(pony: Node) -> float:
	var identity: Variant = pony.get("identity") if is_instance_valid(pony) else null
	if identity != null:
		var radii: Variant = identity.get("tail_segment_radii")
		if radii is Array and (radii as Array).size() > 1:
			return maxf(float((radii as Array)[1]), 0.01)
	return AUTHORED_RADIUS


## How far from the tail axis the knot sits: her tail spring radius plus the fur around it.
## `identity.tail_segment_radii` describes the springs the hair fan is drawn around, so a bow
## placed on that radius disappears inside the tail.
static func standoff(pony: Node) -> float:
	return tail_radius(pony) * FUR_SCALE


## The mesh transform under `mTail2`: on the tail's outer surface at the tie point, with the loops
## spread to her left and right and the tails hanging down the tail. Built from the tail bone's
## rest frame only, so it does not depend on how she was posed when the bow was tied on.
static func local_transform(sk: Skeleton3D, pony: Node3D, cfg: Dictionary) -> Transform3D:
	var root_index := sk.find_bone(TAIL_BONE)
	if root_index < 0:
		return Transform3D.IDENTITY
	var root := sk.get_bone_global_rest(root_index)
	var rest := root.basis.orthonormalized()
	# The tail bone's Y runs up her tail, so down the tail is the reverse.
	var local := placement(root, -rest.y, rest.z, rest.x, tail_radius(pony), standoff(pony), cfg)
	# Spin the whole piece 180 degrees about the vertical through the knot: tied on the dock, the
	# bow's own up has to point up her body, and its face away from her.
	var frame := sk.global_basis.orthonormalized().inverse()
	var body := pony.global_basis.orthonormalized()
	var world := root * local
	var up := (frame * body.y).normalized()
	world = Transform3D(Basis(up, PI) * world.basis, world.origin)
	return root.affine_inverse() * world


## Pure placement: the bow's transform relative to the tail root bone. `axis` is down her tail,
## `out` is away from her body at the tail and `up` is her body up, both in the skeleton's space.
static func placement(root: Transform3D, axis: Vector3, out: Vector3, up: Vector3,
		radius: float, offset: float, cfg: Dictionary) -> Transform3D:
	var z := out - axis * out.dot(axis)
	if z.length() < 0.0001:
		z = up - axis * up.dot(axis)
	if z.length() < 0.0001:
		z = axis.cross(up)
	z = z.normalized()
	var y := -axis - z * (-axis).dot(z)
	if y.length() < 0.0001:
		y = up - z * up.dot(z)
	y = y.normalized()
	var x := y.cross(z).normalized()
	var scale := maxf(radius / AUTHORED_RADIUS * float(cfg.get("size", 1.0)), 0.01)
	var basis := Basis(x, y, z) \
		* Basis(Vector3.RIGHT, deg_to_rad(float(cfg.get("tilt_deg", 0.0))))
	basis = basis.scaled(Vector3.ONE * scale)
	var origin := root.origin + z * (offset + TIE_MARGIN) \
		+ axis * float(cfg.get("along_m", 0.03)) * scale
	return root.affine_inverse() * Transform3D(basis, origin)


static func _register_accessory(pony: Node, on: bool) -> void:
	var identity: Variant = pony.get("identity")
	if identity is Resource:
		var current: Resource = identity as Resource
		var names: Variant = current.get("accessories")
		if names is Array:
			var kept: Array[String] = []
			for name: Variant in names:
				if str(name) != NODE_NAME:
					kept.append(str(name))
			var has := kept.size() != (names as Array).size()
			if on == has:
				return
			if on:
				kept.append(NODE_NAME)
			var copy := current.duplicate() as Resource
			if copy == null:
				return
			# `accessories` is a typed Array[String]; an untyped array would be rejected.
			copy.set("accessories", kept)
			pony.set("identity", copy)
	_refresh_variant(pony, on)


## Both merged meshes cache by geometry variant, so a new accessory needs a fresh key.
static func _refresh_variant(pony: Node, on: bool) -> void:
	if not pony.has_method("refresh_geometry_variant"):
		return
	var variant := str(pony.get_meta("geometry_variant", "")).replace(VARIANT_TAG, "")
	if on:
		variant += VARIANT_TAG
	# Rebuilding both merged meshes costs a hitch; never do it inside the frame that ties the bow
	# on, which is where the player would feel it (an act start or a settings edit).
	pony.call_deferred("refresh_geometry_variant", variant)


# --- Mesh -----------------------------------------------------------------------------------

## The one modelled bow mesh, read from the shipped scene once per process.
static func bow_mesh() -> Mesh:
	if _mesh == null:
		var root: Node = (BOW_SCENE as PackedScene).instantiate()
		for node: Node in root.find_children("*", "MeshInstance3D", true, false):
			_mesh = (node as MeshInstance3D).mesh
			break
		root.free()
	return _mesh


## Matte fabric: no sheen, no metal, no rim highlight. It reads as cloth next to the game's cel
## shading instead of a glossy plastic.
static func satin(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.92
	material.metallic = 0.0
	material.metallic_specular = 0.12
	material.rim_enabled = false
	# Fabric has no wrong side: both faces read as cloth, and winding cannot hide a surface.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func build(colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = NODE_NAME
	node.mesh = bow_mesh()
	node.material_override = satin(colour)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.extra_cull_margin = 0.4
	return node


static func _mods() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("Mods")
