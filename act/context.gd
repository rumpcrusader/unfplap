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
const KISS := preload("res://mods/unfplap/kiss/service.gd")
const SUMMARY := preload("res://mods/unfplap/summary/service.gd")
const STANDING_PRESENTATION := preload("res://mods/unfplap/poses/standing_presentation.gd")
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
## The anatomy act bridge, built by the anatomy facade.
var anatomy: RefCounted = null
var handover: BODY_CHANGE_ACT = null
var gate: SCENE_GATE = null
## The per-act footstool handle, built by the stool service.
var stool: RefCounted = null
var facts: ACT_FACTS = null
var kiss: KISS = null
var summary: SUMMARY = null
var presentation: STANDING_PRESENTATION = null
