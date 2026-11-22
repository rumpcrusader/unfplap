extends RefCounted
## The act's body-change handover: the swap record, the watcher decision and the form request.
## `act/swap.gd` holds the ordered release/resume seams and the one resume caller, the runtime keeps
## the reparent and the adoption binding; this handle decides when they run and owns the record.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_CHANGE_POLICY := preload("res://mods/unfplap/shared/body_change_policy.gd")
const BODY_CHANGE_SERVICE := preload("res://mods/unfplap/body_change/service.gd")
const BODY_CHANGE_SOURCE := preload("res://mods/unfplap/body_change/source.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const ACT_HOST := preload("res://mods/unfplap/body_change/act_host.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## Watcher cadence and the watchdog that gives up on a swap with no new body.
## The provider observes its own pack faster, so a longer wait means no body is coming.
const BODY_SWAP_POLL_S := 0.1
const BODY_SWAP_WATCHDOG_S := 8.0
## Grace after the source stops changing: a body it still reports is adopted by the entry.
const BODY_SWAP_ADOPT_GRACE_S := 0.5

## The debug log's form-state labels. They are never copied to the act facts.
const FORM_HINT_ASK := "Say to her: ask to see the real her."
const FORM_HINT_SHAPE := "Say to her: name the pony she should wear."
## The effects memory kind the provider may carry for the reveal's impression.
const FORM_REVEAL_MEMORY := "form_reveal"

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
## The form interaction: one offer and one reveal per act, the reused policy context and the
## player's line turn. The runtime calls these through the same handle that decides the swap.
var reveal_done := false
var offer_done := false
var offer_pending := false
var context: BODY_CHANGE_POLICY.BodyChangeActContext = \
	BODY_CHANGE_POLICY.BodyChangeActContext.new()
var talk_turn := -1
## The debug log's cached form label; an unchanged label is not logged again.
var form_hint_log := ""
## Debug mode at the act's settings snapshot: only then may the log name the form state.
var form_hint_debug := false
## The world memory a form effect writes; the runtime's builder passes it once.
var memory: Node = null


func _init(act_host: ACT_HOST, memory_in: Node = null) -> void:
	host = act_host
	memory = memory_in


## One watcher or suspended-act tick; it only returns the action the runtime applies.
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


## Release the old body for a change; the act keeps its state.
## True only when this call released it: the runtime applies one action, never a repeat.
func release(swap: BODY_CHANGE) -> bool:
	if suspended or not host.act_live() or swap == null:
		return false
	var body := host.pony()
	if body == null or swap.previous_body != body:
		return false
	if not change_changing(swap):
		return false
	# Another system holding her would keep the old body as the act's owner. Release it before
	# the flame takes the body; a failed release is logged and the watchdog still decides.
	if GAME.is_held(body) and not host.swap().release_carry():
		LOG.debug("body swap: could not release the held body")
	begin(swap)
	# Leave the old body before it is freed. The world keeps the act; the new body adopts the node.
	host.swap().attach_to_world()
	var source := change_source(swap)
	LOG.debug("body swap suspend source=%s target=%s origin=%d form=%s state=%d pose=%s depth=%.3f climaxes=%d", [
		source.source_id() if source != null else "?", swap.target_form_id,
		int(swap.origin), change_form_id(swap), host.state(), pose, host.depth(),
		host.climaxes()])
	# The old body's contact and input state must not survive the flame. The new pose owns the
	# contact after resume; a held key or a running auto stroke would otherwise fire on it.
	host.swap().release_contacts()
	host.swap().remember_auto()
	host.swap().release_act_body()
	host.swap().release_scene()
	host.swap().release_swap_pose()
	host.swap().restore_camera()
	host.swap().stop_breath()
	return true


## Resume the same act on the adopted body, rebuilding the body-bound systems in order.
## State and history survive; a missing body returns false and ends through the one exit.
func resume() -> bool:
	if not suspended:
		return false
	if not is_instance_valid(host.pony()):
		LOG.debug("body swap failed: no body to resume on")
		abort()
		return false
	var swap := change
	var changed := is_instance_valid(new_pony)
	var confirmed := shape_confirmed
	finish()
	host.swap().resume_body()
	host.swap().prepare_anatomy_act()
	host.swap().apply_resume_settings()
	host.swap().rebind_reactions()
	host.swap().set_act_pose_config()
	host.swap().rebuild_act_pose()
	host.swap().sync_start_config()
	host.swap().reset_visual_for_form()
	# The bed path has no placement fit; clear the old body's Hips handshake for every resume.
	host.swap().reset_pelvis()
	host.swap().reset_lean()
	host.swap().open_camera()
	host.swap().reset_wings()
	host.swap().claim_nav()
	host.swap().pause_face_turn()
	host.swap().reset_face()
	host.swap().apply_pose_change()
	host.swap().begin_integrations()
	host.swap().sync_hud()
	host.swap().resume_auto()
	LOG.debug("body swap resumed form=%s state=%d pose=%s depth=%.3f climaxes=%d", [
		change_form_id(swap), host.state(), pose, host.depth(), host.climaxes()])
	complete_resume(swap, changed, confirmed)
	if changed:
		dispatch_event(BODY_CHANGE_POLICY.ActEvent.FORM_SETTLED, swap)
	return true


## A revised form on the same presented body: refresh the eye, pose, camera and the other
## body-bound systems without a resume, a second runtime or an act exit.
func rebind(_form: BODY_FORM.BodyForm) -> void:
	host.swap().rebind_body()
	if not host.act_live():
		return
	host.swap().reset_visual_for_form()
	host.swap().sync_hud()



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


## Ask for a form change; it only starts one, the watcher suspends on a later tick.
## `by_player` marks the player's own ask, which is the only exceptional beat.
func request(true_form: bool, shape_id: String, by_player: bool) -> Dictionary:
	if suspended:
		return {"ok": false, "reason": "a form change is already in progress",
			"message": "A form change is already in progress."}
	if not host.act_live():
		return {"ok": false, "reason": "no live act", "message": "No live act."}
	var body := host.pony()
	if body == null:
		return {"ok": false, "reason": "no body", "message": "No body to change."}
	if GAME.is_held(body):
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
	LOG.debug("body swap requested target=%s form=%s origin=%d pose=%s depth=%.3f climaxes=%d", [
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
			LOG.debug("body swap watchdog; the new body never reported the shape, resuming")
			return Action.RESUME
		return Action.NONE
	if not changing:
		if _late_body_pending(swap):
			if is_instance_valid(new_pony) and _swap_ready(swap, changing):
				return Action.RESUME
			return Action.NONE
		if body != null and body == old_body:
			LOG.debug("body swap failed; the old body survives, resuming pony=%s", [str(body.name)])
			return Action.RESUME
		return _fail("the source stopped without a new body")
	if elapsed >= BODY_SWAP_WATCHDOG_S:
		if body != null and body == old_body:
			LOG.debug("body swap watchdog; the old body survives, resuming")
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


## Keep the act suspended while the change still reports a new body: resuming the old body here
## would attach a second runtime to the new one.
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
## the one exit has returned the act's state; finish the restore now, the act is already ending.
func _restore_tick() -> int:
	var body := host.pony()
	if body == null:
		return Action.NONE
	var live := active_change_for(body)
	if live == null or live.previous_body != body:
		return Action.NONE
	if not change_changing(live):
		return Action.NONE
	LOG.debug("body swap during restore; ending through the one exit")
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

# ------------------------------------------------------------------------- form interaction

## Debug mode at the act's settings snapshot. The runtime writes this once per snapshot; the log
## probe reads it, and no other state depends on it.
func set_form_hint_debug(enabled: bool) -> void:
	form_hint_debug = enabled


## A fresh act: the reveal and the offer are once-per-act, and the reused context and debug label
## start empty. The debug flag comes from the settings snapshot and survives.
func reset_act() -> void:
	reveal_done = false
	offer_done = false
	offer_pending = false
	context.form = null
	context.change = null
	form_hint_log = ""


## The act ended through the one exit: drop the pending offer and the reused context. The debug
## label clears so the log never names an action the player can no longer take.
func end_act() -> void:
	offer_pending = false
	context.form = null
	context.change = null
	form_hint_log = ""


## The HUD's form hint. It is always empty in a release and a debug build: the reveal and the gift
## are for the player to discover, so the dialogue channel never becomes a HUD row.
func form_hint() -> String:
	return ""


## The game's talk turn is the one interaction channel: no new key and no picker. The readiness
## service scores the same turn; this reads it for the source's own words.
func player_line_tick(director: Node) -> void:
	if host.state() != ACT_STATE.State.ACTIVE or suspended or director == null:
		return
	var turn := _talk_turn(director)
	if turn == talk_turn:
		return
	talk_turn = turn
	var text := str(director.get("_player_text")).strip_edges()
	if text.is_empty():
		return
	_on_player_line(text)


## The new act's first talk turn is already seen, so the opening line is not read as fresh input.
func remember_talk_turn(director: Node) -> void:
	talk_turn = _talk_turn(director)


func _talk_turn(director: Node) -> int:
	if director == null:
		return -1
	var value: Variant = director.get("_turn_id")
	return int(value) if value != null else -1


## One player line during a live act. A pending shape offer consumes a named adult mare; a
## source wearing another shape consumes a reveal ask. Everything else is ordinary talk.
func _on_player_line(text: String) -> void:
	if host.state() != ACT_STATE.State.ACTIVE or suspended:
		return
	var provider := source()
	if provider == null:
		return
	if offer_pending:
		var shape := _source_named_form(provider, text)
		if not shape.is_empty():
			var answer: Dictionary = request(false, shape, true)
			if bool(answer.get("ok", false)):
				offer_pending = false
				hint_tick()
				LOG.debug("form change named by player id=%s shape=%s", [host.id(), shape])
				return
			LOG.debug("form change named by player refused id=%s shape=%s reason=%s", [
				host.id(), shape, str(answer.get("reason", ""))])
		var note := _source_named_note(provider, text)
		if not note.is_empty():
			host.status(note)
	if not _source_current_shape(provider).is_empty():
		if reveal_done or not _source_asks_form_change(provider, text):
			return
		var result: Dictionary = request(true, "", true)
		if bool(result.get("ok", false)):
			LOG.debug("form reveal requested id=%s", [host.id()])
		else:
			LOG.debug("form reveal refused id=%s reason=%s", [
				host.id(), str(result.get("reason", ""))])


## The once-per-act gate stays here, so a refusal before the provider's trigger spends nothing.
func offer_tick() -> void:
	if offer_done or suspended or host.state() != ACT_STATE.State.ACTIVE:
		return
	var provider := source()
	if provider == null:
		# This pony has no shape source, and one cannot join a live act; stop asking every tick.
		offer_done = true
		return
	var policy := _policy(provider)
	if policy == null:
		# A provider without a policy never offers; one cannot join a live act.
		offer_done = true
		return
	if not policy.should_offer(_form_context_for(form(), BODY_CHANGE.Origin.PROVIDER, null)):
		return
	var prompt := policy.offer_prompt().strip_edges()
	if prompt.is_empty():
		offer_done = true
		return
	offer_done = true
	offer_pending = true
	hint_tick()
	LOG.debug("form shape offer id=%s climaxes=%d", [host.id(), host.climaxes()])
	if not is_instance_valid(WORLD.game):
		return
	var act_id := host.event_id()
	var valid := host.validity(func() -> bool:
		return not suspended and host.event_id() == act_id and offer_pending)
	var key: String = host.reaction_line(MEMORY.Reaction.FORM_OFFER,
		"%s:form_offer" % act_id, prompt, valid)
	if key.is_empty():
		return
	host.note_reaction(key, host.cue(), host.now() + host.reaction_max_age())
	LOG.debug("utterance kind=reaction key=%s", [key])


## The form state's debug label. It is never copied to the act facts: the HUD keeps no form row
## text in a release or a debug build. The cached label only stops the log repeating itself.
func hint_tick() -> void:
	var next := ""
	if form_hint_debug and host.state() == ACT_STATE.State.ACTIVE and not suspended:
		var provider := source()
		if provider != null:
			if offer_pending:
				next = FORM_HINT_SHAPE
			elif not reveal_done and not _source_current_shape(provider).is_empty():
				next = FORM_HINT_ASK
	if next == form_hint_log:
		return
	form_hint_log = next
	if not next.is_empty():
		LOG.debug("form hint suppressed \"%s\"", [next])


## The new body is up; her own form at the player's ask is the exceptional beat.
## Only the player's own call spends the offer; a failed named change puts it back.
func complete_resume(change: BODY_CHANGE, changed: bool, confirmed := false) -> void:
	var provider := change_source(change)
	var target := change.target_form_id.strip_edges() if change != null else ""
	var by_player := change != null and change.origin == BODY_CHANGE.Origin.PLAYER
	if not changed:
		_restore_shape_offer(target, by_player)
		hint_tick()
		return
	var shape := _source_current_shape(provider)
	if shape.is_empty() and confirmed and change != null and change.form != null:
		shape = change.form.form_id.strip_edges()
	if shape.is_empty() and not target.is_empty() and confirmed:
		shape = target
	if not target.is_empty() and shape != target:
		_restore_shape_offer(target, by_player)
		hint_tick()
		LOG.debug("form change failed id=%s target=%s shape=%s exceptional=false", [
			host.id(), target, shape if not shape.is_empty() else "self"])
		return
	if by_player and target.is_empty() and shape.is_empty() and provider != null:
		if not reveal_done:
			_commit_form_reveal(change)
		hint_tick()
		offer_tick()
		return
	if by_player and not shape.is_empty():
		offer_pending = false
		_apply_offer_accepted(change)
	hint_tick()
	LOG.debug("form changed id=%s shape=%s exceptional=false", [
		host.id(), shape if not shape.is_empty() else "self"])


func _restore_shape_offer(target: String, by_player: bool) -> void:
	if not by_player or target.is_empty():
		return
	if not offer_done or offer_pending:
		return
	offer_pending = true
	LOG.debug("form change failed; the shape offer stands again id=%s", [host.id()])


## Once per act: the provider's typed effects become the readiness spike, cue and peak.
## The private thought names her, not the shape; the world event stays non-graphic.
func _commit_form_reveal(change: BODY_CHANGE) -> void:
	var policy := _policy(change_source(change))
	var effects: BODY_CHANGE_POLICY.BodyChangeEffects = null
	if policy != null:
		effects = policy.on_reveal(_form_context_for(form(), BODY_CHANGE.Origin.PLAYER, change))
	reveal_done = true
	host.set_face(0.85)
	_apply_form_effects(effects)
	dispatch_event(BODY_CHANGE_POLICY.ActEvent.REVEALED, change)
	LOG.debug("form reveal id=%s event=%s readiness=%.0f", [
		host.id(), host.event_id(), host.satisfaction()])


## A player-named shape is the provider's accepted offer. The changelings policy is neutral; a
## future provider may supply its own generic effects.
func _apply_offer_accepted(change: BODY_CHANGE) -> void:
	var policy := _policy(change_source(change))
	if policy == null:
		return
	_apply_form_effects(policy.on_offer_accepted(_form_context_for(form(),
		BODY_CHANGE.Origin.PLAYER, change)))
	dispatch_event(BODY_CHANGE_POLICY.ActEvent.OFFER_ACCEPTED, change)


## Execute one typed effect value. `0`/`""` means none, so a neutral value is a no-op.
func _apply_form_effects(effects: BODY_CHANGE_POLICY.BodyChangeEffects) -> void:
	if effects == null or effects.is_empty():
		return
	if host.state() == ACT_STATE.State.ACTIVE:
		if effects.heat > 0.0:
			host.add_heat(effects.heat)
		if not effects.cue.is_empty():
			host.set_cue_override(effects.cue)
	if effects.memory_kind.is_empty() and effects.peak <= 0.0:
		return
	if memory == null:
		return
	if effects.memory_kind == FORM_REVEAL_MEMORY:
		memory.commit(memory.form_reveal_impression(host.id(), host.event_id()))
	if effects.peak > 0.0:
		memory.record_peak(memory.form_reveal_peak(host.id(), host.event_id(), effects.peak))


## The provider's typed offer/reveal policy, or null. The handover knows the contract, not the
## installed pack.
func _policy(candidate: BODY_CHANGE_SOURCE = null) -> BODY_CHANGE_POLICY:
	var owner := service()
	if owner != null and is_instance_valid(host.pony()):
		var policy := owner.policy_for(host.pony())
		if policy != null:
			return policy
	if candidate == null:
		candidate = source()
	if candidate == null:
		return null
	return candidate.policy()


## Fill the reused typed act context the provider policy reads. The offer tick runs every ACTIVE
## frame, so this writes fields and never allocates.
func _form_context_for(form: BODY_FORM.BodyForm, origin: BODY_CHANGE.Origin,
		change: BODY_CHANGE) -> BODY_CHANGE_POLICY.BodyChangeActContext:
	var value := context
	value.pony_id = host.id()
	value.form = form
	value.change = change
	value.origin = origin
	value.state = change.state if change != null else BODY_CHANGE.State.REQUESTED
	value.offer_pending = offer_pending
	value.reveal_used = reveal_done
	value.by_player = origin == BODY_CHANGE.Origin.PLAYER
	value.pony_climaxes = host.climaxes()
	value.max_climaxes = host.max_climaxes()
	value.act_active = host.state() == ACT_STATE.State.ACTIVE and not suspended
	return value


## Dispatch one generic act milestone to the provider policy. The context is the reused act value;
## a provider that does not care keeps the base no-op.
func dispatch_event(event: BODY_CHANGE_POLICY.ActEvent, change: BODY_CHANGE = null) -> void:
	var policy := _policy(change_source(change))
	if policy == null:
		return
	var origin := change.origin if change != null else BODY_CHANGE.Origin.PROVIDER
	policy.on_act_event(event, _form_context_for(form(), origin, change))


func _source_current_shape(provider: BODY_CHANGE_SOURCE) -> String:
	var body := host.pony()
	if provider == null or body == null:
		return ""
	return provider.presented_form_id(body).strip_edges()


func _source_asks_form_change(provider: BODY_CHANGE_SOURCE, text: String) -> bool:
	return provider != null and provider.asks_form_change(text)


func _source_named_form(provider: BODY_CHANGE_SOURCE, text: String) -> String:
	if provider == null:
		return ""
	return provider.named_form(text).strip_edges()


func _source_named_note(provider: BODY_CHANGE_SOURCE, text: String) -> String:
	if provider == null:
		return ""
	return provider.named_form_note(text).strip_edges()
