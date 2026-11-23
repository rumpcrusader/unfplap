extends RefCounted
## Coat queries shared by every caress mode; base-game dictionaries are parsed here.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const MODEL := preload("res://mods/unfplap/hands/model.gd")


## PonyTouchBody follows the game's own hands, which the missionary act parks; refresh the rig
## first or a stale hull puts the palm at an old height.
static func sync_touch(pony: Node3D) -> void:
	if not is_instance_valid(pony):
		return
	var touch: Variant = pony.get("touch_body")
	if not touch is Node or not (touch as Node).has_method("_unprofiled_sync"):
		return
	var body := touch as Node
	var rigs: Variant = touch.get("_rigs")
	var entries: Variant = touch.get("_entries")
	if not rigs is Array or (rigs as Array).is_empty():
		return
	if not entries is Array or (entries as Array).is_empty():
		return
	# The neck and head hulls live on the body and head rigs; sync every valid rig so a caress
	# that moves up to the cheek sees the act's live pose, not stale standing hulls.
	for rig in (rigs as Array).size():
		if is_instance_valid((rigs as Array)[rig]):
			WORLD.flank(body).sync(rig)


static func region_ignored(region: String, ignore: Array[String]) -> bool:
	if ignore.is_empty():
		return false
	var name := region.to_lower()
	for value: String in ignore:
		var prefix := value.to_lower()
		if name == prefix or name.begins_with(prefix + "_"):
			return true
	return false


static func region_allowed(region: String, allowed: Array[String]) -> bool:
	if allowed.is_empty():
		return true
	var name := region.to_lower()
	for value: String in allowed:
		var wanted := value.to_lower()
		if name == wanted:
			return true
		if wanted == "head" and name.begins_with("head_"):
			return true
	return false


static func _entry_of(value: Variant) -> MODEL.TouchEntry:
	if not value is Dictionary:
		return null
	var entry: Dictionary = value
	var out := MODEL.TouchEntry.new()
	out.region = str(entry.get("region", ""))
	var world: Variant = entry.get("world")
	if world is Transform3D:
		out.world = world
	out.a = entry.get("a", Vector3.ZERO)
	out.b = entry.get("b", Vector3.ZERO)
	out.r = float(entry.get("r", 0.0))
	return out


## PonyTouchBody.nearest() without the ignored regions, optionally restricted to a region list.
static func nearest_touch(pony: Node3D, point: Vector3, ignore: Array[String],
		allowed: Array[String] = []) -> MODEL.TouchHit:
	var out := MODEL.TouchHit.new()
	var touch: Variant = pony.get("touch_body") if is_instance_valid(pony) else null
	if touch == null or not touch.has_method("nearest"):
		return out
	var near: Dictionary = WORLD.flank(touch).touch_nearest(point)
	var entry := _entry_of(near.get("entry"))
	if ignore.is_empty() and allowed.is_empty():
		if entry != null:
			out.hit = true
			out.entry = entry
			out.distance = float(near.get("distance", 0.0))
			var local: Variant = near.get("local")
			if local is Vector3:
				out.local = local
			var normal: Variant = near.get("normal")
			if normal is Vector3:
				out.normal = normal
		return out
	if entry != null and not region_ignored(entry.region, ignore) \
			and region_allowed(entry.region, allowed):
		out.hit = true
		out.entry = entry
		out.distance = float(near.get("distance", 0.0))
		var local: Variant = near.get("local")
		if local is Vector3:
			out.local = local
		var normal: Variant = near.get("normal")
		if normal is Vector3:
			out.normal = normal
		return out
	var entries: Variant = touch.get("_entries")
	if not entries is Array:
		return out
	var best_distance := INF
	for e: Variant in entries:
		var parsed := _entry_of(e)
		if parsed == null:
			continue
		if region_ignored(parsed.region, ignore) or not region_allowed(parsed.region, allowed):
			continue
		var local: Vector3 = parsed.world.affine_inverse() * point
		var ab := parsed.b - parsed.a
		var t := clampf((local - parsed.a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var away := local - (parsed.a + ab * t)
		var distance := away.length() - parsed.r
		if distance < best_distance:
			best_distance = distance
			out.hit = true
			out.entry = parsed
			out.distance = distance
			out.local = local
			out.normal = away.normalized() if away.length() > 0.000001 else Vector3.UP
	return out


## Nearest coat point and normal for a palm: the flank patch first, then the body hulls.
static func contact(pony: Node3D, point: Vector3, outward_hint: Vector3,
		ignore: Array[String] = [], regions: Array[String] = []) -> MODEL.Contact:
	var out := MODEL.Contact.new()
	out.point = point
	out.normal = outward_hint
	if not is_instance_valid(pony):
		return out
	var outward := outward_hint.normalized()
	if outward.length_squared() < 0.5:
		outward = pony.global_basis.x.normalized()
	out.normal = outward
	var flank: Node = pony.get_node_or_null("FlankTouch")
	if is_instance_valid(flank) and regions.is_empty():
		var surface: Variant = flank.get("surface")
		var frame := flank_frame(flank)
		var sk: Variant = pony.get("skeleton")
		if surface != null and surface.has_method("contact") and frame.is_finite():
			var local_point: Vector3 = frame.affine_inverse() * point
			var reach := flank_radii(flank).z
			# The flank patch only covers the cheek. Skip its skinning and query when the point is
			# outside the last posed bounds, so a shoulder caress goes straight to the hulls.
			var bounds: Variant = surface.get("bounds")
			var near_flank := not bounds is AABB or not (bounds as AABB).has_volume() \
				or (bounds as AABB).grow(reach + 0.02).has_point(local_point)
			if near_flank:
				if surface.has_method("update_pose") and sk is Skeleton3D:
					WORLD.flank(flank).update_surface(surface, sk, frame)
				var local_palm: Vector3 = (frame.basis.inverse() * -outward).normalized()
				var hit := flank_contact(flank, local_point, local_palm)
				if hit != null:
					var hit_world: Vector3 = frame * hit.point
					var hit_normal: Vector3 = (frame.basis.inverse().transposed() \
						* hit.normal).normalized()
					if hit_normal.dot(outward) < 0.0:
						hit_normal = -hit_normal
					out.point = hit_world
					out.normal = hit_normal
					out.source = "flank"
					return out
	var near := nearest_touch(pony, point, ignore, regions)
	if near.hit and near.entry != null:
		var hit_normal: Vector3 = (near.entry.world.basis * near.normal).normalized()
		var distance := near.distance
		if hit_normal.dot(outward) < 0.0:
			hit_normal = -hit_normal
			distance = -distance
		out.point = point - hit_normal * distance
		out.normal = hit_normal
		out.source = "hull"
		return out
	return out


## The world frame of the posed flank patch.
static func flank_frame(flank: Node) -> Transform3D:
	if not is_instance_valid(flank):
		return Transform3D.IDENTITY
	var value: Variant = flank.get("frame")
	if value is Transform3D and (value as Transform3D).is_finite():
		return value
	return flank.global_transform


static func flank_radii(flank: Node) -> Vector3:
	if not is_instance_valid(flank):
		return Vector3.ZERO
	var value: Variant = flank.get("radii")
	return value if value is Vector3 else Vector3.ZERO


static func flank_centers(flank: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not is_instance_valid(flank):
		return out
	var value: Variant = flank.get("centers")
	if not value is Array:
		return out
	for centre: Variant in (value as Array):
		if centre is Vector3:
			out.append(centre)
	return out


static func flank_normals(flank: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not is_instance_valid(flank):
		return out
	var value: Variant = flank.get("normals")
	if not value is Array:
		return out
	for normal: Variant in (value as Array):
		if normal is Vector3:
			out.append(normal)
	return out


static func flank_surface(flank: Node) -> Variant:
	if not is_instance_valid(flank):
		return null
	return flank.get("surface")


## The posed patch's triangle normals and face corners, or empty when the surface is absent.
static func flank_faces(flank: Node) -> PackedVector3Array:
	var surface: Variant = flank_surface(flank)
	if surface == null:
		return PackedVector3Array()
	var value: Variant = surface.get("faces")
	return value if value is PackedVector3Array else PackedVector3Array()


static func flank_vertex_normals(flank: Node) -> PackedVector3Array:
	var surface: Variant = flank_surface(flank)
	if surface == null:
		return PackedVector3Array()
	var value: Variant = surface.get("vertex_normals")
	return value if value is PackedVector3Array else PackedVector3Array()


## Skin the patch to the act skeleton before its faces are read.
static func flank_update(pony: Node3D, flank: Node) -> void:
	var surface: Variant = flank_surface(flank)
	if surface == null or not surface.has_method("update_pose"):
		return
	var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if sk is Skeleton3D:
		WORLD.flank(flank).update_surface(surface, sk, flank_frame(flank))


## Refine a local patch point onto the real triangle so the palm normal follows the coat.
static func flank_contact(flank: Node, local_point: Vector3,
		local_normal: Vector3) -> MODEL.FlankContact:
	var surface: Variant = flank_surface(flank)
	if surface == null or not surface.has_method("contact"):
		return null
	var reach := 0.10
	var radii := flank_radii(flank)
	if radii.z > 0.0:
		reach = radii.z
	var raw := WORLD.flank(flank).surface_contact(surface, local_point, -local_normal, reach)
	if raw.is_empty():
		return null
	var raw_point: Variant = raw.get("position")
	var raw_normal: Variant = raw.get("normal")
	if not raw_point is Vector3 or not raw_normal is Vector3:
		return null
	var out := MODEL.FlankContact.new()
	out.point = raw_point
	out.normal = (raw_normal as Vector3).normalized()
	return out


## Keep a genuine coat normal: a torso radial tilts the palm off the surface and presses its heel in.
static func stable_outward(pony: Node3D, point: Vector3, hint: Vector3,
		use_radial := true) -> Vector3:
	if not is_instance_valid(pony) or not use_radial:
		return hint.normalized()
	var wanted := hint.normalized()
	if wanted.length_squared() < 0.5:
		return radial_outward(pony, point, hint)
	var radial := radial_outward(pony, point, hint)
	if radial.length_squared() < 0.5:
		return wanted
	return radial if wanted.dot(radial) < 0.1 else wanted


static func radial_outward(pony: Node3D, point: Vector3, hint: Vector3) -> Vector3:
	if not is_instance_valid(pony):
		return hint.normalized()
	var scale := clampf(float(pony.get("body_scale")), 0.8, 1.6)
	var centre: Vector3 = pony.global_position + Vector3.UP * (0.55 * scale)
	var radial: Vector3 = point - centre
	if radial.length_squared() < 0.001:
		return Vector3.ZERO
	return radial.normalized()
