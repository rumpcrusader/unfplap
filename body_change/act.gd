extends RefCounted
## The act's body-change handover: the swap record, the watcher decision and the form request.
## The runtime keeps the ordered release, the adoption binding and the one resume; this handle only
## decides when they run and owns the record they read.

const WORLD := preload("res://mods/unfplap/world/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_CHANGE_SERVICE := preload("res://mods/unfplap/body_change/service.gd")
const BODY_CHANGE_SOURCE := preload("res://mods/unfplap/body_change/source.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const ACT_HOST := preload("res://mods/unfplap/body_change/act_host.gd")

## The act watcher reads the body-change service at this cadence and gives up after the watchdog.
## The provider observes its own pack; the flame and the spawn are well inside it, so a longer wait
## means no body is coming.
const BODY_SWAP_POLL_S := 0.1
const BODY_SWAP_WATCHDOG_S := 8.0
## The source may clear its changing state before the spawn hook reaches the entry. Keep the act
## suspended while the source still reports a new body; after this grace the entry adopts it.
const BODY_SWAP_ADOPT_GRACE_S := 0.5

## What the runtime does after one watcher tick.
enum Action { NONE, SUSPEND, RESUME, FAIL, END_RESTORE }

var host: ACT_HOST

var suspended := false
var change: BODY_CHANGE = null
var new_pony: Node = null
var pose := ""
var shape_confirmed := false
var elapsed := 0.0
var clock := 0.0
## The auto stroke's on/off state across a body swap. Its pace, band and shape stay in the
## readiness generator.
var auto_on := false
## The change the watcher just found for the `SUSPEND` action.
var candidate: BODY_CHANGE = null
var fail_reason := ""


func _init(act_host: ACT_HOST) -> void:
	host = act_host


## One watcher/swap tick. The provider observes its own pack and pushes the change; a live act
## reads the body-change service's active change, and a suspended act waits for the adopted
## body's shape, the source's completion, or the watchdog.
func tick(delta: float) -> int:
	candidate = null
	if host.restoring():
		return _restore_tick()
	if suspended:
		return _suspended_tick(delta)
	if not host.act_live():
		return Action.NONE
	clock -= delta
	if clock > 0.0:
		return Action.NONE
	clock = BODY_SWAP_POLL_S
	var body := host.pony()
	var live := active_change_for(body)
	if live == null or live.previous_body != body:
		return Action.NONE
	if not change_changing(live):
		return Action.NONE
	candidate = live
	return Action.SUSPEND


## Record the change the runtime is about to release the old body for. The runtime keeps the
## release order; this record is what the adoption and the one resume read.
func begin(swap: BODY_CHANGE) -> void:
	if suspended or swap == null:
		return
	suspended = true
	change = swap
	new_pony = null
	shape_confirmed = false
	elapsed = 0.0
	var view: Variant = host.pose_view()
	pose = str(view.id) if view != null and not str(view.id).is_empty() else host.start_pose_id()
	PONIES.begin_body_swap(host.runtime(), host.pony(), host.id(), swap)


## `ponies` adopts the new body before the watcher's resume. Adoption binds the record, not the
## act: the runtime moves under the body and the resume stays the watcher's.
func adopt(swap_body: Node) -> void:
	if not suspended or not is_instance_valid(swap_body):
		return
	new_pony = swap_body
	PONIES.clear_body_swap(host.runtime())


## The new body is ready and the runtime resumes. The pose stays: the resume rebuilds it last. The
## cadence restarts so the first live tick does not read the service again.
func finish() -> void:
	suspended = false
	change = null
	new_pony = null
	shape_confirmed = false
	elapsed = 0.0
	clock = BODY_SWAP_POLL_S
	PONIES.clear_body_swap(host.runtime())


## The act ended through the one exit: drop the swap record and the pending marker.
func abort() -> void:
	suspended = false
	change = null
	new_pony = null
	shape_confirmed = false
	auto_on = false
	elapsed = 0.0
	PONIES.clear_body_swap(host.runtime())


## The pending auto stroke state the resume restores. The runtime reads the generator; the record
## keeps the value across the release.
func remember_auto(active: bool) -> void:
	auto_on = active


func clear_auto() -> void:
	auto_on = false


## The act-side form request. It only starts a change; the watcher suspends the act on a later
## tick, so the act's state, depth and climaxes are never handed to a second runtime.
## `by_player` marks a player's own ask; only a requested reveal is exceptional.
func request(true_form: bool, shape_id: String, by_player: bool) -> Dictionary:
	if suspended:
		return {"ok": false, "reason": "a form change is already in progress",
			"message": "A form change is already in progress."}
	if not host.act_live():
		return {"ok": false, "reason": "no live act", "message": "No live act."}
	var body := host.pony()
	if body == null:
		return {"ok": false, "reason": "no body", "message": "No body to change."}
	if body.has_method("is_held") and bool(body.call("is_held")):
		return {"ok": false, "reason": "she is held", "message": "She is being held right now."}
	var owner := service()
	if owner == null:
		return {"ok": false, "reason": "no shape-changing source",
			"message": "No shape-changing mare."}
	if active_change_for(body) != null:
		return {"ok": false, "reason": "the source is already changing",
			"message": "She is already changing."}
	var origin := BODY_CHANGE.Origin.PLAYER if by_player else BODY_CHANGE.Origin.PROVIDER
	var started := false
	if true_form:
		started = owner.request_own_form(body, origin)
	else:
		started = owner.request_form(body, shape_id, origin)
	if not started:
		return {"ok": false, "reason": "the source refused",
			"message": "She cannot take that form now."}
	var label := "her true form" if true_form else host.shape_name(shape_id)
	host.log("body swap requested target=%s form=%s origin=%d pose=%s depth=%.3f climaxes=%d" % [
		shape_id if not shape_id.is_empty() else "self",
		"true" if true_form else "named", int(origin), host.start_pose_id(),
		host.depth(), host.climaxes()])
	return {"ok": true, "reason": "", "message": "Changing to %s." % label}


## The presented body's form, through `PONIES.body_change`; a host without the service (a suite
## or a lab harness) falls back to the identity's typed default own form.
func form() -> BODY_FORM.BodyForm:
	var owner := service()
	if owner != null:
		var stored := owner.form_for(host.pony())
		if stored != null:
			return stored
	return BODY_FORM.default_form(host.pony())


## The act pony's provider, through the body-change service's typed source lookup. The runtime
## knows the contract, not the installed pack.
func source() -> BODY_CHANGE_SOURCE:
	var owner := service()
	var body := host.pony()
	if owner == null or body == null:
		return null
	return owner.source_for(body)


## The world body-change service, or null on a host without it (a suite or a lab harness).
func service() -> BODY_CHANGE_SERVICE:
	if not is_instance_valid(WORLD.game):
		return null
	var value: Variant = PONIES.body_change
	if value is BODY_CHANGE_SERVICE:
		return value
	return null


## The active change for one presented body, through the service's typed per-body read.
func active_change_for(body: Node3D) -> BODY_CHANGE:
	var owner := service()
	if owner == null or not is_instance_valid(body):
		return null
	return owner.active_change_for(body)


## The typed provider behind a change, or null when the handle is not the source base.
func change_source(swap: BODY_CHANGE) -> BODY_CHANGE_SOURCE:
	if swap == null or not is_instance_valid(swap.source):
		return null
	if not swap.source is BODY_CHANGE_SOURCE:
		return null
	return swap.source


## True while the typed provider reports its own change in progress and its pack active.
func change_changing(swap: BODY_CHANGE) -> bool:
	var owner := change_source(swap)
	return owner != null and owner.is_active() and owner.change_in_progress()


func change_form_id(swap: BODY_CHANGE) -> String:
	if swap == null or swap.form == null:
		return ""
	return swap.form.form_id.strip_edges()


func _suspended_tick(delta: float) -> int:
	elapsed += delta
	var swap := change
	var changing := change_changing(swap)
	var old_body: Node3D = swap.previous_body if swap != null else null
	var body := host.pony()
	if is_instance_valid(new_pony):
		if _swap_ready(swap, changing):
			return Action.RESUME
		if elapsed >= BODY_SWAP_WATCHDOG_S:
			host.log("body swap watchdog; the new body never reported the shape, resuming")
			return Action.RESUME
		return Action.NONE
	if not changing:
		if _late_body_pending(swap):
			if is_instance_valid(new_pony) and _swap_ready(swap, changing):
				return Action.RESUME
			return Action.NONE
		if body != null and body == old_body:
			host.log("body swap failed; the old body survives, resuming pony=%s" % str(body.name))
			return Action.RESUME
		return _fail("the source stopped without a new body")
	if elapsed >= BODY_SWAP_WATCHDOG_S:
		if body != null and body == old_body:
			host.log("body swap watchdog; the old body survives, resuming")
			return Action.RESUME
		return _fail("watchdog expired with no body")
	return Action.NONE


## True when the new body is ready to resume the act: the shape it wears is the requested target,
## or the source has finished. A true-form target is empty, so an own body is ready at once.
func _swap_ready(swap: BODY_CHANGE, changing: bool) -> bool:
	var target := swap.target_form_id.strip_edges() if swap != null else ""
	var shape := _presented_shape(swap, new_pony)
	if target.is_empty():
		if shape.is_empty():
			shape_confirmed = true
			return true
		return not changing
	if shape == target:
		shape_confirmed = true
		return true
	return not changing


## The form the adopted body actually presents, through the typed provider hook.
func _presented_shape(swap: BODY_CHANGE, body: Node) -> String:
	var owner := change_source(swap)
	if owner == null or not is_instance_valid(body) or not body is Node3D:
		return ""
	return owner.presented_form_id(body).strip_edges()


## The source finished before the new body's spawn reached the entry. Keep the act suspended
## while the typed change reports a new body, then let the entry adopt it through the same
## pending-swap path; resuming the old body here would attach a second runtime to the new one.
func _late_body_pending(swap: BODY_CHANGE) -> bool:
	if swap == null:
		return false
	var newcomer := swap.next_body
	if not is_instance_valid(newcomer) or newcomer == swap.previous_body:
		return false
	if elapsed < BODY_SWAP_ADOPT_GRACE_S:
		return true
	return PONIES.adopt_pending_body(newcomer)


## A change her AI starts inside the restore window can free the body under the runtime before
## the one exit has returned the act's borrowed state. Finish the restore now instead; the act is
## already ending, so the change is not suspended.
func _restore_tick() -> int:
	var body := host.pony()
	if body == null:
		return Action.NONE
	var live := active_change_for(body)
	if live == null or live.previous_body != body:
		return Action.NONE
	if not change_changing(live):
		return Action.NONE
	host.log("body swap during restore; ending through the one exit")
	return Action.END_RESTORE


## Clear the swap and let the runtime end the act through the one exit. A lost body is not an act
## to resume.
func _fail(reason: String) -> int:
	fail_reason = reason
	PONIES.clear_body_swap(host.runtime())
	suspended = false
	change = null
	new_pony = null
	shape_confirmed = false
	auto_on = false
	return Action.FAIL
