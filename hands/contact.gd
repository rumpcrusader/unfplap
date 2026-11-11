extends RefCounted
## Coat queries shared by every caress mode. This module knows the pony's body, the flank patch
## and the touch hulls, but nothing about poses, paths or palms.


## PonyTouchBody follows the game's own hands, and the missionary act parks them. Without this the
## hull query reads the last standing/pre-act hulls and the palm floats at their old height. The
## act's physics pose is live, so refresh the body rig before the coat query. Guarded: a game
## without the internal sync simply uses the hulls as they are.
static func sync_touch(pony: Variant) -> void:
	if not is_instance_valid(pony):
		return
	var touch: Variant = pony.get("touch_body")
	if touch == null or not touch.has_method("_unprofiled_sync"):
		return
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
			touch.call("_unprofiled_sync", rig, true)


static func region_ignored(region: String, ignore: Array) -> bool:
	if ignore.is_empty():
		return false
	var name := region.to_lower()
	for value: Variant in ignore:
		var prefix := str(value).to_lower()
		if name == prefix or name.begins_with(prefix + "_"):
			return true
	return false


static func region_allowed(region: String, allowed: Array) -> bool:
	if allowed.is_empty():
		return true
	var name := region.to_lower()
	for value: Variant in allowed:
		var wanted := str(value).to_lower()
		if name == wanted:
			return true
		if wanted == "head" and name.begins_with("head_"):
			return true
	return false


## PonyTouchBody.nearest() without the ignored regions, optionally restricted to a region list.
## Only used when a filter is set; otherwise the game's own query is used unchanged.
static func nearest_touch(pony: Variant, point: Vector3, ignore: Array,
		allowed: Array = []) -> Dictionary:
	var touch: Variant = pony.get("touch_body") if is_instance_valid(pony) else null
	if touch == null or not touch.has_method("nearest"):
		return {}
	var near: Dictionary = touch.call("nearest", point)
	if ignore.is_empty() and allowed.is_empty():
		return near
	var entry: Variant = near.get("entry")
	if entry is Dictionary:
		var name := str((entry as Dictionary).get("region", ""))
		if not region_ignored(name, ignore) and region_allowed(name, allowed):
			return near
	var entries: Variant = touch.get("_entries")
	if not entries is Array:
		return {}
	var best: Dictionary = {}
	var best_distance := INF
	for e: Variant in entries:
		if not e is Dictionary:
			continue
		var ed: Dictionary = e
		var name := str(ed.get("region", ""))
		if region_ignored(name, ignore) or not region_allowed(name, allowed):
			continue
		var world: Variant = ed.get("world")
		if not world is Transform3D:
			continue
		var local: Vector3 = (world as Transform3D).affine_inverse() * point
		var a: Vector3 = ed.get("a", Vector3.ZERO)
		var b: Vector3 = ed.get("b", Vector3.ZERO)
		var ab := b - a
		var t := clampf((local - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var away := local - (a + ab * t)
		var distance := away.length() - float(ed.get("r", 0.0))
		if distance < best_distance:
			best_distance = distance
			var normal := Vector3.UP
			if away.length() > 0.000001:
				normal = away.normalized()
			best = {"entry": ed, "distance": distance, "local": local, "normal": normal}
	return best


## Nearest coat point/normal for a palm. FlankSurface owns the flank/rump patch; the body
## hull query covers the shoulder and any point outside that patch. A non-empty `regions` list
## skips the flank patch and restricts the hulls to those regions.
static func contact(pony: Variant, point: Vector3, outward_hint: Vector3,
		ignore: Array = [], regions: Array = []) -> Dictionary:
	if not is_instance_valid(pony):
		return {"point": point, "normal": outward_hint, "source": "fallback"}
	var outward := outward_hint.normalized()
	if outward.length_squared() < 0.5:
		outward = pony.global_basis.x.normalized()
	var flank: Node = pony.get_node_or_null("FlankTouch")
	if is_instance_valid(flank) and regions.is_empty():
		var surface: Variant = flank.get("surface")
		var frame: Variant = flank.get("frame")
		var sk: Variant = pony.get("skeleton")
		if surface != null and surface.has_method("contact") and frame is Transform3D:
			var local_point: Vector3 = (frame as Transform3D).affine_inverse() * point
			var radii: Variant = flank.get("radii")
			var reach := float((radii as Vector3).z) if radii is Vector3 else 0.10
			# The flank patch only covers the cheek. Skip its skinning and query when the point is
			# outside the last posed bounds, so a shoulder or neck caress goes straight to the hulls.
			var bounds: Variant = surface.get("bounds")
			var near_flank := not bounds is AABB or not (bounds as AABB).has_volume() \
				or (bounds as AABB).grow(reach + 0.02).has_point(local_point)
			if near_flank:
				if surface.has_method("update_pose") and sk is Skeleton3D:
					surface.call("update_pose", sk, frame)
				var local_palm: Vector3 = ((frame as Transform3D).basis.inverse() * -outward).normalized()
				var hit: Dictionary = surface.call("contact", local_point, local_point, local_palm, reach)
				var hit_local: Variant = hit.get("position")
				var normal_local: Variant = hit.get("normal")
				if hit_local is Vector3 and normal_local is Vector3:
					var hit_world: Vector3 = (frame as Transform3D) * (hit_local as Vector3)
					var hit_normal: Vector3 = ((frame as Transform3D).basis.inverse().transposed() \
						* (normal_local as Vector3)).normalized()
					if hit_normal.dot(outward) < 0.0:
						hit_normal = -hit_normal
					return {"point": hit_world, "normal": hit_normal, "source": "flank"}
	var touch: Variant = pony.get("touch_body")
	if touch != null and touch.has_method("nearest"):
		var near: Dictionary = nearest_touch(pony, point, ignore, regions)
		var entry: Variant = near.get("entry")
		var normal_local: Variant = near.get("normal")
		if entry is Dictionary and normal_local is Vector3:
			var world: Variant = (entry as Dictionary).get("world")
			if world is Transform3D:
				var hit_normal: Vector3 = ((world as Transform3D).basis \
					* (normal_local as Vector3)).normalized()
				var distance := float(near.get("distance", 0.0))
				if hit_normal.dot(outward) < 0.0:
					hit_normal = -hit_normal
					distance = -distance
				return {"point": point - hit_normal * distance, "normal": hit_normal,
					"source": "hull"}
	return {"point": point, "normal": outward, "source": "fallback"}


## Keep a genuine coat normal: blending toward a torso radial tilts the palm off the surface
## and presses its heel into the coat. The radial is only a fallback for a degenerate normal or
## one that points into the body.
static func stable_outward(pony: Variant, point: Vector3, hint: Vector3,
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


static func radial_outward(pony: Variant, point: Vector3, hint: Vector3) -> Vector3:
	if not is_instance_valid(pony):
		return hint.normalized()
	var scale := clampf(float(pony.get("body_scale")), 0.8, 1.6)
	var centre: Vector3 = pony.global_position + Vector3.UP * (0.55 * scale)
	var radial: Vector3 = point - centre
	if radial.length_squared() < 0.001:
		return Vector3.ZERO
	return radial.normalized()
