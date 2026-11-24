extends "res://mods/unfplap/shared/service.gd"
## Scope: world
## The idle act offer: what a press could start, and the start itself.

const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")
const HUD := preload("res://mods/unfplap/hud/api.gd")
const PONIES := preload("res://mods/unfplap/ponies/api.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/api.gd")
const ACT_GATE := preload("res://mods/unfplap/act_gate/api.gd")
const NEGOTIATION := preload("res://mods/unfplap/negotiation/api.gd")
const AGREEMENT := preload("res://mods/unfplap/shared/agreement.gd")
const POSES := preload("res://mods/unfplap/poses/api.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/api.gd")
const ACT_KEYS := preload("res://mods/unfplap/shared/act_keys.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const POSE_OFFER := preload("res://mods/unfplap/shared/pose_offer.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const FAN_SENSOR := preload("res://mods/unfplap/offer/fan_sensor.gd")
const ACT_OWNER := preload("res://mods/unfplap/act_owner/api.gd")

## The act-key hint in the prompt row. A press taps it like a base prompt, so it never reads as a
## hold.
const OFFER_HINT := "Make love"
## The standing-act note when her reach needs a footstool and Anon has none in the case.
const NEEDS_STOOL_HINT := "Needs a footstool"
## The Agreement auto-start's readiness cadence.
const AGREEMENT_START_S := 0.25
## The runtime's Agreement start answer: a wait leaves it for the next press, started and failed
## both end it. This service never preloads the runtime, so it restates the three outcomes here.
const AGREEMENT_WAIT := 0
const AGREEMENT_STARTED := 1

## The Negotiation service handed over by the entry; its live Agreement is offered before the scene
## pass.
var negotiation: NEGOTIATION = null
## Set by the entry: the HUD, once the player rig arrives.
var hud: Node = null
## Set by the entry: the act frame the offer and its sensor gate on.
var act_owner: ACT_OWNER = null
## The roster: the per-pony runtime and the scene and start handles.
var _ponies: PONIES = null
## The act-target rule and the Base clearance relationship row, injected by the entry.
var _eligibility: ELIGIBILITY = null
var _act_gate: ACT_GATE = null

## The idle offer's playable offer and its blocked variant. Both are typed `PoseOffer` handles;
## null means none.
var _offer: POSE_OFFER = null
var _offer_blocked: POSE_OFFER = null
## The scene transitions the offer reconsiders on.
var _sensor := FAN_SENSOR.new()
## The last seat the idle frame saw; a new one re-reads the bed candidate.
var _seat: Variant = null
var _last_offer_key := ""
var _last_blocked_key := ""
var _stool_hint_toast_shown := false
var _native_hint_label: Control
var _native_hint_text := ""
## The game's hints node and its 2D prompt row; resolved once per world, not per frame.
var _native_hints_node: Node
var _native_hint_row: HBoxContainer
## The Agreement auto-start's readiness clock, in seconds since the last consumed handle.
var _agreement_clock := 0.0
## The runtime whose standing presentation this side started, or null.
var _presented_runtime: Node = null


func _ready() -> void:
	CHANGE.on_changed(Callable(self, "apply_settings"))
	apply_settings()


func _exit_tree() -> void:
	CHANGE.off_changed(Callable(self, "apply_settings"))


## Set by the entry: the Negotiation facade this offer reads, the HUD its hint falls back to, the
## act frame, the roster and the two capability services.
func wire(negotiation: NEGOTIATION, hud: Node, owner: ACT_OWNER,
		ponies: PONIES, eligibility: ELIGIBILITY, act_gate: ACT_GATE) -> void:
	self.negotiation = negotiation
	self.hud = hud
	act_owner = owner
	_ponies = ponies
	_eligibility = eligibility
	_act_gate = act_gate
	_sensor.act_owner = owner
	_sensor.ponies = ponies
	assert(negotiation != null and hud != null and act_owner != null)
	assert(_ponies != null and _eligibility != null and _act_gate != null)


## One idle frame: the presentation first, then the fan sensor, the prompt row and the
## Agreement clock. The act key's immediate read is `reconsider()` after a forced sense.
func tick(delta: float) -> void:
	_sync_presentation()
	PERF.begin("offer_sensor")
	var changed := _sense(delta)
	PERF.end("offer_sensor")
	if changed:
		reconsider()
	PERF.begin("entry_hint")
	_sync_native_hint(_hint_text())
	PERF.end("entry_hint")
	_tick_agreement_auto_start(delta)


## Tick the sensor; true when a transition needs a fresh evaluation.
## The act key forces it, so the press never uses a stale result.
func _sense(delta: float, force := false) -> bool:
	if not is_instance_valid(WORLD.player_rig()) or not WORLD.ready():
		return false
	if not WORLD.can_interact():
		return false
	var seat: Variant = WORLD.player_rig().get("seat")
	var seat_changed: bool = seat != _seat
	if seat_changed:
		_seat = seat
	var pony_form := WORLD.player_is_pony()
	_sensor.advance(delta)
	if not (force or seat_changed or _sensor.due(pony_form)):
		return false
	var view: Camera3D = WORLD.camera()
	if view == null:
		return seat_changed
	PERF.begin("offer_sensor_read")
	# A new seat forces the read, so a partner already lying there is seen on that frame.
	var changed := _sensor.update(0.0, view.global_position, -view.global_basis.z,
		pony_form, force or seat_changed)
	PERF.end("offer_sensor_read")
	return changed or seat_changed


## The current offer's pony, for the Proactive service's cuddle check; a pure read that never
## re-evaluates, because the sensor owns the transitions.
func offer_target() -> Node:
	if _offer == null:
		return null
	var target: Variant = _offer.pony
	return target if is_instance_valid(target) else null


## The offer a press would start, or null.
func current() -> POSE_OFFER:
	return _offer


## The blocked offer, the standing gate's footstool block, or null.
func blocked() -> POSE_OFFER:
	return _offer_blocked


## The offer was started or a new Agreement formed: drop the playable offer and leave the hint to
## the caller. The blocked record and the logged keys stay.
func clear_current() -> void:
	_offer = null


## An act owns the frame: there is no offer to start and the hint goes away.
func hide_hint() -> void:
	_offer = null
	_offer_blocked = null
	_sync_native_hint("")


## The act key's one start entry. It always accepts and never refuses; a missing context pose is
## no attempt, since the tolerance stop owns the refusal path.
func try_start() -> bool:
	if (act_owner.act_running() if is_instance_valid(act_owner) else false):
		return false
	# No idle input: a paused tree or a free cursor refuses the press before any read.
	if not WORLD.can_interact():
		return false
	_sense(0.0, true)
	reconsider()
	if _offer == null:
		if _offer_blocked != null:
			return start_pose_offer(_offer_blocked)
		LOG.debug("hotkey no context pose")
		_toast("There is nothing to start here.")
		return false
	return start_pose_offer(_offer)


## Dispatch a typed offer to its trigger's start path, so no pose is named here.
func start_pose_offer(offer: POSE_OFFER) -> bool:
	if offer == null or not offer.valid():
		return false
	if not offer.blocked.is_empty():
		var toast := str(offer.blocked.get("toast", ""))
		if not toast.is_empty():
			_toast(toast)
		return false
	if offer.trigger == "agreement":
		return _start_agreement_offer(offer, false)
	return _start_hotkey_offer(offer)


## The hotkey: an exact Agreement match starts it and skips the presentation; otherwise any live
## negotiation or Agreement is interrupted and the immediate attempt runs.
func _start_hotkey_offer(offer: POSE_OFFER) -> bool:
	var runtime: Node = offer.runtime
	if not is_instance_valid(runtime):
		return false
	var id := PONY_ID.from(str(offer.pony.get_meta("relationship_id", "")),
		offer.pony.get("identity")) if is_instance_valid(offer.pony) else "?"
	# The one act-key decision: an exact Agreement match starts it; anything else live ends here.
	var handle := negotiation.press(runtime, _option_for(offer)) \
		if is_instance_valid(negotiation) else null
	if handle != null:
		return _start_agreement_offer(offer, true)
	LOG.debug("hotkey immediate id=%s pose=%s source=%s", [id, offer.pose, offer.source])
	var start := _ponies.start_of(runtime)
	var started := start != null \
		and bool(start.start_hotkey(offer.pose, offer.bed, offer.source))
	if not started:
		LOG.debug("hotkey start blocked id=%s pose=%s source=%s", [id, offer.pose, offer.source])
		return false
	_clear_offer_hint()
	return true


## The exact pose option a hotkey attempt names. The idle hint never offers a cuddle, so the flag
## is false; a cuddle Agreement is consumed by its own offer path instead.
func _option_for(offer: POSE_OFFER) -> POSE_OPTIONS.Option:
	var option := POSE_OPTIONS.Option.new()
	option.pose = offer.pose
	option.source = offer.source
	option.bed = offer.bed
	return option


## Consume a live Agreement through its scene-only start. A wait keeps both for the next press;
## started or failed clears the hint and reports the result.
func _start_agreement_offer(offer: POSE_OFFER, skip_presentation: bool) -> bool:
	var handle := negotiation.handle() if is_instance_valid(negotiation) else null
	if handle == null or not is_instance_valid(offer.runtime):
		_clear_offer_hint()
		return false
	var start := _ponies.start_of(offer.runtime)
	if start == null:
		_clear_offer_hint()
		return false
	var result := int(start.start_agreement(handle, skip_presentation))
	var id := PONY_ID.from(str(offer.pony.get_meta("relationship_id", "")),
		offer.pony.get("identity")) if is_instance_valid(offer.pony) else "?"
	LOG.debug("agreement start id=%s pose=%s skip_presentation=%s result=%d", [
		id, offer.pose, str(skip_presentation), result])
	if result == AGREEMENT_WAIT:
		LOG.debug("agreement start waiting pose=%s source=%s", [offer.pose, offer.source])
		return false
	_clear_offer_hint()
	_report_agreement(handle, result == AGREEMENT_STARTED)
	return result == AGREEMENT_STARTED


## The Agreement's automatic start: once the presentation settles and Anon is in position it
## consumes the handle with no key press. A live act, menu, paused tree or free cursor holds it back.
func _tick_agreement_auto_start(delta: float) -> void:
	if (act_owner.act_running() if is_instance_valid(act_owner) else false) \
			or not is_instance_valid(negotiation):
		return
	# The clock ticks before the handle read, so the common frame pays one arithmetic step and a
	# handle that shows up mid-poll is caught on the next tick.
	_agreement_clock += delta
	if _agreement_clock < AGREEMENT_START_S:
		return
	var handle := negotiation.handle()
	if handle == null:
		return
	_agreement_clock = 0.0
	if WORLD.menu_panel_open() or not WORLD.can_interact():
		return
	var pony: Node3D = handle.pony
	if not is_instance_valid(pony) or handle.option == null:
		return
	# The readiness read is the negotiation's; a private Agreement that lost its cover is
	# cancelled there. The scene rows are this side's, because the scene gate answers them.
	if not negotiation.can_start() or not _agreement_ready(handle):
		return
	var typed: POSE_OFFER = agreement_offer(handle)
	if typed == null:
		return
	LOG.debug("agreement auto-start id=%s pose=%s", [handle.pony_id, typed.pose])
	LOG.debug("agreement auto-start pony=%s pose=%s", [str(pony.name), typed.pose])
	_start_agreement_offer(typed, false)


## The live scene's Agreement rows with the frozen pose pair; a missing scene refuses.
func _agreement_ready(handle: AGREEMENT.Handle) -> bool:
	var runtime: Node = _ponies.runtime_for(handle.pony) \
		if is_instance_valid(handle.pony) else null
	var scene := _ponies.scene_of(runtime) if is_instance_valid(runtime) else null
	var option := handle.option
	if scene == null or option == null:
		return false
	return bool(scene.agreement_ready(option.pose, option.source, option.bed,
		SCENE_GATE.FrozenPose.new(bool(handle.pose_profile_ok), bool(handle.pose_source_ok))))


## The standing presentation is act-owned but starts here, before any interaction gate, so a menu
## cannot suppress the turn. It starts once per Agreement and clears when the handle vanishes.
func _sync_presentation() -> void:
	var handle := negotiation.handle() if is_instance_valid(negotiation) else null
	if handle == null:
		_clear_presentation()
		return
	if is_instance_valid(_presented_runtime):
		return
	var option := handle.option
	if option == null or str(option.pose) != CATALOG.STANDING:
		return
	var runtime: Node = _ponies.runtime_for(handle.pony) \
		if is_instance_valid(handle.pony) else null
	if not is_instance_valid(runtime):
		return
	_presented_runtime = runtime
	var presentation := _ponies.presentation_of(runtime)
	if presentation == null or not bool(presentation.present_standing()):
		LOG.debug("agreement present failed pony=%s", [str(handle.pony.name)])


## Take the presentation started here away again; a runtime that is gone needs nothing.
func _clear_presentation() -> void:
	if not is_instance_valid(_presented_runtime):
		return
	var presentation := _ponies.presentation_of(_presented_runtime)
	_presented_runtime = null
	if presentation != null:
		presentation.clear_presentation()


## The runtime's Agreement start result, forwarded to the Negotiation service.
func _report_agreement(handle: AGREEMENT.Handle, started: bool) -> void:
	if is_instance_valid(negotiation):
		negotiation.report(handle, started)


## Clear the act-key hint and its cached offer.
func _clear_offer_hint() -> void:
	clear_current()
	if is_instance_valid(hud):
		hud.hide_prompt()


func _toast(text: String) -> void:
	if text.is_empty() or not is_instance_valid(hud):
		return
	hud.toast(text, 4.0)


## A settings edit: drop the hint row, forget the sensor's senses and let the next idle frame
## re-evaluate the offer with the new values.
func apply_settings() -> void:
	_clear_native_hint()
	_sensor.reset()


## The world entered: drop the old sensor and parse the two offerable pose assets while the world
## is still under its loading cover, so the first hint never loads them inside its evaluation.
func on_world(_host: Node) -> void:
	on_world_closed()
	for pose: String in [POSE_SPECS.MISSIONARY, POSE_SPECS.STANDING]:
		var asset_path := str(POSE_SPECS.spec(pose).get("asset", ""))
		POSES.warm_asset(asset_path)


## A world enter or a world close: drop the offer, the one-shot flags, the sensor and the hint row
## of the world that is gone.
func on_world_closed() -> void:
	_clear_presentation()
	_offer = null
	_offer_blocked = null
	_sensor.reset()
	_seat = null
	_last_offer_key = ""
	_last_blocked_key = ""
	_stool_hint_toast_shown = false
	_clear_native_hint()


## Re-evaluate the offer from the sensor's current candidates. The idle tick calls it on a
## transition; the press calls it after forcing a fresh sensor read.
func reconsider() -> void:
	PERF.begin("offer_reconsider")
	_reconsider()
	PERF.end("offer_reconsider")


## One full evaluation: the Agreement, the two bed candidates, then the standing fan. Each
## business check is one call, and no row list is built on this path.
func _reconsider() -> void:
	if not is_instance_valid(WORLD.player_rig()) or not WORLD.ready():
		_offer = null
		_offer_blocked = null
		_sensor.focus(null)
		return
	# Keep the last offer while `can_interact()` is false: the menu hides the row, and the next
	# transition refreshes it.
	if not WORLD.can_interact():
		return
	if WORLD.camera() == null:
		_offer = null
		_offer_blocked = null
		_sensor.focus(null)
		return
	_offer = null
	_offer_blocked = null
	_sensor.focus(null)
	var pony_form: bool = WORLD.player_is_pony()

	# A live Agreement owns the hint while it is ready: it is already a yes. While its rows wait
	# or the presentation turns, the scene pass below still finds a hotkey attempt, so a press
	# can start the exact match immediately or interrupt a different one.
	if is_instance_valid(negotiation):
		PERF.begin("offer_agreement")
		var live: POSE_OFFER = null
		if negotiation.can_start():
			live = agreement_offer(negotiation.handle())
		PERF.end("offer_agreement")
		if live != null:
			_offer = live
			_sensor.focus(live.pony)
			_log_offer()
			return

	# Missionary now requires Anon to be seated/lying on the bed with a pony lying there. A
	# standing or cradling Anon has no valid missionary camera, so that entry is not offered.
	if not pony_form and _offer_bed_side(pony_form):
		return
	# Missionary, AnonPony: an awake pony already lying on a bed.
	if _offer_lying(pony_form):
		return
	_offer_standing()


## Missionary while a seated or lying Anon has a pony lying beside him on the bed.
func _offer_bed_side(pony_form: bool) -> bool:
	if pony_form:
		return false
	var lying: Node3D = _sensor.beside()
	if not is_instance_valid(lying) or not _act_target(lying):
		return false
	var runtime: Node = _ponies.runtime_for(lying)
	if not is_instance_valid(runtime):
		return false
	var scene := _ponies.scene_of(runtime)
	var bed: Node3D = scene.find_bed_under() if scene != null else null
	if bed == null or not _candidate_ready(runtime, CATALOG.MISSIONARY, "bed_side", bed):
		return false
	if not _relationship_ok(lying):
		return false
	_offer = _new_offer(runtime, lying, CATALOG.MISSIONARY, "bed_side", bed)
	_sensor.focus(lying)
	_log_offer()
	return true


## Missionary, AnonPony: the best pony already lying in front of the eye and on a bed.
func _offer_lying(pony_form: bool) -> bool:
	if not pony_form:
		return false
	var lying: Node3D = _sensor.lying()
	if not is_instance_valid(lying) or not _act_target(lying):
		return false
	var runtime: Node = _ponies.runtime_for(lying)
	if not is_instance_valid(runtime):
		return false
	var scene := _ponies.scene_of(runtime)
	var bed: Node3D = scene.find_bed_under() if scene != null else null
	if bed == null or not _candidate_ready(runtime, CATALOG.MISSIONARY, "already_lying", bed):
		return false
	if not _relationship_ok(lying):
		return false
	_offer = _new_offer(runtime, lying, CATALOG.MISSIONARY, "already_lying", bed)
	_sensor.focus(lying)
	_log_offer()
	return true


## Standing: Anon in the fan behind her rump, no crosshair aim, nearest act target first. Only
## clearance and the small scene checks make her ready.
func _offer_standing() -> void:
	for candidate: Node3D in _sensor.candidates():
		if not _act_target(candidate):
			continue
		var runtime: Node = _ponies.runtime_for(candidate)
		if not is_instance_valid(runtime):
			continue
		if not _candidate_ready(runtime, CATALOG.STANDING, "", null):
			continue
		if not _relationship_ok(candidate):
			continue
		PERF.begin("offer_stool")
		var presentation := _ponies.presentation_of(runtime)
		var pair: Vector2i = presentation.stool_pair(CATALOG.STANDING) \
			if presentation != null else Vector2i(-1, -1)
		PERF.end("offer_stool")
		if pair.x > 0 and pair.y < pair.x:
			var blocked_offer := _new_offer(runtime, candidate, CATALOG.STANDING, "", null)
			blocked_offer.blocked = _blocked_record(pair.x, _stool_hint_for(pair.x))
			_offer_blocked = blocked_offer
			_log_blocked_offer(runtime, candidate, pair.x)
			return
		_offer = _new_offer(runtime, candidate, CATALOG.STANDING, "", null)
		_sensor.focus(candidate)
		_log_offer()
		return


## The eligibility service's act-target rule.
func _act_target(pony: Node) -> bool:
	return is_instance_valid(pony) and is_instance_valid(_eligibility) \
		and _eligibility.eligible(pony, ELIGIBILITY.Target.ACT)


## The act gate's Base clearance relationship row.
func _relationship_ok(pony: Node) -> bool:
	return is_instance_valid(pony) and is_instance_valid(_act_gate) \
		and _act_gate.relationship_ok(pony)


## The scene checks the hint and the press share, without the composite's duplicate reads. The
## cheap refusals come first and the clearance row last, so a busy scene never pays the bond read.
func _candidate_ready(runtime: Node, pose: String, source: String, bed: Variant) -> bool:
	var gate := _ponies.scene_of(runtime)
	if gate == null or not gate.available():
		return false
	if not gate.pose_supported(pose, source):
		return false
	if not gate.player_ready(pose, source, bed):
		return false
	if not gate.navigator_allows(pose, source):
		return false
	return gate.posture_allows(pose)


## The prompt-row hint: the offer, else the blocked note, else nothing. With neither, both logged
## keys reset so the next offer logs again.
func _hint_text() -> String:
	if _offer != null:
		return OFFER_HINT
	if _offer_blocked != null:
		var blocked_hint := _offer_blocked.blocked_hint()
		return blocked_hint if not blocked_hint.is_empty() else NEEDS_STOOL_HINT
	_last_offer_key = ""
	_last_blocked_key = ""
	return ""


## Build one typed offer for the idle hint. The idle offers carry no cancel callback because a
## live Agreement press goes through the scene-only start.
func _new_offer(runtime: Node, pony: Node, pose: String, source: String,
		bed: Variant = null) -> POSE_OFFER:
	var offer := POSE_OFFER.new()
	offer.runtime = runtime
	offer.pony = pony as Node3D
	offer.pose = pose
	offer.source = source
	offer.bed = bed
	return offer


## The blocked record: the prompt hint and the toast a press shows.
func _blocked_record(need: int, hint: String) -> Dictionary:
	return {"hint": hint, "need": maxi(1, need), "toast": _stool_find_hint(need)}


func _native_row() -> HBoxContainer:
	# The row is read every frame, so it is cached: the path lookup allocates a NodePath and walks
	# the tree, and the game keeps the same hints node and row for the whole world.
	if is_instance_valid(_native_hint_row) and _native_hint_row.is_inside_tree():
		return _native_hint_row
	_native_hint_row = null
	_native_hints_node = WORLD.interaction_hints()
	if not is_instance_valid(_native_hints_node):
		return null
	# VR uses the world-space prompt row; the act-key hint falls back to the HUD prompt there.
	if bool(_native_hints_node.get("xr")):
		return null
	var row: Variant = _native_hints_node.get("_prompt2d")
	if row is HBoxContainer and is_instance_valid(row):
		_native_hint_row = row
		return row
	return null


## Match the native prompt row's style so the hint blends in beside base prompts.
func _make_native_hint_label(text: String) -> Control:
	var cap := _act_key_label() if text == OFFER_HINT else ""
	return HUD.prompt_row("", text, cap)


func _remove_native_hint(row: HBoxContainer = null) -> void:
	_native_hint_text = ""
	if is_instance_valid(_native_hint_label):
		var holder: Node = _native_hint_label.get_parent()
		if is_instance_valid(holder):
			holder.remove_child(_native_hint_label)
		_native_hint_label.queue_free()
	_native_hint_label = null
	if row != null and is_instance_valid(row):
		var parent: Node = row.get_parent()
		if is_instance_valid(parent) and parent is Control and row.get_child_count() == 0:
			(parent as Control).visible = false


func _clear_native_hint() -> void:
	_remove_native_hint(_native_row())
	_native_hint_row = null
	_native_hints_node = null


func _sync_native_hint(text: String) -> void:
	var row: HBoxContainer = _native_row()
	if row == null:
		if is_instance_valid(hud):
			if text.is_empty():
				hud.hide_prompt()
			else:
				hud.show_prompt(text, "",
					_act_key_label() if text == OFFER_HINT else "")
		return
	# The sensor changes the hint only on a transition; the common frame has nothing to apply, so
	# it returns before the label checks and the container pokes.
	if text == _native_hint_text:
		if text.is_empty():
			return
		if is_instance_valid(_native_hint_label) and _native_hint_label.get_parent() == row:
			return
	if text.is_empty():
		_remove_native_hint(row)
		if is_instance_valid(hud):
			hud.hide_prompt()
		return
	if not is_instance_valid(_native_hint_label) or _native_hint_label.get_parent() != row \
			or _native_hint_label.is_queued_for_deletion() or _native_hint_text != text:
		_remove_native_hint(row)
		_native_hint_label = _make_native_hint_label(text)
		_native_hint_text = text
		row.add_child(_native_hint_label)
	var parent: Node = row.get_parent()
	if parent is Control:
		(parent as Control).visible = true
	if is_instance_valid(hud):
		hud.hide_prompt()


## The act key's cap label, resolved once when a hint row is built.
func _act_key_label() -> String:
	return ACT_KEYS.label(int(SETTINGS.act_key.get_num()))


func _stool_hint_for(need: int) -> String:
	return NEEDS_STOOL_HINT if need <= 1 else "Needs %d footstools" % need


func _stool_find_hint(need: int) -> String:
	return "Find a footstool in a house." if need <= 1 \
		else "Find %d footstools in a house." % need


func _log_blocked_offer(runtime: Node, target: Node, need: int) -> void:
	var key := "stool:%d:%d" % [target.get_instance_id(), need]
	if key == _last_blocked_key:
		return
	_last_blocked_key = key
	var presentation := _ponies.presentation_of(runtime)
	var gap: Variant = presentation.stool_gap_m() if presentation != null else NAN
	var gap_text := "n/a" if not (gap is float or gap is int) \
		or not is_finite(float(gap)) else "%.3f" % float(gap)
	var have := int(presentation.stool_case_count()) if presentation != null else 0
	LOG.debug("OFFER blocked pony=%s reason=needs_stool gap=%s need=%d have=%d", [
		str(target.name), gap_text, need, have])
	if not _stool_hint_toast_shown:
		_stool_hint_toast_shown = true
		if is_instance_valid(hud):
			hud.toast(_stool_find_hint(need), 4.0)


## A live Agreement typed as a press offer; no rump fan or policy snapshot is needed.
## Null while the world is not ready.
func agreement_offer(handle: AGREEMENT.Handle) -> POSE_OFFER:
	if handle == null or not handle.valid():
		return null
	var option: Variant = handle.option
	if option == null:
		return null
	var pony: Variant = handle.pony
	var runtime: Node = _ponies.runtime_for(pony) if is_instance_valid(pony) else null
	if not is_instance_valid(runtime):
		return null
	var offer := POSE_OFFER.new()
	offer.runtime = runtime
	offer.pony = pony as Node3D
	offer.pose = str(option.pose)
	offer.source = str(option.source)
	offer.bed = option.bed
	offer.trigger = "agreement"
	offer.pending = false
	return offer


func _log_offer() -> void:
	if _offer == null:
		return
	var target: Variant = _offer.pony
	var key := "%s:%s:%s:%s" % [
		str(target.name) if is_instance_valid(target) else "?",
		_offer.pose, _offer.source, str(_offer.pending)]
	if key == _last_offer_key:
		return
	_last_offer_key = key
	LOG.debug("OFFER pony=%s pose=%s source=%s bed=%s pending=%s", [
		str(target.name) if is_instance_valid(target) else "?",
		_offer.pose, _offer.source, str(_offer.bed), str(_offer.pending)])
