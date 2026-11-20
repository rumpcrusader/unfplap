extends Node
## Service: offer
## Contract: docs/offer.md
## Scope: world
## Import: offer/service.gd only
## The idle act offer: what a press could start, and the start itself.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const NEGOTIATION := preload("res://mods/unfplap/negotiation/service.gd")
const POSES := preload("res://mods/unfplap/poses/service.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/service.gd")
const ACT_KEYS := preload("res://mods/unfplap/shared/act_keys.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const POSE_OFFER := preload("res://mods/unfplap/shared/pose_offer.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const RUMP_CONE := preload("res://mods/unfplap/shared/rump_cone.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")

## The act-key hint in the prompt row. A press taps it like a base prompt, so it never reads as a
## hold.
const OFFER_HINT := "Make love"
## The idle offer hint's scan cadence.
const OFFER_SCAN_S := 1.0
## The standing gate's refresh cadence for one mare; the full gate is expensive, so the cone scan
## reuses its verdict between refreshes.
const GATE_REFRESH_S := 2.0
## The standing-act note when her reach needs a footstool and Anon has none in the case.
const NEEDS_STOOL_HINT := "Needs a footstool"
## The Agreement auto-start's readiness cadence.
const AGREEMENT_START_S := 0.25
## The runtime's Agreement start answer: a wait leaves it for the next press, started and failed
## both end it. Kept local because this service never preloads the runtime.
const AGREEMENT_WAIT := 0
const AGREEMENT_STARTED := 1

## The per-pony gate handle: the scene verdicts and the offer readiness reads.
func _gate(runtime: Node) -> Variant:
	return runtime.get("gate")

## The Negotiation service bound by the entry; its live Agreement is offered before the scan. It
## stays a plain handle because only its public reads are used.
var negotiation: Node = null
## Set by the entry's `bind()`: the privacy provider, resampled before a private Agreement
## auto-starts.
var privacy: PRIVACY = null
## Set by the entry's `bind()`: the HUD, once the player rig arrives.
var hud: Node = null

## The idle scan's playable offer and its blocked variant. Both are typed `PoseOffer` handles;
## null means none.
var _offer: POSE_OFFER = null
var _offer_blocked: POSE_OFFER = null
var _offer_clock := 0.0
## The standing gate's last verdict and its footstool pair, kept while the same mare holds the
## cone target.
var _gate_target: Node
var _gate_at := 0.0
var _gate_ready := false
var _gate_stool_need := 0
var _gate_stool_have := 0
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


func _ready() -> void:
	CHANGE.on_changed(Callable(self, "apply_settings"))


func _exit_tree() -> void:
	CHANGE.off_changed(Callable(self, "apply_settings"))


## Set by the entry: the Negotiation and privacy facades this offer reads and the HUD its hint
## falls back to. The registry and the act reads are the preloaded `PONIES` facade.
func bind(negotiation_node: Node, privacy_node: PRIVACY, hud_node: Node) -> void:
	negotiation = negotiation_node
	privacy = privacy_node
	hud = hud_node


## One idle frame: the scan cadence, the hint that follows it and the Agreement auto-start clock.
## The act key's immediate rescan is `scan()`.
func tick(delta: float) -> void:
	var timed := LOG.idle_on()
	_offer_clock += delta
	if _offer_clock >= OFFER_SCAN_S:
		_offer_clock = 0.0
		var scan_started := Time.get_ticks_usec() if timed else 0
		scan()
		if timed:
			LOG.close("offer_scan", scan_started)
	var hint_started := Time.get_ticks_usec() if timed else 0
	_sync_native_hint(_hint_text())
	if timed:
		LOG.close("entry_hint", hint_started)
	_tick_agreement_auto_start(delta)


## The current offer's pony, for the Proactive service's cuddle check; a pure read that never
## rescans, because the loop owns the cadence.
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
	if PONIES.act_running():
		return false
	scan()
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
	if is_instance_valid(negotiation):
		var handle: Variant = negotiation.call("handle")
		if handle != null:
			var match: Variant = negotiation.call("hotkey_handle", runtime, _option_for(offer))
			if match != null:
				LOG.debug("hotkey exact match id=%s pose=%s", [id, offer.pose])
				return _start_agreement_offer(offer, true)
			LOG.debug("hotkey interrupt agreement id=%s", [id])
			negotiation.call("interrupt_for_hotkey")
		elif bool(negotiation.call("is_locked")):
			LOG.debug("hotkey interrupt negotiation id=%s", [id])
			negotiation.call("interrupt_for_hotkey")
	LOG.debug("hotkey immediate id=%s pose=%s source=%s", [id, offer.pose, offer.source])
	var started := bool(_gate(runtime).start_hotkey(offer.pose, offer.bed, offer.source))
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
	var handle: Variant = negotiation.call("handle") if is_instance_valid(negotiation) else null
	if handle == null or not is_instance_valid(offer.runtime):
		_clear_offer_hint()
		return false
	var result := int(_gate(offer.runtime).start_agreement(handle, skip_presentation))
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
	if PONIES.act_running() or not is_instance_valid(negotiation):
		return
	# The clock ticks before the handle read, so the common frame pays one arithmetic step and a
	# handle that shows up mid-poll is caught on the next tick.
	_agreement_clock += delta
	if _agreement_clock < AGREEMENT_START_S:
		return
	var handle: Variant = negotiation.call("handle")
	if handle == null:
		return
	_agreement_clock = 0.0
	if WORLD.menu_panel_open():
		return
	if DisplayServer.get_name() != "headless" and not WORLD.headset_view() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var pony: Variant = handle.pony
	var runtime: Node = PONIES.runtime_for(pony) if is_instance_valid(pony) else null
	var gate: Variant = _gate(runtime) if is_instance_valid(runtime) else null
	if gate == null:
		return
	var typed: POSE_OFFER = agreement_offer(handle)
	if typed == null:
		return
	var option: Variant = handle.option
	var cuddle := option != null and bool(option.cuddle)
	var pony_id := str(handle.pony_id)
	if pony_id.is_empty() and is_instance_valid(pony):
		pony_id = PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))
	LOG.debug("agreement auto-start id=%s pose=%s", [pony_id, typed.pose])
	if bool(handle.private) and not _agreement_private_now(pony, cuddle):
		LOG.debug("agreement auto-start privacy lost pony=%s", [str(pony.name)])
		negotiation.call("cancel", handle, "privacy")
		return
	LOG.debug("agreement auto-start pony=%s pose=%s", [str(pony.name), typed.pose])
	_start_agreement_offer(typed, false)


## A fresh privacy sample for the auto-start, with the offer's cuddle rule. Without a provider the
## answer is public, so nothing starts on a stale one.
func _agreement_private_now(pony: Node, cuddle: bool) -> bool:
	if not is_instance_valid(privacy):
		return false
	return privacy.cuddle_private(pony) if cuddle else privacy.offer_private(pony)


## The runtime's Agreement start result, forwarded to the Negotiation service.
func _report_agreement(handle: Variant, started: bool) -> void:
	if is_instance_valid(negotiation):
		negotiation.call("report", handle, started)


## Clear the act-key hint and its cached offer.
func _clear_offer_hint() -> void:
	clear_current()
	if is_instance_valid(hud):
		hud.call("hide_prompt")


func _toast(text: String) -> void:
	if text.is_empty():
		return
	HUD.toast(text, 4.0)


## A settings edit: the key cap in the hint row is rebuilt on the next frame.
func apply_settings() -> void:
	_clear_native_hint()


## The world entered: drop the old scan and parse the two offerable pose assets while the world is
## still under its loading cover, so the first hint never loads them inside its scan.
func on_world(_host: Node) -> void:
	on_world_closed()
	for pose: String in [POSE_SPECS.MISSIONARY, POSE_SPECS.STANDING]:
		var asset_path := str(POSE_SPECS.spec(pose).get("asset", ""))
		POSES.warm_asset(asset_path)


## A world enter or a world close: drop the offer, the gate verdict, the one-shot flags and the
## hint row of the world that is gone.
func on_world_closed() -> void:
	_offer = null
	_offer_blocked = null
	_offer_clock = 0.0
	_gate_target = null
	_gate_at = 0.0
	_gate_ready = false
	_gate_stool_need = 0
	_gate_stool_have = 0
	_last_offer_key = ""
	_last_blocked_key = ""
	_stool_hint_toast_shown = false
	_clear_native_hint()


## The scan order: the Agreement, then the two bed rows, then the standing cone and gate.
func scan() -> void:
	_offer = null
	_offer_blocked = null
	if not is_instance_valid(WORLD.player) or not is_instance_valid(WORLD.game):
		return
	var tree := get_tree()
	if tree == null or tree.paused:
		return
	if DisplayServer.get_name() != "headless" and not WORLD.headset_view() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var view: Camera3D = WORLD.camera()
	if view == null:
		return
	var form: Dictionary = PLAYER_FORM.active(tree)
	var pony_form: bool = PLAYER_FORM.is_pony(form)

	# A live Agreement owns the hint while it is ready: it is already a yes. While its rows wait
	# or the presentation turns, the context scan below still finds a hotkey attempt, so a press
	# can start the exact match immediately or interrupt a different one.
	if is_instance_valid(negotiation):
		var handle: Variant = negotiation.call("handle")
		if handle != null:
			var live: POSE_OFFER = agreement_offer(handle)
			if live != null:
				_offer = live
				_log_offer()
				return

	# Missionary now requires Anon to be seated/lying on the bed with a pony lying there. A
	# standing or cradling Anon has no valid missionary camera, so that entry is not offered.
	if not pony_form and is_instance_valid(WORLD.player) and WORLD.player.get("seat") != null:
		var lying: Node = _bedside_pony(view)
		if is_instance_valid(lying):
			var runtime: Node = PONIES.runtime_for(lying)
			if is_instance_valid(runtime):
				var bed: Node3D = _gate(runtime).find_bed_under()
				if bed != null and bool(_gate(runtime).hotkey_ready(CATALOG.MISSIONARY, "bed_side", bed)):
					_offer = _new_offer(runtime, lying, CATALOG.MISSIONARY, "bed_side", bed)
					_log_offer()
					return

	# Missionary, AnonPony: an awake pony already lying on a bed.
	if pony_form:
		var lying: Node = _nearest_lying(view)
		if is_instance_valid(lying):
			var runtime: Node = PONIES.runtime_for(lying)
			if is_instance_valid(runtime):
				var bed: Node3D = _gate(runtime).find_bed_under()
				if bed != null and bool(_gate(runtime).hotkey_ready(CATALOG.MISSIONARY, "already_lying", bed)):
					_offer = _new_offer(runtime, lying, CATALOG.MISSIONARY, "already_lying", bed)
					_log_offer()
					return

	# Standing: Anon in the cone behind her rump, no crosshair aim. Only clearance and the scene
	# rows make her ready.
	var timed := LOG.idle_on()
	var cone_started := Time.get_ticks_usec() if timed else 0
	var standing: Node = _rump_cone_target(view)
	if timed:
		LOG.note("offer_cone", Time.get_ticks_usec() - cone_started)
	if is_instance_valid(standing):
		var runtime: Node = PONIES.runtime_for(standing)
		if is_instance_valid(runtime):
			var gate_started := Time.get_ticks_usec() if timed else 0
			var ready := _standing_ready(standing, runtime)
			if timed:
				LOG.note("offer_gate", Time.get_ticks_usec() - gate_started)
			if ready:
				_offer = _new_offer(runtime, standing, CATALOG.STANDING, "", null)
				_log_offer()
			else:
				var need := _gate_stool_need
				if need > 0 and _gate_stool_have < need:
					var blocked_offer := _new_offer(runtime, standing, CATALOG.STANDING, "", null)
					blocked_offer.blocked = _blocked_record(need, _stool_hint_for(need))
					_offer_blocked = blocked_offer
					_log_blocked_offer(runtime, standing, need)


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


## The standing gate, with one mare's verdict reused across scans. The act key runs it again on
## every press, so a stale yes can only hide the hint, never start an act.
func _standing_ready(target: Node, runtime: Node) -> bool:
	var now := Time.get_ticks_msec() * 0.001
	if target == _gate_target and now - _gate_at < GATE_REFRESH_S:
		return _gate_ready
	_gate_target = target
	_gate_at = now
	_gate_ready = bool(_gate(runtime).hotkey_ready(CATALOG.STANDING, "", null))
	_gate_stool_need = 0
	_gate_stool_have = 0
	if not _gate_ready:
		var stool: Dictionary = _gate(runtime).hint_stool()
		_gate_stool_need = int(stool.get("need", 0))
		_gate_stool_have = int(stool.get("have", 0))
	return _gate_ready


## Build one typed offer for the idle scan. The idle offers carry no cancel callback because a
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


## The standing act-key zone: the nearest standing mare whose rear cone holds Anon. Only the cone
## decides; the crosshair may point anywhere.
func _rump_cone_target(view: Camera3D) -> Node:
	if not is_instance_valid(view):
		return null
	var eye: Vector3 = view.global_position
	# Geometry first: a profile resolve is expensive, so only in-cone candidates pay for it and
	# only while they beat the nearest eligible find. One pass keeps the scan allocation-free.
	var best: Node3D = null
	var best_distance := INF
	for node: Variant in WORLD.mares():
		if not is_instance_valid(node):
			continue
		var actor: Node3D = node as Node3D
		if actor == null or not actor.has_method("posture_status"):
			continue
		if str(actor.posture_status().get("requested", "")) != "stand":
			continue
		var runtime: Node = PONIES.runtime_for(actor)
		if not is_instance_valid(runtime):
			continue
		var anchor: Variant = _gate(runtime).rump_anchor()
		if not anchor is Vector3:
			continue
		var rump: Vector3 = anchor
		if not rump.is_finite():
			continue
		if not RUMP_CONE.contains(actor.global_basis.z, rump, eye):
			continue
		var flat := Vector3(eye.x - rump.x, 0.0, eye.z - rump.z)
		var distance := flat.length()
		if distance > RUMP_CONE.REACH_M or distance >= best_distance:
			continue
		if not PONIES.act_target(actor):
			continue
		best_distance = distance
		best = actor
	return best


func _native_row() -> HBoxContainer:
	# The row is read every frame, so it is cached: the path lookup allocates a NodePath and walks
	# the tree, and the game keeps the same hints node and row for the whole world.
	if is_instance_valid(_native_hint_row) and _native_hint_row.is_inside_tree():
		return _native_hint_row
	_native_hint_row = null
	if not is_instance_valid(_native_hints_node) or _native_hints_node.get_parent() != WORLD.game:
		_native_hints_node = WORLD.game.get_node_or_null("InteractionHints") \
			if is_instance_valid(WORLD.game) else null
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
				hud.call("hide_prompt")
			else:
				hud.call("show_prompt", text, "",
					_act_key_label() if text == OFFER_HINT else "")
		return
	# The scan changes the hint at most once a second; the common frame has nothing to apply, so it
	# returns before the label checks and the container pokes.
	if text == _native_hint_text:
		if text.is_empty():
			return
		if is_instance_valid(_native_hint_label) and _native_hint_label.get_parent() == row:
			return
	if text.is_empty():
		_remove_native_hint(row)
		if is_instance_valid(hud):
			hud.call("hide_prompt")
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
		hud.call("hide_prompt")


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
	var gap: Variant = _gate(runtime).stool_gap_m()
	var gap_text := "n/a" if not (gap is float or gap is int) \
		or not is_finite(float(gap)) else "%.3f" % float(gap)
	var have := int(_gate(runtime).stool_case_count())
	LOG.debug("OFFER blocked pony=%s reason=needs_stool gap=%s need=%d have=%d", [
		str(target.name), gap_text, need, have])
	if not _stool_hint_toast_shown:
		_stool_hint_toast_shown = true
		HUD.toast(_stool_find_hint(need), 4.0)


## A live Agreement typed as a press offer; no rump fan or policy snapshot is needed.
## Null while the world is not ready.
func agreement_offer(handle: NEGOTIATION.AGREEMENT.Handle) -> POSE_OFFER:
	if handle == null:
		return null
	var pony: Variant = handle.pony
	var runtime: Node = PONIES.runtime_for(pony) if is_instance_valid(pony) else null
	var gate: Variant = _gate(runtime) if is_instance_valid(runtime) else null
	if gate == null:
		return null
	if not bool(gate.agreement_offer_ready(handle)):
		return null
	var option: Variant = handle.option
	if option == null:
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


func _bedside_pony(_view: Camera3D) -> Node:
	# The player's bed/couch seat knows exactly who lies beside Anon.
	if is_instance_valid(WORLD.player):
		var seat: Variant = WORLD.player.get("seat")
		if is_instance_valid(seat) and seat.has_meta("couch"):
			var couch: Variant = seat.get_meta("couch")
			if is_instance_valid(couch) and couch.has_method("partner"):
				var partner: Variant = couch.call("partner", seat)
				if partner is Node and is_instance_valid(partner) and PONIES.act_target(partner):
					return partner
	return null


func _nearest_lying(view: Camera3D) -> Node:
	if view == null:
		return null
	var best: Node
	var best_dot := 0.78
	var forward := -view.global_basis.z
	for node: Variant in WORLD.mares():
		if not is_instance_valid(node):
			continue
		var actor: Node3D = node as Node3D
		if actor == null or not actor.has_method("posture_status"):
			continue
		if not PONIES.act_target(actor):
			continue
		var status: Dictionary = actor.posture_status()
		if str(status.get("requested", "")) != "lie_down":
			continue
		var at := actor.global_position + Vector3.UP * 0.5
		var delta := at - view.global_position
		if delta.length() > 3.2:
			continue
		var dot := forward.dot(delta.normalized())
		if dot > best_dot:
			best_dot = dot
			best = actor
	return best
