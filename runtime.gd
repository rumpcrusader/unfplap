extends Node
## One per pony. **The host**: it exists, it is parented under the body and reparented across a
## body swap, it forwards the two engine frames to the act session, and it releases the per-pony
## services when the world closes. The `act/` modules own the state, the schedule, the ledgers, the
## view and the act's behaviour; this node owns no act rule and holds no act value.
##
## The public surface is `act`, `gate`, `pony`, `live_id()`, `attach_to_body()`, `adopt_body()` and
## the engine callbacks. Everything the act modules and the services need is constructed by
## `act/build.gd` and read from there.
##
## See `docs/runtime.md`.

const ACT_BUILD := preload("res://mods/unfplap/act/build.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_GATE := preload("res://mods/unfplap/act/gate.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")

## The pony this runtime presents. Assigning a body rebinds the pose session and the act host
## through the bundle; nothing else is rebound per frame.
var pony: Node:
	get:
		return _pony_node
	set(value):
		_pony_node = value
		_bundle.bind_pony(value)

var _pony_node: Node = null
## The per-pony composition root's product: every system, host, module and typed collaborator.
var _bundle: ACT_BUILD.Bundle = null

## The act's one session handle: the state, the timers, the ledgers, the view and the input
## protocol. The entry, the input service and the debug actions read it.
var act: ACT_SESSION:
	get:
		return _bundle.act if _bundle != null else null

## The offer-facing gate handle: scene verdicts, the Agreement start, the hotkey readiness and the
## stool/rump/presentation reads. `offer`, `negotiation` and `initiation` use this handle.
var gate: ACT_GATE:
	get:
		return _bundle.act_gate if _bundle != null else null

## `reparent()` runs `_exit_tree()`. The handover moves the live runtime between bodies, so that
## signal must not run the world-close release it exists for.
var _swapping_parent := false


func _init() -> void:
	_bundle = ACT_BUILD.build(null, self)


func _ready() -> void:
	set_process(true)
	set_physics_process(true)
	# Run after locomotion/navigator/attention so the body facing lock and head glance win.
	process_physics_priority = 100
	# Identity is the key for per-mare preferences, poses, prompts and memory. It can arrive after
	# the pony enters the tree, so read it now and once more after the first frame.
	act.refresh_identity()
	_bundle.bind_pony(pony)
	act.call_deferred("refresh_identity")
	act.prepare_idle_perf()
	_bundle.face.bind(pony, self)
	# integration: anatomy is persistent outside acts. Retry once after the first frame for a mod
	# that assigns the pony's identity after she enters the tree.
	act.refresh_anatomy()
	act.call_deferred("refresh_anatomy")


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


## `ponies` calls this when the source's new body spawns. The runtime is already under the entry;
## it moves under the new body, binds its pose, face and anatomy, and waits for the handover's
## resume. A body that is not an adult mare ends the act through the one exit.
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
## global AffectionPose settings, the anatomy nodes are persistent, and the face timer is a child;
## none of them may be left behind.
func _exit_tree() -> void:
	if _swapping_parent:
		return
	PONIES.clear_body_swap(self)
	_bundle.kiss.restore_forelegs()
	act.release_stool()
	_bundle.host.end_tail_tuck()
	_bundle.afterglow.clear_post_act(pony if is_instance_valid(pony) else null)
	# integration: never leave the anatomy nodes or the per-act controller behind.
	_bundle.anatomy_bridge.bind(_bundle.anatomy_host)
	_bundle.anatomy_bridge.end()
	_bundle.anatomy_bridge.detach()
	_bundle.face.shutdown()
