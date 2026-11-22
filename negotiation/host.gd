extends RefCounted
## Service: negotiation, private. Contract: `docs/negotiation.md` (`## Bridge`).
##
## Builds the typed `Host` the service runs on from the live world, and owns the Anon-offer watch.

const PROMPTS := preload("res://mods/unfplap/negotiation/prompts.gd")
const ADAPTER := preload("res://mods/unfplap/negotiation/adapter.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const ACT_GATE := preload("res://mods/unfplap/act_gate/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const RELATIONSHIP_CUE := preload("res://mods/unfplap/shared/relationship_cue.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const SCENE_GATE := preload("res://mods/unfplap/scene_gate/service.gd")

## The longest player line the Anon-offer classifier reads; a longer line is not an ask.
const MAX_LINE := 600

## The act state through the runtime's session handle; an invalid runtime is IDLE.
func _state_of(runtime: Node) -> int:
	var session: Variant = runtime.get("act") if is_instance_valid(runtime) else null
	return int(session.state) if session != null else 0

## The negotiation service: the lock read, the Anon answer and the Agreement cancel.
var service: Node = null
## The adapter node the service builds; this bridge only calls into it.
var adapter: ADAPTER = null
## The services this bridge reads. `eligibility` alone is handed over again on each world enter,
## because the entry constructs a fresh one.
var eligibility: ELIGIBILITY = null
## The dynamic gate: the relationship row and the Context facts.
var gate: ACT_GATE = null
var memory: MEMORY = null
var privacy: PRIVACY = null
var hud: Node = null
var initiation: Node = null
var offer: Node = null
## True while the adapter's global Anon-offer watch is armed.
var _watching := false


# ------------------------------------------------------------------------- host callbacks

func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func eligible(pony: Variant) -> bool:
	var node := pony as Node
	return is_instance_valid(eligibility) and is_instance_valid(node) \
		and eligibility.eligible(node, ELIGIBILITY.Target.ACT)


func relationship_ok(pony: Node) -> bool:
	return is_instance_valid(gate) and gate.relationship_ok(pony)


func privacy_private(pony: Node, cuddle: bool) -> bool:
	if not is_instance_valid(privacy):
		return false
	return privacy.is_private(pony, PRIVACY.Kind.CUDDLE if cuddle else PRIVACY.Kind.OFFER)


func placement_for(runtime: Node) -> POSE_OPTIONS.Placement:
	if is_instance_valid(initiation) and initiation.has_method("placement_for"):
		return initiation.placement_for(runtime)
	return POSE_OPTIONS.Placement.new()


## The live placement re-check the Agreement asks for: the chosen option's scene-only rows, with
## no frozen capability and no hold exemption. It is a scene check, not a new policy read.
func pose_placed(runtime: Node, option: POSE_OPTIONS.Option) -> bool:
	var scene := PONIES.scene_of(runtime) if is_instance_valid(runtime) else null
	if scene == null or option == null:
		return false
	var verdict: Variant = scene.scene_only_verdict(option.pose, option.source,
		option.bed, null)
	return verdict != null and bool(verdict.hard_ok)


## The live readiness of a formed Agreement: its small scene checks with the frozen pose pair.
## The press and auto-start call it through `ready_offer()`; it builds no row list.
func scene_ready(pony: Node, option: POSE_OPTIONS.Option, profile_ok: bool, source_ok: bool) -> bool:
	var runtime: Variant = PONIES.runtime_for(pony) if is_instance_valid(pony) else null
	var scene := PONIES.scene_of(runtime) if is_instance_valid(runtime) else null
	if scene == null or option == null:
		return false
	return bool(scene.agreement_ready(option.pose, option.source, option.bed,
		SCENE_GATE.FrozenPose.new(profile_ok, source_ok)))


func hold_for(runtime: Node) -> RefCounted:
	var presentation := PONIES.presentation_of(runtime) if is_instance_valid(runtime) else null
	return presentation.hold_handle() if presentation != null else null


func classify(request: PROMPTS.Request, scope: String, done: Callable) -> bool:
	return is_instance_valid(adapter) and adapter.classify(request, scope, done)


func reason(request: PROMPTS.Request, scope: String, done: Callable) -> bool:
	return is_instance_valid(adapter) and adapter.reason(request, scope, done)


func await_answer(pony: Node, scope: String, done: Callable) -> bool:
	return is_instance_valid(adapter) and adapter.await_answer(pony, scope, done)


func cancel_scope(scope: String) -> void:
	if is_instance_valid(adapter):
		adapter.cancel_scope(scope)


func toast(text: String) -> void:
	if is_instance_valid(hud):
		hud.toast(text)


# ------------------------------------------------------------------------- facts

## The Context facts both Mare reasoning stages and the Negotiation read. One snapshot per call
## from the eligibility facts, act history, memory and the live privacy state.
func context_facts(pony: Node) -> Dictionary:
	var out: Dictionary = {}
	if not is_instance_valid(pony) or not is_instance_valid(gate):
		return out
	var verdict: ACT_GATE.Verdict = gate.get_verdict(pony, ACT_GATE.Mode.OFFER)
	if verdict == null or verdict.facts == null:
		return out
	var facts: ACT_GATE.Facts = verdict.facts
	var history: ACT_GATE.History = facts.history
	var id := facts.id
	out["willingness"] = facts.willing
	out["history"] = {
		"tier": history.tier, "hurt": history.hurt, "comfort": history.comfort,
		"blocks_start": history.blocks_start, "blocks_offers": history.blocks_offers,
		"offer_weight": history.offer_weight,
	}
	out["cycle_phase"] = facts.cycle_phase
	out["heat"] = facts.heat
	out["aftercare"] = pony.has_meta("sex_aftercare")
	out["private"] = is_instance_valid(privacy) and privacy.is_private(pony)
	out["public_preference"] = facts.consent.public
	out["mood"] = _world_mood(id)
	out["relation_note"] = _relation_note(id)
	out["history_note"] = ACT_HISTORY.ask_note(ACT_HISTORY.effective_row(
		ACT_HISTORY.section(), id, ACT_HISTORY.day_now())) if not id.is_empty() else ""
	return out


## The world-context impression mood for one id, or "".
func _world_mood(id: String) -> String:
	if id.is_empty() or not is_instance_valid(WORLD.game):
		return ""
	var context := GAME.world_context(WORLD.game)
	var impressions := GAME.impressions_of(context)
	return GAME.impression_mood(impressions, id, "")


## The relationship prompt note for one id, or "".
func _relation_note(id: String) -> String:
	if id.is_empty() or not is_instance_valid(memory) or not is_instance_valid(WORLD.game):
		return ""
	var facts: MEMORY.CueFacts = memory.cue_facts(id, "")
	var facts_dict := facts.to_dict()
	var note := RELATIONSHIP_CUE.note(facts_dict)
	if note.is_empty():
		return ""
	return note + " " + RELATIONSHIP_CUE.tone_line(RELATIONSHIP_CUE.tone(facts_dict))


# ------------------------------------------------------------------------- watch

## The global Anon-offer watch runs only while nothing is negotiating or acting, so a line that
## answers a Mare offer is never read as a new one.
func tick_watch() -> void:
	if not is_instance_valid(adapter) or not is_instance_valid(service):
		return
	var free: bool = not PONIES.act_running() and not bool(service.is_locked())
	if free:
		if not _watching:
			_watching = true
			adapter.watch_player(Callable(self, "on_anon_line"))
			LOG.debug("anon_watch armed")
		return
	if _watching:
		_watching = false
		adapter.unwatch_player()
		LOG.debug("anon_watch disarmed reason=%s", [
			"act" if PONIES.act_running() else "locked"])


## Drop the adapter's global watch, which still holds the world that is gone.
func disarm() -> void:
	if not _watching:
		return
	_watching = false
	if is_instance_valid(adapter):
		adapter.unwatch_player()


## The first new player line while he talks to a mare: an Anon offer. The service classifies
## intent; a normal line forms nothing and says nothing.
func on_anon_line(text: String) -> void:
	var line := text.strip_edges()
	LOG.debug("anon_line received len=%d", [line.length()])
	if line.is_empty():
		LOG.debug("anon_line skip reason=empty")
		return
	if line.length() > MAX_LINE:
		LOG.debug("anon_line skip reason=too_long len=%d", [line.length()])
		return
	if not is_instance_valid(service) or service.is_locked():
		LOG.debug("anon_line skip reason=locked")
		return
	if not _classifier_ready():
		LOG.debug("anon_line skip reason=no_classifier")
		return
	var pony := _conversation_mare()
	if not is_instance_valid(pony):
		LOG.debug("anon_line skip reason=no_target")
		return
	var runtime: Variant = PONIES.runtime_for(pony)
	if not is_instance_valid(runtime) or _state_of(runtime) != 0:
		LOG.debug("anon_line skip reason=runtime_state state=%s", [
			str(_state_of(runtime)) if is_instance_valid(runtime) else "none"])
		return
	if is_instance_valid(initiation) and initiation.has_method("cancel_approach"):
		initiation.cancel_approach()
	var id := PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))
	LOG.debug("anon_line -> negotiation id=%s", [id if not id.is_empty() else str(pony.name)])
	var started: bool = service.begin_anon_offer(runtime, line)
	LOG.debug("anon_line negotiation started=%s", [str(started)])


## A missing classifier means no answer; the Proactive service owns that node.
func _classifier_ready() -> bool:
	return is_instance_valid(initiation) and initiation.has_method("classifier_available") \
		and initiation.classifier_available()


## The mare whose conversation target is Anon, nearest first. The game's own target decides; the
## classifiers never reroute the director.
func _conversation_mare() -> Node:
	if not is_instance_valid(WORLD.player):
		return null
	var best: Node = null
	var best_distance := INF
	for node: Variant in WORLD.mares():
		if not is_instance_valid(node) or not eligible(node):
			continue
		var target: Variant = node.get("conversation_target")
		if not is_instance_valid(target):
			continue
		var bound: bool = target == WORLD.player \
			or (WORLD.player is Node and (WORLD.player as Node).is_ancestor_of(target))
		if not bound:
			continue
		var actor := node as Node3D
		var distance := actor.global_position.distance_to(WORLD.player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best
