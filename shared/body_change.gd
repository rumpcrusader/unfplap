extends RefCounted
## One body change: the source that started it, its origin, the old and new presented bodies, the
## target form and the prepared form, the lifecycle state and the start time. A read model only;
## the body-change service owns the transition.
##
## The source is a typed `Node`: the provider base (`body_change/source.gd`) preloads this file, so
## this shared read model cannot preload the base back without a cycle and a shared -> provider
## import.

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
