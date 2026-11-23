extends Node
## One per pony: **the host**. It exists, is parented under the body and reparented across a body
## swap, forwards both engine frames and releases what outlives an act. The `act/` modules own
## the state and the behaviour; this node holds no act rule or act value.
##
## See `docs/runtime.md`.

const ACT_BUILD := preload("res://mods/unfplap/act/build.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/service.gd")
const START_PORT := preload("res://mods/unfplap/shared/start_port.gd")
const PRESENTATION_PORT := preload("res://mods/unfplap/shared/presentation_port.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const HANDLES := preload("res://mods/unfplap/world/handles.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")

## One act's presentation began. The entry connects this to the world integrations, so the
## undress and the anatomy act handle fire from the runtime instead of the anatomy service.
signal act_started(pony: Node3D)

## The presented body. A new assignment rebinds the pose session and host through the bundle;
## nothing rebinds per frame.
var pony: Node:
	get:
		return _pony_node
	set(value):
		_pony_node = value
		_bundle.bind_pony(value)

var _pony_node: Node = null
## The World services this pony's act reads; a bare `new()` gets an empty record.
var _world: HANDLES = null
## The per-pony composition root's product: every system, host, module and typed collaborator.
var _bundle: ACT_BUILD.Bundle = null

## The act's one session handle: the state, the timers, the ledgers, the view and the input
## protocol. The entry, the input service and the debug actions read it.
var act: ACT_SESSION:
	get:
		return _bundle.act if _bundle != null else null

## The per-pony scene gate: the offer-facing verdicts and readiness reads.
var scene: SCENE_GATE:
	get:
		return _bundle.gate if _bundle != null else null

## The per-pony start handle: the hotkey and Agreement starts and the footstool hint.
var start: START_PORT:
	get:
		return _bundle.agreement if _bundle != null else null

## The per-pony presentation handle: the stool reads, the scene hold and the standing invitation.
var presentation: PRESENTATION_PORT:
	get:
		return _bundle.act if _bundle != null else null

## `reparent()` runs `_exit_tree()`. The handover moves the live runtime between bodies, so that
## signal must not run the world-close release it exists for.
var _swapping_parent := false


## The World record is built here so the act modules read it unguarded; the parameter body stays
## unbound until the setter hands it to the bundle.
func _init(pony: Node = null, world: HANDLES = null) -> void:
	_world = world if world != null else HANDLES.new()
	_bundle = ACT_BUILD.build(null, self, _world)
	_pony_node = pony if is_instance_valid(pony) else null


func _ready() -> void:
	set_process(true)
	set_physics_process(true)
	# Run after locomotion/navigator/attention so the body facing lock and head glance win.
	process_physics_priority = 100
	# Identity is the key for per-mare preferences, poses, prompts and memory. It can arrive after
	# the pony enters the tree, so read it now and once more after the first frame.
	act.refresh_identity()
	_bundle.bind_pony(pony)
	act.refresh_identity.call_deferred()
	_bundle.face.bind(pony, self)
	# integration: anatomy is persistent outside acts. Retry once after the first frame for a mod
	# that assigns the pony's identity after she enters the tree.
	act.refresh_anatomy()
	act.refresh_anatomy.call_deferred()


func _process(delta: float) -> void:
	act.render(delta)


func _physics_process(delta: float) -> void:
	act.tick(delta)


## The stable pony id the act is on, read from the live body. `ponies` matches a prompt note to its
## one runtime through this; the id itself stays the act's.
func live_id() -> String:
	act.refresh_identity()
	return act.pony_id


## Move the live runtime under another node without running its world-close `_exit_tree()`. The
## handover moves it off the old body and then onto the new one.
func attach_to_body(parent: Node) -> void:
	if not is_instance_valid(parent) or get_parent() == parent:
		return
	_swapping_parent = true
	reparent(parent)
	_swapping_parent = false


## Called when the source's new body spawns, while the runtime is already under the entry: it moves
## under the new body, binds pose, face and anatomy and waits for the resume; a non-adult ends it.
func adopt_body(new_pony: Node) -> void:
	if not act.suspended() or not is_instance_valid(new_pony):
		return
	_bundle.handover.adopt(new_pony)
	pony = new_pony
	act.bind_adopted_body(new_pony)
	if not act.swap.new_body_is_adult():
		act.swap.end_non_adult(new_pony)
		return
	WORLD.refresh_body_lod(new_pony)


## World close or mod switch-off: release what outlives an act. The kiss foreleg overrides are
## global AffectionPose settings, the anatomy nodes are persistent and none may be left behind.
func _exit_tree() -> void:
	if _swapping_parent:
		return
	PONIES.clear_body_swap(self)
	_bundle.kiss.restore_forelegs()
	act.release_stool()
	_bundle.host.end_tail_tuck()
	_bundle.afterglow.clear_post_act(pony if is_instance_valid(pony) else null)
	# integration: never leave the anatomy act handle or the per-pony controller behind.
	act.release_anatomy()
	_bundle.face.shutdown()
