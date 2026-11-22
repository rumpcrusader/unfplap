extends RefCounted
## The typed collaborators the runtime's own modules read. One per pony, built once by the runtime;
## the runtime points the fields at the live systems. No callables and no scene node. The act's own
## values live on `act/session.gd`, not here.
##
## See `docs/runtime.md`.

const POSE_SESSION := preload("res://mods/unfplap/poses/service.gd")
const ACT_CAMERA := preload("res://mods/unfplap/camera/service.gd")
const READINESS := preload("res://mods/unfplap/readiness/service.gd")
const AFTERGLOW := preload("res://mods/unfplap/afterglow/service.gd")
const FACE := preload("res://mods/unfplap/face/service.gd")
const REACTIONS := preload("res://mods/unfplap/reactions/service.gd")
const ACT_DIALOGUE := preload("res://mods/unfplap/dialogue/service.gd")
const BODY_CHANGE_ACT := preload("res://mods/unfplap/body_change/act.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/service.gd")
const SCENE_HOLD := preload("res://mods/unfplap/scene_hold/service.gd")
const KISS := preload("res://mods/unfplap/kiss/service.gd")
const SUMMARY := preload("res://mods/unfplap/summary/service.gd")
const REST := preload("res://mods/unfplap/rest/service.gd")
const STANDING_PRESENTATION := preload("res://mods/unfplap/poses/standing_presentation.gd")
const STANDING_ANON := preload("res://mods/unfplap/poses/standing_anon.gd")
const WING := preload("res://mods/unfplap/poses/wing_control.gd")
const HANDS := preload("res://mods/unfplap/hands/api.gd")
const INTEGRATIONS := preload("res://mods/unfplap/integrations/service.gd")
const CAMERA_VIEW := preload("res://mods/unfplap/camera/view.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const ACT_FRAME := preload("res://mods/unfplap/act/frame.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")
const STOOL_ACT := preload("res://mods/unfplap/stool/act.gd")


var pose: POSE_SESSION = null
var camera: ACT_CAMERA = null
var readiness: READINESS = null
## The lazy per-act audio node; the view and idle schedule do not read it.
var audio: Variant = null
var afterglow: AFTERGLOW = null
var face: FACE = null
var reactions: REACTIONS = null
var dialogue: ACT_DIALOGUE = null
## The anatomy act handle and the caller-owned read models it stages with. The handle is typed by
## convention: the API's inner class, and a suite may substitute a fake.
var anatomy: RefCounted = null
var anon: RefCounted = null
var pose_view: RefCounted = null
var stage: RefCounted = null
var handover: BODY_CHANGE_ACT = null
var gate: SCENE_GATE = null
## The act's scene ownership: navigator, player lock and face turn.
var hold: SCENE_HOLD = null
## The per-act footstool handle, bound by the start ledger and released by the exit.
var stool: STOOL_ACT = null
## The world-scope stool facade that creates the per-act handle above.
var stool_service: STOOL = null
## The world HUD and memory the act modules read; null outside a runtime built with them.
var hud: Node = null
var memory: Node = null
## The act's consent response: the tolerance warning, its line and the stop presentation.
var consent: RefCounted = null
## The act's stroke presentation and its one post-move path.
var impact: RefCounted = null
## The act's player frame: the start placement, the stance and the one restore.
var frame: ACT_FRAME = null
var facts: ACT_FACTS = null
var kiss: KISS = null
var summary: SUMMARY = null
var presentation: STANDING_PRESENTATION = null
var standing_anon: STANDING_ANON = null
var wings: WING = null
var hands: HANDS = null
var integrations: INTEGRATIONS = null
## The one live act view: the standing offsets, the glance and the missionary eye.
var view: CAMERA_VIEW = null
var rest: REST = null
