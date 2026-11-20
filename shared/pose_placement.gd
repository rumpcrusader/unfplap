extends RefCounted
## Pure pose placement: plain world facts for one chosen option produce a typed ok/reason. It reads
## no scene, service, setting, clock or file. Contract: `docs/scene_gate.md`
## (`## Pose options and placement`).
##
## Placement is live world feasibility; the pose capability froze at formation, the rest is live.

const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")

const REASON_POSE := "pose"
const REASON_SOURCE := "pose_source"
const REASON_BED := "bed"
const REASON_BED_FRONT := "bed_front"
const REASON_STANDING := "standing_free"
const REASON_STOOL := "stool"
const REASON_PLAYER := "player"


## The live placement facts for the chosen option.
class Facts:
	## A bed resolves for the pose.
	var bed_known := false
	## The resolved bed has a finite front stand spot.
	var bed_front_known := false
	## A standing pose: she is not held or seated.
	var standing_free := false
	## Enough footstools for the pose.
	var stool_ok := true
	## Anon is free and in position for the pose.
	var player_ready := true


## The typed placement answer.
class Result:
	var ok := false
	var reason := ""

	func accepted() -> bool:
		return ok


## Check one option against the live facts.
static func check(pose: String, source: String, facts: Facts) -> Result:
	var out := Result.new()
	if not POSE_SPECS.is_public(pose) or not POSE_SPECS.is_offerable(pose) \
			or str(POSE_SPECS.scene(pose).get("frame", "")).is_empty():
		out.reason = REASON_POSE
		return out
	if not _source_allowed(pose, source):
		out.reason = REASON_SOURCE
		return out
	var scene := POSE_SPECS.scene(pose)
	if bool(scene.get("requires_bed", false)):
		if not facts.bed_known:
			out.reason = REASON_BED
			return out
		if not facts.bed_front_known:
			out.reason = REASON_BED_FRONT
			return out
	if bool(scene.get("standing_free", false)) and not facts.standing_free:
		out.reason = REASON_STANDING
		return out
	if bool(scene.get("stool", false)) and not facts.stool_ok:
		out.reason = REASON_STOOL
		return out
	if not facts.player_ready:
		out.reason = REASON_PLAYER
		return out
	out.ok = true
	return out


## Whether the pose's authored scene accepts this act source. An empty source list places no
## constraint.
static func source_allowed(pose: String, source: String) -> bool:
	return _source_allowed(pose, source)


static func _source_allowed(pose: String, source: String) -> bool:
	var sources: Variant = POSE_SPECS.scene(pose).get("sources", [])
	if not sources is Array:
		return true
	var list := sources as Array
	return list.is_empty() or source in list
