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
const HANDS := preload("res://mods/unfplap/hands/service.gd")
const INTEGRATIONS := preload("res://mods/unfplap/integrations/service.gd")
const STANDING_CAMERA := preload("res://mods/unfplap/camera/standing_camera.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")


var pose: POSE_SESSION = null
var camera: ACT_CAMERA = null
var readiness: READINESS = null
## The lazy per-act audio node; the view and idle schedule do not read it.
var audio: Node = null
var afterglow: AFTERGLOW = null
var face: FACE = null
var reactions: REACTIONS = null
var dialogue: ACT_DIALOGUE = null
## The anatomy act bridge, built by the anatomy facade, and the typed host it binds.
var anatomy: RefCounted = null
var anatomy_host: RefCounted = null
var handover: BODY_CHANGE_ACT = null
var gate: SCENE_GATE = null
## The act's scene ownership: navigator, player lock and face turn.
var hold: SCENE_HOLD = null
## The per-act footstool handle, bound by the start ledger and released by the exit.
var stool: RefCounted = null
var facts: ACT_FACTS = null
var kiss: KISS = null
var summary: SUMMARY = null
var presentation: STANDING_PRESENTATION = null
var standing_anon: STANDING_ANON = null
var wings: WING = null
var hands: HANDS = null
var integrations: INTEGRATIONS = null
var standing_camera: STANDING_CAMERA = null
var rest: REST = null
