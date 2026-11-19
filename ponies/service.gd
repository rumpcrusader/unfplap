extends RefCounted
## Service: ponies
## Contract: docs/ponies.md
## Scope: world
## Import: ponies/service.gd only
##
##   const PONIES := preload("res://mods/unfplap/ponies/service.gd")
##   PONIES.attach(pony)
##   if PONIES.act_running():
##       return
##
## The one registry of per-pony runtimes: the attach and prepare hooks every new body passes
## through, the typed pending body swap and its adoption, the live act pointer, the serial
## allocator and the prompt note the game reads. Static like `world/service.gd`: a consumer
## preloads it and the entry binds the pieces it built.
##
## The runtime is built by the entry's factory, so this service never imports `runtime.gd`; every
## call into a runtime is dynamic on its `Node`.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")

## (`Node pony`) -> Node, the entry's runtime factory. The runtime file stays the entry's preload.
static var factory := Callable()
## The services one attached body passes through, bound once by the entry. `eligibility` is rebuilt
## on every world enter, so the entry rebinds that one.
static var anatomy: Node = null
static var body_change: Node = null
static var stock_smack: Node = null
static var offer: Node = null
static var eligibility: ELIGIBILITY = null
## The cross-mod API facade, bound once by the entry. An integration registers its mare here.
static var api: Node = null

## pony -> its one runtime.
static var _runtimes: Dictionary = {}
## One suspended act waiting for the body its source is building. The runtime reparents itself to
## the entry before the old body goes; the new body's spawn adopts it here.
static var _swap: Dictionary = {}
## The runtime of the live act, or null.
static var _active: Node = null
## The last serial this process issued, kept as a floor under the stored one.
static var _serial_issued := 0
## The settings change listener. A static facade has no instance, so the callable is a closure
## over this file's own pass.
static var _listener := func() -> void: _on_settings_changed()


## A body entered the world. The player's own AnonPony is a pony_locomotion too and never gets an
## intimacy runtime; a body the pending swap claims is adopted instead, so a suspended act is never
## displaced by a second act owner.
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
	if is_instance_valid(anatomy):
		anatomy.call("bind", pony, runtime)
	if runtime.get_parent() != pony:
		pony.add_child(runtime)
	_runtimes[pony] = runtime
	LOG.debug("runtime attached %s id=%s" % [
		str(pony.name), str(pony.get_meta("relationship_id", ""))])
	pony.tree_exiting.connect(func() -> void: _runtimes.erase(pony))


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


## An act took the frame: the idle offer that would start another is dropped and the stock smack
## layer begins its act.
static func set_active(runtime: Node) -> void:
	_active = runtime
	if is_instance_valid(offer):
		offer.call("clear_current")
	if is_instance_valid(stock_smack):
		stock_smack.call("act_start", runtime.get("pony"))


## The act ended, or a world close: the frame is free again.
static func clear_active(runtime: Node) -> void:
	if _active == runtime:
		_active = null
		if is_instance_valid(stock_smack):
			stock_smack.call("act_end", runtime.get("pony"))


## The live act's runtime, or null.
static func active() -> Node:
	return _active if is_instance_valid(_active) else null


## True while an act owns the frame: the idle probe, the act key and the offer all gate on it.
static func act_running() -> bool:
	return is_instance_valid(_active)


## The act-target capability. The eligibility service owns the rule; a scan checks it before
## building a runtime gate for a stallion or a young pony.
static func act_target(pony: Node) -> bool:
	return is_instance_valid(pony) and is_instance_valid(eligibility) \
		and eligibility.eligible(pony, ELIGIBILITY.Target.ACT)


## The mares that hold a runtime, for the settings tail pass and the debug block. Allocation is
## fine here: both callers run on a settings edit or a closed wheel, never per frame.
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
		var runtime_id := str(live.call("live_id"))
		if runtime_id.is_empty():
			var target: Variant = live.get("pony")
			if is_instance_valid(target):
				runtime_id = ANATOMY.pony_id(target)
		if runtime_id != id:
			continue
		var note := str(live.call("prompt_note"))
		var cycle := str(live.call("cycle_note"))
		if not cycle.is_empty():
			note = cycle if note.is_empty() else note + " " + cycle
		return note
	return ""


## Live adult mares that are not in the base roster, for the Characters selector. A modded mare
## appears while she is in the world; her saved preset stays in settings.json when she despawns.
## Installed-profile sources also list their mares while they are away.
static func live_character_ids() -> Array[String]:
	var ids: Array[String] = []
	for pony: Variant in _runtimes.keys():
		if pony is Node3D and is_instance_valid(pony) and is_instance_valid(eligibility) \
				and eligibility.eligible(pony, ELIGIBILITY.Target.CHARACTER):
			ids.append(ANATOMY.pony_id(pony))
	var out: Array[String] = ANATOMY.off_roster_ids(ids, SETTINGS.CHARACTER_ORDER)
	for id: String in installed_character_ids():
		if not id in SETTINGS.CHARACTER_ORDER and not out.has(id):
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		return SETTINGS.character_name(a).naturalnocasecmp_to(
			SETTINGS.character_name(b)) < 0)
	return out


## Mares an active installed-profile source lists even while she is away. The source owns the
## installation gate; the base roster stays the base roster.
static func installed_character_ids() -> Array[String]:
	if not is_instance_valid(body_change):
		return []
	return body_change.call("installed_character_ids")


## One serial per act, the `unfplap.serial` state key. The stored value is the record; the last
## value issued here is a floor under it, so a store that cannot keep the write never hands out a
## serial twice.
static func allocate_serial() -> int:
	var value: int = _serial_issued + 1
	var mods := _mods()
	if mods != null:
		var section: Dictionary = mods.call("state", "unfplap")
		value = maxi(int(section.get("serial", 0)), _serial_issued) + 1
		section["serial"] = value
		mods.call("save_changed")
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


## The live settings pass over every runtime, not only the act's: a settings edit or an API layer
## change reaches each attached body.
static func apply_live_settings() -> void:
	for runtime: Variant in _runtimes.values():
		if is_instance_valid(runtime) and runtime.has_method("apply_live_settings"):
			runtime.call("apply_live_settings")


## Join the settings change notification. It is one static facade, so the entry calls this once
## while it binds the registry and `shutdown()` leaves.
static func bind_settings() -> void:
	CHANGE.on_changed(_listener)


## Bind the services one attached body passes through. The entry builds every service first and
## calls this once at the end of its list, so a body spawned during construction still reads a
## complete set.
static func bind(anatomy_service: Node, body_change_service: Node, offer_service: Node,
		stock_smack_service: Node, eligibility_service: ELIGIBILITY, api_service: Node) -> void:
	anatomy = anatomy_service
	body_change = body_change_service
	offer = offer_service
	stock_smack = stock_smack_service
	eligibility = eligibility_service
	api = api_service


## A settings edit: the pass above, and the act a pending body swap has taken out of the registry.
static func _on_settings_changed() -> void:
	apply_live_settings()
	if is_instance_valid(_active) and not _runtimes.has(_active.get("pony")):
		_active.call("apply_live_settings")


## A world started: the pending swap belongs to the world that is gone.
static func reset() -> void:
	_swap = {}


## The world closed: its act ends through the one exit and the pending swap goes with it. The
## runtimes leave with their bodies.
static func close_world() -> void:
	if is_instance_valid(_active) and _active.has_method("force_stop"):
		_active.call("force_stop")
	_active = null
	_swap = {}


## The entry is leaving: close the act, stop and free every runtime and drop the bound handles, so
## a fresh entry binds its own.
static func shutdown() -> void:
	CHANGE.off_changed(_listener)
	close_world()
	for runtime: Variant in _runtimes.values():
		if not is_instance_valid(runtime):
			continue
		if runtime.has_method("force_stop"):
			runtime.call("force_stop")
		(runtime as Node).queue_free()
	_runtimes.clear()
	factory = Callable()
	anatomy = null
	body_change = null
	stock_smack = null
	offer = null
	eligibility = null
	api = null


## Fit and prepare a new body before it can take a runtime or an act. The body-change service asks
## the handling provider for the body's form and mirrors it before anatomy attaches. Every hook is
## idempotent.
static func _prepare(pony: Node) -> void:
	if is_instance_valid(body_change):
		body_change.call("notify_body_ready", pony)
	if is_instance_valid(anatomy):
		anatomy.call("tail_ready", pony)
	if is_instance_valid(stock_smack):
		stock_smack.call("pony_ready", pony)


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
		and bool(source.call("claims_body", pony))
	if not claimed:
		var identity: Variant = pony.get("identity")
		var new_id := PONY_ID.from(str(pony.get_meta("relationship_id", "")), identity)
		if new_id != str(_swap.get("id", "")):
			return false
	var duplicate: Variant = _runtimes.get(pony)
	if is_instance_valid(duplicate) and duplicate != runtime:
		# A runtime created before adoption could only be a race; the suspended act is the owner.
		# Its anatomy controller holds the duplicate's facts, so drop it before the bind below.
		if is_instance_valid(anatomy) and anatomy.has_method("detach_controller"):
			anatomy.call("detach_controller", pony)
		if duplicate.has_method("force_stop"):
			duplicate.call("force_stop")
		duplicate.queue_free()
	var old_pony: Variant = _swap.get("old_pony")
	if is_instance_valid(old_pony) and _runtimes.get(old_pony) == runtime:
		_runtimes.erase(old_pony)
	_runtimes[pony] = runtime
	if is_instance_valid(anatomy):
		anatomy.call("bind", pony, runtime)
	if runtime.get_parent() != pony:
		runtime.call("attach_to_body", pony)
	pony.tree_exiting.connect(func() -> void: _runtimes.erase(pony))
	_swap = {}
	runtime.call("adopt_body", pony)
	return true


## The game's mod registry. A static facade cannot name the autoload: a `--script` suite preloads
## this file before the autoloads exist.
static func _mods() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("Mods")


## The idle perf block's header counts, `{runtimes, mares}`. The entry binds the two counters to
## `LOG.runtime_count` and `LOG.mare_count`
## and it is read once per window, never per note.
## The live runtimes, for the idle perf block's header.
static func runtime_count() -> int:
	var runtimes := 0
	for runtime: Variant in _runtimes.values():
		if is_instance_valid(runtime):
			runtimes += 1
	return runtimes


## The live mares, for the idle perf block's header.
static func mare_count() -> int:
	return WORLD.mares().size()
