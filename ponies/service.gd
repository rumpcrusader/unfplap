extends "res://mods/unfplap/shared/service.gd"
## Service: ponies
## Scope: world
## Contract: docs/ponies.md
## The roster that owns one runtime per pony body.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const ACT_OWNER := preload("res://mods/unfplap/act_owner/service.gd")
const HANDLES := preload("res://mods/unfplap/world/handles.gd")

## The roster's own group, and the set of live runtimes it reads.
const GROUP := "unfplap_ponies"
const RUNTIME_GROUP := "unfplap_pony"
const RUNTIME_NAME := "UnfplapRuntime"

## (`Node pony`) -> Node, the entry's runtime factory. The runtime file stays the entry's preload.
var factory := Callable()
## The World services one attached body passes through; the composition root is the only caller.
var _world: HANDLES = null
## The settings change listener.
var _listener := func() -> void: _on_settings_changed()


func _ready() -> void:
	add_to_group(GROUP)
	CHANGE.on_changed(_listener)


func _exit_tree() -> void:
	CHANGE.off_changed(_listener)


## Takes the world record; the composition root is the only caller.
func wire(world: HANDLES) -> void:
	_world = world
	assert(world != null)


## A body entered the world; the player's own AnonPony is refused, an unclaimed body gets a runtime.
## The pending swap is offered first, so a suspended act is never displaced by a second owner.
func attach(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	if pony.name == "PlayerPony" or is_instance_valid(pony.get("rig")):
		return
	_prepare(pony)
	if _adopt_pending(pony):
		return
	if is_instance_valid(runtime_for(pony)):
		return
	var runtime: Node = factory.call(pony) if factory.is_valid() else null
	if not is_instance_valid(runtime):
		return
	if runtime.get_parent() != pony:
		pony.add_child(runtime)
	LOG.debug("runtime attached %s id=%s", [
		str(pony.name), str(pony.get_meta("relationship_id", ""))])
	pony.tree_exiting.connect(func() -> void: _on_body_exit(pony))


## One body left the tree: drop its anatomy and its estrus schedule.
func _on_body_exit(pony: Node) -> void:
	if _world != null and is_instance_valid(_world.estrus):
		_world.estrus.untrack(pony)
	if _world != null and is_instance_valid(_world.anatomy):
		_world.anatomy.withdraw(pony as Node3D)


## A mod that adds a node the first prepare needed, such as the changelings tail chain, calls this
## once it exists. Every prepare hook is idempotent, and this never creates a runtime.
func prepare_late(pony: Node) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(WORLD.world_root()):
		return
	_prepare(pony)


## The pony's one runtime, from the node it is parented under. Null when the body never got one.
func runtime_for(pony: Node) -> Node:
	if not is_instance_valid(pony):
		return null
	var runtime: Node = pony.get_node_or_null(RUNTIME_NAME)
	return runtime if is_instance_valid(runtime) else null


## The runtime's act session, or null.
func _session_of(runtime: Node) -> Variant:
	return runtime.get("act") if is_instance_valid(runtime) else null


## The per-pony handles the world services read. `Object` is the shared base of the `Node` the
## suites substitute and the `RefCounted` the runtime exposes; the properties stay typed.
func scene_of(runtime: Node) -> Object:
	if not is_instance_valid(runtime):
		return null
	return runtime.get("scene")


func start_of(runtime: Node) -> Object:
	if not is_instance_valid(runtime):
		return null
	return runtime.get("start")


func presentation_of(runtime: Node) -> Object:
	if not is_instance_valid(runtime):
		return null
	return runtime.get("presentation")


## The live bodies holding a runtime.
## Called on an edit or a closed wheel, never per frame, so allocation is fine here.
func live_ponies() -> Array[Node]:
	var out: Array[Node] = []
	for runtime: Node in _live_runtimes():
		var pony: Variant = runtime.get("pony")
		if not pony is Node or not is_instance_valid(pony):
			continue
		if not _departing(pony):
			out.append(pony)
	return out


## The runtimes that joined the runtime group and are still inside the tree.
func _live_runtimes() -> Array[Node]:
	var out: Array[Node] = []
	if not is_inside_tree():
		return out
	for runtime: Node in get_tree().get_nodes_in_group(RUNTIME_GROUP):
		if is_instance_valid(runtime) and runtime.is_inside_tree():
			out.append(runtime)
	return out


## True while the owner's pending swap is taking this body's runtime away; the roster skips it, the
## way the swap used to erase its entry at the suspend.
func _departing(pony: Node) -> bool:
	var owner: ACT_OWNER = _world.act_owner if _world != null else null
	var swap: ACT_OWNER.Swap = owner.pending_swap() if is_instance_valid(owner) else null
	return swap != null and swap.old_pony == pony


## Live act/afterglow context for the game's normal dialogue prompt (pony_prompt_notes).
func prompt_note(id: String) -> String:
	if id.is_empty():
		return ""
	for live: Node in _live_runtimes():
		var target: Variant = live.get("pony")
		if not target is Node or not is_instance_valid(target) or _departing(target):
			continue
		var runtime_id := str(live.live_id())
		if runtime_id.is_empty():
			runtime_id = PONY_ID.of(target)
		if runtime_id != id:
			continue
		var session: Variant = _session_of(live)
		if session == null:
			continue
		var note := str(session.prompt_note())
		var cycle := str(session.cycle_note())
		if not cycle.is_empty():
			note = cycle if note.is_empty() else note + " " + cycle
		return note
	return ""


## The base roster as the typed array the anatomy id helper takes.
func _base_order() -> Array[String]:
	var order: Array[String] = []
	order.assign(SETTINGS.CHARACTER_ORDER)
	return order


## Live adult mares outside the base roster, for the Characters selector.
## A despawned mare keeps her saved preset; an installed source still lists hers.
func live_character_ids() -> Array[String]:
	var service: ELIGIBILITY = _world.eligibility if _world != null else null
	var ids: Array[String] = []
	for pony: Node in live_ponies():
		if pony is Node3D and is_instance_valid(service) \
				and service.eligible(pony, ELIGIBILITY.Target.CHARACTER):
			ids.append(PONY_ID.of(pony))
	var out: Array[String] = PONY_ID.off_roster(ids, _base_order())
	for id: String in installed_character_ids():
		if not id in SETTINGS.CHARACTER_ORDER and not out.has(id):
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		return SETTINGS.character_name(a).naturalnocasecmp_to(
			SETTINGS.character_name(b)) < 0)
	return out


## Mares an active installed source lists while she is away.
## The source owns its installation gate; the base roster is unchanged.
func installed_character_ids() -> Array[String]:
	if _world == null or not is_instance_valid(_world.body_change):
		return []
	return _world.body_change.installed_character_ids()


## Adopt the body the suspended act's source reports when the spawn hook arrives too late for the
## pending swap. The runtime calls this from its watcher after the adoption grace.
func adopt_pending_body(pony: Node) -> bool:
	if not is_instance_valid(pony):
		return false
	_prepare(pony)
	return _adopt_pending(pony)


## Push a settings edit into every attached body's act.
## Each act keeps its own snapshot, so every one needs the new values.
func apply_live_settings() -> void:
	for runtime: Node in _live_runtimes():
		var session: Variant = _session_of(runtime)
		if session != null:
			session.apply_live_settings()


## A settings edit reaches every runtime, the suspended act included.
func _on_settings_changed() -> void:
	apply_live_settings()


## A world started: the roster's list is the live group, so nothing crosses worlds.
func on_world(_host: Node) -> void:
	pass


## The world closed: its live act ends through the one exit and the owner's frame is freed.
func on_world_closed() -> void:
	var owner: ACT_OWNER = _world.act_owner if _world != null else null
	if not is_instance_valid(owner):
		return
	var live: Node = owner.active()
	if not is_instance_valid(live):
		return
	var session: Variant = _session_of(live)
	if session != null:
		session.force_stop()
	owner.clear_active(live)
	owner.clear_body_swap(live)


## The entry is leaving: close the act, free every runtime and drop the record and the factory.
## A fresh entry then wires its own.
func shutdown() -> void:
	CHANGE.off_changed(_listener)
	on_world_closed()
	for runtime: Node in _live_runtimes():
		var session: Variant = _session_of(runtime)
		if session != null:
			session.force_stop()
		# Leave the live set at once; the node itself is freed at the end of the frame.
		runtime.remove_from_group(RUNTIME_GROUP)
		runtime.queue_free()
	factory = Callable()
	_world = null


## Fit and prepare a new body before it can take a runtime or an act.
## The provider's form is mirrored before anatomy attaches; every hook is idempotent.
func _prepare(pony: Node) -> void:
	if _world == null:
		return
	if is_instance_valid(_world.body_change):
		_world.body_change.notify_body_ready(pony)
	_present_anatomy(pony)
	if is_instance_valid(_world.estrus):
		_world.estrus.track(pony)
	if is_instance_valid(_world.stock_smack):
		_world.stock_smack.pony_ready(pony)
	if is_instance_valid(_world.eligibility):
		_world.eligibility.warm(pony)
	if is_instance_valid(_world.act_gate):
		_world.act_gate.warm(pony)


## The one anatomy assignment, with the provider's stored form; the API gates the identity.
func _present_anatomy(pony: Node) -> void:
	if _world == null or not is_instance_valid(pony) or not is_instance_valid(_world.anatomy):
		return
	var body := pony as Node3D
	if not is_instance_valid(body):
		return
	var form: Variant = _world.body_change.form_for(body) \
		if is_instance_valid(_world.body_change) else null
	_world.anatomy.present(body, form)


## Adopt the suspended act onto a newly spawned body. Runs after the adapter fitted it but before
## a runtime is created, so there is never a second act owner. Returns true when it adopted.
func _adopt_pending(pony: Node) -> bool:
	var owner: ACT_OWNER = _world.act_owner if _world != null else null
	var swap: ACT_OWNER.Swap = owner.pending_swap() if is_instance_valid(owner) else null
	if swap == null or not is_instance_valid(pony):
		return false
	var runtime: Variant = swap.runtime
	if not is_instance_valid(runtime):
		owner.clear_body_swap(runtime)
		return false
	var change: Variant = swap.change
	var source: Node = null
	if change is BODY_CHANGE and is_instance_valid((change as BODY_CHANGE).source):
		source = (change as BODY_CHANGE).source
	var claimed: bool = is_instance_valid(source) and source.has_method("claims_body") \
		and bool(source.claims_body(pony))
	if not claimed:
		var identity: Variant = pony.get("identity")
		var new_id := PONY_ID.from(str(pony.get_meta("relationship_id", "")), identity)
		if new_id != swap.id:
			return false
	var duplicate: Variant = runtime_for(pony)
	if is_instance_valid(duplicate) and duplicate != runtime:
		# A runtime created before adoption could only be a race; the suspended act is the owner.
		# Its anatomy controller belongs to the duplicate, so withdraw it before the adopt.
		if is_instance_valid(_world.anatomy):
			_world.anatomy.withdraw(pony as Node3D)
		var session: Variant = _session_of(duplicate)
		if session != null:
			session.force_stop()
		# The act's runtime keeps the one name under the body; the discarded one is only queued.
		duplicate.name = RUNTIME_NAME + "Discarded"
		duplicate.queue_free()
	_present_anatomy(pony)
	if runtime.get_parent() != pony:
		runtime.attach_to_body(pony)
	pony.tree_exiting.connect(func() -> void: _on_body_exit(pony))
	owner.clear_body_swap(runtime)
	runtime.adopt_body(pony)
	return true
