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
const NEGOTIATION_HANDLE := preload("res://mods/unfplap/negotiation/agreement.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")

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
func start_verdict(pose: String, act_source: String, bed_in: Node3D = null,
		verdict_in: ELIGIBILITY.Verdict = null) -> SCENE_GATE.GateVerdict:
	session.refresh_identity()
	return scene.start_verdict(pose, act_source, bed_in, verdict_in)


## The scene-only start rows for an accepted Agreement.
func scene_only_verdict(pose: String, act_source: String, bed_in: Node3D = null,
		frozen: SCENE_GATE.FrozenPose = null, stool_need: int = -1,
		stool_have: int = -1) -> SCENE_GATE.SceneVerdict:
	session.refresh_identity()
	var capability := frozen if frozen != null else SCENE_GATE.FrozenPose.new(true, true)
	return scene.scene_only_verdict(pose, act_source, bed_in, capability, stool_need, stool_have)


func hotkey_ready(pose: String, act_source: String, bed_in: Node3D = null,
		stool_pair: Vector2i = SCENE_GATE.NO_STOOL_PAIR) -> bool:
	return scene.hotkey_ready(pose, act_source, bed_in, stool_pair)


## The small scene checks, for the hint that builds no rows. `agreement_ready` takes the
## Agreement's frozen pose capability.
func available() -> bool:
	return scene.available()


func pose_supported(pose: String, act_source: String) -> bool:
	return scene.pose_supported(pose, act_source)


func navigator_allows(pose: String, act_source: String) -> bool:
	return scene.navigator_allows(pose, act_source)


func posture_allows(pose: String) -> bool:
	return scene.posture_allows(pose)


func player_ready(pose: String, act_source: String, bed_in: Node3D = null) -> bool:
	return scene.player_ready(pose, act_source, bed_in)


func agreement_ready(pose: String, act_source: String, bed_in: Node3D = null,
		frozen: SCENE_GATE.FrozenPose = null) -> bool:
	return scene.agreement_ready(pose, act_source, bed_in, frozen)


## The footstool pair one scan reads and hands to `hotkey_ready`.
func stool_pair(pose: String) -> Vector2i:
	var stool := session.stool() as STOOL.ACT
	return stool.hotkey_pair(pose) if stool != null else SCENE_GATE.NO_STOOL_PAIR


func hint_stool() -> Dictionary:
	return agreement.hint_stool()


func agreement_offer_ready(handle: NEGOTIATION_HANDLE.Handle, skip_presentation := false) -> bool:
	return agreement.agreement_offer_ready(handle, skip_presentation)


func start_hotkey(pose: String, bed_in: Variant, act_source: String,
		skip_presentation := false) -> bool:
	return agreement.start_hotkey(pose, bed_in, act_source, skip_presentation)


func start_agreement(handle: NEGOTIATION_HANDLE.Handle, skip_presentation := false) -> int:
	return agreement.start_agreement(handle, skip_presentation)


func find_bed_under() -> Node3D:
	return scene.find_bed_under()


## The debug status line: the scene gate owns the row and verdict assembly.
func debug_line(pose: String, act_source: String, bed_in: Node3D = null,
		distance: float = -1.0, dot: float = -1.0) -> String:
	session.refresh_identity()
	return scene.debug_line(pose, act_source, bed_in, distance, dot)


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
	var stool := session.stool() as STOOL.ACT
	return stool.gap_m() if stool != null else NAN


func stool_needed_count() -> int:
	var stool := session.stool() as STOOL.ACT
	return stool.needed_count() if stool != null else 0


func stool_case_count() -> int:
	var stool := session.stool() as STOOL.ACT
	return stool.case_count() if stool != null else 0


func stool_state_text() -> String:
	var stool := session.stool() as STOOL.ACT
	return stool.state_text() if stool != null else "stool unavailable"


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
