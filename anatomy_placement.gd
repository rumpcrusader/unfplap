extends RefCounted
## Anatomy placement data and resolution.
##
## Placement lives in `settings.json` under one block:
##
##   anatomy.placement.default.*        the global default for every mare, including modded mares
##   anatomy.placement.anon.*           the player part
##   anatomy.placement.<mare id>.*      a per-mare override
##
## `default` and `anon` are reserved; every other key is a pony id. A per-mare block stores only
## the keys that differ from the resolved default, so the file stays small and the shipped
## defaults stay the single source of truth.

const KEYS := ["offset_x", "offset_y", "offset_z", "pitch_deg", "scale", "tail_y", "tail_z", "dock_y", "dock_scale"]
## Shipped per-mare defaults. Keep partial: a missing key falls back to the global default.
## `/sync-settings` promotes a custom mare placement here when the user asks for it.
const MARE_DEFAULTS := {
}

## One-time import of the old user://mods/data/unfplap/anatomy_place.json. The old file carried a
## version because the calibration moved twice; these shifts are the only place those offsets stay.
const LEGACY_VERSION := 3
const LEGACY_FORWARD_M := 0.005
const LEGACY_RIGHT_M := 0.005
const LEGACY_FORWARD_STEP_M := 0.003


## One row of the old file, in the new key names. Missing keys are omitted so a partial row can
## still merge over the default.
static func row_to_placement(row: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not row is Dictionary:
		return out
	var block: Dictionary = row
	var position: Variant = block.get("position")
	if position is Array and (position as Array).size() == 3:
		out["offset_x"] = float(position[0])
		out["offset_y"] = float(position[1])
		out["offset_z"] = float(position[2])
	for pair: Array in [["pitch", "pitch_deg"], ["scale", "scale"]]:
		var source := str(pair[0])
		if block.has(source):
			out[str(pair[1])] = float(block[source])
	return out


## Shift every old row onto the current coordinate space. Pure; the caller writes the result.
static func migrate_legacy(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	if version >= LEGACY_VERSION:
		return data
	var shift := Vector3.ZERO
	if version < 1:
		shift.z = LEGACY_FORWARD_M
	if version < 2:
		shift.x = LEGACY_RIGHT_M
	if version < 3:
		shift.z += LEGACY_FORWARD_STEP_M
	for id: Variant in data.keys():
		if str(id) == "version":
			continue
		var row: Variant = data[id]
		if not row is Dictionary:
			continue
		var position: Variant = (row as Dictionary).get("position")
		if position is Array and (position as Array).size() == 3:
			(row as Dictionary)["position"] = [
				float(position[0]) + shift.x,
				float(position[1]) + shift.y,
				float(position[2]) + shift.z,
			]
	data["version"] = LEGACY_VERSION
	return data


## Overlay the finite keys from `over` onto a copy of `base`, without filling missing keys.
static func overlay(base: Dictionary, over: Variant) -> Dictionary:
	var out := base.duplicate(true)
	if over is Dictionary:
		var block: Dictionary = over
		for key: String in KEYS:
			if not block.has(key):
				continue
			var value: Variant = block[key]
			if (value is float or value is int) and is_finite(float(value)):
				out[key] = float(value)
	return out


## Merge a partial block over a complete one. The result always has all nine keys and a positive
## anatomy and dock scale; keep `base` complete when the result is used as a placement.
static func merge(base: Dictionary, over: Variant) -> Dictionary:
	return sanitize(overlay(base, over), base)


## Fill missing or malformed keys from `fallback`.
static func sanitize(raw: Variant, fallback: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in KEYS:
		var value := 0.0
		if fallback.has(key):
			value = float(fallback[key])
		if raw is Dictionary and (raw as Dictionary).has(key):
			var candidate: Variant = (raw as Dictionary)[key]
			if (candidate is float or candidate is int) and is_finite(float(candidate)):
				value = float(candidate)
		out[key] = value
	out["scale"] = maxf(0.05, float(out["scale"]))
	out["dock_scale"] = maxf(0.05, float(out["dock_scale"]))
	return out


## Only the keys that differ from `base`, so a saved per-mare block stays a real override.
static func diff(values: Dictionary, base: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in KEYS:
		var value := float(values.get(key, 0.0))
		var reference := float(base.get(key, 0.0))
		if absf(value - reference) > 0.000001:
			out[key] = value
	return out


static func same(a: Dictionary, b: Dictionary) -> bool:
	for key: String in KEYS:
		if absf(float(a.get(key, 0.0)) - float(b.get(key, 0.0))) > 0.000001:
			return false
	return true


static func text(values: Dictionary) -> String:
	return "position=(%.3f,%.3f,%.3f) pitch=%.1f scale=%.3f tail=(%.1f,%.1f)mm dock=(%.1f,%.2f×)" % [
		float(values.get("offset_x", 0.0)),
		float(values.get("offset_y", 0.0)),
		float(values.get("offset_z", 0.0)),
		float(values.get("pitch_deg", 0.0)),
		float(values.get("scale", 1.0)),
		float(values.get("tail_y", 0.0)) * 1000.0,
		float(values.get("tail_z", 0.0)) * 1000.0,
		float(values.get("dock_y", 0.0)) * 1000.0,
		float(values.get("dock_scale", 1.0)),
	]
