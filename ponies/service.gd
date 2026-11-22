extends RefCounted
## Service: ponies
## Contract: docs/ponies.md
## Scope: world
## Import: ponies/service.gd only
## The registry that owns one runtime per pony body.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const ACT_GATE := preload("res://mods/unfplap/act_gate/service.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const RUMP_CONE := preload("res://mods/unfplap/shared/rump_cone.gd")

## (`Node pony`) -> Node, the entry's runtime factory. The runtime file stays the entry's preload.
static var factory := Callable()
## The services one attached body passes through, bound once by the entry.
## Eligibility is rebuilt each world enter, so the entry rebinds that one.
static var anatomy: ANATOMY = null
static var estrus: Node = null
static var body_change: Node = null
static var stock_smack: Node = null
static var offer: Node = null
static var eligibility: ELIGIBILITY = null
## The dynamic act gate, rebuilt on every world enter like eligibility.
static var act_gate: ACT_GATE = null
## The cross-mod API facade, bound once by the entry. An integration registers its mare here.
static var api: Node = null


## The two persistent services the anatomy host reads. A static read is the script's, so a caller
## can bind it without naming the runtime node.
static func anatomy_service() -> Node:
	return anatomy


static func estrus_service() -> Node:
	return estrus


static func eligibility_service() -> ELIGIBILITY:
	return eligibility

## pony -> its one runtime.
static var _runtimes: Dictionary = {}
## The one suspended act awaiting the body its source is building.
## The runtime waits under the entry while the old body goes; the newcomer adopts it here.
static var _swap: Dictionary = {}
## The runtime of the live act, or null.
static var _active: Node = null
## The last serial this process issued, kept as a floor under the stored one.
static var _serial_issued := 0
## The settings change listener. A static facade has no instance, so the callable is a closure
## over this file's own pass.
static var _listener := func() -> void: _on_settings_changed()


## A body entered the world; the player's own AnonPony is refused, an unclaimed body gets a runtime.
## The pending swap is offered first, so a suspended act is never displaced by a second owner.
static func attach(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	if pony.name == "PlayerPony" or is_instance_valid(pony.get("rig")):
		return
	_prepare(pony)
	if _adopt_pending(pony):
		return
	if _runtimes.has(pony):
		return
	var runtime: Node = factory.call(pony) if factory.is_valid() else null
	if not is_instance_valid(runtime):
		return
	if runtime.get_parent() != pony:
		pony.add_child(runtime)
	_runtimes[pony] = runtime
	LOG.debug("runtime attached %s id=%s", [
		str(pony.name), str(pony.get_meta("relationship_id", ""))])
	pony.tree_exiting.connect(func() -> void: _on_body_exit(pony))


## One body left the tree: drop its runtime, its anatomy and its estrus schedule.
static func _on_body_exit(pony: Node) -> void:
	_runtimes.erase(pony)
	if is_instance_valid(estrus):
		estrus.untrack(pony)
	if is_instance_valid(anatomy):
		anatomy.withdraw(pony as Node3D)


## A mod that adds a node the first prepare needed, such as the changelings tail chain, calls this
## once it exists. Every prepare hook is idempotent, and this never creates a runtime.
static func prepare_late(pony: Node) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(WORLD.game):
		return
	_prepare(pony)


## The pony's one runtime, from the registry or from the node it was parented under. Null when the
## body never got one.
static func runtime_for(pony: Node) -> Node:
	if not is_instance_valid(pony):
		return null
	var runtime: Variant = _runtimes.get(pony)
	if is_instance_valid(runtime):
		return runtime
	var child: Node = pony.get_node_or_null("UnfplapRuntime")
	return child if is_instance_valid(child) else null


## An act took the frame: the idle offer is cleared and the smack layer starts.
static func set_active(runtime: Node) -> void:
	_active = runtime
	if is_instance_valid(offer):
		offer.clear_current()
	if is_instance_valid(stock_smack):
		stock_smack.act_start(runtime.get("pony"))


## The act ended, or a world close: the frame is free again.
static func clear_active(runtime: Node) -> void:
	if _active == runtime:
		_active = null
		if is_instance_valid(stock_smack):
			stock_smack.act_end(runtime.get("pony"))


## The live act's runtime, or null.
static func active() -> Node:
	return _active if is_instance_valid(_active) else null


## The per-pony handles the world services read. `Object` is the shared base of the `Node` the
## suites substitute and the `RefCounted` the runtime exposes; the properties stay typed.
static func scene_of(runtime: Node) -> Object:
	if not is_instance_valid(runtime):
		return null
	return runtime.get("scene")


static func start_of(runtime: Node) -> Object:
	if not is_instance_valid(runtime):
		return null
	return runtime.get("start")


static func presentation_of(runtime: Node) -> Object:
	if not is_instance_valid(runtime):
		return null
	return runtime.get("presentation")


## An act owns the frame; every starter gates on it.
static func act_running() -> bool:
	return is_instance_valid(_active)


## The act-target capability. The eligibility service owns the rule; a scan checks it before
## building a runtime gate for a stallion or a young pony.
static func act_target(pony: Node) -> bool:
	return is_instance_valid(pony) and is_instance_valid(eligibility) \
		and eligibility.eligible(pony, ELIGIBILITY.Target.ACT)


## The Base clearance relationship row: live relationship, romance and the Promiscuity floor.
static func relationship_ok(pony: Node) -> bool:
	return is_instance_valid(pony) and is_instance_valid(act_gate) \
		and act_gate.relationship_ok(pony)


## The nearest act target whose rear fan holds the eye, or null.
## One pass over the game's own mare array: no copy, and the target read runs in distance order.
static func cone_target(eye: Vector3) -> Node3D:
	if not eye.is_finite() or not is_instance_valid(WORLD.game):
		return null
	var mares: Variant = WORLD.game.get("mares")
	if not mares is Array:
		return null
	var found: Array = []
	for node: Variant in mares as Array:
		if not node is Node3D or not is_instance_valid(node):
			continue
		var actor := node as Node3D
		if not actor.has_method("posture_status"):
			continue
		var rump := RUMP_CONE.approx_point(actor)
		var delta := Vector3(eye.x - rump.x, 0.0, eye.z - rump.z)
		var distance := delta.length_squared()
		if distance > RUMP_CONE.REACH_SQ:
			continue
		if str(actor.posture_status().get("requested", "")) != "stand":
			continue
		if not RUMP_CONE.contains(actor.global_basis.z, rump, eye):
			continue
		found.append({"pony": actor, "distance": distance})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"]))
	for candidate: Dictionary in found:
		var actor: Node3D = candidate["pony"]
		if act_target(actor):
			return actor
	return null


## The live bodies holding a runtime.
## Called on an edit or a closed wheel, never per frame, so allocation is fine here.
static func live_ponies() -> Array[Node]:
	var out: Array[Node] = []
	for pony: Variant in _runtimes.keys():
		if is_instance_valid(pony):
			out.append(pony)
	return out


## Live act/afterglow context for the game's normal dialogue prompt (pony_prompt_notes).
static func prompt_note(id: String) -> String:
	if id.is_empty():
		return ""
	for live: Variant in _runtimes.values():
		if not is_instance_valid(live):
			continue
		var runtime_id := str(live.live_id())
		if runtime_id.is_empty():
			var target: Variant = live.get("pony")
			if is_instance_valid(target):
				runtime_id = PONY_ID.of(target)
		if runtime_id != id:
			continue
		var session: Variant = live.get("act")
		if session == null:
			continue
		var note := str(session.prompt_note())
		var cycle := str(session.cycle_note())
		if not cycle.is_empty():
			note = cycle if note.is_empty() else note + " " + cycle
		return note
	return ""


## The base roster as the typed array the anatomy id helper takes.
static func _base_order() -> Array[String]:
	var order: Array[String] = []
	order.assign(SETTINGS.CHARACTER_ORDER)
	return order


## Live adult mares outside the base roster, for the Characters selector.
## A despawned mare keeps her saved preset; an installed source still lists hers.
static func live_character_ids() -> Array[String]:
	var ids: Array[String] = []
	for pony: Variant in _runtimes.keys():
		if pony is Node3D and is_instance_valid(pony) and is_instance_valid(eligibility) \
				and eligibility.eligible(pony, ELIGIBILITY.Target.CHARACTER):
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
static func installed_character_ids() -> Array[String]:
	if not is_instance_valid(body_change):
		return []
	return body_change.installed_character_ids()


## The next serial for a new act, stored under the `unfplap.serial` key.
## The process's last value outranks a stale store, so no serial repeats.
static func allocate_serial() -> int:
	var value: int = _serial_issued + 1
	var mods := _mods()
	if mods != null:
		var section := GAME.mods_state(mods, "unfplap")
		value = maxi(int(section.rows.get("serial", 0)), _serial_issued) + 1
		section.rows["serial"] = value
		GAME.mods_save(mods)
	_serial_issued = value
	return value


## Record the act's one pending body swap. The runtime keeps the act; this record only lets the new
## body's spawn find it before a second runtime is created.
static func begin_body_swap(runtime: Node, old_pony: Node, id: String, change: BODY_CHANGE) -> void:
	if not is_instance_valid(runtime) or change == null:
		return
	_swap = {
		"runtime": runtime,
		"old_pony": old_pony,
		"id": id,
		"change": change,
	}
	if is_instance_valid(old_pony) and _runtimes.get(old_pony) == runtime:
		_runtimes.erase(old_pony)


## The swap finished, failed or the act ended. Idempotent and scoped to the runtime.
static func clear_body_swap(runtime: Node) -> void:
	if _swap.get("runtime") == runtime:
		_swap = {}


static func body_swap_pending() -> bool:
	return not _swap.is_empty()


## Adopt the body the suspended act's source reports when the spawn hook arrives too late for the
## pending swap. The runtime calls this from its watcher after the adoption grace.
static func adopt_pending_body(pony: Node) -> bool:
	if not is_instance_valid(pony):
		return false
	_prepare(pony)
	return _adopt_pending(pony)


## Push a settings edit into every attached body's act.
## Each act keeps its own snapshot, so every one needs the new values.
static func apply_live_settings() -> void:
	for runtime: Variant in _runtimes.values():
		if not is_instance_valid(runtime):
			continue
		var session: Variant = runtime.get("act")
		if session != null:
			session.apply_live_settings()


## Join the settings change notification. It is one static facade, so the entry calls this once
## while it binds the registry and `shutdown()` leaves.
static func bind_settings() -> void:
	CHANGE.on_changed(_listener)


## Bind the services one attached body passes through.
## The entry binds at the end of its build, so a body spawned mid-build still reads a complete set.
static func bind(anatomy_service: ANATOMY, body_change_service: Node, offer_service: Node,
		stock_smack_service: Node, eligibility_service: ELIGIBILITY, gate_service: ACT_GATE,
		estrus_service: Node, api_service: Node) -> void:
	anatomy = anatomy_service
	estrus = estrus_service
	body_change = body_change_service
	offer = offer_service
	stock_smack = stock_smack_service
	eligibility = eligibility_service
	act_gate = gate_service
	api = api_service


## A settings edit: also the swapped act the registry no longer holds.
static func _on_settings_changed() -> void:
	apply_live_settings()
	if is_instance_valid(_active) and not _runtimes.has(_active.get("pony")):
		var session: Variant = _active.get("act")
		if session != null:
			session.apply_live_settings()


## A world started: the old world's pending swap is dropped.
static func reset() -> void:
	_swap = {}


## The world closed: its act ends through the one exit and the pending swap goes with it. The
## runtimes leave with their bodies.
static func close_world() -> void:
	if is_instance_valid(_active):
		var session: Variant = _active.get("act")
		if session != null:
			session.force_stop()
	_active = null
	_swap = {}


## The entry is leaving: close the act, free every runtime and drop the bound handles.
## A fresh entry then binds its own.
static func shutdown() -> void:
	CHANGE.off_changed(_listener)
	close_world()
	for runtime: Variant in _runtimes.values():
		if not is_instance_valid(runtime):
			continue
		var session: Variant = runtime.get("act")
		if session != null:
			session.force_stop()
		(runtime as Node).queue_free()
	_runtimes.clear()
	factory = Callable()
	anatomy = null
	estrus = null
	body_change = null
	stock_smack = null
	offer = null
	eligibility = null
	act_gate = null
	api = null


## Fit and prepare a new body before it can take a runtime or an act.
## The provider's form is mirrored before anatomy attaches; every hook is idempotent.
static func _prepare(pony: Node) -> void:
	if is_instance_valid(body_change):
		body_change.notify_body_ready(pony)
	_present_anatomy(pony)
	if is_instance_valid(estrus):
		estrus.track(pony)
	if is_instance_valid(stock_smack):
		stock_smack.pony_ready(pony)
	if is_instance_valid(eligibility):
		eligibility.warm(pony)
	if is_instance_valid(act_gate):
		act_gate.warm(pony)


## The one anatomy assignment, with the provider's stored form; the API gates the identity.
static func _present_anatomy(pony: Node) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(anatomy):
		return
	var body := pony as Node3D
	if not is_instance_valid(body):
		return
	var form: Variant = body_change.form_for(body) if is_instance_valid(body_change) else null
	anatomy.present(body, form)


## Adopt the suspended act onto a newly spawned body. Runs after the adapter fitted it but before
## a runtime is created, so there is never a second act owner. Returns true when it adopted.
static func _adopt_pending(pony: Node) -> bool:
	if _swap.is_empty() or not is_instance_valid(pony):
		return false
	var runtime: Variant = _swap.get("runtime")
	if not is_instance_valid(runtime):
		_swap = {}
		return false
	var change: Variant = _swap.get("change")
	var source: Node = null
	if change is BODY_CHANGE and is_instance_valid((change as BODY_CHANGE).source):
		source = (change as BODY_CHANGE).source
	var claimed: bool = is_instance_valid(source) and source.has_method("claims_body") \
		and bool(source.claims_body(pony))
	if not claimed:
		var identity: Variant = pony.get("identity")
		var new_id := PONY_ID.from(str(pony.get_meta("relationship_id", "")), identity)
		if new_id != str(_swap.get("id", "")):
			return false
	var duplicate: Variant = _runtimes.get(pony)
	if is_instance_valid(duplicate) and duplicate != runtime:
		# A runtime created before adoption could only be a race; the suspended act is the owner.
		# Its anatomy controller belongs to the duplicate, so withdraw it before the adopt.
		if is_instance_valid(anatomy):
			anatomy.withdraw(pony as Node3D)
		var session: Variant = duplicate.get("act")
		if session != null:
			session.force_stop()
		duplicate.queue_free()
	var old_pony: Variant = _swap.get("old_pony")
	if is_instance_valid(old_pony) and _runtimes.get(old_pony) == runtime:
		_runtimes.erase(old_pony)
	_runtimes[pony] = runtime
	_present_anatomy(pony)
	if runtime.get_parent() != pony:
		runtime.attach_to_body(pony)
	pony.tree_exiting.connect(func() -> void: _on_body_exit(pony))
	_swap = {}
	runtime.adopt_body(pony)
	return true


## The game's mod registry. A static facade cannot name the autoload: a `--script` suite preloads
## this file before the autoloads exist.
static func _mods() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("Mods")


## The stable act identity of one presented body: the relationship id when it is ready, the
## pony-identity fallback otherwise. The act reads id and display name through this one record.
class Identity extends RefCounted:
	var id := ""
	var body: Node = null


## Read one body's stable act identity. The relationship meta is preferred whenever it appears;
## a mod may assign it after the pony enters the tree.
static func identity_of(body: Node) -> Identity:
	var out := Identity.new()
	out.body = body
	if not is_instance_valid(body):
		return out
	var meta_id := str(body.get_meta("relationship_id", "")) if body.has_meta("relationship_id") else ""
	out.id = meta_id if not meta_id.is_empty() else PONY_ID.from("", body.get("identity"))
	return out


## The presented body's name for the act caption and dialogue.
## A borrowed shape still belongs to the same relationship, preferences and history.
static func display_name_for(form: BODY_FORM.BodyForm, body: Node, id: String) -> String:
	var presented := str(form.form_name).strip_edges() if form != null else ""
	if presented.is_empty() and is_instance_valid(body):
		var identity: Variant = body.get("identity")
		var display: Variant = identity.get("display_name") if identity != null else null
		presented = str(display).strip_edges() if display != null else ""
	return presented if not presented.is_empty() else id
