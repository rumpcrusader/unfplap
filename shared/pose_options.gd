extends RefCounted
## Pure pose-option builder: the capability table plus plain placement facts produce the list of
## options an offer may choose from. It never reads a scene, service, setting, clock or file.
## Contract: `docs/scene_gate.md` (`## Pose placement`) and `docs/poses.md`.
##
## An option is `(pose, source, bed)`. Only placeable, offerable options are returned; an empty
## list means no offer and no reasoning.

const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

## The act source of a missionary option offered from a bed she is already on.
const SOURCE_ALREADY_LYING := "already_lying"
## The act source of a missionary option offered from the bed side.
const SOURCE_BED_SIDE := "bed_side"


## One available choice.
class Option:
	var pose := ""
	var source := ""
	var bed: Variant = null
	var cuddle := false

	## False for the empty sentinel.
	func valid() -> bool:
		return not pose.is_empty()

	## Exact identity match: pose, source and the same bed node (or both empty).
	func matches(pose_in: String, source_in: String, bed_in: Variant, cuddle_in := false) -> bool:
		return pose == pose_in and source == source_in and Option.same_bed(bed, bed_in) \
			and cuddle == cuddle_in

	## Two bed handles are the same when both are empty or both are the same node.
	static func same_bed(a: Variant, b: Variant) -> bool:
		if not is_instance_valid(a) and not is_instance_valid(b):
			return true
		if not is_instance_valid(a) or not is_instance_valid(b):
			return false
		return a == b

	## A stable debug/handoff key.
	func key() -> String:
		var bed_id := "none"
		if is_instance_valid(bed):
			bed_id = str((bed as Node).get_instance_id())
		return "%s|%s|%s|%s" % [pose, source, bed_id, str(cuddle)]


## The plain placement facts the caller gathers. One placement pass answers every option.
class Placement:
	## She is in an active cuddle and a bed is under her.
	var cuddle := false
	## The bed under her, when `cuddle` is true.
	var cuddle_bed: Variant = null
	## A free bed near Anon, ready to lead her to.
	var bed: Variant = null
	## The free stand spot in front of that bed; null when the bed has none.
	var bed_front: Variant = null
	## A free navigator, same region, within approach reach.
	var standing_free := false


## The missionary source the player's form uses.
static func source_for(form: String) -> String:
	return SOURCE_ALREADY_LYING if form == "pony" else SOURCE_BED_SIDE


## Build the available options, in the order the caller should preference them: cuddle, bed,
## standing. A pose whose capability row rejects the form or view, or whose scene rejects the
## source, is omitted.
static func build(form: String, view: String, placement: Placement) -> Array[Option]:
	var out: Array[Option] = []
	if placement == null:
		return out
	var source := source_for(form)
	if placement.cuddle and is_instance_valid(placement.cuddle_bed):
		var cuddle_option := _option(CATALOG.MISSIONARY, source, placement.cuddle_bed, form, view)
		if cuddle_option != null:
			cuddle_option.cuddle = true
			out.append(cuddle_option)
	if is_instance_valid(placement.bed) and placement.bed_front is Vector3 \
			and (placement.bed_front as Vector3).is_finite():
		var bed_option := _option(CATALOG.MISSIONARY, source, placement.bed, form, view)
		if bed_option != null:
			out.append(bed_option)
	if placement.standing_free:
		var standing_option := _option(CATALOG.STANDING, "", null, form, view)
		if standing_option != null:
			out.append(standing_option)
	return out


## Find an exact option in a list. The returned option is the list's own object.
static func find(options: Array[Option], pose: String, source: String, bed: Variant,
		cuddle := false) -> Option:
	for option: Option in options:
		if option.matches(pose, source, bed, cuddle):
			return option
	return null


## Whether a list contains the exact option.
static func has(options: Array[Option], pose: String, source: String, bed: Variant,
		cuddle := false) -> bool:
	return find(options, pose, source, bed, cuddle) != null


## Debug text for a log line.
static func describe(options: Array[Option]) -> String:
	if options.is_empty():
		return "none"
	var keys: PackedStringArray = []
	for option: Option in options:
		keys.append(option.key())
	return ",".join(keys)


static func same_bed(a: Variant, b: Variant) -> bool:
	return Option.same_bed(a, b)


static func _option(pose: String, source: String, bed: Variant, form: String,
		view: String) -> Option:
	if not POSE_SPECS.is_public(pose) or not POSE_SPECS.is_offerable(pose):
		return null
	if str(POSE_SPECS.scene(pose).get("frame", "")).is_empty():
		return null
	if not POSE_SPECS.supports(pose, form, view):
		return null
	if not _source_allowed(pose, source):
		return null
	var out := Option.new()
	out.pose = pose
	out.source = source
	out.bed = bed
	return out


static func _source_allowed(pose: String, source: String) -> bool:
	var sources: Variant = POSE_SPECS.scene(pose).get("sources", [])
	if not sources is Array:
		return true
	var list := sources as Array
	return list.is_empty() or source in list
