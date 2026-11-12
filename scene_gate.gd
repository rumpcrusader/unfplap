extends RefCounted
## The scene half of the act gate and the refusal executor: the live state, cuddle, affection,
## navigator, player, pose, stool and bed rows, the bed search, the structural rows, the
## policy/scene merge, the start/offer verdicts, the debug status line, the buck/push refusal and
## its mood beat. Eligibility owns the policy. Contract: `docs/scene_gate.md`.

const ELIGIBILITY := preload("res://mods/unfplap/eligibility.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const REST := preload("res://mods/unfplap/rest_control.gd")
const MEMORY := preload("res://mods/unfplap/memory.gd")

const STATE_IDLE := 0

## The act's scene handles. The runtime binds them on every gate call.
var pony: Variant = null
var main: Variant = null
## The pose session, for the missionary asset/rig rows. Its facade answers both.
var pose_session: Variant = null

## The act identity and state the rows read.
var state := 0
var id := ""
var features: Dictionary = {}

## Host boundary. A missing callback is a no-op.
var stool_need := Callable()
var stool_count := Callable()
var request_face_active := Callable()
var release_carry := Callable()
## The runtime owns the refusal face; this only says whether the moment was a buck.
var on_refusal_face := Callable()
## The policy verdict and the debug context. The runtime supplies both; the gate never reads
## eligibility's own logic or the runtime's private fields.
var policy_verdict := Callable()
var debug_context := Callable()


## Bind the scene nodes and the pose session. A missing node fails the gate closed.
func bind(pony_node: Variant, main_node: Variant, session: Variant) -> void:
	pony = pony_node
	main = main_node
	pose_session = session


## The runtime's live gate values. The act state, id and feature snapshot change per act.
func configure(state_value: int, id_value: String, features_block: Dictionary) -> void:
	state = state_value
	id = id_value
	features = features_block


## The scene-only rows. They never enter the pure policy. `mode` is `start` or `offer`.
func rows(pose: String, act_source: String, bed_in: Variant, mode: String,
		forced: bool) -> Array:
	var rows_out: Array = []
	if not is_instance_valid(pony):
		return rows_out
	_row(rows_out, "state", state == STATE_IDLE, "state=%d" % state)
	var tree: SceneTree = pony.get_tree()
	_row(rows_out, "paused", forced or tree == null or not tree.paused, "paused")
	_row(rows_out, "conversation", conversation_ok(), "conversation")
	_row(rows_out, "sleeping", not pony.sleeping, "sleeping")
	_row(rows_out, "sex_active", not bool(pony.get_meta("sex_active", false)), "sex_active")
	_row(rows_out, "aftercare", not pony.has_meta("sex_aftercare"), "aftercare")
	_row(rows_out, "cuddle",
		not cuddle_active() or cuddle_start_override(pose, act_source), "cuddle")
	_row(rows_out, "affection", free_of_affection(), "affection")
	if mode == "start":
		_row(rows_out, "player", player_ready_for(pose, act_source, bed_in), "player")
	var nav: Node = pony.get_node_or_null("Navigator")
	if mode == "start":
		_row(rows_out, "navigator", nav != null, "no_navigator")
		if nav != null:
			_row(rows_out, "navigator_reserved",
				str(nav.get("reserved_by")) == "", "navigator_reserved")
			_row(rows_out, "nav_owner", nav_owner_allows(pose, act_source), "nav_owner")
		_row(rows_out, "nav_pose", nav_pose_gate(pose, act_source), "nav_pose")
	else:
		_row(rows_out, "nav_owner",
			nav != null and nav_owner_allows(pose, act_source), "nav_owner")
	if pose == CATALOG.STANDING:
		var need := needed_stool()
		_row(rows_out, "stool", need <= 0 or owned_stools() >= need, "needs_stool")
	if pose == CATALOG.MISSIONARY:
		var pose_ready := authored_ready()
		_row(rows_out, "pose_asset", pose_ready, authored_reason())
		if pose_ready:
			var missing := rig_missing()
			_row(rows_out, "pose_rig", missing.is_empty(), rig_reason(missing))
		var found: Node3D = resolve_bed(pose, act_source, bed_in)
		_row(rows_out, "bed", found != null, "no_bed")
		if found != null:
			_row(rows_out, "bed_occupied", not main.bed_occupied(found, pony), "bed_occupied")
			if mode == "start":
				_row(rows_out, "bed_gate", bed_gate(pose, act_source, found), "bed_gate")
	elif mode == "offer":
		if pose == CATALOG.STANDING:
			_row(rows_out, "standing_free",
				not pony.is_held() and not pony.has_meta("seated"), "standing_free")
		else:
			_row(rows_out, "pose", false, "pose")
	return rows_out


## The structural rows and the policy/scene merge. The runtime supplies the policy verdict and
## the debug context; the gate owns the merge and the debug string.
func start_verdict(pose: String, act_source: String, bed_in: Variant = null,
		verdict_in: ELIGIBILITY.Verdict = null) -> Dictionary:
	var data := _gate_data(pose, act_source, bed_in, "start", false, verdict_in)
	var policy: ELIGIBILITY.Verdict = data.get("policy")
	var scene_ok := bool(data.get("scene_ok", false))
	return {
		"show": policy != null and policy.show and scene_ok,
		"attempt": policy != null and policy.attempt and scene_ok,
		"buck_refuse": policy != null and policy.buck_refuse,
		"history_refuse": policy != null and policy.history_refuse and scene_ok,
		"rows": data.get("rows", []),
		"policy": policy,
	}


## The full proactive-offer gate. It uses the offer-safe scene subset.
func offer_verdict(pose: String, act_source: String, bed_in: Variant = null,
		forced := false, verdict_in: ELIGIBILITY.Verdict = null) -> Dictionary:
	var data := _gate_data(pose, act_source, bed_in, "offer", forced, verdict_in)
	var policy: ELIGIBILITY.Verdict = data.get("policy")
	var scene_ok := bool(data.get("scene_ok", false))
	return {
		"ok": policy != null and policy.offer and scene_ok,
		"rows": data.get("rows", []),
		"policy": policy,
	}


func _gate_data(pose: String, act_source: String, bed_in: Variant, mode: String,
		forced := false, verdict_in: ELIGIBILITY.Verdict = null) -> Dictionary:
	var structural: Array = []
	_gate_row(structural, "invalid_pony", is_instance_valid(pony), "invalid_pony")
	if not is_instance_valid(pony):
		return {"rows": structural, "policy": null, "scene_ok": false}
	_gate_row(structural, "no_main", is_instance_valid(main), "no_main")
	if not is_instance_valid(main):
		return {"rows": structural, "policy": null, "scene_ok": false}
	_gate_row(structural, "no_player", is_instance_valid(main.player), "no_player")
	if not is_instance_valid(main.player):
		return {"rows": structural, "policy": null, "scene_ok": false}
	_gate_row(structural, "no_game", is_instance_valid(main.game), "no_game")
	if not is_instance_valid(main.game):
		return {"rows": structural, "policy": null, "scene_ok": false}
	var policy_mode: ELIGIBILITY.Mode = ELIGIBILITY.Mode.OFFER if mode == "offer" \
		else ELIGIBILITY.Mode.START
	var policy: ELIGIBILITY.Verdict = _policy_verdict(policy_mode, verdict_in)
	var scene_rows: Array = rows(pose, act_source, bed_in, mode, forced)
	var rows_all: Array = structural.duplicate()
	if policy != null:
		for row: ELIGIBILITY.Row in policy.rows:
			rows_all.append(row)
	for row: Variant in scene_rows:
		rows_all.append(row)
	return {
		"rows": rows_all,
		"policy": policy,
		"scene_ok": _report_ok(scene_rows),
	}


func _policy_verdict(mode: ELIGIBILITY.Mode,
		verdict_in: ELIGIBILITY.Verdict = null) -> ELIGIBILITY.Verdict:
	if verdict_in != null:
		return verdict_in
	if policy_verdict.is_valid():
		return policy_verdict.call(mode, verdict_in)
	return null


func _gate_row(rows_out: Array, key: String, ok: bool, reason := "") -> void:
	var row := ELIGIBILITY.Row.new()
	row.key = key
	row.ok = ok
	row.reason = reason if not reason.is_empty() else key
	rows_out.append(row)


func _report_ok(rows_in: Array) -> bool:
	for row: ELIGIBILITY.Row in rows_in:
		if not row.ok:
			return false
	return true


## The failed reasons of a row list. The runtime's `offer_reasons` and `_start_reasons`
## read it; the gate's own debug line uses it too.
func report_reasons(rows_in: Array) -> PackedStringArray:
	var reasons: PackedStringArray = []
	for row: ELIGIBILITY.Row in rows_in:
		if not row.ok:
			reasons.append(row.reason)
	return reasons


func _policy_row_ok(policy: ELIGIBILITY.Verdict, key: String) -> bool:
	if policy == null:
		return true
	for row in policy.rows:
		if row.key == key:
			return row.ok
	return true


## The debug status line. The gate owns the row and verdict assembly; the runtime supplies the
## live act values through the context callback.
func debug_line(pose: String, act_source: String, bed_in: Variant = null,
		distance := -1.0, dot := -1.0) -> String:
	var context: Dictionary = debug_context.call() if debug_context.is_valid() else {}
	var gate := start_verdict(pose, act_source, bed_in)
	var policy: ELIGIBILITY.Verdict = gate.get("policy")
	var relations: ELIGIBILITY.Relations = policy.relations if policy != null \
		else ELIGIBILITY.Relations.new()
	var reasons: PackedStringArray = report_reasons(gate.get("rows", []))
	var reason_text := "none" if reasons.is_empty() else ",".join(reasons)
	var found_bed: Node3D = resolve_bed(pose, act_source, bed_in) if pose == CATALOG.MISSIONARY else null
	var bed_text := "n/a"
	if pose == CATALOG.MISSIONARY:
		bed_text = str(found_bed != null and bed_gate(pose, act_source, found_bed))
	var text := "pony=%s id=%s dist=%.2f dot=%.2f stage=%s love=%s(level%d) welcomes=%s bond=%s start=%s mood=%s | show=%s attempt=%s offer=%s buck=%s history=%s | state=%d presenting=%s sleep=%s held=%s grounded=%s seated=%s cuddle=%s motion=%s speed=%.2f posture=%s interrupt=%s | nav owner=%s target=%s reserved=%s | player locked=%s flying=%s seat=%s mouse=%s paused=%s | gates rel=%s form=%s romance=%s promiscuity=%s bondrow=%s cycle=%s historyrow=%s conv=%s aff=%s player=%s navowner=%s navpose=%s bed=%s | can_start=%s reasons=%s" % [
		str(context.get("display", "?")), str(context.get("id", "")),
		float(distance), float(dot), str(context.get("stage", "")),
		str(context.get("love_name", "?")), int(context.get("love_level", 0)),
		str(context.get("welcomes", false)), str(context.get("bond", false)),
		str(context.get("sex_start", "")), str(context.get("mood", "?")),
		str(bool(gate.get("show", false))), str(bool(gate.get("attempt", false))),
		str(policy != null and policy.offer), str(policy != null and policy.buck_refuse),
		str(policy != null and policy.history_refuse),
		int(context.get("state", 0)), str(context.get("presenting", false)),
		str(context.get("sleeping", false)), str(context.get("held", false)),
		str(context.get("grounded", false)), str(context.get("seated", false)),
		str(context.get("cuddle", false)), str(context.get("motion", false)),
		float(context.get("speed", 0.0)), str(context.get("posture", "")),
		str(context.get("interrupt", "")),
		str(context.get("owner", "")), str(context.get("target", false)),
		str(context.get("reserved", "")),
		str(context.get("body_controls_locked", "?")),
		str(context.get("body_flying", "?")), str(context.get("body_seat", "?")),
		str(context.get("mouse", "")), str(context.get("paused", false)),
		str(_policy_row_ok(policy, "relation")), str(_policy_row_ok(policy, "form")),
		str(_policy_row_ok(policy, "romance")), str(_policy_row_ok(policy, "promiscuity")),
		str(_policy_row_ok(policy, "sex_bond")), str(_policy_row_ok(policy, "cycle")),
		str(_policy_row_ok(policy, "history")), str(conversation_ok()), str(free_of_affection()),
		str(player_ready_for(pose, act_source, bed_in)), str(nav_owner_allows(pose, act_source)),
		str(nav_pose_gate(pose, act_source)), bed_text, str(bool(gate.get("show", false))),
		reason_text]
	if int(context.get("state", 0)) != STATE_IDLE:
		var limit_text := "∞" if int(context.get("max_pony_climaxes", 0)) <= 0 \
			else str(int(context.get("max_pony_climaxes", 0)))
		text += " | readiness=%.0f mood=%s climaxes=%d/%s intensity=%s pattern=%s cue=%s up=%s penetration=%.1f/%.1fcm | %s" % [
			float(context.get("satisfaction", 0.0)), str(context.get("mood", "")),
			int(context.get("pony_climaxes", 0)), limit_text,
			str(context.get("last_intensity", "")), str(context.get("last_pattern", "")),
			str(context.get("cue", "")), str(context.get("thrust_up", false)),
			float(context.get("penetration_m", 0.0)) * 100.0,
			float(context.get("penetration_reach", 0.0)) * 100.0,
			str(context.get("preferences", "")).replace("\n", "; ")]
	text += " | " + str(context.get("voice_status_line", ""))
	return text


## The footstool rule lives in the per-act handle `stool/act.gd`; the rows reach it through the
## runtime's callbacks.
func needed_stool() -> int:
	return int(stool_need.call()) if stool_need.is_valid() else 0


func owned_stools() -> int:
	return int(stool_count.call()) if stool_count.is_valid() else 0


func authored_ready() -> bool:
	return pose_session != null and bool(pose_session.call("authored_ready"))


func authored_reason() -> String:
	return str(pose_session.call("authored_reason")) if pose_session != null else "pose_asset"


func rig_missing() -> Array:
	var missing: Variant = pose_session.call("rig_missing") if pose_session != null else []
	return missing if missing is Array else []


func rig_reason(missing: Array) -> String:
	return str(pose_session.call("rig_reason", missing)) if pose_session != null else ""


## A refusal is a real mood beat, not just a buck animation. The game's lasting feeling is the
## impression note, which drives eligibility, anger, offers, approaches and her dialogue; the held
## face displays it (`mood_face.gd`). A buck is the stronger moment, so it is the stronger mood.
func note_refusal(bucked: bool) -> void:
	if is_instance_valid(main) and is_instance_valid(main.game) and main.memory != null:
		var impression := MEMORY.Impression.new()
		impression.id = id
		impression.event_id = "unfplap_refusal_%s_%d" % [id, Time.get_ticks_usec()]
		impression.slot = MEMORY.ImpressionSlot.REFUSAL
		impression.mood = "angry" if bucked else "annoyed"
		main.memory.commit(impression)
	refuse_trust()
	if on_refusal_face.is_valid():
		on_refusal_face.call(bucked)


## The game's own unwelcome-contact hook: a little trust lost and the boundary signal. It never
## sets a mood itself, so the refusal impression owns that.
func refuse_trust() -> void:
	if not is_instance_valid(pony):
		return
	if not pony.has_meta("relationship_runtime"):
		return
	var rel: Variant = pony.get_meta("relationship_runtime")
	if rel == null or not is_instance_valid(rel):
		return
	var bonds: Variant = rel.get("bonds")
	if bonds != null and is_instance_valid(bonds) and bonds.has_method("unwanted_contact"):
		bonds.call("unwanted_contact", id, "kiss")


## Whether the scene itself can host a refusal at all. The policy must already say `buck_refuse`.
func refuse_available(pose: String, act_source: String, bed_in: Variant,
		gate: Dictionary) -> bool:
	if state != STATE_IDLE or not is_instance_valid(pony) or not is_instance_valid(main):
		return false
	if not is_instance_valid(main.player) or not is_instance_valid(main.game):
		return false
	var policy: ELIGIBILITY.Verdict = gate.get("policy")
	if policy == null or not policy.buck_refuse:
		return false # Willing, or not an eligible adult mare: the normal offer/start path owns it.
	if pony.sleeping or bool(pony.get_meta("sex_active", false)) or pony.has_meta("sex_aftercare"):
		return false
	if not conversation_ok() or not free_of_affection():
		return false
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav == null or str(nav.get("reserved_by")) != "":
		return false
	if not nav_owner_allows(pose, act_source):
		return false
	var body: Variant = main.player
	if body.get("controls_locked") == true or body.get("flying") == true:
		return false
	if bool(body.get_meta("knocked_down", false)):
		return false
	if DisplayServer.get_name() != "headless" and not headset_view() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	var affection: Node = pony.get_node_or_null("Affection")
	if affection == null or not affection.has_method("buck"):
		return false
	if pose == CATALOG.STANDING:
		if pony.is_held() or not pony.grounded() or pony.has_meta("seated"):
			return false
		var status: Dictionary = pony.posture_status()
		if str(status.get("requested", "")) != "stand" or not bool(status.get("settled", false)):
			return false
		if pony.global_position.distance_to(body.global_position) > 2.4:
			return false
		return true
	if act_source == "cradle":
		var reach: Node = main.interactor()
		if not is_instance_valid(reach):
			return false
		return reach.get("held") == pony and reach.get("cradled") == true
	if act_source == "already_lying":
		var bed: Node3D = resolve_bed(pose, act_source, bed_in)
		if bed == null:
			return false
		var status2: Dictionary = pony.posture_status()
		if str(status2.get("requested", "")) != "lie_down":
			return false
		return main.player_beside_bed(bed)
	return false


## The refusal itself: a standing buck/push, or the cradle/bed release then the same reaction.
func refuse(pose: String, act_source: String, bed_in: Variant, gate: Dictionary) -> void:
	if not refuse_available(pose, act_source, bed_in, gate):
		return
	if pose == CATALOG.STANDING:
		note_refusal(buck_or_push())
		return
	if act_source == "cradle":
		if not release_carry.is_valid() or not bool(release_carry.call()):
			return
		var at := refusal_floor()
		var forward: Vector3 = main.player.global_position - at
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			forward = -main.player.global_basis.z
		forward = forward.normalized()
		pony.reset_motion(Transform3D(Basis.looking_at(forward, Vector3.UP), at))
		pony.reset_physics_interpolation()
		pony.request_posture("stand")
		var tree: SceneTree = pony.get_tree()
		if tree != null:
			await tree.physics_frame
		note_refusal(buck_or_push())
		return
	if act_source == "already_lying":
		if not REST.release_managed(pony):
			return
		pony.request_posture("stand")
		var tree: SceneTree = pony.get_tree()
		if tree != null:
			await tree.physics_frame
		note_refusal(buck_or_push())


func refusal_floor() -> Vector3:
	var forward: Vector3 = -main.player.global_basis.z
	var view: Camera3D = main.camera()
	if view != null:
		forward = -view.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var at: Vector3 = main.player.global_position + forward * 1.1
	var world: World3D = main.player.get_world_3d()
	if world != null:
		var space: PhysicsDirectSpaceState3D = world.direct_space_state
		if space != null:
			var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 4.0, 1)
			var hit: Dictionary = space.intersect_ray(query)
			if not hit.is_empty():
				at = hit.get("position", at)
	return at


func buck_or_push() -> bool:
	if not is_instance_valid(pony) or not is_instance_valid(main):
		return false
	var affection: Node = pony.get_node_or_null("Affection")
	if affection != null and affection.has_method("buck"):
		if bool(affection.call("buck", main.player_body())):
			return true
	var body: Variant = main.player
	if not is_instance_valid(body):
		return false
	var knockdown: Variant = body.get("knockdown")
	if knockdown == null or not knockdown.has_method("start"):
		return false
	var direction: Vector3 = pony.global_position - body.global_position
	direction.y = 0.25
	if direction.length_squared() < 0.0001:
		direction = -body.global_basis.z
	knockdown.call("start", body, direction.normalized() * 3.0)
	return true


func conversation_ok() -> bool:
	if not is_instance_valid(pony) or not is_instance_valid(main):
		return false
	var target: Variant = pony.get("conversation_target")
	if target == null or not is_instance_valid(target):
		return true
	var body: Node3D = main.player_body()
	if target == main.player or target == body:
		return true
	# The player's body/avatar is under the rig; another pony's is not.
	if is_instance_valid(main.player) and main.player is Node \
			and (main.player as Node).is_ancestor_of(target as Node):
		return true
	return false


## The stock bed marks a lying companion with couch_cuddle; cuddle/player_input then automatically
## begins a CuddleSession. That interrupts missionary, so keep it off while an act is active.
func suppress_auto_cuddle() -> void:
	if state == STATE_IDLE or not is_instance_valid(pony):
		return
	if pony.has_meta("couch_cuddle"):
		pony.remove_meta("couch_cuddle")
	var session: Node = pony.get_node_or_null("CuddleSession")
	if session != null and (bool(session.get("enabled")) or float(session.get("blend")) > 0.0):
		if session.has_method("end"):
			session.call("end", true)
	if pony.has_meta("cuddle_active"):
		pony.remove_meta("cuddle_active")


## The stock cuddle gate is bypassable by feature flag. The normal bed-side paths remain.
func cuddle_start_override(pose: String, act_source: String) -> bool:
	if pose == CATALOG.MISSIONARY and act_source in ["bed_side", "already_lying"]:
		return true
	if features.is_empty():
		return SETTINGS.allow_act_during_cuddle.get_bool()
	return bool(features.get("allow_act_during_cuddle", false))


func cuddle_active() -> bool:
	if not is_instance_valid(pony):
		return false
	if pony.has_meta("cuddle_active"):
		return true
	# cuddle_session is a persistent reference to the cuddle input's session; the session stays on
	# the pony after end(). Only an enabled/blending session is an active cuddle.
	if not pony.has_meta("cuddle_session"):
		return false
	var session: Variant = pony.get_meta("cuddle_session")
	if session == null or not is_instance_valid(session):
		return false
	if bool(session.get("enabled")):
		return true
	var blend: Variant = session.get("blend")
	return blend != null and float(blend) > 0.01


func free_of_affection() -> bool:
	if not is_instance_valid(pony):
		return false
	var affection: Node = pony.get_node_or_null("Affection")
	if affection != null:
		var kind: Variant = affection.get("kind")
		if kind != null and not str(kind).is_empty():
			return false
	var hoof: Variant = pony.get("hoof_hold")
	if hoof != null and hoof.has_method("active") and bool(hoof.call("active")):
		return false
	return true


func nav_owner_allows(pose: String, act_source: String) -> bool:
	if not is_instance_valid(pony):
		return false
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav == null:
		return false
	var owner := str(nav.get("command_owner"))
	if owner.is_empty():
		return true
	# The request controller holds her while she walks over, presents and waits for Y.
	if owner.begins_with("unfplap:request:"):
		return state == STATE_IDLE
	# NightRest's new [go_to_bed] owns her with a sleep: lease. While she is lying awake in a bed,
	# a bed-side act is still valid; walking to bed or sleeping is not.
	if owner.begins_with("sleep:"):
		return sleep_owner_allows_bed(pose, act_source)
	if owner.begins_with("unfplap:"):
		return false
	if owner.begins_with("weather:") or owner.begins_with("show:"):
		return false
	if owner.begins_with("cuddle:"):
		return pose == CATALOG.MISSIONARY and act_source in ["bed_side", "already_lying"]
	# A managed bed/couch rest is valid for missionary; every other leisure seat is not.
	if owner.begins_with("leisure:"):
		return pose == CATALOG.MISSIONARY and act_source in ["bed_side", "already_lying"]
	# Player conversation is free; another pony's conversation is not.
	if owner.begins_with("social:"):
		return owner.begins_with("social:talk") and conversation_ok()
	# Normal routine owners: idle routines are free, an active route is not.
	if owner.begins_with("life:") or owner.begins_with("day:"):
		return not bool(nav.get("_has_target"))
	# A player-owned date/outing, following the player, or an idle rest.
	if owner.begins_with("bond:") or owner.begins_with("player:") or owner == "rest_after_command":
		return true
	return false


## NightRest's sleep: lease is also used for an awake [go_to_bed] rest. Only a pony already lying
## in a bed, with Anon there too, may accept a bed-side act through it.
func sleep_owner_allows_bed(pose: String, act_source: String) -> bool:
	if pose != CATALOG.MISSIONARY or act_source not in ["bed_side", "already_lying"]:
		return false
	if not is_instance_valid(pony) or bool(pony.get("sleeping")):
		return false
	if not pony.has_method("posture_status"):
		return false
	var status: Dictionary = pony.posture_status()
	return str(status.get("requested", "")) == "lie_down"


func nav_pose_gate(pose: String, act_source: String) -> bool:
	if not is_instance_valid(pony):
		return false
	if pose == CATALOG.STANDING:
		if pony.is_held() or not pony.grounded():
			return false
		if bool(pony.motion_paused):
			return false
		if pony.has_meta("seated"):
			return false
		var interruption := str(pony.action_interruption_reason())
		if not interruption.is_empty():
			# The request's own affection_active hold is not a gate against its invite.
			var request_hold := request_face_active.is_valid() and bool(request_face_active.call())
			if not (request_hold and state == STATE_IDLE and interruption.contains("Affection")):
				return false
		var status: Dictionary = pony.posture_status()
		if str(status.get("requested", "")) != "stand" or not bool(status.get("settled", false)):
			return false
		if float(pony.actual_speed) > 0.06:
			return false
		return true
	if act_source == "cradle":
		return true
	# already_lying: seated is allowed; held/grounded/interruption are not used.
	return true


func bed_gate(pose: String, act_source: String, found: Node3D) -> bool:
	if pose != CATALOG.MISSIONARY or not is_instance_valid(pony) or not is_instance_valid(main):
		return pose != CATALOG.MISSIONARY
	var rest: Node = pony.get_node_or_null("CradleRest")
	if rest != null:
		if bool(rest.get("asleep")):
			return false
		if act_source == "cradle" and float(rest.get("drowse")) >= 0.5:
			return false
	var tree: SceneTree = pony.get_tree()
	if act_source == "cradle":
		var reach: Node = main.interactor()
		if not is_instance_valid(reach):
			return false
		if reach.get("held") != pony or reach.get("cradled") != true:
			return false
		# The cradle path exists only for human Anon.
		if PLAYER_FORM.is_pony(PLAYER_FORM.active(tree)):
			return false
		return true
	if act_source == "bed_side":
		var status: Dictionary = pony.posture_status()
		if str(status.get("requested", "")) != "lie_down" or not bool(status.get("settled", false)):
			return false
		return main.player_beside_bed(found)
	if not PLAYER_FORM.is_pony(PLAYER_FORM.active(tree)):
		return false
	var status2: Dictionary = pony.posture_status()
	if str(status2.get("requested", "")) != "lie_down" or not bool(status2.get("settled", false)):
		return false
	return main.player_beside_bed(found)


func resolve_bed(pose: String, act_source: String, bed_in: Variant) -> Node3D:
	if pose != CATALOG.MISSIONARY or not is_instance_valid(main):
		return null
	if bed_in is Node3D and is_instance_valid(bed_in):
		var real: Variant = main.real_bed(bed_in) if main.has_method("real_bed") else bed_in
		if real is Node3D and is_instance_valid(real):
			return real
	if act_source == "cradle":
		return main.bed_for_cradle(pony)
	return find_bed_under()


func find_bed_under() -> Node3D:
	if not is_instance_valid(pony) or not is_instance_valid(main):
		return null
	var exclude: RID = pony.get_rid() if pony is CollisionObject3D else RID()
	return main.bed_under(pony.global_position, exclude)


func player_ready_for(pose: String, act_source: String, bed_in: Variant) -> bool:
	if not is_instance_valid(main):
		return false
	var body: Variant = main.player
	if not is_instance_valid(body):
		return false
	# A headset rig is a plain Node3D: it has neither desktop `controls_locked` nor `flying`, and
	# `bool(null)` is an error in GDScript, so compare against true instead.
	if body.get("controls_locked") == true:
		return false
	if body.get("flying") == true:
		return false
	var wing: Variant = body.get("wing_flight")
	if wing != null and bool(wing.get("active")):
		return false
	if bool(body.get_meta("knocked_down", false)):
		return false
	var swimming: Variant = body.get("swimming")
	if swimming != null and bool(swimming.get("active")):
		return false
	if DisplayServer.get_name() != "headless" and not headset_view() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	var inventory: Variant = main.game.get("inventory") \
		if is_instance_valid(main.game) else null
	if inventory != null:
		var held: Variant = inventory.get("held")
		if held is Dictionary and not (held as Dictionary).is_empty():
			return false
		if str(inventory.get("holding_case")) != "":
			return false
	var seat: Variant = body.get("seat")
	if pose == CATALOG.STANDING:
		if seat != null:
			return false
	elif act_source == "cradle":
		if seat != null:
			return false
	elif act_source == "already_lying":
		var found: Node3D = resolve_bed(pose, act_source, bed_in)
		if not main.player_beside_bed(found):
			return false
	elif act_source == "bed_side":
		if seat == null:
			return false
		var rest: Variant = body.get("_couch_rest")
		if rest != null and is_instance_valid(rest) and float(rest.get("amount")) < 0.99:
			return false
		var found_bed: Node3D = resolve_bed(pose, act_source, bed_in)
		if not main.player_beside_bed(found_bed):
			return false
	return true


func headset_view() -> bool:
	return is_instance_valid(main) and is_instance_valid(main.game) \
		and bool(main.game.get("headset_view"))


func _row(rows_out: Array, key: String, ok: bool, reason := "") -> void:
	var row := ELIGIBILITY.Row.new()
	row.key = key
	row.ok = ok
	row.reason = reason if not reason.is_empty() else key
	rows_out.append(row)
