extends RefCounted
## One body change: the source, origin, presented bodies, target and prepared form, lifecycle state
## and start time. A read model only; the body-change service owns the transition.
##
## The source is a typed `Node`, so this file cannot preload the provider base back.

const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")

enum State { REQUESTED, PREPARING, ADOPTED, SETTLED, FAILED }
enum Origin { PLAYER, AI, PROVIDER }

var source: Node = null
var origin: Origin = Origin.PROVIDER
var previous_body: Node3D = null
var next_body: Node3D = null
var target_form_id: String = ""
var form: BODY_FORM.BodyForm = null
var state: State = State.REQUESTED
var started_s: float = 0.0
