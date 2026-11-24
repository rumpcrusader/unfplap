extends RefCounted
## The pose read model: one scene-free mutable object per pose session, filled by
## `poses/api.gd` and carried by `shared/act_facts.gd`. Presentation modules read this; it
## mirrors the session, it is not a second authority.

## The pose state values. A3 owns the transitions; A1 fills a live session with `STEADY` and
## resets to `IDLE` when it is released.
const IDLE := 0
const ENTERING := 1
const STEADY := 2
const TRANSITIONING := 3
const EXITING := 4

# Identity.
var id := ""
var family := ""
var frame := ""
var settings_group := ""
var pose_state := IDLE

# The live config. `pose_config` is the session's one dictionary; `from_config`/`to_config` point
# at it too until A3 splits the two sides of a transition.
var pose_config: Dictionary = {}
var from_config: Dictionary = {}
var to_config: Dictionary = {}
var weight := 0.0
var from_id := ""
var to_id := ""
var edge_id := ""
var edge_t := 0.0

# The spec profiles, as references to the registry's dictionaries.
var camera: Dictionary = {}
var hands: Dictionary = {}
var controls: Dictionary = {}
var audio: Dictionary = {}
var afterglow: Dictionary = {}
var presentation: Dictionary = {}
var contact: Dictionary = {}
var anon: Dictionary = {}
var scene: Dictionary = {}
var modifiers: Dictionary = {}

# Support and ownership.
var forms: Array[String] = []
var views: Array[String] = []
var public_pose := false
var offerable := false

# The only values that change per tick: the contact kind, its target and the facing basis.
var contact_kind := "none"
var contact_target := Vector3.INF
var facing := Basis.IDENTITY
var facing_amount := 0.0

## The live space the authored pose is rendered in, or null outside a pose.
var bed_frame: Variant = null
## The authored asset the live rig renders, or null when the pose has none.
var authored: Variant = null

## The empty values `clear()` points at, allocated once so a release never allocates another.
var _empty_config: Dictionary = {}
var _empty_profile: Dictionary = {}


## Fill from one `poses/pose_spec.gd` wrapper and the session's live config. The profiles and the
## config are references; nothing is copied and the view aliases the session's live object.
func fill(spec: Variant, config: Dictionary) -> void:
	id = str(spec.id)
	family = str(spec.family)
	frame = str(spec.frame)
	settings_group = str(spec.settings_group)
	camera = spec.camera
	hands = spec.hands
	controls = spec.controls
	audio = spec.audio
	afterglow = spec.afterglow
	presentation = spec.presentation
	contact = spec.contact
	anon = spec.anon
	scene = spec.scene
	modifiers = spec.modifiers
	forms.assign(spec.forms)
	views.assign(spec.views)
	public_pose = bool(spec.public_pose)
	offerable = bool(spec.offerable)
	pose_config = config
	from_config = config
	to_config = config
	weight = 1.0
	from_id = id
	to_id = id
	edge_id = ""
	edge_t = 0.0
	pose_state = STEADY


## Reset every field without allocating a new dictionary and without touching the live config's
## contents. The session calls this after it has cleared the live object.
func clear() -> void:
	id = ""
	family = ""
	frame = ""
	settings_group = ""
	pose_state = IDLE
	pose_config = _empty_config
	from_config = _empty_config
	to_config = _empty_config
	weight = 0.0
	from_id = ""
	to_id = ""
	edge_id = ""
	edge_t = 0.0
	camera = _empty_profile
	hands = _empty_profile
	controls = _empty_profile
	audio = _empty_profile
	afterglow = _empty_profile
	presentation = _empty_profile
	contact = _empty_profile
	anon = _empty_profile
	scene = _empty_profile
	modifiers = _empty_profile
	forms.clear()
	views.clear()
	public_pose = false
	offerable = false
	contact_kind = "none"
	contact_target = Vector3.INF
	facing = Basis.IDENTITY
	facing_amount = 0.0
	bed_frame = null
	authored = null