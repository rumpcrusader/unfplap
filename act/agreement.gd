extends RefCounted
## The scene-only Agreement start and the act key's immediate start: the frozen-pose verdict, the
## presentation wait, the hotkey readiness and the footstool hint.
##
## See `docs/runtime.md`, `docs/offer.md`, `docs/negotiation.md` and `docs/scene_gate.md`.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_START := preload("res://mods/unfplap/act/start.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## The Agreement start's answer: a transient row or an unsettled presentation keeps waiting; a
## technical rollback is a start failure.
const AGREEMENT_WAIT := 0
const AGREEMENT_STARTED := 1
const AGREEMENT_FAILED := 2

var host: ACT_HOST = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null
var start: ACT_START = null


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT, session_in: ACT_SESSION,
		start_in: ACT_START) -> void:
	host = host_in
	context = context_in
	session = session_in
	start = start_in


## The scene-only Agreement start. Negotiation froze the policy and the pose capability; only the
## world rows run. `WAIT` keeps the Agreement live; `STARTED` and `FAILED` are reported by the offer.
func start_agreement(handle: Variant, skip_presentation := false) -> int:
	if handle == null or not bool(handle.call("valid")):
		return AGREEMENT_FAILED
	var option: Variant = handle.get("option")
	if option == null:
		return AGREEMENT_FAILED
	session.refresh_identity()
	var pose := str(option.pose)
	var act_source := str(option.source)
	var verdict: Variant = context.gate.scene_only_verdict(pose, act_source, option.bed,
		SCENE_GATE.FrozenPose.new(bool(handle.pose_profile_ok), bool(handle.pose_source_ok)))
	if verdict == null or not bool(verdict.hard_ok):
		LOG.debug("agreement start blocked pose=%s source=%s pony=%s reasons=%s", [
			pose, act_source, host.pony_name(),
			"none" if verdict == null else ",".join(verdict.reasons)])
		return AGREEMENT_FAILED
	if not bool(verdict.ok):
		LOG.debug("agreement start waiting pose=%s source=%s transient=%s", [
			pose, act_source, ",".join(verdict.transient)])
		return AGREEMENT_WAIT
	if not skip_presentation and POSE_SPECS.start_setup(pose) == "standing_place" \
			and context.presentation.presentation_active() \
			and not context.presentation.presentation_settled():
		LOG.debug("agreement start waiting pose=%s source=%s presentation", [pose, act_source])
		return AGREEMENT_WAIT
	session.clear_aftercare()
	var started := start.run(pose, option.bed, act_source, skip_presentation)
	LOG.debug("agreement start %s pose=%s source=%s", [
		"started" if started else "failed", pose, act_source])
	return AGREEMENT_STARTED if started else AGREEMENT_FAILED


## True when the scene-only rows pass and, for a standing option, the presentation is settled.
func agreement_offer_ready(handle: Variant, skip_presentation := false) -> bool:
	if handle == null or not bool(handle.call("valid")):
		return false
	var option: Variant = handle.option
	if option == null:
		return false
	session.refresh_identity()
	var pose := str(option.pose)
	var verdict: Variant = context.gate.scene_only_verdict(pose, str(option.source), option.bed,
		SCENE_GATE.FrozenPose.new(bool(handle.pose_profile_ok), bool(handle.pose_source_ok)))
	if verdict == null or not bool(verdict.ok):
		return false
	if not skip_presentation and POSE_SPECS.start_setup(pose) == "standing_place" \
			and context.presentation.presentation_active() \
			and not context.presentation.presentation_settled():
		return false
	return true


## The act key's readiness check; unlike a policy start it never bucks.
func hotkey_ready(pose: String, act_source: String, bed_in: Variant = null) -> bool:
	session.refresh_identity()
	var stool_act: Variant = session.stool()
	var pair := Vector2i(-1, -1)
	if stool_act != null:
		pair = stool_act.call("hotkey_pair", pose)
	PERF.begin("offer_rows")
	var allowed: bool = context.gate.hotkey_ready(pose, act_source, bed_in, pair)
	PERF.end("offer_rows")
	return allowed


## The footstool pair this call's gate used, so the blocked standing note does not repeat the
## reach and case reads.
func hint_stool() -> Dictionary:
	var stool_act: Variant = session.stool()
	if stool_act == null:
		return {"need": 0, "have": 0}
	return stool_act.call("hint_pair")


## The act key's immediate attempt, with no Agreement and no presentation wait.
func start_hotkey(pose: String, bed_in: Variant, act_source: String,
		skip_presentation := false) -> bool:
	if not hotkey_ready(pose, act_source, bed_in):
		LOG.debug("hotkey blocked pose=%s source=%s pony=%s", [
			pose, act_source, host.pony_name()])
		return false
	session.clear_aftercare()
	var started := start.run(pose, bed_in, act_source, skip_presentation)
	LOG.debug("hotkey start %s pose=%s source=%s", [
		"started" if started else "failed", pose, act_source])
	return started
