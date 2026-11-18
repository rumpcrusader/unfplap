extends "res://mods/unfplap/body_change/source.gd"
## Queen Chrysalis, by changelings: the typed body-change provider for the installed-mare profile,
## the forms the pack brings and her own spring tail.
##
## The pack's own body script extends the game's pony, so unfplap already attaches its runtime and
## anatomy controller. This adapter adds only what the generic core cannot know: her approved
## profile as a provider layer, the body form for each body the pack brings, the installed list
## entry while the pack is active, and the player's own words for the reveal ask and the named
## shape. It reads the pack's public nodes and state; it never edits the pack and never requires a
## rebuild.
##
## Scope: world. `main.gd` constructs it once and registers it with `main.body_change`. It never
## preloads `main.gd` or `runtime.gd`.
##
## See `docs/integrations.md` and `docs/anatomy.md` (`## Placement`, `## Tail seating`).

const WORLD := preload("res://mods/unfplap/world/service.gd")
const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")
const CHANGELINGS_POLICY := preload("res://mods/unfplap/integrations/changelings_policy.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

const MOD_ID := "changelings"
const GROUP := "changelings_mod"
const ID := "chrysalis"
## Her hair script puts one attachment per part on the game rig; the visible tail root is the
## chain under the tail attachment (`Hair_` + part).
const TAIL_ATTACHMENT := "Hair_tail"
const TAIL_CHAIN := "Chain"
## The adapter-owned placement node above the chain. The act tail modifiers keep rotating the
## chain itself, so a placement edit and an act never restore each other.
const TAIL_WRAPPER := "UnfplapTailPlacement"
## A disguise marks its body with this geometry variant (`changeling=<pony id>` in 0.2.12).
const SHAPE_PREFIX := "changeling="
## Her own body script hides every mesh under her model that lacks this pack marker, so the
## anatomy mesh on her skeleton must carry it or it is hidden for good.
const BODY_OWN_META := "chrysalis_own"
## Her own body's rig row. The cell body is the princess profile, not the ordinary mare body.
const OWN_RIG := "celestia"
## The pack builds her hair a few frames after the body's first prepare. Retry the tail-root
## lookup for a short grace so the wrapper can attach once the chain exists.
const LATE_TAIL_TRIES := 6
const LATE_TAIL_STEP_S := 0.05
## The provider's own pack read. The base service never polls; this adapter observes its pack at
## the same 0.1 s cadence the act watcher uses and pushes the change through the service.
const OBSERVE_S := 0.1
## The player's own words for the reveal ask, lower-case and matched inside the line. The core
## owns no phrasing; a later source brings its own.
const REVEAL_PHRASES := [
	"true form", "real form", "real self", "real you", "real her", "as yourself",
	"show yourself", "show me the real", "drop the disguise", "take off the disguise",
	"lose the disguise", "unmask", "who you really are",
]
## A shape request is imperative or a whole name; a mention or a description is ordinary talk.
const SHAPE_REQUEST_PHRASES := [
	"wear", "become", "turn into", "change into", "name yourself",
]
## Words that make a line a refusal or a description rather than a request, even when it carries
## a request phrase ("I don't want to wear Rarity").
const SHAPE_NEGATIONS := [
	"not", "never", "dont", "don t", "doesn t", "didn t", "can t", "cannot", "won t",
]
const NOTE_WEARING := "She is already wearing that shape."
const NOTE_HERSELF := "She is already herself."
const NOTE_CANNOT := "She cannot wear that shape."

## The approved provider profile. No `eligible` assertion: her identity decides age, so a young
## disguised shape still fails the act gate.
const DESCRIPTOR := {
	"schema": 1,
	"id": ID,
	"source": MOD_ID,
	"name": "Queen Chrysalis",
	"preferences": {
		"intensity": "firm",
		"pattern": "teasing",
		"touch": ["caress", "kiss"],
		"dislikes": ["smack"],
		"talk": ["praise", "playful"],
		"warmth": "slow",
		"tolerance": "normal",
		"notes": "You are proud, theatrical and possessive, and you enjoy an audience. Kindness that asks nothing unsettles you, though you would never admit it. You show affection more in staying than in saying, and you remember who stayed.",
	},
	"placement": {
		"offset_y": 0.49, "offset_z": 0.271, "pitch_deg": 8.0, "scale": 0.422,
		"tail_y": 0.04, "tail_z": 0.0, "tail_tilt_deg": 0.0,
	},
}

var main: Node
## Test seam for the pack-active check. Production sets it in `setup()`.
var mod_active := Callable()

var _registered := false
## The typed change the runtime reads through the source methods below; it never sees the pack's
## own fields.
var _change: BODY_CHANGE = null
var _changing := false
var _change_old: Node = null
var _change_new: Node = null
var _change_target := ""
## A named change's variant is refitted and announced once when it settles.
var _change_variant_done := false
## Presented body -> the signature of the last form the provider returned and its revision.
## A late variant that changes the descriptor bumps the revision for that body only.
var _form_signatures: Dictionary = {}
var _form_revisions: Dictionary = {}
var _policy: POLICY = null
## The last body the source lookup asked about. The runtime resolves its source through
## `handles_pony` before each observation, so this is the act pony without a new contract method.
var _act_pony: Node = null
## The pack's `busy` on the previous poll. A rising edge with the act pony as `actor` is a change
## her own AI started, which no `request_*` call announced.
var _busy_seen := false
## The provider's observation clock; the pack read runs once per `OBSERVE_S`, not per frame.
var _observe_clock := 0.0
## Pony -> attempts used while her spring chain is still being built.
var _late_tail: Dictionary = {}
var _late_tail_timer: Timer
## Pony -> the placement wrapper above her spring chain.
var _tail_wrappers: Dictionary = {}


func setup(main_node: Node) -> void:
	main = main_node
	if mod_active.is_null():
		mod_active = Callable(self, "_mod_active")


func _ready() -> void:
	if mod_active.is_null():
		mod_active = Callable(self, "_mod_active")
	set_process(false)
	refresh()


## True while the Queen Chrysalis pack is loaded this launch.
func active() -> bool:
	return not mod_active.is_null() and bool(mod_active.call())


## Mares this source installs even while they are away. The generic listing merges this with the
## live off-roster mares.
func installed_character_ids() -> Array[String]:
	var out: Array[String] = []
	if active() and _registered:
		out.append(ID)
	return out


## The pack's offer/reveal policy. The base runtime executes its typed effects.
func policy() -> POLICY:
	if _policy == null:
		_policy = CHANGELINGS_POLICY.new()
	return _policy


# --------------------------------------------------------------------------- body-change source
#
# Only this adapter reads the pack's own `busy`, `actor` and `disguised_as` fields and calls
# `reveal()` / `disguise()`.

## The stable provider id for the body-change service.
func source_id() -> String:
	return MOD_ID


## True when this installed body may be changed through the pack.
func handles_pony(pony: Node3D) -> bool:
	if not active() or not is_instance_valid(pony):
		return false
	var handled := _is_disguise(pony) or _is_own_body(pony)
	if not handled:
		var identity: Variant = pony.get("identity")
		handled = identity != null and str(identity.get("id")) == ID
	if handled:
		_act_pony = pony
	return handled


## The body a new change should claim, so the act is adopted before the pack finishes settling.
func claims_body(pony: Node3D) -> bool:
	if not _changing or not is_instance_valid(pony):
		return false
	if _change_target.is_empty():
		if _is_disguise(pony):
			# Her own AI may begin a shape change before `disguised_as` names it. Claim the body
			# by the identity it keeps, not by a shape the pack has not written yet.
			return _same_identity(pony, _change_old) or _same_relationship(pony, _change_old)
		if _is_own_body(pony):
			return true
		var identity: Variant = pony.get("identity")
		return identity != null and str(identity.get("id")) == ID
	return _shape_of(pony) == _change_target


func is_active() -> bool:
	return active()


func change_in_progress() -> bool:
	return _changing


## The last announced change. A completed change keeps its terminal state as a read-only record;
## `change_in_progress()` is the in-progress gate.
func active_change() -> BODY_CHANGE:
	return _change


## The requested shape id; empty while she returns to her own form.
func target_form_id() -> String:
	return _change_target


## The shape the presented body wears; empty for her own form.
func presented_form_id(body: Node3D) -> String:
	if not is_instance_valid(body):
		return ""
	var shape := _shape_of(body)
	if not shape.is_empty():
		return shape
	var mod := _source_mod()
	if mod == null:
		return ""
	var actor: Variant = mod.get("actor")
	if actor is Node and is_instance_valid(actor) and actor == body:
		return str(mod.get("disguised_as")).strip_edges()
	return ""


## The shape she wears now; empty while she is her own form. The spawned body's geometry variant
## is exact as soon as the pack brings it, while `disguised_as` is only written once the change
## has settled.
func current_shape() -> String:
	var mod := _source_mod()
	if mod == null:
		return ""
	var actor: Variant = mod.get("actor")
	if actor is Node and is_instance_valid(actor):
		var worn := presented_form_id(actor as Node3D)
		if not worn.is_empty():
			return worn
		if _is_own_body(actor as Node):
			return ""
	return str(mod.get("disguised_as")).strip_edges()


## Ask for a borrowed or custom form. The pack owns whether that shape is available.
func request_form(body: Node3D, form_id: String, origin: BODY_CHANGE.Origin) -> bool:
	return _start_shape(body, form_id, origin)


## Ask for the identity's own form. The pack plays the flame and replaces the body.
func request_own_form(body: Node3D, origin: BODY_CHANGE.Origin) -> bool:
	return _start_own_form(body, origin)


func _start_own_form(body: Node3D, origin: BODY_CHANGE.Origin) -> bool:
	var mod := _source_mod()
	if not active() or _changing or mod == null:
		return false
	var current: Variant = mod.get("actor")
	if not current is Node3D or not is_instance_valid(current):
		return false
	if str(mod.get("disguised_as")).is_empty():
		return false
	var old: Node = body if is_instance_valid(body) else current as Node
	_begin_change(old, "", origin)
	mod.call("reveal")
	return true


func _start_shape(body: Node3D, shape_id: String, origin: BODY_CHANGE.Origin) -> bool:
	var shape := shape_id.strip_edges()
	var mod := _source_mod()
	if not active() or _changing or mod == null or shape.is_empty():
		return false
	var current: Variant = mod.get("actor")
	if not current is Node3D or not is_instance_valid(current):
		return false
	var old: Node = body if is_instance_valid(body) else current as Node
	_begin_change(old, shape, origin)
	mod.call("disguise", shape)
	return true


## The idle debug helper: bring her out as she is. It is not a shape change.
func request_appear() -> bool:
	var mod := _source_mod()
	if not active() or _changing or mod == null:
		return false
	var current: Variant = mod.get("actor")
	if current is Node3D and is_instance_valid(current):
		return true
	mod.call("bring_out")
	return true


## Read the pack's completion state on the provider's own observation tick. A change her own AI
## starts is caught without a zero-frame gap between the flame and the handover; once the new
## body's variant reports the target, prepare the form again so the revision can bump.
func poll() -> void:
	var mod := _source_mod()
	if mod == null:
		if _changing:
			_end_change()
		return
	if not _changing:
		_observe(mod)
		return
	var current: Variant = mod.get("actor")
	if current is Node3D and is_instance_valid(current) and current != _change_old:
		if current != _change_new:
			_change_new = current as Node
			if _change != null:
				_change.next_body = _change_new
			# The pack writes the copied id on the new body or `disguised_as`; a true-form body
			# is not a disguise, so the empty target stays correct for a reveal.
			if _change_target.is_empty() and _is_disguise(_change_new):
				var shape := _shape_of(_change_new)
				if shape.is_empty():
					shape = str(mod.get("disguised_as")).strip_edges()
				if not shape.is_empty():
					_change_target = shape
					if _change != null:
						_change.target_form_id = shape
			_notify_source_changed()
			_notify_body_ready(_change_new)
	if not _change_target.is_empty() and not _change_variant_done \
			and is_instance_valid(_change_new):
		if _pack_shape(_change_new, mod) == _change_target:
			_change_variant_done = true
			_notify_body_ready(_change_new)
			_prepare_change_body(_change_new)
	if not bool(mod.get("busy")):
		_end_change()


## A `busy` edge with the act pony as `actor` is a change no `request_*` announced: her own AI
## took the shape off or put one on. Only the act pony's own change reaches the handover; any
## other `busy` still ends when the pack goes idle.
func _observe(mod: Node) -> void:
	var busy := bool(mod.get("busy"))
	var rising := busy and not _busy_seen
	_busy_seen = busy
	if not rising:
		return
	var actor: Variant = mod.get("actor")
	if not actor is Node3D or not is_instance_valid(actor):
		return
	if not _same_actor(actor as Node):
		return
	# Prefer the act pony itself: the pack may already have moved `actor` to the new body while
	# the old one is still inside the flame. The watcher can still suspend on the old body, and
	# `poll()` picks the new actor up on the next tick.
	var old := actor as Node
	if is_instance_valid(_act_pony):
		old = _act_pony
	_begin_change(old, "", BODY_CHANGE.Origin.AI)


## True when the player's own words ask her to drop the shape and show herself.
func asks_form_change(text: String) -> bool:
	if not active():
		return false
	var key := _normalize(text)
	if key.is_empty():
		return false
	for phrase: String in REVEAL_PHRASES:
		if key.contains(phrase):
			return true
	return false


## The adult mare named in the player's line, or "". She, the shape she already wears and a
## body the pack cannot copy are never returned. An ambiguous name matches nothing.
func named_form(text: String) -> String:
	if not active():
		return ""
	var key := _normalize(text)
	if key.is_empty():
		return ""
	var mod := _source_mod()
	var actor := _actor_id(mod)
	var current := current_shape()
	var best := ""
	var best_score := 0
	var tied := false
	var whole := 0
	for id: String in _shape_candidates():
		if id == actor or id == current:
			continue
		var score := _name_score(key, id)
		if score <= 0:
			continue
		if score >= 900:
			whole += 1
		if score > best_score:
			best = id
			best_score = score
			tied = false
		elif score == best_score:
			tied = true
	if best.is_empty() or tied or whole > 1:
		return ""
	return best if _copyable(best) else ""


## A short status when the line names a shape she wears, herself, or a known ineligible body.
## Ordinary talk returns "", so the offer can stay pending without a status on every line.
func named_form_note(text: String) -> String:
	if not active():
		return ""
	var key := _normalize(text)
	if key.is_empty():
		return ""
	var mod := _source_mod()
	var current := current_shape()
	if not current.is_empty() and _name_score(key, current) > 0:
		return NOTE_WEARING
	var actor := _actor_id(mod)
	if not actor.is_empty() and _name_score(key, actor) > 0:
		return NOTE_HERSELF
	var candidates := _shape_candidates()
	for id: String in _all_shape_ids(candidates):
		if id == actor or id == current:
			continue
		if _name_score(key, id) <= 0:
			continue
		if not _is_adult_shape(id, candidates) or not _copyable(id):
			return NOTE_CANNOT
	return ""


## Register or drop the provider layer after a pack check. Idempotent. The adapter observes its
## pack only while the pack is active; a change still running when it goes away is ended here.
func refresh() -> void:
	if active():
		_register()
		set_process(true)
	else:
		if _changing:
			_end_change()
		_unregister()
		set_process(false)


## Build one presented body's form. Her own body carries her rig, fit, marker and spring-tail
## root; a borrowed form carries the copied pony's fit and rig, keeps the source marker and has no
## own tail root. The old body and unrelated ponies never receive the new body's form, and a late
## variant that changes the descriptor bumps this body's revision.
func prepare_body(body: Node3D, change: BODY_CHANGE) -> BODY_FORM.BodyForm:
	if not is_instance_valid(body):
		return null
	if change != null and change.state == BODY_CHANGE.State.REQUESTED:
		change.state = BODY_CHANGE.State.PREPARING
	var form := _build_form(body, _form_shape_for(body, change))
	var signature := _form_signature(form)
	var previous := str(_form_signatures.get(body, ""))
	var revision := int(_form_revisions.get(body, 0))
	if not previous.is_empty() and previous != signature:
		revision += 1
	_form_signatures[body] = signature
	_form_revisions[body] = revision
	form.revision = revision
	return form


func has_tail_placement(pony: Node3D) -> bool:
	if not active() or not is_instance_valid(pony) or not presented_form_id(pony).is_empty():
		return false
	return _is_own_body(pony) and is_instance_valid(_tail_root(pony))


func apply_tail_placement(pony: Node3D) -> void:
	if not active() or not is_instance_valid(pony) or not presented_form_id(pony).is_empty():
		return
	var root := _tail_root(pony)
	if is_instance_valid(root):
		_apply_tail_placement_now(pony, root)
	elif _may_be_hers(pony):
		_schedule_late_tail(pony)


func tail_placement_report() -> String:
	var lines := PackedStringArray()
	for pony: Variant in _tail_wrappers.keys():
		var wrapper: Variant = _tail_wrappers[pony]
		if not is_instance_valid(pony) or not is_instance_valid(wrapper):
			_tail_wrappers.erase(pony)
			continue
		var offset: Vector3 = (wrapper as Node3D).get_meta("unfplap_tail_offset", Vector3.ZERO)
		lines.append("%s custom tail offset=(%.3f,%.3f,%.3f)" % [
			ID, offset.x, offset.y, offset.z])
	return "\n".join(lines)


func _form_shape_for(body: Node3D, change: BODY_CHANGE) -> String:
	var shape := _shape_of(body)
	if not shape.is_empty():
		return shape
	var changing_shape := _change_shape_for(body)
	if not changing_shape.is_empty():
		return changing_shape
	if change != null and not change.target_form_id.is_empty() \
			and body != change.previous_body and change.next_body == body:
		return change.target_form_id
	return ""


func _build_form(body: Node3D, shape: String) -> BODY_FORM.BodyForm:
	var form := BODY_FORM.BodyForm.new()
	form.pony_id = ID
	form.form_id = shape
	form.owned_mesh_meta = BODY_OWN_META
	form.body_scale = _live_scale(body)
	if not shape.is_empty():
		form.form_name = _shape_name(shape)
		form.fit_id = shape
		form.rig = BODY_PROFILE.rig_for_key(shape)
		return form
	form.form_name = "Queen Chrysalis"
	form.fit_id = ID
	form.rig = BODY_PROFILE.rig_for_key(OWN_RIG)
	var root := _tail_root(body)
	if is_instance_valid(root):
		_apply_tail_placement_now(body, root)
		form.tail_root = root
	elif _may_be_hers(body):
		_schedule_late_tail(body)
	return form


func _shape_name(shape: String) -> String:
	var name := SETTINGS.character_name(shape).strip_edges()
	return name if not name.is_empty() else shape


func _live_scale(body: Node3D) -> float:
	var value: Variant = body.get("body_scale")
	return maxf(float(value), 0.1) if value != null else 1.0


func _form_signature(form: BODY_FORM.BodyForm) -> String:
	var rig_id := form.rig.id if form.rig != null else "-"
	var tail := str(form.tail_root.get_instance_id()) if is_instance_valid(form.tail_root) else "-"
	return "%s|%s|%s|%s|%s|%.4f|%s" % [
		form.pony_id, form.form_id, form.form_name, form.fit_id, rig_id, form.body_scale, tail]


func _may_be_hers(pony: Node) -> bool:
	if _is_own_body(pony):
		return true
	var identity: Variant = pony.get("identity")
	return identity == null or str(identity.get("id")).strip_edges() == ID


## The metadata from an earlier prepare, then the chain under the rig's tail attachment. The
## wrapper may have taken the chain, so the path can fail while the metadata still names it.
func _tail_root(pony: Node) -> Node3D:
	if pony.has_meta("tail_pose_root"):
		var held: Variant = pony.get_meta("tail_pose_root")
		if held is Node3D and is_instance_valid(held):
			return held as Node3D
	var rig := pony.get("skeleton") as Node3D
	if is_instance_valid(rig):
		var attached := rig.get_node_or_null(TAIL_ATTACHMENT) as Node3D
		if is_instance_valid(attached):
			var chain := attached.get_node_or_null(TAIL_CHAIN) as Node3D
			if is_instance_valid(chain):
				return chain
	# Runtime-built nodes have no scene owner, so the search must include unowned children.
	var attach := pony.find_child(TAIL_ATTACHMENT, true, false) as Node3D
	if is_instance_valid(attach):
		return attach.get_node_or_null(TAIL_CHAIN) as Node3D
	return null


## Put one placement node between the chain and its parent. Repeated prepares reuse it, so the
## chain is never nested under a second wrapper.
func _ensure_tail_wrapper(pony: Node, root: Node3D) -> Node3D:
	var known: Variant = _tail_wrappers.get(pony)
	if is_instance_valid(known) and (known as Node3D).is_inside_tree():
		var held := known as Node3D
		if root.get_parent() != held:
			root.reparent(held, true)
		return held
	var parent := root.get_parent() as Node3D
	if not is_instance_valid(parent):
		return null
	var wrapper: Node3D = parent if str(parent.name) == TAIL_WRAPPER else null
	if not is_instance_valid(wrapper):
		wrapper = parent.get_node_or_null(TAIL_WRAPPER) as Node3D
	if not is_instance_valid(wrapper):
		wrapper = Node3D.new()
		wrapper.name = TAIL_WRAPPER
		parent.add_child(wrapper)
	if root.get_parent() != wrapper:
		root.reparent(wrapper, true)
	_tail_wrappers[pony] = wrapper
	return wrapper


func _apply_tail_placement_now(pony: Node, root: Node3D) -> bool:
	var body := pony as Node3D
	if not is_instance_valid(body) or not body.is_inside_tree():
		return false
	var wrapper := _ensure_tail_wrapper(pony, root)
	if not is_instance_valid(wrapper) or not wrapper.is_inside_tree():
		return false
	if not SETTINGS.reseat_tails.get_bool():
		wrapper.transform = Transform3D.IDENTITY
		wrapper.set_meta("unfplap_tail_offset", Vector3.ZERO)
		return true
	# The resolved tail keys are absolute from the pack's modelled chain, like the seat's from
	# its reference dock; her provider placement bakes her own tail reference.
	var placement := SETTINGS.anatomy_placement(ID, ID)
	var offset := Vector3(0.0, float(placement.get("tail_y", 0.0)),
		float(placement.get("tail_z", 0.0)))
	var tilt := deg_to_rad(float(placement.get("tail_tilt_deg", 0.0)))
	var parent := wrapper.get_parent() as Node3D
	if not is_instance_valid(parent):
		return false
	# Rotation-only mapping into the wrapper's parent: the body scale belongs to the world root,
	# and the tail keys are body-space metres like the hair-link placement.
	var to_parent := parent.global_transform.basis.orthonormalized().inverse() \
		* body.global_transform.basis.orthonormalized()
	var local := to_parent * offset
	var next := Transform3D(Basis.IDENTITY, local)
	if absf(tilt) > 0.000001:
		var axis := (to_parent * Vector3.BACK).normalized()
		next.basis = Basis(axis, tilt)
	wrapper.transform = next
	wrapper.set_meta("unfplap_tail_offset", offset)
	return true


## Her own body arrives before the pack's hair. Retry until the chain exists, then apply the
## wrapper and ask main for the late fit/ownership prepare.
func _schedule_late_tail(pony: Node) -> void:
	if not is_instance_valid(pony) or not pony.is_inside_tree() or _late_tail.has(pony):
		return
	_late_tail[pony] = 0
	if not is_instance_valid(_late_tail_timer):
		_late_tail_timer = Timer.new()
		_late_tail_timer.name = "UnfplapLateTail"
		_late_tail_timer.wait_time = LATE_TAIL_STEP_S
		_late_tail_timer.one_shot = false
		add_child(_late_tail_timer)
		_late_tail_timer.timeout.connect(_poll_late_tail)
	if _late_tail_timer.is_stopped():
		_late_tail_timer.start()


func _poll_late_tail() -> void:
	if _late_tail.is_empty():
		if is_instance_valid(_late_tail_timer):
			_late_tail_timer.stop()
		return
	for pony: Variant in _late_tail.keys():
		_late_tail_one(pony)


func _late_tail_one(pony: Variant) -> void:
	if not _late_tail.has(pony):
		return
	var node := pony as Node
	if not active() or not is_instance_valid(node) or not node.is_inside_tree():
		_late_tail.erase(pony)
		return
	if _is_disguise(node):
		_late_tail.erase(pony)
		return
	var identity: Variant = node.get("identity")
	if identity != null and str(identity.get("id")).strip_edges() != ID \
			and not _is_own_body(node):
		_late_tail.erase(pony)
		return
	var root := _tail_root(node)
	if is_instance_valid(root):
		_notify_body_ready(node)
		if is_instance_valid(main) and main.has_method("prepare_pony_late"):
			main.call("prepare_pony_late", pony)
		_late_tail.erase(pony)
		return
	var tries := int(_late_tail.get(pony, 0)) + 1
	if tries >= LATE_TAIL_TRIES:
		_late_tail.erase(pony)
		return
	_late_tail[pony] = tries


func _clear_late_tail() -> void:
	_late_tail.clear()
	if is_instance_valid(_late_tail_timer):
		_late_tail_timer.stop()
		_late_tail_timer.queue_free()
		_late_tail_timer = null


## The entry node's teardown. Idempotent.
func shutdown() -> void:
	_end_change()
	_clear_change_read()
	_unregister()
	_clear_late_tail()
	set_process(false)
	_tail_wrappers.clear()
	_form_signatures.clear()
	_form_revisions.clear()
	main = null


func _exit_tree() -> void:
	_end_change()
	_clear_change_read()
	_unregister()
	_clear_late_tail()
	_tail_wrappers.clear()
	_form_signatures.clear()
	_form_revisions.clear()


func _is_disguise(pony: Node) -> bool:
	return str(pony.get_meta("geometry_variant", "")).begins_with(SHAPE_PREFIX)


## The target shape while `pony` is the change's new body, or "". The new body may exist before
## the pack writes its variant, so its spawn prepare must fit the requested shape, not her own.
func _change_shape_for(pony: Node) -> String:
	if not _changing or _change_target.is_empty() or not is_instance_valid(pony):
		return ""
	if is_instance_valid(_change_new):
		return _change_target if pony == _change_new else ""
	if pony == _change_old:
		return ""
	var mod := _source_mod()
	if mod == null:
		return ""
	var actor: Variant = mod.get("actor")
	if actor is Node and is_instance_valid(actor) and pony == actor:
		return _change_target
	return ""


## The shape the pack reports for a new body: its exact geometry variant, or `disguised_as` when
## the body is the pack's current actor.
func _pack_shape(pony: Node, mod: Node) -> String:
	var shape := _shape_of(pony)
	if not shape.is_empty():
		return shape
	if mod == null:
		return ""
	var actor: Variant = mod.get("actor")
	if actor is Node and is_instance_valid(actor) and pony == actor:
		return str(mod.get("disguised_as")).strip_edges()
	return ""


## The copied pony's id from the pack's own geometry variant, or "".
func _shape_of(pony: Node) -> String:
	var variant := str(pony.get_meta("geometry_variant", ""))
	return variant.trim_prefix(SHAPE_PREFIX).strip_edges() if variant.begins_with(SHAPE_PREFIX) else ""


## The body the pack is acting through, by its identity. "" while she has no body.
func _actor_id(mod: Node) -> String:
	if mod == null:
		return ""
	var actor: Variant = mod.get("actor")
	if not actor is Node or not is_instance_valid(actor):
		return ""
	return _identity_id(actor as Node)


## The stable identity id a body keeps across a shape change.
func _identity_id(pony: Node) -> String:
	if not is_instance_valid(pony):
		return ""
	var identity: Variant = pony.get("identity")
	if identity == null:
		return ""
	return str(identity.get("id")).strip_edges()


## True when the pack's actor is the act pony, or the same identity after a body swap.
func _same_actor(actor: Node) -> bool:
	if not is_instance_valid(actor):
		return false
	if is_instance_valid(_act_pony) and actor == _act_pony:
		return true
	return _same_identity(actor, _act_pony)


func _same_identity(a: Node, b: Node) -> bool:
	var id := _identity_id(a)
	return not id.is_empty() and id == _identity_id(b)


## A copied body may keep the pack's relationship id even when its identity is the copied pony.
func _same_relationship(a: Node, b: Node) -> bool:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return false
	var id := str(a.get_meta("relationship_id", "")).strip_edges()
	return not id.is_empty() and id == str(b.get_meta("relationship_id", "")).strip_edges()


## Every adult mare the player may name: the base roster plus the live off-roster and provider
## mares the entry lists. The base roster is adult by construction; the entry's list is already
## gated for a character.
func _shape_candidates() -> Array[String]:
	var out: Array[String] = []
	for id: String in SETTINGS.CHARACTER_ORDER:
		if not id.is_empty() and not out.has(id):
			out.append(id)
	if is_instance_valid(main) and main.has_method("live_character_ids"):
		var live: Variant = main.call("live_character_ids")
		if live is Array:
			for raw: Variant in live:
				var id := str(raw).strip_edges()
				if not id.is_empty() and not out.has(id):
					out.append(id)
	return out


## Every body the pack may copy: the adult candidates plus the population catalogue's own ids.
## The extra ids are what the note needs to recognize a young or male name; a real choice still
## has to pass `_is_adult_shape()` and the copyable check.
func _all_shape_ids(candidates: Array[String]) -> Array[String]:
	var out := candidates.duplicate()
	if is_instance_valid(main):
		var game: Variant = WORLD.game
		if game is Node and is_instance_valid(game):
			var population: Variant = (game as Node).get("population")
			if population != null and is_instance_valid(population):
				var available: Variant = (population as Node).get("available")
				if available is Dictionary:
					for raw: Variant in (available as Dictionary).keys():
						var id := str(raw).strip_edges()
						if not id.is_empty() and not out.has(id):
							out.append(id)
	return out


## The eligibility facade is the age/sex authority for a body that may not be live. The adult
## candidate list is already gated; a population-only body asks the service's id-only target.
func _is_adult_shape(id: String, candidates: Array[String]) -> bool:
	if candidates.has(id):
		return true
	if not is_instance_valid(main):
		return false
	var eligibility: Variant = main.get("eligibility")
	if eligibility == null or not is_instance_valid(eligibility) \
			or not eligibility.has_method("eligible_id"):
		return false
	return bool(eligibility.call("eligible_id", id))


## The pack copies a shape by the game's population entry. Without a population (the lab's
## `--character` starts) the adult roster is still a valid choice.
func _copyable(shape_id: String) -> bool:
	if not is_instance_valid(main):
		return true
	var game: Variant = WORLD.game
	if not game is Node or not is_instance_valid(game):
		return true
	var population: Variant = (game as Node).get("population")
	if population == null:
		return true
	var available: Variant = population.get("available")
	if not available is Dictionary:
		return true
	return not str((available as Dictionary).get(shape_id, "")).is_empty()


## 0 for no match. A whole display name beats the id's words, which beat one distinctive word.
## A name inside a sentence only counts with an imperative request, so "you are a rarity",
## "I don't want Rarity" and "your name is Rarity" never silently pick Rarity, and "apple"
## still never silently picks one apple mare.
func _name_score(key: String, id: String) -> int:
	var name := _normalize(SETTINGS.character_name(id))
	var ident := _normalize(id.replace("_", " "))
	var best := 0
	var request := _has_shape_request(key)
	var padded := " %s " % key
	# A whole line is a name on its own; a name inside a sentence needs the imperative.
	if not name.is_empty() and (key == name or (request and padded.contains(" %s " % name))):
		best = 1000 + name.length()
	if not ident.is_empty() and (key == ident or (request and padded.contains(" %s " % ident))):
		best = maxi(best, 900 + ident.length())
	# A single word of a name is common enough to appear in ordinary talk; it only counts on its
	# own line or with an imperative.
	for word: String in name.split(" ", false):
		if word.length() >= 4 and key.split(" ", false).has(word):
			if request or key == word:
				best = maxi(best, 100 + word.length())
	return best


## True when the player's line asks her to take a form, not merely mentions a name. A negation
## anywhere in the line wins over the request phrase.
func _has_shape_request(key: String) -> bool:
	if _negated(key):
		return false
	var padded := " %s " % key
	for phrase: String in SHAPE_REQUEST_PHRASES:
		if padded.contains(" %s " % phrase):
			return true
	return key.begins_with("name ")


## A refusal or a description is never a request, even when it names a shape.
func _negated(key: String) -> bool:
	var padded := " %s " % key
	for word: String in SHAPE_NEGATIONS:
		if padded.contains(" %s " % word):
			return true
	return false


## Lower-case words only, so punctuation and casing never hide a name.
static func _normalize(text: String) -> String:
	var out := ""
	for index in text.length():
		var c := text[index].to_lower()
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		else:
			out += " "
	return " ".join(out.split(" ", false))


## One change, one old body. A second request while it runs is refused by the caller's gate.
func _begin_change(old: Node, shape_id: String, origin: BODY_CHANGE.Origin) -> void:
	_changing = true
	_change_old = old
	_change_new = null
	_change_target = shape_id
	_change_variant_done = false
	_change = BODY_CHANGE.new()
	_change.source = self
	_change.origin = origin
	_change.previous_body = old as Node3D
	_change.target_form_id = shape_id
	_change.state = BODY_CHANGE.State.REQUESTED
	_change.started_s = Time.get_ticks_msec() / 1000.0
	# The pack is busy from here; the next rising edge is a new change, not this one.
	_busy_seen = true
	_notify_source_changed()


## The pack has finished (or vanished). The typed change keeps its terminal state for the held
## runtime; the service clears its active entry. The per-change variant flag resets.
func _end_change() -> void:
	_changing = false
	_change_variant_done = false
	if _change != null:
		_change.state = BODY_CHANGE.State.SETTLED if is_instance_valid(_change_new) \
			else BODY_CHANGE.State.FAILED
	_notify_source_changed()
	var mod := _source_mod()
	_busy_seen = mod != null and bool(mod.get("busy"))


func _clear_change_read() -> void:
	_change = null
	_notify_source_changed()


func _body_change() -> Node:
	if not is_instance_valid(main):
		return null
	var value: Variant = main.get("body_change")
	return value as Node if value is Node else null


func _notify_source_changed() -> void:
	var service := _body_change()
	if service != null and service.has_method("notify_source_changed"):
		service.call("notify_source_changed", self)


func _notify_body_ready(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	var service := _body_change()
	if service != null and service.has_method("notify_body_ready"):
		service.call("notify_body_ready", pony)


## The new body's shape is on it now: fit it as the target and let the anatomy, tail and LOD
## rebuild against the body that is actually rendered.
func _prepare_change_body(pony: Node) -> void:
	if not is_instance_valid(main) or not is_instance_valid(pony):
		return
	if main.has_method("prepare_pony_late"):
		main.call("prepare_pony_late", pony)
	if main.has_method("refresh_anatomy"):
		main.call("refresh_anatomy")
	WORLD.refresh_body_lod(pony)


## The pack's world node. The pack registers this group in its own `_ready`.
func _source_mod() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(GROUP)


## The provider's own 10 Hz pack read. No runtime or base-service call pumps this.
func _process(delta: float) -> void:
	_observe_clock += maxf(0.0, delta)
	if _observe_clock < OBSERVE_S:
		return
	_observe_clock = 0.0
	poll()


## Her own body: the pack's own meshes, or its spring-tail script. A copied pony has neither.
func _is_own_body(pony: Node) -> bool:
	if is_instance_valid(_tail_root(pony)):
		return true
	var meshes: Variant = pony.get("own_meshes")
	return meshes is Array and not (meshes as Array).is_empty()


func _register() -> void:
	if _registered:
		return
	var api := _api()
	if api == null or not api.has_method("register_mare"):
		return
	var result: Variant = api.call("register_mare", self, DESCRIPTOR.duplicate(true))
	_registered = result is Dictionary and bool((result as Dictionary).get("ok", false))
	if not _registered:
		_log("provider registration failed")


func _unregister() -> void:
	if not _registered:
		return
	_registered = false
	var api := _api()
	if api == null or not api.has_method("unregister_mare"):
		return
	api.call("unregister_mare", self, ID)


func _api() -> Node:
	if not is_instance_valid(main):
		return null
	var value: Variant = main.get("api")
	return value as Node if value is Node else null


func _mod_active() -> bool:
	var mods := get_node_or_null("/root/Mods")
	if mods == null or not mods.has_method("is_active"):
		return false
	return bool(mods.call("is_active", MOD_ID))


func _log(text: String) -> void:
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", "[changelings] " + text)
