extends RefCounted
## The offer-facing gate handle: the scene verdicts, the Agreement start, the hotkey readiness,
## the stool/rump hints and the scene-hold presentation reads. `offer`, `negotiation` and
## `initiation` read this handle; the runtime node keeps only the handle.
##
## See `docs/runtime.md`, `docs/scene_gate.md` and `docs/offer.md`.

const SCENE_GATE := preload("res://mods/unfplap/scene_gate/service.gd")
const ACT_AGREEMENT := preload("res://mods/unfplap/act/agreement.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const REACTIONS := preload("res://mods/unfplap/reactions/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")

var scene: SCENE_GATE = null
var agreement: ACT_AGREEMENT = null
var session: ACT_SESSION = null
var reactions: REACTIONS = null


func bind(scene_in: SCENE_GATE, agreement_in: ACT_AGREEMENT, session_in: ACT_SESSION,
		reactions_in: REACTIONS) -> void:
	scene = scene_in
	agreement = agreement_in
	session = session_in
	reactions = reactions_in


## The policy + scene rows for a start. The identity is refreshed first so a late-assigned
## relationship id is the one the rows read.
func start_verdict(pose: String, act_source: String, bed_in: Variant = null,
		verdict_in: ELIGIBILITY.Verdict = null) -> Dictionary:
	session.refresh_identity()
	return scene.start_verdict(pose, act_source, bed_in, verdict_in)


## The scene-only start rows for an accepted Agreement.
func scene_only_verdict(pose: String, act_source: String, bed_in: Variant = null,
		frozen: Variant = null, stool_need: int = -1, stool_have: int = -1) -> Variant:
	session.refresh_identity()
	var capability: Variant = frozen if frozen != null else SCENE_GATE.FrozenPose.new(true, true)
	return scene.scene_only_verdict(pose, act_source, bed_in, capability, stool_need, stool_have)


func hotkey_ready(pose: String, act_source: String, bed_in: Variant = null) -> bool:
	return agreement.hotkey_ready(pose, act_source, bed_in)


func hint_stool() -> Dictionary:
	return agreement.hint_stool()


func agreement_offer_ready(handle: Variant, skip_presentation := false) -> bool:
	return agreement.agreement_offer_ready(handle, skip_presentation)


func start_hotkey(pose: String, bed_in: Variant, act_source: String,
		skip_presentation := false) -> bool:
	return agreement.start_hotkey(pose, bed_in, act_source, skip_presentation)


func start_agreement(handle: Variant, skip_presentation := false) -> int:
	return agreement.start_agreement(handle, skip_presentation)


func find_bed_under() -> Node3D:
	return scene.find_bed_under()


func cuddle_active() -> bool:
	return scene.cuddle_active()


func free_of_affection() -> bool:
	return scene.free_of_affection()


func suppress_auto_cuddle() -> void:
	scene.suppress_auto_cuddle()


## The rump point the offer hint anchors to.
func rump_anchor() -> Vector3:
	return reactions.rump_point()


func stool_gap_m() -> float:
	var stool: Variant = session.stool()
	return float(stool.call("gap_m")) if stool != null else NAN


func stool_needed_count() -> int:
	var stool: Variant = session.stool()
	return int(stool.call("needed_count")) if stool != null else 0


func stool_case_count() -> int:
	var stool: Variant = session.stool()
	return int(stool.call("case_count")) if stool != null else 0


func stool_state_text() -> String:
	var stool: Variant = session.stool()
	return str(stool.call("state_text")) if stool != null else "stool unavailable"


## The scene hold and the standing presentation are the offer's placement reads.
func hold_handle() -> RefCounted:
	return session.hold_handle()


func present_standing() -> bool:
	return session.present_standing()


func presentation_active() -> bool:
	return session.presentation_active()


func presentation_settled() -> bool:
	return session.presentation_settled()


func clear_presentation() -> void:
	session.clear_presentation()
