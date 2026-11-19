extends Node
## The debug actions: every Debug block button and wheel slot, the show-data collector, the wheel
## gate and the skeleton overlay. The entry adds this one node; `debug/service.gd` dispatches to it
## and the registry's `target` is this node. See `docs/debug.md`.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const ACT_FACE := preload("res://mods/unfplap/shared/act_face.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_CHANGE_SERVICE := preload("res://mods/unfplap/body_change/service.gd")
const INITIATION := preload("res://mods/unfplap/initiation/service.gd")
const NEGOTIATION := preload("res://mods/unfplap/negotiation/service.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")
const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/service.gd")
const DEBUG_BED := preload("res://mods/unfplap/debug/bed.gd")
const DEBUG_PONY := preload("res://mods/unfplap/debug/pony.gd")
const DEBUG_STRETCH := preload("res://mods/unfplap/debug/idle_stretch.gd")
const DEBUG_SKELETON := preload("res://mods/unfplap/debug/skeleton.gd")
const DEBUG_WHEEL := preload("res://mods/unfplap/debug/wheel.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
## The debug name action cycles these shipped adult mares, so the lab can test more than one fit
## without a text prompt. Player-named shapes belong to the dialogue path.
const FORM_DEBUG_SHAPES := ["fluttershy", "rarity", "applejack", "pinkie_pie", "twilight_sparkle"]


## The live act state. The entry binds these named reads once instead of handing over the
## registry, so the actions node never preloads `ponies`.
class Host extends RefCounted:
	## -> the live act's runtime, or null.
	var act := Callable()
	## (Node pony) -> Node runtime.
	var runtime_for := Callable()
	## -> Array of every live runtime node.
	var runtimes := Callable()
	## (Variant pony) -> bool, the act-target capability.
	var act_target := Callable()
	## -> String, the authored pose re-read behind Reload posed base; "" on success.
	var reload_posed_base := Callable()


## Set by the entry at construction.
var host: Host = null
## Set by the entry: the body-change service, the offer service and the Negotiation service.
var body_change: BODY_CHANGE_SERVICE = null
var initiation: INITIATION = null
var negotiation: NEGOTIATION = null
## Plain handles, set by the entry. The anatomy facade stays untyped because the placement editor
## reads its aim rule from `debug/service.gd`; a typed import here would close a service cycle.
var anatomy: Node = null
var pantyhose: Node = null

var _debug_skeleton: Node3D
var _debug_wheel: CanvasLayer
## The installed Idle Life entry node, for the deep-stretch action.
var _idle_life: Node
var _debug_face_index := -1
var _form_shape_index := 0


func _ready() -> void:
	DEBUG_ACTIONS.target = self


func _exit_tree() -> void:
	if DEBUG_ACTIONS.target == self:
		DEBUG_ACTIONS.target = null


## The installed Idle Life entry node, when that mod is on; the deep-stretch action uses it.
func on_idle_life(node: Node) -> void:
	_idle_life = node if node.has_method("play") else null


## Debug Actions entries (`DEBUG_ACTIONS.ACTIONS`). The offer helper forces a proactive request for
## the aimed mare, bypassing the quiet/cooldown/AI-usage checks so the lab can test requests with
## ai_usage=talk.
func action_bed_offer() -> String:
	return _debug_offer_request(CATALOG.MISSIONARY)


func action_standing_offer() -> String:
	return _debug_offer_request(CATALOG.STANDING)


## Debug: form an Anon offer for the aimed mare as if Anon had just asked her. The classifier still
## decides the option and the response; this only skips typing the line in a conversation.
func action_anon_offer() -> String:
	if not is_instance_valid(negotiation) or not is_instance_valid(WORLD.player):
		return "Act system not ready."
	var target: Node = _aim()
	if not is_instance_valid(target):
		return "No mare under the crosshair."
	var runtime: Node = _runtime_for(target)
	if not is_instance_valid(runtime):
		return "No runtime for %s." % str(target.name)
	var formed := negotiation.begin_anon_offer(runtime, "I want you. Come here.")
	LOG.debug("anon offer button: %s formed=%s" % [str(target.name), str(formed)])
	if formed:
		return "Anon offer started for %s." % str(target.name)
	return "Anon offer refused for %s." % str(target.name)


## Wheel-only: start the stock bed cuddle. The bed, recline and invite sequence runs after this
## returns, so the wheel closes immediately and the debug log carries the detailed result.
func action_bed_cuddle() -> String:
	if not is_instance_valid(WORLD.player):
		return "Player not ready."
	var target: Node = _aim()
	if not is_instance_valid(target):
		return "No pony under the crosshair."
	if not is_instance_valid(DEBUG_BED.find_bed(self)):
		return "No bed found in this house."
	_bed_cuddle_sequence(target)
	return "Bed cuddle started for %s." % str(target.name)


func _bed_cuddle_sequence(target: Node) -> void:
	var result: String = await DEBUG_BED.invite(self, target)
	LOG.debug("bed cuddle: " + result)


## Wheel-only: play Idle Life's deep stretch on the live act's pony, else the aimed mare. It
## ignores her posture and a live act, so the idle is forced to the end.
func action_deep_stretch() -> String:
	var target: Node = null
	var act: Node = _act()
	if is_instance_valid(act):
		var pony: Variant = act.get("pony")
		if pony is Node3D and is_instance_valid(pony):
			target = pony
	else:
		target = _aim()
	return DEBUG_STRETCH.stretch(_idle_life, target as Node3D)


## Wheel-only: qualify the aimed adult mare for the act gate. The helper clears her busy state,
## writes the game's bond record and a neutral mood; her romance tier is untouched.
func action_sex_ready() -> String:
	var target: Node = _aim()
	if not is_instance_valid(target) or not target is Node3D or not _is_act_target(target):
		return "No adult mare under the crosshair."
	return DEBUG_PONY.sex_ready(self, target as Node3D)


## Debug-only estrus phase controls. The override is session-only and per pony; `cycle_auto`
## clears it and resumes the automatic day/id cycle. A toggle's label follows the target's phase.
func action_toggle_heat() -> String:
	return _debug_cycle_toggle(CYCLE.HEAT)


func action_toggle_diestrus() -> String:
	return _debug_cycle_toggle(CYCLE.DIESTRUS)


func action_cycle_auto() -> String:
	return _debug_cycle_request("")


func _debug_cycle_toggle(phase_name: String) -> String:
	if not is_instance_valid(WORLD.player):
		return "Player not ready."
	var target: Node = _aim()
	if not is_instance_valid(target):
		return "No mare under the crosshair."
	var runtime: Node = _runtime_for(target)
	if not is_instance_valid(runtime) or not runtime.has_method("set_cycle_override"):
		return "No runtime for %s." % str(target.name)
	var current := str(runtime.call("cycle_phase")) if runtime.has_method("cycle_phase") else ""
	var next := CYCLE.NORMAL if current == phase_name else phase_name
	runtime.call("set_cycle_override", next)
	var verb := "cleared" if next == CYCLE.NORMAL else "forced"
	LOG.debug("cycle %s %s=%s" % [phase_name, str(target.name), next])
	return "%s %s for %s." % [phase_name.capitalize(), verb, str(target.name)]


## The aimed mare's effective estrus phase, or "" when there is no target.
func debug_cycle_phase() -> String:
	if not is_instance_valid(WORLD.player):
		return ""
	var target: Node = _aim()
	if not is_instance_valid(target):
		return ""
	var runtime: Node = _runtime_for(target)
	if not is_instance_valid(runtime) or not runtime.has_method("cycle_phase"):
		return ""
	return str(runtime.call("cycle_phase"))


func _debug_cycle_request(phase_name: String) -> String:
	if not is_instance_valid(WORLD.player):
		return "Player not ready."
	var target: Node = _aim()
	if not is_instance_valid(target):
		return "No mare under the crosshair."
	var runtime: Node = _runtime_for(target)
	if not is_instance_valid(runtime) or not runtime.has_method("set_cycle_override"):
		return "No runtime for %s." % str(target.name)
	runtime.call("set_cycle_override", phase_name)
	var label := "automatic" if phase_name.is_empty() else phase_name
	LOG.debug("cycle override %s=%s" % [str(target.name), label])
	return "Cycle for %s: %s." % [str(target.name), label]


## Debug form-change actions. They use the active source through the act's generic request when an
## act is live, and the source directly while idle. A source that is absent says so and does
## nothing; there is no global hotkey.
func action_form_true() -> String:
	return _form_change_request(true, "")


func action_form_name() -> String:
	var shape := str(FORM_DEBUG_SHAPES[_form_shape_index % FORM_DEBUG_SHAPES.size()])
	_form_shape_index += 1
	return _form_change_request(false, shape)


func action_form_idle() -> String:
	if is_instance_valid(_act()):
		return "Form: the act is already live."
	var source: Variant = _form_source()
	if source == null:
		return "No shape-changing mare."
	if not source.has_method("request_appear") or not bool(source.call("request_appear")):
		return "She cannot come out now."
	return "She is out or coming."


func _form_change_request(true_form: bool, shape_id: String) -> String:
	var label := "her true form" if true_form else SETTINGS.character_name(shape_id)
	var act: Node = _act()
	if is_instance_valid(act) and act.has_method("request_form_change"):
		var result: Variant = act.call("request_form_change", true_form, shape_id)
		if result is Dictionary:
			var answer: Dictionary = result
			LOG.debug("form change %s: %s" % [label, str(answer.get("reason", ""))])
			return str(answer.get("message", answer.get("reason", "")))
		return "Form change refused."
	var body := _form_body()
	if body == null or not is_instance_valid(body_change):
		return "No shape-changing mare."
	var started := false
	if true_form:
		started = body_change.request_own_form(body, BODY_CHANGE.Origin.PROVIDER)
	else:
		started = body_change.request_form(body, shape_id, BODY_CHANGE.Origin.PROVIDER)
	LOG.debug("form change idle %s started=%s" % [label, str(started)])
	if started:
		return "Changing to %s." % label
	return "She cannot take that form now."


## The aimed mare's body, else a live body an active source handles, for the idle debug request.
func _form_body() -> Node3D:
	var target: Node = _aim()
	if target is Node3D and _shape_source_for(target) != null:
		return target
	for pony: Variant in _runtimes():
		if pony is Node3D and is_instance_valid(pony) and _shape_source_for(pony) != null:
			return pony
	return null


## The aimed mare's source, else the first active one. The idle action only needs a source.
func _form_source() -> Variant:
	var target: Node = _aim()
	if is_instance_valid(target):
		var aimed: Variant = _shape_source_for(target)
		if aimed != null:
			return aimed
	if not is_instance_valid(body_change):
		return null
	var active := body_change.active_sources()
	if not active.is_empty():
		return active[0]
	return null


## Shared by the Debug actions.
func _debug_offer_request(pose := "") -> String:
	if not is_instance_valid(initiation) or not is_instance_valid(WORLD.player):
		return "Act system not ready."
	var target: Node = _aim()
	if not is_instance_valid(target):
		LOG.debug("request: no pony target")
		return "No mare under the crosshair."
	var runtime: Node = _runtime_for(target)
	if not is_instance_valid(runtime):
		LOG.debug("request: no runtime for %s" % str(target.name))
		return "No runtime for %s." % str(target.name)
	var result: INITIATION.ForceResult = initiation.force(runtime, pose)
	var started := result != null and result.ok
	var label := ""
	if pose == CATALOG.MISSIONARY:
		label = " (bed)"
	elif pose == CATALOG.STANDING:
		label = " (standing)"
	if started:
		LOG.debug("request button: %s%s" % [str(target.name), label])
		return "Offer started for %s%s." % [str(target.name), label]
	var reason := "unknown"
	if result != null and not result.reject.is_empty():
		reason = result.reject
	LOG.debug("request button reject %s%s reason=%s" % [str(target.name), label, reason])
	return "Offer rejected for %s%s: %s." % [str(target.name), label, reason]


## Debug: re-read the active pose's authored base without restarting. A running act picks the new
## pose up on its next frame, so the lab (export) -> game (reload) loop works while posing.
func action_reload_pose() -> String:
	var error := ""
	var act: Node = _act()
	if is_instance_valid(act):
		error = str(act.call("reload_pose_asset"))
	else:
		error = _reload_posed_base()
	if not error.is_empty():
		LOG.debug("pose reload failed: %s" % error)
		return "Pose reload failed: %s" % error
	if is_instance_valid(act) and act.has_method("_sync_missionary_pose_config"):
		act.call("_sync_missionary_pose_config")
	LOG.debug("pose reloaded")
	return "Reloaded the active posed base."


## Debug: toggle the internal standing_test pose in a live standing act. The edge holds the body;
## the reverse edge returns to standing. Never ends the act.
func action_pose_test_variant() -> String:
	var act: Node = _act()
	if not is_instance_valid(act):
		return "No act."
	var view: Variant = act.call("pose_view")
	var active := str(view.id) if view != null else ""
	if active.is_empty():
		return "No act."
	if active != CATALOG.STANDING and active != CATALOG.STANDING_TEST:
		return "Only in a standing act."
	var target := CATALOG.STANDING_TEST if active == CATALOG.STANDING else CATALOG.STANDING
	var result: Variant = act.call("request_pose", target, "debug")
	if result is Dictionary:
		var code := str((result as Dictionary).get("code", ""))
		LOG.debug("pose test variant %s -> %s: %s" % [active, target, code])
		return "Pose %s: %s." % [target, code]
	return "Pose request failed."


## Debug: toggle the internal bed face-sit in a live missionary act. The face-sit has no offer and
## no key; this button is its only trigger. The edge changes the arrangement and the contact and
## never ends the act.
func action_facesit_variant() -> String:
	var act: Node = _act()
	if not is_instance_valid(act):
		return "No act."
	var error := str(act.call("face_sit_error"))
	if not error.is_empty():
		LOG.debug("face-sit refused: %s" % error)
		return "Face-sit refused: %s." % error
	var view: Variant = act.call("pose_view")
	var active := str(view.id) if view != null else ""
	var target := CATALOG.BED_FACESIT if active == CATALOG.MISSIONARY else CATALOG.MISSIONARY
	var result: Variant = act.call("request_pose", target, "facesit")
	if result is Dictionary:
		var code := str((result as Dictionary).get("code", ""))
		LOG.debug("pose face-sit %s -> %s: %s" % [active, target, code])
		return "Pose %s: %s." % [target, code]
	return "Pose request failed."


## Debug: one structured dump for the aimed mare. Show data, and a future always-on overlay, can
## render the same sections: TARGET, CYCLE, GATE, REQUEST, ACT, STOOL, HISTORY, PROMPT, BED.
func action_show_data() -> String:
	if not is_instance_valid(WORLD.player):
		return "Player not ready."
	var target: Node = _aim()
	if not is_instance_valid(target):
		return "No pony under the crosshair."
	var data := debug_data(target)
	var rows: Array[String] = []
	for section: Variant in data.get("sections", []):
		if not section is Dictionary:
			continue
		var item: Dictionary = section
		rows.append(str(item.get("title", "")))
		for row: Variant in item.get("rows", []):
			rows.append("  " + str(row))
	LOG.block("DATA " + str(target.name), rows)
	return "Data written to the debug log for %s." % str(target.name)


## The structured per-mare collector. `ACT` is present only while this target owns the live act.
func debug_data(target: Node) -> Dictionary:
	var data := {"target": target, "sections": []}
	if not is_instance_valid(target):
		return data
	var runtime: Node = _runtime_for(target)
	var id := _debug_pony_id(target)
	var act: Node = _act()
	var sections: Array = data["sections"]
	sections.append(_debug_section("TARGET", _debug_target_rows(target, runtime, id)))
	sections.append(_debug_section("CYCLE", _debug_cycle_rows(runtime)))
	sections.append(_debug_section("GATE", _debug_gate_rows(target, runtime)))
	if is_instance_valid(initiation):
		sections.append(_debug_section("REQUEST", initiation.debug_rows(target)))
	else:
		sections.append(_debug_section("REQUEST", ["request service unavailable"]))
	if is_instance_valid(negotiation):
		sections.append(_debug_section("NEGOTIATION", negotiation.debug_rows(target)))
	else:
		sections.append(_debug_section("NEGOTIATION", ["negotiation service unavailable"]))
	if is_instance_valid(act) and runtime == act:
		sections.append(_debug_section("ACT", _debug_act_rows(runtime)))
	sections.append(_debug_section("STOOL", _debug_stool_rows(runtime)))
	sections.append(_debug_section("HISTORY", _debug_history_rows(target)))
	sections.append(_debug_section("PROMPT", _debug_prompt_rows(target)))
	sections.append(_debug_section("BED", DEBUG_BED.rows(self, target)))
	return data


func _debug_section(title: String, rows: Array) -> Dictionary:
	var lines: Array[String] = []
	for row: Variant in rows:
		lines.append(str(row))
	return {"title": title, "rows": lines}


func _debug_target_rows(target: Node, runtime: Variant, id: String) -> Array[String]:
	var state := "none"
	if is_instance_valid(runtime):
		state = "live" if runtime == _act() else "idle"
	return ["pony=%s id=%s" % [str(target.name), id if not id.is_empty() else "?"],
		"runtime=%s" % state]


func _debug_cycle_rows(runtime: Variant) -> Array[String]:
	if not is_instance_valid(runtime):
		return ["no runtime"]
	var phase := str(runtime.call("cycle_phase")) if runtime.has_method("cycle_phase") else "?"
	var override := str(runtime.call("cycle_override")) if runtime.has_method("cycle_override") else "?"
	return ["phase=%s override=%s" % [phase, override if not override.is_empty() else "none"],
		"heat=%s" % str(phase == CYCLE.HEAT)]


func _debug_gate_rows(target: Node, runtime: Variant) -> Array[String]:
	if not is_instance_valid(runtime):
		return ["no runtime"]
	var view: Camera3D = WORLD.camera()
	var dist := -1.0
	var dot := -1.0
	if is_instance_valid(view) and target is Node3D:
		var delta: Vector3 = (target as Node3D).global_position + Vector3.UP * 0.9 \
			- view.global_position
		dist = delta.length()
		if dist > 0.001:
			dot = (-view.global_basis.z).dot(delta.normalized())
	var pose := CATALOG.STANDING
	var source := ""
	var bed: Variant = null
	var status: Dictionary = target.call("posture_status") if target.has_method("posture_status") else {}
	if str(status.get("requested", "")) == "lie_down":
		pose = CATALOG.MISSIONARY
		source = "already_lying"
		bed = runtime.call("find_bed_under")
	var line := str(runtime.call("debug_line", pose, source, bed, dist, dot)) \
		if runtime.has_method("debug_line") else "no debug line"
	return [line]


func _debug_act_rows(runtime: Variant) -> Array[String]:
	var rows: Array[String] = [
		"state=%d pose=%s" % [int(runtime.get("state")), str(runtime.get("pose_id"))],
		"climaxes=%d satisfaction=%.2f" % [
			int(runtime.get("pony_climaxes")), float(runtime.get("satisfaction"))],
	]
	if runtime.has_method("act_face_rows"):
		rows.append("face:")
		for row: Variant in runtime.call("act_face_rows"):
			rows.append("  " + str(row))
	if runtime.has_method("pose_state_rows"):
		rows.append("pose state:")
		for row: Variant in runtime.call("pose_state_rows"):
			rows.append("  " + str(row))
	return rows


func _debug_stool_rows(runtime: Variant) -> Array[String]:
	if not is_instance_valid(runtime):
		return ["no runtime"]
	if not runtime.has_method("stool_state_text"):
		return ["stool unavailable"]
	return [str(runtime.call("stool_state_text"))]


## Debug: cycle the game's expression faces on the active act or the aimed mare.
func action_force_act_face() -> String:
	if not is_instance_valid(WORLD.player):
		return "Player not ready."
	var target: Node = _aim()
	if not is_instance_valid(target):
		return "No mare under the crosshair."
	_debug_face_index = (_debug_face_index + 1) % ACT_FACE.FACES.size()
	var face := str(ACT_FACE.FACES[_debug_face_index])
	var runtime: Node = _runtime_for(target)
	var shown := false
	if is_instance_valid(runtime) and runtime.has_method("force_act_face"):
		shown = bool(runtime.call("force_act_face", face))
	if not shown:
		shown = ACT_FACE.react(target, face, 3.0)
	LOG.debug("act face %s=%s shown=%s" % [str(target.name), face, str(shown)])
	return "Act face %s: %s%s." % [str(target.name), face,
		"" if shown else " (a spoken line owns the face)"]


## Debug: clear the aimed mare's proactive-offer cooldown and short retry.
func action_clear_cooldown() -> String:
	var target: Node = _aim()
	if not is_instance_valid(target):
		return "No mare under the crosshair."
	var name := str(target.name)
	if not is_instance_valid(initiation) or not initiation.clear_cooldown(target):
		return "No request state for %s." % name
	LOG.debug("request cooldown cleared %s" % name)
	return "Offer cooldown cleared for %s." % name


## Debug: clear the aimed mare's long-term act history.
func action_reset_act_history() -> String:
	if not is_instance_valid(WORLD.player):
		return "Act system not ready."
	var target: Node = _aim()
	if not is_instance_valid(target):
		return "No pony under the crosshair."
	var id := _debug_pony_id(target)
	if id.is_empty():
		return "No relationship id for %s." % str(target.name)
	var section: Dictionary = ACT_HISTORY.section()
	if not ACT_HISTORY.reset(section, id):
		return "No act history for %s." % str(target.name)
	ACT_HISTORY.save()
	LOG.debug("act history reset for %s" % id)
	return "Act history cleared for %s." % str(target.name)


## The stored act history, as Show data's HISTORY section.
func _debug_history_rows(target: Node) -> Array[String]:
	var id := _debug_pony_id(target)
	var rows: Array[String] = ["pony=%s id=%s" % [
		str(target.name), id if not id.is_empty() else "?"]]
	if id.is_empty():
		rows.append("no relationship id")
		return rows
	var row := ACT_HISTORY.effective_row(ACT_HISTORY.section(), id, ACT_HISTORY.day_now())
	var acts := int(row.get("acts", 0))
	if acts <= 0 and int(row.get("hurt", 0)) <= 0 and int(row.get("comfort", 0)) <= 0:
		rows.append("no history stored")
		return rows
	rows.append("tier=%s hurt=%d comfort=%d acts=%d good=%d bad=%d neutral=%d" % [
		ACT_HISTORY.tier_name(row), int(row.get("hurt", 0)), int(row.get("comfort", 0)),
		acts, int(row.get("good", 0)), int(row.get("bad", 0)), int(row.get("neutral", 0))])
	rows.append("streaks good=%d bad=%d announced=%d" % [
		int(row.get("streak_good", 0)), int(row.get("streak_bad", 0)),
		int(row.get("announced_tier", 0))])
	var reason_values: Array = row.get("last_reasons", [])
	var reason_text := ",".join(PackedStringArray(reason_values))
	rows.append("last grade=%s quality=%.2f reasons=%s" % [
		str(row.get("last_grade", "")), float(row.get("last_quality", 0.0)), reason_text])
	var text := str(row.get("last_text", "")).strip_edges()
	var wants := str(row.get("last_wants", "")).strip_edges()
	rows.append("last text=%s" % (text if not text.is_empty() else "none"))
	rows.append("wants=%s" % (wants if not wants.is_empty() else "none"))
	var stop_until := float(row.get("stop_until", 0.0))
	var now := Time.get_unix_time_from_system()
	if stop_until > now:
		rows.append("stop_until=%.0fs left (%s)" % [
			stop_until - now, str(row.get("last_stop_kind", ""))])
	var pending := ACT_HISTORY.pending_line(row)
	rows.append("pending=%s" % (pending if not pending.is_empty() else "none"))
	var recent: Variant = row.get("recent", [])
	if recent is Array and not (recent as Array).is_empty():
		rows.append("recent:")
		for entry: Variant in recent:
			if not entry is Dictionary:
				continue
			var item: Dictionary = entry
			var stamp := Time.get_datetime_string_from_unix_time(int(item.get("at", 0.0)), true)
			rows.append("- %s %.2f %s %s" % [
				str(item.get("grade", "")), float(item.get("quality", 0.0)), stamp,
				str(item.get("text", "")).strip_edges()])
	return rows


## The mod-owned parts of the next dialogue request, as Show data's PROMPT section.
func _debug_prompt_rows(target: Node) -> Array[String]:
	var id := _debug_pony_id(target)
	var rows: Array[String] = ["pony=%s id=%s" % [
		str(target.name), id if not id.is_empty() else "?"]]
	if id.is_empty():
		rows.append("no relationship id")
		return rows
	var runtime: Node = _runtime_for(target)
	if not is_instance_valid(runtime):
		rows.append("no runtime")
		return rows
	rows.append("prompt_note: " + str(runtime.call("prompt_note")))
	rows.append("cycle_note: " + str(runtime.call("cycle_note")))
	var history_row := ACT_HISTORY.effective_row(ACT_HISTORY.section(), id, ACT_HISTORY.day_now())
	var history_note := ACT_HISTORY.prompt_note(history_row)
	rows.append("history_note: " + (history_note if not history_note.is_empty() else "none"))
	var ctx: Variant = WORLD.game.get("world_context") if is_instance_valid(WORLD.game) else null
	if ctx != null and is_instance_valid(ctx):
		var events: Array = ctx.call("events_for", id, 10) if ctx.has_method("events_for") else []
		rows.append("recent events:")
		for event: Variant in events:
			if event is Dictionary:
				var item: Dictionary = event
				rows.append("  %s: %s" % [str(item.get("kind", "")), str(item.get("text", ""))])
		var impressions: Variant = ctx.get("impressions")
		if impressions != null and is_instance_valid(impressions) \
				and impressions.has_method("standing_line"):
			rows.append("standing_line: " + str(impressions.call("standing_line", id)))
	return rows


func action_reset_act_prompts() -> String:
	SETTINGS.reset_act_prompts()
	return "Act prompts reset to defaults."


func action_give_stool() -> String:
	if not is_instance_valid(WORLD.game):
		return "Act system not ready."
	var inventory: Variant = WORLD.game.get("inventory")
	if not is_instance_valid(inventory):
		return "No briefcase."
	var store: Variant = inventory.get("inventory")
	if store == null:
		return "No briefcase."
	var slot := int(store.call("grant", STOOL.ID, 1))
	if slot < 0:
		return "No room in the briefcase."
	LOG.debug("stool granted slot=%d" % slot)
	return "Footstool added."


## Rebuild the worn-garment depth field after a precision edit. The integration owns the cache
## and the scan; the actions node only forwards the button.
func action_pantyhose_rebuild() -> String:
	if not is_instance_valid(pantyhose):
		return "Pantyhose integration is not running."
	return str(pantyhose.call("rebuild_hull"))


func _debug_pony_id(target: Node) -> String:
	return PONY_ID.from(str(target.get_meta("relationship_id", "")), target.get("identity"))


func action_force_tolerance_warning() -> String:
	return _debug_force_tolerance("warning")


func action_force_tolerance_stop() -> String:
	return _debug_force_tolerance("stop")


func _debug_force_tolerance(kind: String) -> String:
	var act: Node = _act()
	if not is_instance_valid(act):
		return "No act is active."
	if not act.has_method("debug_force_tolerance"):
		return "The act cannot force a neglect warning."
	if not bool(act.call("debug_force_tolerance", kind)):
		return "Neglect forcing is only available during a live act."
	return "Neglect %s queued." % kind


## integration: the anatomy service owns the placement editor.
func _placement_debug(op: String, value := 0.0) -> String:
	if is_instance_valid(anatomy):
		return str(anatomy.call("placement_debug", op, value))
	return "Anatomy service unavailable."


func action_anatomy_up() -> String:
	return _placement_debug("y", 0.005)


func action_anatomy_down() -> String:
	return _placement_debug("y", -0.005)


func action_anatomy_forward() -> String:
	return _placement_debug("z", 0.005)


func action_anatomy_back() -> String:
	return _placement_debug("z", -0.005)


func action_anatomy_pitch_up() -> String:
	return _placement_debug("pitch", 1.0)


func action_anatomy_pitch_down() -> String:
	return _placement_debug("pitch", -1.0)


func action_anatomy_scale_up() -> String:
	return _placement_debug("scale", 0.02)


func action_anatomy_scale_down() -> String:
	return _placement_debug("scale", -0.02)


func action_tail_seat_up() -> String:
	return _placement_debug("tail_up", 0.005)


func action_tail_seat_down() -> String:
	return _placement_debug("tail_down", 0.005)


func action_tail_dock_up() -> String:
	return _placement_debug("dock_up", 0.005)


func action_tail_dock_down() -> String:
	return _placement_debug("dock_down", 0.005)


func action_tail_dock_scale_up() -> String:
	return _placement_debug("dock_scale_up", 0.05)


func action_tail_dock_scale_down() -> String:
	return _placement_debug("dock_scale_down", 0.05)


func action_tail_seat_forward() -> String:
	return _placement_debug("tail_forward", 0.005)


func action_tail_seat_back() -> String:
	return _placement_debug("tail_back", 0.005)


func action_tail_tilt_left() -> String:
	return _placement_debug("tail_tilt_left", 1.0)


func action_tail_tilt_right() -> String:
	return _placement_debug("tail_tilt_right", 1.0)


func action_placement_save() -> String:
	return _placement_debug("save")


func action_placement_reset() -> String:
	return _placement_debug("reset")


func action_placement_show() -> String:
	if is_instance_valid(anatomy):
		return str(anatomy.call("placement_show"))
	return "Anatomy service unavailable."


## The actions' optional `requires` gate. Only `shape_source` exists today: the form buttons stay
## off every surface while no shape-changing source is installed.
func shape_source_active() -> bool:
	return is_instance_valid(body_change) and body_change.active()


## The persisted Anatomy debug flag is the only switch; the overlay is live only while debug is on.
func sync_skeleton_overlay() -> void:
	var enabled := LOG.debug_logs and SETTINGS.skeleton_overlay.get_bool()
	if enabled:
		if not is_instance_valid(_debug_skeleton):
			_debug_skeleton = DEBUG_SKELETON.new()
			_debug_skeleton.name = "UnfplapSkeleton"
			_debug_skeleton.set("actions", self)
			add_child(_debug_skeleton)
		_debug_skeleton.set("enabled", true)
	elif is_instance_valid(_debug_skeleton):
		_debug_skeleton.set("enabled", false)


## The debug wheel is created lazily on the first middle press. The gate here keeps a pack with
## debug off from creating the node at all.
func debug_wheel_input(event: InputEvent) -> bool:
	if not is_instance_valid(_debug_wheel):
		if not LOG.debug_logs:
			return false
		if not event is InputEventMouseButton:
			return false
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_MIDDLE or not button.pressed:
			return false
		_debug_wheel = DEBUG_WHEEL.new()
		_debug_wheel.name = "UnfplapDebugWheel"
		_debug_wheel.set("actions", self)
		add_child(_debug_wheel)
	return bool(_debug_wheel.call("handle_input", event))


func debug_wheel_open() -> bool:
	return is_instance_valid(_debug_wheel) and bool(_debug_wheel.call("is_open"))


func close_debug_wheel() -> void:
	if is_instance_valid(_debug_wheel):
		_debug_wheel.call("close")


func debug_wheel_act_live() -> bool:
	return is_instance_valid(_act())


## The wheel's open gate: this frame's facts, handed to the facade's one ruled decision.
func debug_wheel_allowed() -> bool:
	var tree := get_tree()
	var viewport: Viewport = get_viewport() if tree != null else null
	var focus: Control = viewport.gui_get_focus_owner() if viewport != null else null
	return DEBUG_ACTIONS.wheel_gate(LOG.debug_logs,
		DisplayServer.get_name() == "headless",
		is_instance_valid(WORLD.player) and is_instance_valid(WORLD.game),
		tree != null and tree.paused, WORLD.headset_view(), DisplayServer.window_is_focused(),
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, WORLD.menu_open(),
		focus is LineEdit or focus is TextEdit,
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))


## The wheel's target: the active act's pony while an act runs, else the aimed mare.
func debug_wheel_context() -> Dictionary:
	var out := {"pony": null, "name": "No mare", "source": "none", "act": false}
	var act: Node = _act()
	if is_instance_valid(act):
		out["act"] = true
		var act_pony: Variant = act.get("pony")
		if is_instance_valid(act_pony):
			out["pony"] = act_pony
			out["name"] = str((act_pony as Node).name)
			out["source"] = "act"
			return out
		return out
	var target: Node = _aim()
	if is_instance_valid(target):
		out["pony"] = target
		out["name"] = str(target.name)
		out["source"] = "aimed"
	return out


## Run a wheel action, toast its one-line result and log it. Show data's multi-line block stays in
## the log; the toast only carries the summary.
func debug_wheel_action(name: String) -> String:
	var result := DEBUG_ACTIONS.run_action(name, self)
	LOG.debug("wheel %s: %s" % [name, result])
	if not result.is_empty():
		HUD.toast(result, 3.0)
	return result


func skeleton_click() -> bool:
	if not is_instance_valid(_debug_skeleton) or not bool(_debug_skeleton.get("enabled")):
		return false
	return bool(_debug_skeleton.call("handle_click"))


## The aimed mare: the closest mare to the camera's aim ray, else nothing.
func _aim() -> Node:
	return DEBUG_ACTIONS.aimed_pony(WORLD.camera())


func _act() -> Node:
	if host == null or not host.act.is_valid():
		return null
	var runtime: Node = host.act.call()
	return runtime if is_instance_valid(runtime) else null


func _runtime_for(pony: Node) -> Node:
	if host == null or not host.runtime_for.is_valid():
		return null
	var runtime: Node = host.runtime_for.call(pony)
	return runtime if is_instance_valid(runtime) else null


func _runtimes() -> Array:
	if host == null or not host.runtimes.is_valid():
		return []
	var list: Variant = host.runtimes.call()
	return list if list is Array else []


func _is_act_target(pony: Variant) -> bool:
	return host != null and host.act_target.is_valid() and bool(host.act_target.call(pony))


func _reload_posed_base() -> String:
	if host == null or not host.reload_posed_base.is_valid():
		return "no pose loader"
	return str(host.reload_posed_base.call())


func _shape_source_for(pony: Node) -> Variant:
	if not is_instance_valid(body_change) or not pony is Node3D:
		return null
	return body_change.source_for(pony as Node3D)
