extends Node
## Service: offer
## Contract: docs/offer.md
## Scope: world
## Import: offer/service.gd only
##
##   offer = OFFER.new()
##   offer.runtime_for = Callable(PONIES, "runtime_for")
##   offer.act_target = Callable(PONIES, "act_target")
##   offer.act_live = Callable(PONIES, "act_running")
##   offer.negotiation = negotiation
##   offer.privacy = privacy
##   add_child(offer)
##
## The idle act offer: the one-second scene scan, the standing gate behind it, the typed offer the
## act key would start, the footstool block and the "Make love" hint beside the game's prompt row.
## It also owns the act start that follows a scan: the act key's press, the hotkey attempt, the
## live Agreement start and the Agreement's own auto-start. Every scene read is `WORLD`; the
## pony registry, the act-target rule and the live act reach this service as the callables the
## entry binds, so it never preloads the runtime or the registry.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
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

## The offer hint beside the game's prompt row: a single act-key press starts the act, so it reads
## like the base game's tap prompts ("G · Carry"), not a hold. Only holding the act key during an
## act is a hold.
const OFFER_HINT := "Make love"
## The idle offer hint's scan cadence.
const OFFER_SCAN_S := 1.0
## The standing gate's refresh cadence while the same mare stays the cone target; the scan reads
## the cone every `OFFER_SCAN_S`, the full gate is the expensive half.
const GATE_REFRESH_S := 2.0
## The standing-act note when her reach needs a footstool and Anon has none in the case.
const NEEDS_STOOL_HINT := "Needs a footstool"
## The Agreement auto-start's readiness cadence.
const AGREEMENT_START_S := 0.25
## The runtime's Agreement start answer, the protocol `runtime.start_agreement()` returns: a
## transient row or an unsettled presentation waits, a technical rollback is a failure. It is
## restated here because a service never preloads the runtime; `tests/offer/test_start.gd` holds
## the two in agreement.
const AGREEMENT_WAIT := 0
const AGREEMENT_STARTED := 1

## Set by the entry: (Node pony) -> its live runtime, or null.
var runtime_for := Callable()
## Set by the entry: (Variant pony) -> bool, the act-target capability.
var act_target := Callable()
## Set by the entry: () -> bool, true while an act owns the frame.
var act_live := Callable()
## Set by the entry: the Negotiation service, whose live Agreement is offered before the scan. A
## plain handle because this side only calls its public reads, and `agreement_offer()` keeps the
## typed `AGREEMENT.Handle` contract.
var negotiation: Node = null
## Set by the entry: the privacy provider, resampled before a private Agreement auto-starts.
var privacy: PRIVACY = null
## Set by the entry: the HUD, once the player rig arrives.
var hud: Node = null

## The idle scan's playable offer and its blocked variant. Both are typed `PoseOffer` handles;
## null means none.
var _offer: POSE_OFFER = null
var _offer_blocked: POSE_OFFER = null
var _offer_clock := 0.0
## The standing gate's last verdict and its footstool pair, reused while the same mare stays the
## cone target. See `_standing_ready()`.
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


## The current offer's pony, for the Proactive service's cuddle check. It reads the scan result
## and never rescans: the loop owns the cadence.
func offer_target() -> Node:
	if _offer == null:
		return null
	var target: Variant = _offer.pony
	return target if is_instance_valid(target) else null


## The playable offer the act key would start, or null.
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


## The act key's one start entry. The act key is the hotkey: it always accepts, never bucks or
## refuses, and a missing context pose is no attempt. The tolerance stop owns the refusal path.
func try_start() -> bool:
	if _act_live():
		return false
	scan()
	if _offer == null:
		if _offer_blocked != null:
			return start_pose_offer(_offer_blocked)
		LOG.debug("hotkey no context pose")
		_toast("There is nothing to start here.")
		return false
	return start_pose_offer(_offer)


## The one typed act-start path. The act key and the Agreement auto-start call this. The offer
## carries its pose and trigger, so this function never names a pose.
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


## The hotkey: a live Agreement's exact match starts it immediately and skips the presentation;
## any other live negotiation or Agreement is interrupted and the immediate attempt runs. The
## attempt is Base clearance plus the scene-only rows, with no offer cooldown.
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
				LOG.debug("hotkey exact match id=%s pose=%s" % [id, offer.pose])
				return _start_agreement_offer(offer, true)
			LOG.debug("hotkey interrupt agreement id=%s" % id)
			negotiation.call("interrupt_for_hotkey")
		elif bool(negotiation.call("is_locked")):
			LOG.debug("hotkey interrupt negotiation id=%s" % id)
			negotiation.call("interrupt_for_hotkey")
	LOG.debug("hotkey immediate id=%s pose=%s source=%s" % [id, offer.pose, offer.source])
	var started := bool(runtime.call("start_hotkey", offer.pose, offer.bed, offer.source))
	if not started:
		LOG.debug("hotkey start blocked id=%s pose=%s source=%s" % [id, offer.pose, offer.source])
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


## The act key consumes a live Agreement through its scene-only start. `WAIT` keeps the hint and
## the Agreement for the next press; a started or failed attempt clears the hint and hands the
## result to the Negotiation service. `skip_presentation` is the exact hotkey match.
func _start_agreement_offer(offer: POSE_OFFER, skip_presentation: bool) -> bool:
	var handle: Variant = negotiation.call("handle") if is_instance_valid(negotiation) else null
	if handle == null or not is_instance_valid(offer.runtime):
		_clear_offer_hint()
		return false
	var result := int(offer.runtime.call("start_agreement", handle, skip_presentation))
	var id := PONY_ID.from(str(offer.pony.get_meta("relationship_id", "")),
		offer.pony.get("identity")) if is_instance_valid(offer.pony) else "?"
	LOG.debug("agreement start id=%s pose=%s skip_presentation=%s result=%d" % [
		id, offer.pose, str(skip_presentation), result])
	if result == AGREEMENT_WAIT:
		LOG.debug("agreement start waiting pose=%s source=%s" % [offer.pose, offer.source])
		return false
	_clear_offer_hint()
	_report_agreement(handle, result == AGREEMENT_STARTED)
	return result == AGREEMENT_STARTED


## The Agreement's automatic start: it waits for the presentation to settle and Anon to be in
## position, then consumes the handle with no key press. A live act, a menu, a paused tree or a
## loose cursor holds it. A private Agreement takes a fresh privacy sample; the exact hotkey match
## does not, because a live Agreement's own visibility wins for that press.
func _tick_agreement_auto_start(delta: float) -> void:
	if _act_live() or not is_instance_valid(negotiation):
		return
	# The clock runs before the handle read so the common frame pays one arithmetic step: a
	# handle that appears between polls is consumed on the next one, 0.25 s later at most.
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
	var runtime: Node = _runtime_for(pony) if is_instance_valid(pony) else null
	if not is_instance_valid(runtime) or not runtime.has_method("agreement_offer_ready"):
		return
	var typed: POSE_OFFER = agreement_offer(handle)
	if typed == null:
		return
	var option: Variant = handle.option
	var cuddle := option != null and bool(option.cuddle)
	var pony_id := str(handle.pony_id)
	if pony_id.is_empty() and is_instance_valid(pony):
		pony_id = PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))
	LOG.debug("agreement auto-start id=%s pose=%s" % [pony_id, typed.pose])
	if bool(handle.private) and not _agreement_private_now(pony, cuddle):
		LOG.debug("agreement auto-start privacy lost pony=%s" % str(pony.name))
		negotiation.call("cancel", handle, "privacy")
		return
	LOG.debug("agreement auto-start pony=%s pose=%s" % [str(pony.name), typed.pose])
	_start_agreement_offer(typed, false)


## A fresh privacy sample for the auto-start, with the offer's cuddle rule. A missing provider
## reads as public, so a private Agreement does not start on a stale answer.
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


## A world enter or a world close: no offer, no gate verdict, no one-shot flags, and the hint row
## is detached from the world that is gone.
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


## One full scan: the live Agreement first, then the bed-side and already-lying missionary rows,
## then the standing cone and its gate.
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
			var runtime: Node = _runtime_for(lying)
			if is_instance_valid(runtime):
				var bed: Node3D = runtime.find_bed_under()
				if bed != null and bool(runtime.call("hotkey_ready", CATALOG.MISSIONARY, "bed_side", bed)):
					_offer = _new_offer(runtime, lying, CATALOG.MISSIONARY, "bed_side", bed)
					_log_offer()
					return

	# Missionary, AnonPony: an awake pony already lying on a bed.
	if pony_form:
		var lying: Node = _nearest_lying(view)
		if is_instance_valid(lying):
			var runtime: Node = _runtime_for(lying)
			if is_instance_valid(runtime):
				var bed: Node3D = runtime.find_bed_under()
				if bed != null and bool(runtime.call("hotkey_ready", CATALOG.MISSIONARY, "already_lying", bed)):
					_offer = _new_offer(runtime, lying, CATALOG.MISSIONARY, "already_lying", bed)
					_log_offer()
					return

	# Standing: Anon must stand in the cone behind her rump. No crosshair aim is needed. The
	# hotkey readiness is Base clearance plus the scene-only rows, with no policy snapshot.
	var timed := LOG.idle_on()
	var cone_started := Time.get_ticks_usec() if timed else 0
	var standing: Node = _rump_cone_target(view)
	if timed:
		LOG.note("offer_cone", Time.get_ticks_usec() - cone_started)
	if is_instance_valid(standing):
		var runtime: Node = _runtime_for(standing)
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


## The hint beside the game's prompt row: the offer, else the blocked note, else nothing. No
## offer of either kind clears both logged keys, so the same offer logs again when it returns.
func _hint_text() -> String:
	if _offer != null:
		return OFFER_HINT
	if _offer_blocked != null:
		var blocked_hint := _offer_blocked.blocked_hint()
		return blocked_hint if not blocked_hint.is_empty() else NEEDS_STOOL_HINT
	_last_offer_key = ""
	_last_blocked_key = ""
	return ""


## A pony's live runtime, through the bound read.
func _runtime_for(pony: Node) -> Node:
	if not runtime_for.is_valid() or not is_instance_valid(pony):
		return null
	var runtime: Variant = runtime_for.call(pony)
	return runtime if is_instance_valid(runtime) else null


## The act-target capability, through the bound read.
func _act_target(pony: Variant) -> bool:
	if not act_target.is_valid() or not is_instance_valid(pony):
		return false
	return bool(act_target.call(pony))


## True while an act owns the frame, through the bound read. An unbound read means no act.
func _act_live() -> bool:
	return act_live.is_valid() and bool(act_live.call())


## The standing gate, with its verdict reused while the same mare stays the cone target. The full
## gate costs about half a millisecond (the scene rows, the pose rows and her relationship ladder),
## and its inputs change on a state transition the cone scan cannot see, so it is refreshed every
## `GATE_REFRESH_S`. The act key runs the gate again on every press, so a reused verdict can only
## hold the hint back, never start or block an act.
func _standing_ready(target: Node, runtime: Node) -> bool:
	var now := Time.get_ticks_msec() * 0.001
	if target == _gate_target and now - _gate_at < GATE_REFRESH_S:
		return _gate_ready
	_gate_target = target
	_gate_at = now
	_gate_ready = bool(runtime.call("hotkey_ready", CATALOG.STANDING, "", null))
	_gate_stool_need = 0
	_gate_stool_have = 0
	if not _gate_ready:
		var stool: Dictionary = runtime.call("hint_stool")
		_gate_stool_need = int(stool.get("need", 0))
		_gate_stool_have = int(stool.get("have", 0))
	return _gate_ready


## Build one typed offer for the idle scan. A live Agreement press is consumed by the scene-only
## start, not a request close, so the idle offers carry no cancel callback.
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


## The standing act-key zone: the nearest standing mare whose rear cone holds Anon. The cone alone
## decides, so the crosshair can point anywhere as long as he stands behind her rump.
func _rump_cone_target(view: Camera3D) -> Node:
	if not is_instance_valid(view):
		return null
	var eye: Vector3 = view.global_position
	# Geometry first: eligibility resolves a whole profile per mare, so only the in-cone
	# candidates pay for it, and only while they beat the nearest eligible one already found.
	# One pass keeps the scan allocation-free: the scan runs every second in the frame.
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
		var runtime: Node = _runtime_for(actor)
		if not is_instance_valid(runtime):
			continue
		var anchor: Variant = runtime.call("rump_anchor")
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
		if not _act_target(actor):
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


## The offer hint is one more unit in the game's own prompt row, in that row's style and phrasing
## ("Hold G · Bridal carry" reads as "Hold: ..."), so it sits beside base prompts unnoticed.
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


## The act key's key cap label, read when a hint row is built and never per frame.
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
	var gap: Variant = runtime.call("stool_gap_m")
	var gap_text := "n/a" if not (gap is float or gap is int) \
		or not is_finite(float(gap)) else "%.3f" % float(gap)
	var have := int(runtime.call("stool_case_count"))
	LOG.debug("OFFER blocked pony=%s reason=needs_stool gap=%s need=%d have=%d" % [
		str(target.name), gap_text, need, have])
	if not _stool_hint_toast_shown:
		_stool_hint_toast_shown = true
		HUD.toast(_stool_find_hint(need), 4.0)


## The live Agreement as the act key's own typed offer. It is a yes already, so the rump fan and
## the policy snapshot do not rediscover it; the scene-only rows and the settled presentation
## decide the hint. Null while the world is not ready.
func agreement_offer(handle: NEGOTIATION.AGREEMENT.Handle) -> POSE_OFFER:
	if handle == null:
		return null
	var pony: Variant = handle.pony
	var runtime: Node = _runtime_for(pony) if is_instance_valid(pony) else null
	if not is_instance_valid(runtime) or not runtime.has_method("agreement_offer_ready"):
		return null
	if not bool(runtime.call("agreement_offer_ready", handle)):
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
	LOG.debug("OFFER pony=%s pose=%s source=%s bed=%s pending=%s" % [
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
				if partner is Node and is_instance_valid(partner) and _act_target(partner):
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
		if not _act_target(actor):
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
