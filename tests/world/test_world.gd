extends "res://mods/unfplap/tests/support/suite.gd"
## The world facade: the bound scene handles, the camera cache, the bed resolution, the menu and
## headset gates, the player body and mare reads, the LOD rebuild, the act chat and its bound views.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/world/test_world.gd

const WORLD := preload("res://mods/unfplap/world/api.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const VOICE := preload("res://mods/unfplap/shared/voice_status.gd")
const HYBRID_NEAR_MESH := preload("res://world/characters/hybrid_mare/hybrid_near_mesh.gd")
const HYBRID_FAR_MESH := preload("res://world/characters/hybrid_mare/hybrid_far_mesh.gd")



class FakePlayer extends Node3D:
	var seat: Variant = null
	var camera: Variant = null
	var controls_locked := false
	var form_driver: Variant = null
	var eye_line := 1.5

	func eye_height() -> float:
		return eye_line


class FakeGame extends Node:
	var mares: Array = []
	var headset_view := false
	var inventory: Variant = null
	var save_menu: Variant = null
	var pause_menu: Variant = null
	var player: Variant = null
	var found_camera: Variant = null
	var find_calls := 0
	var kisser: Variant = null
	var world_context: Variant = null
	var relationship_runtime: Variant = null
	var desktop_presentation: Variant = null
	var population: Variant = null

	func _find_camera(_body: Variant) -> Variant:
		find_calls += 1
		return found_camera


## The population catalogue: one scene path per shape id.
class FakePopulation extends Node:
	var available: Dictionary = {}


## The same world without `_find_camera`: the viewport camera is the fallback.
class BareGame extends Node:
	var mares: Array = []
	var headset_view := false


class FakeMare extends Node3D:
	var requested := "stand"

	func posture_status() -> Dictionary:
		return {"requested": requested}


class FakePanel extends Node:
	var opened := false
	var active := false


class FakeCase extends Control:
	pass


class FakeInventory extends Node:
	var case: Variant = null
	var customizer: Variant = null
	var inspector: Variant = null
	var held: Dictionary = {}
	var holding_case := ""


class FakeMapInventory extends FakeInventory:
	func _map_open() -> bool:
		return true


## The briefcase store: the slot rows, the loans and the three write ops the inventory view calls.
class FakeStore extends RefCounted:
	var slots: Array = []
	var loans: Dictionary = {}
	var writable := true
	var taken: Array = []
	var put_back: Array = []
	var granted: Array = []

	func available(slot: int) -> int:
		var row: Dictionary = slots[slot] if slot < slots.size() else {}
		return int(row.get("count", 0))

	func take(slot: int) -> String:
		taken.append(slot)
		return "token-%d" % slot

	func put(token: String, slot: int) -> bool:
		put_back.append([token, slot])
		return true

	func grant(id: String, count: int) -> int:
		granted.append([id, count])
		return 3


## The inventory node: its store, the quick-slot bar, the HUD flag and its own world drops.
class FakeInventoryNode extends Node:
	var inventory: Variant = null
	var hotbar: Variant = null
	var hud_hidden := false
	var held: Dictionary = {}
	var holding_case := ""
	var placed := 0
	var dropped: Array = []

	func spawn_owned_drop(id: String, pose: Transform3D) -> Node:
		dropped.append([id, pose])
		return Node3D.new()

	func _place_hotbar() -> void:
		placed += 1


## The quick-slot bar: its visibility and the canvas layer it draws on.
class FakeHotbar extends Control:
	var _hud: CanvasLayer = null
	var hud_calls: Array = []

	func set_hud_visible(on: bool) -> void:
		hud_calls.append(on)


## The HUD's toast slot: the lines the menu view hands it.
class FakeToast extends Node:
	var shown: Array = []

	func _show_toast(text: String, seconds: float) -> void:
		shown.append([text, seconds])


class FakeChat extends Node:
	var opened := false
	var saw_unlocked := false
	var watcher: Variant = null
	var _lock_owned := true

	func _open() -> bool:
		opened = true
		if watcher != null:
			saw_unlocked = not bool(watcher.get("controls_locked"))
		return opened


class FakeSeat extends Node3D:
	var free_for_pony: Variant = null

	func free_for(pony: Variant) -> bool:
		return pony == free_for_pony


class FakeIdentity extends Resource:
	var id := "fake_mare"


class FakeBody extends Node3D:
	var identity: Resource = FakeIdentity.new()
	var reference_face_enabled := false
	var shading_version := 3
	var head_width := 1.0
	var head_width_factor := 1.0
	var near_mesh_enabled := true
	var near_calls: Array = []
	var boop_node: Variant = null
	var body_scale: Variant = null
	var head: Variant = null
	var expressions: Variant = null
	var eye_y := 0.0
	var skeleton: Skeleton3D
	var hair_skeleton: Skeleton3D
	var hair: Node3D
	var _model: Node
	var hair_link: Node
	var _far_mesh_shown := false
	var eye_motion: Node

	func set_near_mesh(enabled: bool) -> void:
		near_calls.append(enabled)

	func _set_eye_y(value: float) -> void:
		eye_y = value


## A house interior with the one bed builder the facade calls.
class FakeHouse extends Node3D:
	var bed: Variant = null
	var kinds: Array = []

	func ensure_bed(kind: String) -> Variant:
		kinds.append(kind)
		return bed


## A body the facade's velocity write reaches.
class FakeMoving extends Node3D:
	var velocity := Vector3.ZERO


## A couch rest: the seats, the guest entry and the partner one seat reads.
class FakeCouch extends Node3D:
	var seats: Array = []
	var _mare_fits := false
	var _cooldowns := {}
	var invites: Array = []
	var finishes := 0
	var releases: Array = []

	func pony_transform(seat: Node3D) -> Transform3D:
		return Transform3D(Basis.IDENTITY, seat.global_position)

	func open() -> bool:
		return true

	func invite(pony: Node3D, seat: Node3D) -> bool:
		invites.append([pony, seat])
		return true

	func approach(_seat: Node3D) -> Vector3:
		return Vector3(2.0, 0.0, 0.0)

	func partner(seat: Node) -> Variant:
		return seats[0] if seat != seats[0] else null

	func rest_word() -> String:
		return "bed"

	func _finish_guest() -> void:
		finishes += 1

	func _release_pony(id: int, _force: bool) -> void:
		releases.append(id)


## The stock bed rest: the fit, guest and sleeper rows the bed consumers gate on.
class FakeRest extends Node:
	var _bed: Variant = null
	var _mare_fits := false
	var _guest := {}
	var _sleeper: Variant = null
	var _front := Vector3.ONE
	var refreshes := 0

	func refresh() -> void:
		refreshes += 1

	func accept(_pony: Node3D) -> bool:
		return _mare_fits

	func _willing(_pony: Node3D) -> bool:
		return true

	func eligible(_pony: Node3D) -> bool:
		return _mare_fits

	func _front_for(_pony: Node3D) -> Vector3:
		return _front


## The pony seating system: one entry per pony and the release the rest helper takes.
class FakeSeating extends Node:
	var _users := {}
	var released: Array = []

	func _release(entry: Dictionary) -> void:
		released.append(entry.get("id"))


## The game's pony kisser: one latch per kiss.
class FakeKisser extends Node:
	var _active: Variant = "pony"
	var _her_kiss := true
	var _used_hold := true
	var begins := 0
	var accepts := true

	func begin_from_pony(_pony: Node) -> bool:
		begins += 1
		return accepts


## The stock affection the act temporarily feeds.
class FakeAffection extends Node:
	var kind := "kiss"
	var amount := 0.4
	var target := Vector3.ZERO
	var eye := Vector3.ZERO
	var face := Basis.IDENTITY
	var ended := 0
	var cancelled := 0
	var bucks := 0
	var mouth := Vector3(1.0, 1.0, 1.0)

	func end() -> void:
		ended += 1

	func cancel_afterglow() -> void:
		cancelled += 1

	func buck(_body: Node3D) -> bool:
		bucks += 1
		return true

	func mouth_point() -> Vector3:
		return mouth


## The stock kiss pose's own side latch.
class FakeKissPose extends SkeletonModifier3D:
	var _side: Variant = null
	var _side_now := 0.0
	var _side_wait := 0.0


## The same modifier before it grew the side latch.
class BareKissPose extends SkeletonModifier3D:
	pass


## A mouth rig that takes the expression writes.
class FakeExpressionMouth extends Node:
	var faces: Array[String] = []

	func set_expression(name: String, _amount: float) -> void:
		faces.append(name)


## The excitement Beat's own hold field.
class FakeExcitement extends Node:
	var _until := 3.0


## The game's hair link: the pelvis offset the tail seat writes and its private body update.
class FakeHairLink extends Node:
	var pelvis_offset := Transform3D(Basis(), Vector3(0.0, 1.0, 2.0))
	var updates := 0

	func _body_updated() -> void:
		updates += 1


## A body that never grew the eye-line setter: the accessor must leave its field alone.
class FakePlainBody extends Node3D:
	var eye_y := 0.0


class FakeBoop extends Node:
	var amount := -1.0
	var head_skeleton: Skeleton3D

	func sustain_blush(value: float) -> void:
		amount = value


class FakeMouth extends "res://mods/unfplap/tests/support/fakes/fake_mouth.gd":
	pass


## A mouth rig that takes both the viseme writes and the mouth expressions.
class FakeFullMouth extends "res://mods/unfplap/tests/support/fakes/fake_mouth.gd":
	var faces: Array[String] = []

	func set_expression(name: String, _amount: float) -> void:
		faces.append(name)


class FakeHead extends Node:
	var mouth: Variant = null


class FakeFlank extends Node:
	var calls := 0

	func _own_body_materials() -> void:
		calls += 1


class FakeForm extends RefCounted:
	var avatar: Variant = null


## The navigator the standing invitation turns with: the face point, the stay and the facing clear.
class FakeNavigator extends Node:
	var face_point := Vector3.INF
	var conversation_target: Variant = null
	var conversation_hold := true
	var command_owner := ""
	var reserved_by := ""
	var wander_enabled := true
	var command_speed_limit := NAN
	var command_pace_target := NAN
	var _has_target := false
	var stays := 0

	func stay() -> void:
		stays += 1

	func set_conversation_target(who: Variant, hold := true) -> void:
		conversation_target = who
		conversation_hold = hold


## The body's own locomotion turn, for an actor without a navigator.
class FakeTurnPony extends Node3D:
	var face_turn_rate := 0.45
	var facings: Array = []

	func face_direction(direction: Vector3) -> void:
		facings.append(direction)


## An identity resource with wings.
class FakeWingedIdentity extends Resource:
	func has_wings() -> bool:
		return true


## The excitement Beat's wing members: the private node, the stock spread and the flutter.
class FakeWingedExcitement extends FakeExcitement:
	var wings: Variant = null
	var spreads: Array = []
	var flutters := 0

	func _wings() -> Variant:
		return wings

	func spread(seconds: float) -> void:
		spreads.append(seconds)

	func flutter() -> void:
		flutters += 1


## The wing node the act holds: the hold lease, the open switch and the fold blends.
class FakeWings extends Node:
	var opened := false
	var tuck := 0.0
	var half := 0.0
	var holds: Array = []
	var releases: Array = []
	var opens: Array = []

	func hold_at(by: String, value: float) -> bool:
		holds.append([by, value])
		return true

	func release_hold(by: String) -> void:
		releases.append(by)

	func set_open(open: bool) -> void:
		opens.append(open)
		opened = open


## The desktop pose driver the Anon body wraps: the torso pose, the rest-hand pair and the holds.
class FakePoseDriver extends Node3D:
	var torsos: Array = []
	var rest: Array = []
	var clears: Array = []
	var holds: Array = []
	var releases: Array = []
	var palm := Transform3D.IDENTITY

	func apply_torso_pose(hip: Node3D, facing: Basis) -> void:
		torsos.append([hip, facing])

	func set_rest_hand_targets(left: Node3D, right: Node3D) -> void:
		rest.append([left, right])

	func clear_rest_hand_targets(left: Node3D, right: Node3D) -> void:
		clears.append([left, right])

	func set_hold_target(side: String, frame: Transform3D, kind := "hold") -> void:
		holds.append([side, frame, kind])

	func clear_hold_target(side: String) -> void:
		releases.append(side)

	func hand_frame(side: String) -> Transform3D:
		palm.origin = Vector3.ZERO
		return palm if side == "right" else Transform3D.IDENTITY


## A desktop Anon body with only the one nullable member the act parks and restores.
class FakeAvatar extends Node3D:
	var desktop_pose_driver: Variant = null


## The player rig the Anon view binds: the private members it writes and the body it resolves.
class FakeAnonPlayer extends FakePlayer:
	var _pitch := 0.0
	var _stand_eye := 1.5
	var _eye_height := 1.5
	var _q_held := false
	var _space_hold := 0.0
	var _rest_held := false
	var knockdown: Variant = null
	var stand_ups := 0
	var sits: Array = []
	var sleeps := 0
	var eye_y := 0.0

	func _set_eye_y(value: float) -> void:
		eye_y = value

	func force_stand_up() -> void:
		stand_ups += 1

	func sit_on(seat: Node3D) -> bool:
		sits.append(seat)
		return true

	func toggle_couch_sleep() -> bool:
		sleeps += 1
		return true


## The form driver the view clamps and whose kind the form readers report.
class FakeFormDriver extends Node:
	var form := {}
	var clamps := 0

	func clamp_view() -> void:
		clamps += 1


## The knockdown handle his body carries.
class FakeKnockdown extends RefCounted:
	var starts: Array = []

	func start(body: Node3D, direction: Vector3) -> void:
		starts.append([body, direction])



## Her own awareness facing, which the gaze fallback reads off the body.
class FakeAwarePony extends Node3D:
	var forward := Vector3.FORWARD

	func awareness_forward() -> Vector3:
		return forward


## The pony's joint limits: the clamp the pose rig applies after a rotation.
class FakeLimits extends RefCounted:
	var clamps: Array = []

	func constrain(bone: int, basis: Basis) -> Basis:
		clamps.append([bone, basis])
		return Basis(Vector3.UP, 0.5)


## Her expression controller: every write the face view makes, and the two live fields it reads.
class FakeExpressions extends RefCounted:
	var touches: Array = []
	var releases: Array = []
	var stares: Array = []
	var flusters: Array = []
	var cleared := 0
	var finished := 0.0
	var fluster_amount := 0.0
	var dialogue_face := ""

	func touch(source: String, smile: float, lids: float) -> void:
		touches.append([source, smile, lids])

	func release_touch(source: String) -> void:
		releases.append(source)

	func stare(on: bool, lids: float) -> void:
		stares.append([on, lids])

	func fluster(seconds: float, peeks: bool) -> void:
		flusters.append([seconds, peeks])

	func set_dialogue(face: String) -> void:
		dialogue_face = face

	func finish_dialogue(seconds: float) -> void:
		finished = seconds

	func clear_dialogue() -> void:
		cleared += 1
		dialogue_face = ""


## Her touch body: the hull sync the flank view runs.
class FakeTouchBody extends Node3D:
	var synced: Array = []

	func _unprofiled_sync(rig: int, _all: bool) -> void:
		synced.append(rig)


## The flank patch the act skins and jiggles.
class FakeFlankTouch extends Node:
	var _jiggle_amount := -1.0
	var impacts: Array = []
	var wakes := 0
	var jiggles: Array = []
	var frames := 0

	func impact(index: int, at: Vector3, strength: float) -> void:
		impacts.append([index, at, strength])

	func wake_tick() -> void:
		wakes += 1

	func _start_jiggle(index: int, strength: float) -> void:
		jiggles.append([index, strength])

	func _process(_delta: float) -> void:
		frames += 1


## The posed patch's own skinning call.
class FakeSurface extends RefCounted:
	var skins: Array = []

	func update_pose(skeleton: Skeleton3D, frame: Transform3D) -> void:
		skins.append([skeleton, frame])


## The director's model config: the game's own AI gate reads its usage mode.
class FakeConfig extends Node:
	func get_value(_key: String, fallback: Variant = null) -> Variant:
		return fallback


## The director's model client: the status path the classifier shows.
class FakeLlm extends Node:
	var status_path := ""


## The director's TTS node: its mode and its server answer.
class FakeTts extends Node:
	var voice_mode := "auto"
	var live := true

	func has_server() -> bool:
		return live


## An approach or group exchange the director reports.
class FakeSubsystem extends RefCounted:
	var live := false

	func active() -> bool:
		return live


## Her generated vocal node: the cache prepare and the play.
class FakeVocal extends Node:
	var prepared: Array = []

	func prepare(id: String) -> void:
		prepared.append(id)

	func play(_id: String, _gender: String, _pony: Variant, _db: float) -> bool:
		return true


## Her boop node's kiss op.
class FakeKissBoop extends Node:
	var kisses := 0

	func play_kiss(_db: float, _loop: bool) -> void:
		kisses += 1


## The conversation director: the live routing fields and the authored-line host.
class FakeDirector extends Node:
	var state := "idle"
	var characters: Dictionary = {}
	var tts: Variant = null
	var vocal: Variant = null
	var config: Variant = null
	var llm: Variant = null
	var interrupts := 0
	var cancelled: Array = []
	var _section: Dictionary = {}

	func interrupt() -> void:
		interrupts += 1

	func _now() -> float:
		return 42.0

	func _llm_section() -> Dictionary:
		return _section

	func begin_player_greeting(_id: String, _context: String) -> bool:
		return true

	func queue_generated_intent(_id: String, _purpose: String, _key: String, _valid: Callable,
			_finished: Callable, _once := false, _firm := false) -> bool:
		return true

	func cancel_authored_line(key: String) -> void:
		cancelled.append(key)


## The world context: the story journal, the impressions store and the event list.
class FakeContext extends Node:
	var story: Variant = null
	var impressions: Variant = null
	var events: Array = []
	var records: Array = []
	var state: Dictionary = {}

	func record(kind: String, text: String, witnesses: Array, subjects: Array, event_id: String,
			place := "") -> void:
		records.append({"kind": kind, "text": text, "witnesses": witnesses,
			"subjects": subjects, "id": event_id, "place": place})

	func events_for(_id: String, limit: int) -> Array:
		return events.slice(0, limit)


## The impressions store: one profile per mare and the commit key.
class FakeImpressions extends Node:
	var profiles: Dictionary = {}
	var commits: Array = []

	func profile(id: String) -> Dictionary:
		return profiles.get(id, {})

	func commit(id: String, data: Dictionary, key: String) -> void:
		commits.append({"id": id, "data": data, "key": key})

	func standing_line(_id: String) -> String:
		return "steady"


## The story journal: its store, its open flag and its line wording.
class FakeStory extends RefCounted:
	var store: Variant = null
	var live := true

	func is_open() -> bool:
		return live

	func line_text(row: Variant, pony: String, with_day: bool) -> String:
		return "%s:%s:%s" % [row.id, pony, str(with_day)]


## The story line store: the newest id, the word search and the witnessed lines.
class FakeStoryStore extends RefCounted:
	var rows: Array = []
	var seen: Array = []
	var last := 7

	func last_line_id() -> int:
		return last

	func search(_pony: String, _words: Array, _before: int, limit: int) -> Array:
		return rows.slice(0, limit)

	func witnessed(_pony: String, limit: int, _before: int, _kinds: Array) -> Array:
		return seen.slice(0, limit)


## The scene's relationship runtime: one bond store and one ladder row per pony.
class FakeRelationRuntime extends Node:
	var bonds: Variant = null
	var ladders: Dictionary = {}

	func ladder(id: String) -> Dictionary:
		return ladders.get(id, {})


## The bond store: the record, the romance test, the welcome, the day and the two writes.
class FakeBonds extends RefCounted:
	var rows: Dictionary = {}
	var met: Array = []
	var spaces: Array = []
	var romance := true
	var day_now := 12.5

	func record_for(id: String) -> Dictionary:
		return rows.get(id, {})

	func eligible_for_romance(_id: String) -> bool:
		return romance

	func welcomes(_id: String, kind: String) -> bool:
		return kind == "kiss"

	func day() -> float:
		return day_now

	func mark_met(id: String) -> void:
		met.append(id)

	func request_space(id: String) -> void:
		spaces.append(id)


## The game's mods registry autoload: one live section per mod, the pack rows and the save call.
class FakeModsHost extends Node:
	var data: Dictionary = {}
	var rows: Array = []
	var saves := 0

	func state(id: String) -> Dictionary:
		if not data.has(id):
			data[id] = {}
		return data[id]

	func is_active(id: String) -> bool:
		return id == "dance_mod"

	func save_changed() -> void:
		saves += 1

	func list() -> Array:
		return rows


## The stock cuddle session the act ends before it takes the pose.
class FakeCuddle extends Node:
	var ended := 0

	func end(_force: bool) -> void:
		ended += 1


## Her hoof hold's active flag.
class FakeHoof extends RefCounted:
	func active() -> bool:
		return true


## The reach that carries a pony, with its desktop actions node.
class FakeReach extends Node:
	var held: Variant = null
	var cradled := false
	var desktop_actions: Variant = null


## The desktop actions that hear the carried pony was released.
class FakeActions extends Node:
	var released := 0

	func pony_released() -> void:
		released += 1


## A body that owns her own hold interaction.
class FakeEndPony extends Node3D:
	var endings := 0

	func end_interaction() -> void:
		endings += 1



func run() -> void:
	_check_unbound()
	_check_binding()
	_check_game_player()
	_check_accessors()
	_check_camera()
	_check_player_body()
	_check_real_bed()
	_check_bed_occupancy()
	_check_player_beside_bed()
	_check_menu_and_headset()
	_check_open_chat()
	_check_place_and_ops()
	_check_kiss_and_settings()
	_check_turn_and_wing_accessors()
	_check_pose_accessors()
	_check_views()
	_check_anon_view()
	_check_bed_view()
	_check_director_and_story()
	_check_inventory_and_menu()
	_check_relationship_mods_affection()
	_check_body_lod()
	_check_desktop()
	await _check_bed_under()
	_check_freed_handles()
	WORLD.unbind()
	check(WORLD.world_root() == null and WORLD.player_rig() == null, "unbind clears the bound handles")

	finish()


## A bound handle freed without unbind answers the unbound values, not a dead node's.
func _check_freed_handles() -> void:
	var game := FakeGame.new()
	root.add_child(game)
	var player := FakePlayer.new()
	root.add_child(player)
	WORLD.bind_world(game)
	WORLD.bind_player(player)
	game.free()
	player.free()
	check(WORLD.headset_view() == false, "a freed world is no headset")
	check(WORLD.game_player() == null, "a freed world has no game player")
	check(WORLD.mares().is_empty(), "a freed world has no mares")
	check(not WORLD.menu_panel_open(), "a freed world has no open panel")
	check(WORLD.camera() == null, "a freed rig has no camera")
	check(not WORLD.open_chat(), "a freed world opens no chat")
	WORLD.unbind()


func _check_unbound() -> void:
	WORLD.unbind()
	check(WORLD.world_root() == null and WORLD.player_rig() == null, "an unbound facade has no world")
	check(WORLD.camera() == null, "an unbound facade has no camera")
	check(WORLD.interactor() == null, "an unbound facade has no interactor")
	check(WORLD.player_body() == null, "an unbound facade has no player body")
	check(WORLD.mares().is_empty(), "an unbound facade has no mares")
	check(WORLD.bed_under(Vector3.ZERO) == null, "an unbound facade finds no bed")
	check(WORLD.real_bed(null) == null, "no node is no bed")
	check(WORLD.bed_for_cradle(null) == null, "no pony is no cradle bed")
	check(not WORLD.bed_occupied(null, null), "no bed is not occupied")
	check(not WORLD.player_beside_bed(null), "no player is not beside a bed")
	check(not WORLD.headset_view(), "no world is no headset")
	check(not WORLD.open_chat(), "no world opens no chat")
	check(not WORLD.ready(), "an unbound facade is not ready")
	check(WORLD.player_rig() == null, "an unbound facade has no rig")
	check(WORLD.world_root() == null, "an unbound facade has no world root")
	check(WORLD.interaction_hints() == null, "an unbound facade has no hints node")
	check(WORLD.presentation() == null, "an unbound facade has no presentation")
	check(WORLD.shape_ids().is_empty(), "an unbound facade has no shape catalogue")
	check(not WORLD.bond_level("rarity").found, "an unbound facade has no bond level")
	check(not WORLD.paused(), "an unbound facade is not paused")
	WORLD.refresh_body_lod(null)


func _check_binding() -> void:
	var game := FakeGame.new()
	root.add_child(game)
	var list: Array = [FakeMare.new(), FakeMare.new()]
	game.mares = list
	WORLD.bind_world(game)
	check(WORLD.world_root() == game, "bind_world stores the world root")
	check(not is_same(WORLD.mares(), list), "the facade answers with a copy, not the game array")
	check(WORLD.mares().size() == list.size(), "the copy holds every mare")
	var player := FakePlayer.new()
	WORLD.bind_player(player)
	check(WORLD.player_rig() != null, "bind_player stores Anon's body")
	check(WORLD.player_rig() == player, "the facade hands back the bound rig")
	check(WORLD.ready(), "a bound world and rig are ready")
	WORLD.bind_world(null)
	check(WORLD.player_rig() != null, "a world bind keeps the player")
	check(WORLD.world_root() == null, "a null world bind clears the world")
	check(not WORLD.ready(), "a missing world is not ready")
	WORLD.bind_world(game)
	WORLD.bind_player(null)
	check(WORLD.world_root() == game and WORLD.player_rig() == null, "the player leaves on its own")
	for mare: Node in list:
		mare.free()
	player.free()
	game.queue_free()
	WORLD.unbind()


## Every base-game accessor: the live answer and the absent one.
func _check_accessors() -> void:
	var player := FakePlayer.new()
	root.add_child(player)
	var camera := Camera3D.new()
	player.add_child(camera)
	player.camera = camera
	check(GAME.player_camera(player) == camera, "the rig's own camera is read")
	check(GAME.player_camera(null) == null, "no rig reads no camera")
	var plain := Node3D.new()
	root.add_child(plain)
	check(GAME.player_camera(plain) == null, "a rig without a camera reads null")

	var game := FakeGame.new()
	root.add_child(game)
	var found := Camera3D.new()
	root.add_child(found)
	game.found_camera = found
	check(GAME.find_camera(game, player) == found, "the scene's camera search is read")
	check(GAME.find_camera(plain, player) == null, "a scene without the search finds no camera")
	check(GAME.find_camera(game, null) == null, "no player finds no camera")

	var mare := FakeMare.new()
	var stray := Node.new()
	root.add_child(mare)
	root.add_child(stray)
	game.mares = [mare, stray, null]
	var copy := GAME.mares(game)
	check(copy.size() == 1 and copy[0] == mare, "the mare copy keeps only live bodies")
	check(GAME.mares(null).is_empty(), "no world copies no mares")

	var avatar := Node3D.new()
	player.add_child(avatar)
	var form := FakeForm.new()
	form.avatar = avatar
	player.form_driver = form
	check(GAME.player_avatar(player) == avatar, "the form driver's avatar is read")
	check(GAME.player_avatar(plain) == null, "a rig without a form has no avatar")
	var body := Node3D.new()
	body.name = "Body"
	plain.add_child(body)
	check(GAME.player_body_node(plain) == body, "the rig's Body child is found")
	check(GAME.player_body_node(null) == null, "no rig has no body child")

	var seat := FakeSeat.new()
	player.seat = seat
	check(GAME.seat_of(player) == seat, "the rig's seat is read")
	check(GAME.seat_of(plain) == null, "a standing rig has no seat")

	player.controls_locked = true
	check(GAME.controls_locked(player), "a held rig reads locked")
	GAME.set_controls_locked(player, false)
	check(not player.controls_locked, "the hold is released")
	check(not GAME.controls_locked(plain), "an absent hold flag reads unlocked")
	GAME.set_controls_locked(null, true)

	check(GAME.menu_panel(game, "settings_menu") == null, "an absent panel reads null")
	var save_menu := FakePanel.new()
	game.save_menu = save_menu
	check(GAME.menu_panel(game, "save_menu") == save_menu, "a named panel is read")
	check(GAME.menu_panel(null, "save_menu") == null, "no world reads no panel")

	var inventory := FakeInventory.new()
	game.inventory = inventory
	check(GAME.inventory(game) == inventory, "the inventory is read")
	check(GAME.inventory(null) == null, "no world has no inventory")
	check(not GAME.map_open(inventory), "an inventory without a map test is closed")
	var map_inventory := FakeMapInventory.new()
	root.add_child(map_inventory)
	check(GAME.map_open(map_inventory), "the inventory's own map test answers")
	var briefcase := FakeCase.new()
	briefcase.visible = true
	inventory.case = briefcase
	check(GAME.case_visible(inventory), "a visible briefcase reads open")
	briefcase.visible = false
	check(not GAME.case_visible(inventory), "a hidden briefcase reads closed")
	var customizer := FakePanel.new()
	customizer.opened = true
	inventory.customizer = customizer
	check(GAME.customizer_opened(inventory), "an opened customizer reads open")
	var inspector := FakePanel.new()
	inspector.active = true
	inventory.inspector = inspector
	check(GAME.inspector_active(inventory), "an active inspector reads active")
	check(not GAME.inspector_active(null), "no inventory has no inspector")

	var chat := FakeChat.new()
	chat.name = "ChatBox"
	chat.watcher = player
	game.add_child(chat)
	player.controls_locked = true
	check(GAME.chat_box(game) == chat, "the chat box is read by name")
	check(GAME.open_chat(game, player), "the chat opens past the hold")
	check(chat.saw_unlocked, "the hold is released while the chat opens")
	check(player.controls_locked, "the hold is restored after the chat opens")
	check(not GAME.open_chat(null, player), "no world opens no chat")

	var pony := FakeBody.new()
	root.add_child(pony)
	check(GAME.identity_of(pony) == pony.identity, "a hybrid identity is read")
	check(GAME.identity_of(plain) == null, "a plain node has no identity")
	var boop := FakeBoop.new()
	pony.boop_node = boop
	check(GAME.boop_of(pony) == boop, "the blush sustainer is read")
	check(GAME.boop_of(plain) == null, "a body without a sustainer reads null")
	GAME.sustain_blush(boop, 0.5)
	check(boop.amount == 0.5, "the sustainer takes the amount")
	GAME.sustain_blush(plain, 0.7)
	check(boop.amount == 0.5, "a node without the method stays silent")
	var head_skeleton := Skeleton3D.new()
	boop.add_child(head_skeleton)
	boop.head_skeleton = head_skeleton
	check(GAME.head_skeleton_of(boop) == head_skeleton, "the sustainer's head skeleton is read")
	check(GAME.head_skeleton_of(plain) == null, "a plain node has no head skeleton")
	var head := FakeHead.new()
	root.add_child(head)
	var mouth := FakeMouth.new()
	head.add_child(mouth)
	head.mouth = mouth
	pony.head = head
	check(GAME.head_of(pony) == head, "the head node is read")
	check(GAME.head_of(plain) == null, "a plain node has no head")
	check(GAME.mouth_of(head) == mouth, "the head's mouth rig is read")
	check(GAME.mouth_of(plain) == null, "a plain head has no mouth")
	GAME.set_viseme(mouth, "D")
	check(mouth.visemes == ["D"], "the viseme is written to the mouth rig")
	GAME.set_viseme(plain, "D")
	check(mouth.visemes == ["D"], "a node without the viseme method stays silent")
	GAME.clear_viseme(mouth)
	check(mouth.clears == 1, "the viseme clear reaches the mouth rig")
	GAME.clear_viseme(plain)
	check(mouth.clears == 1, "a node without the clear method stays silent")
	head.queue_free()

	# The body members the anatomy reads: skeleton, hair, model, dock link, LOD and the eye rig.
	var rig := FakeBody.new()
	root.add_child(rig)
	var body_skeleton := Skeleton3D.new()
	rig.add_child(body_skeleton)
	rig.skeleton = body_skeleton
	var hair_skeleton := Skeleton3D.new()
	rig.add_child(hair_skeleton)
	rig.hair_skeleton = hair_skeleton
	var hair := Node3D.new()
	rig.add_child(hair)
	rig.hair = hair
	var model := Node3D.new()
	rig.add_child(model)
	rig._model = model
	var drawn_body := MeshInstance3D.new()
	drawn_body.name = "MareBody"
	model.add_child(drawn_body)
	var link := FakeHairLink.new()
	rig.add_child(link)
	rig.hair_link = link
	var eye := SkeletonModifier3D.new()
	rig.add_child(eye)
	rig.eye_motion = eye
	rig.body_scale = 1.25
	var dock := MeshInstance3D.new()
	dock.name = "OpenPonyDock"
	rig.add_child(dock)
	check(GAME.skeleton_of(rig) == body_skeleton, "the body skeleton is read")
	check(GAME.skeleton_of(plain) == null, "a plain node has no body skeleton")
	check(GAME.hair_skeleton_of(rig) == hair_skeleton, "the hair skeleton is read")
	check(GAME.hair_skeleton_of(plain) == null, "a plain node has no hair skeleton")
	check(GAME.hair_of(rig) == hair, "the hair node is read")
	check(GAME.hair_of(plain) == null, "a plain node has no hair")
	check(GAME.dock_of(rig) == dock, "the game dock is found under the pony")
	check(GAME.dock_of(plain) == null, "a plain node has no dock")
	check(is_equal_approx(GAME.body_scale_of(rig), 1.25), "the body scale is read")
	check(is_equal_approx(GAME.body_scale_of(plain), 1.0), "an absent body scale answers 1.0")
	var flank := FakeFlank.new()
	flank.name = "FlankTouch"
	rig.add_child(flank)
	GAME.own_body_materials(rig)
	check(flank.calls == 1, "the per-pony body materials are copied")
	GAME.own_body_materials(plain)
	check(flank.calls == 1, "a pony without FlankTouch stays silent")
	check(GAME.model_of(rig) == model, "the model root is read")
	check(GAME.model_of(plain) == null, "a plain node has no model")
	check(GAME.body_of(rig) == drawn_body, "the drawn MareBody is found under the model")
	check(GAME.body_of(plain) == null, "a plain node has no drawn body")
	check(GAME.hair_link_of(rig) == link, "the hair link is read")
	check(GAME.hair_link_of(plain) == null, "a plain node has no hair link")
	check(GAME.hair_link_ready(rig), "a link with a pelvis offset is ready")
	check(GAME.hair_link_pelvis(rig) == link.pelvis_offset, "the pelvis offset is read")
	check(not GAME.hair_link_ready(plain), "a node without a link is not ready")
	check(GAME.hair_link_pelvis(plain) == Transform3D.IDENTITY,
		"an absent link answers the identity")
	GAME.set_hair_link_pelvis(rig, Transform3D.IDENTITY)
	check(rig.hair_link.pelvis_offset == Transform3D.IDENTITY, "the pelvis offset is written")
	GAME.notify_hair_link(rig)
	check(link.updates == 1, "the link's body update is forwarded")
	GAME.set_hair_link_pelvis(plain, Transform3D.IDENTITY)
	GAME.notify_hair_link(plain)
	check(not GAME.far_mesh_shown(rig), "the near mesh reads as the shown one")
	rig._far_mesh_shown = true
	check(GAME.far_mesh_shown(rig), "the far mesh flag is read")
	check(not GAME.far_mesh_shown(plain), "a plain node is never far")
	GAME.set_near_mesh(rig, false)
	check(rig.near_calls == [false], "the near-mesh switch is forwarded")
	GAME.set_near_mesh(plain, true)
	check(GAME.eye_motion_of(rig) == eye, "the eye modifier is read")
	check(GAME.eye_motion_of(plain) == null, "a plain node has no eye modifier")
	var anon := Node3D.new()
	anon.name = "AnonBody"
	player.add_child(anon)
	check(GAME.anon_body_of(player) == anon, "Anon's body is found under the rig")
	check(GAME.anon_body_of(plain) == null, "a rig without Anon's body answers null")
	anon.queue_free()
	eye.queue_free()
	flank.queue_free()
	dock.queue_free()
	link.queue_free()
	drawn_body.queue_free()
	model.queue_free()
	hair.queue_free()
	hair_skeleton.queue_free()
	body_skeleton.queue_free()
	rig.queue_free()

	check(GAME.headset_view(null) == false, "no world is no headset")
	check(GAME.game_player(null) == null, "no world has no game player")
	check(GAME.chat_box(null) == null, "no world has no chat box")
	check(GAME.identity_of(null) == null, "no pony has no identity")
	check(GAME.boop_of(null) == null, "no pony has no sustainer")
	check(is_nan(GAME.eye_height(null)), "no rig answers NAN")

	check(GAME.eye_height(player) == player.eye_line, "the rig's eye line is read")
	check(is_nan(GAME.eye_height(plain)), "a rig without the read answers NAN")
	GAME.set_eye_y(pony, 1.4)
	check(pony.eye_y == 1.4, "the eye setter writes the line")
	var bare := FakePlainBody.new()
	root.add_child(bare)
	GAME.set_eye_y(bare, 1.4)
	check(bare.eye_y == 0.0, "a rig without the setter is left alone")

	var bed := Node3D.new()
	bed.set_meta("mattress_top", 0.6)
	root.add_child(bed)
	var support := Node3D.new()
	bed.add_child(support)
	check(GAME.bed_of(support) == bed, "a mattress ancestor is the bed")
	check(GAME.bed_of(bare) == null, "a plain collider is no bed")
	check(GAME.bed_of(null) == null, "no collider is no bed")

	var cached := HYBRID_NEAR_MESH.cache.size()
	GAME.refresh_body_lod(plain)
	check(HYBRID_NEAR_MESH.cache.size() == cached, "a plain node has no LOD cache to drop")

	chat.queue_free()
	pony.queue_free()
	bare.queue_free()
	bed.queue_free()
	seat.free()
	boop.free()
	save_menu.queue_free()
	inventory.queue_free()
	map_inventory.queue_free()
	customizer.queue_free()
	inspector.queue_free()
	briefcase.queue_free()
	stray.queue_free()
	mare.queue_free()
	plain.queue_free()
	player.queue_free()
	game.queue_free()
	found.queue_free()


## The game's own player read stays defensive: a missing or renamed property is null, not a crash.
func _check_game_player() -> void:
	WORLD.unbind()
	check(WORLD.game_player() == null, "an unbound facade has no game player")
	var game := FakeGame.new()
	root.add_child(game)
	WORLD.bind_world(game)
	check(WORLD.game_player() == null, "a game without a player read has no game player")
	var player := FakePlayer.new()
	root.add_child(player)
	game.player = player
	check(WORLD.game_player() == player, "the game's player property is read defensively")
	var wrong := Node.new()
	root.add_child(wrong)
	game.player = wrong
	check(WORLD.game_player() == null, "a non-Node3D player reads as null")
	game.player = null
	player.queue_free()
	wrong.queue_free()
	game.queue_free()
	WORLD.unbind()


func _check_camera() -> void:
	var player := FakePlayer.new()
	var direct := Camera3D.new()
	root.add_child(player)
	player.add_child(direct)
	player.camera = direct
	WORLD.bind_player(player)
	check(WORLD.camera() == direct, "Anon's own camera wins")

	player.camera = null
	var game := FakeGame.new()
	root.add_child(game)
	WORLD.bind_world(game)
	WORLD.camera()
	WORLD.camera()
	check(game.find_calls == 1, "the found camera is cached for a second")

	var bare := BareGame.new()
	root.add_child(bare)
	WORLD.bind_world(bare)
	check(WORLD.camera() == root.get_camera_3d(),
		"no player camera and no find hook read the viewport camera")

	WORLD.bind_player(null)
	check(WORLD.camera() == null, "no player is no camera")
	player.queue_free()
	game.queue_free()
	bare.queue_free()
	WORLD.unbind()


func _check_player_body() -> void:
	var player := FakePlayer.new()
	root.add_child(player)
	WORLD.bind_player(player)
	check(WORLD.player_body() == player, "the rig is the body when it has no Body child")
	var body := Node3D.new()
	body.name = "Body"
	player.add_child(body)
	check(WORLD.player_body() == body, "the rig's Body child is the shown body")
	var avatar := Node3D.new()
	avatar.name = "AnonBody"
	player.add_child(avatar)
	var form := FakeForm.new()
	form.avatar = avatar
	player.form_driver = form
	check(WORLD.player_body() == avatar, "the AnonPony avatar wins")
	player.queue_free()
	WORLD.unbind()


func _check_real_bed() -> void:
	var bed := Node3D.new()
	bed.set_meta("mattress_top", 0.6)
	root.add_child(bed)
	var support := Node3D.new()
	bed.add_child(support)
	check(WORLD.real_bed(support) == bed, "a mattress ancestor is the bed")
	var rest_support := Node3D.new()
	rest_support.set_meta("shared_rest_support", true)
	bed.add_child(rest_support)
	check(WORLD.real_bed(rest_support) == bed, "a shared rest support resolves to its parent")
	var soft := Node3D.new()
	soft.set_meta("soft_support", true)
	root.add_child(soft)
	check(WORLD.real_bed(soft) == soft, "a soft support is its own bed")
	var floor := Node3D.new()
	root.add_child(floor)
	check(WORLD.real_bed(floor) == null, "a plain node is no bed")
	bed.queue_free()
	soft.queue_free()
	floor.queue_free()


func _check_bed_occupancy() -> void:
	var game := FakeGame.new()
	root.add_child(game)
	var bed := Node3D.new()
	bed.set_meta("mattress_top", 0.6)
	root.add_child(bed)
	var target := FakeMare.new()
	var neighbour := FakeMare.new()
	neighbour.requested = "lie_down"
	root.add_child(target)
	root.add_child(neighbour)
	game.mares = [target, neighbour]
	neighbour.global_position = bed.to_global(Vector3(0.0, 0.6, 0.0))
	WORLD.bind_world(game)
	check(WORLD.bed_occupied(bed, target), "a lying mare on the mattress top occupies it")
	check(not WORLD.bed_occupied(bed, neighbour), "the target never occupies its own bed")
	neighbour.requested = "stand"
	check(not WORLD.bed_occupied(bed, target), "a standing mare does not occupy the bed")
	neighbour.requested = "lie_down"
	neighbour.global_position = bed.to_global(Vector3(3.0, 0.6, 0.0))
	check(not WORLD.bed_occupied(bed, target), "a mare across the room does not occupy it")
	neighbour.global_position = bed.to_global(Vector3(0.0, 1.8, 0.0))
	check(not WORLD.bed_occupied(bed, target), "a mare a storey up does not occupy it")
	game.queue_free()
	bed.queue_free()
	target.queue_free()
	neighbour.queue_free()
	WORLD.unbind()


func _check_player_beside_bed() -> void:
	var game := FakeGame.new()
	root.add_child(game)
	WORLD.bind_world(game)
	var bed := Node3D.new()
	root.add_child(bed)
	var player := FakePlayer.new()
	root.add_child(player)
	WORLD.bind_player(player)
	check(WORLD.player_beside_bed(bed), "a standing Anon is beside the bed")
	var seat := FakeSeat.new()
	bed.add_child(seat)
	player.seat = seat
	check(WORLD.player_beside_bed(bed), "a seat on the bed is beside it")
	var elsewhere := FakeSeat.new()
	root.add_child(elsewhere)
	player.seat = elsewhere
	check(not WORLD.player_beside_bed(bed), "a seat elsewhere is not beside it")
	player.queue_free()
	bed.queue_free()
	elsewhere.queue_free()
	game.queue_free()
	WORLD.unbind()


func _check_menu_and_headset() -> void:
	var game := FakeGame.new()
	root.add_child(game)
	WORLD.bind_world(game)
	check(not WORLD.menu_panel_open(), "an empty world has no open panel")
	var save_menu := FakePanel.new()
	save_menu.opened = true
	game.save_menu = save_menu
	check(WORLD.menu_panel_open(), "an opened save menu owns the mouse")
	save_menu.opened = false
	check(not WORLD.menu_panel_open(), "a closed save menu does not")
	var inventory := FakeInventory.new()
	var case := FakeCase.new()
	case.visible = true
	inventory.case = case
	root.add_child(inventory)
	game.inventory = inventory
	check(WORLD.menu_panel_open(), "a visible briefcase owns the mouse")
	case.visible = false
	check(not WORLD.menu_panel_open(), "a hidden briefcase does not")
	check(WORLD.menu_open() == (Input.mouse_mode != Input.MOUSE_MODE_CAPTURED),
		"menu_open adds the visible cursor to the panel test")
	game.headset_view = true
	check(WORLD.headset_view(), "the world's headset flag is the headset view")
	paused = true
	check(WORLD.paused(), "the live world's paused tree is the paused read")
	check(WORLD.menu_panel_open(), "a paused tree is an open panel")
	paused = false
	check(not WORLD.paused(), "an unpaused tree is not paused")
	var hints := Node.new()
	hints.name = "InteractionHints"
	game.add_child(hints)
	var presentation := Node.new()
	game.desktop_presentation = presentation
	check(WORLD.interaction_hints() == hints, "the world's own hints node is read")
	check(WORLD.presentation() == presentation, "the game's desktop presentation is read")
	var population := FakePopulation.new()
	population.available = {"rarity": "res://rarity.tscn", "": "res://skip.tscn"}
	root.add_child(population)
	game.population = population
	check(WORLD.shape_ids() == ["rarity"],
		"the population catalogue is copied by non-empty shape id")
	check(WORLD.shape_scene("missing") == null, "a shape the catalogue does not hold has no scene")
	game.queue_free()
	inventory.queue_free()
	population.queue_free()
	save_menu.free()
	case.free()
	presentation.free()
	WORLD.unbind()


func _check_open_chat() -> void:
	var game := FakeGame.new()
	root.add_child(game)
	var player := FakePlayer.new()
	root.add_child(player)
	var chat := FakeChat.new()
	chat.name = "ChatBox"
	game.add_child(chat)
	WORLD.bind_world(game)
	WORLD.bind_player(player)
	player.controls_locked = true
	check(WORLD.open_chat(), "the act chat opens past the controls lock")
	check(chat.opened, "the game's chat box was opened")
	check(player.controls_locked, "the controls lock is restored")
	check(not bool(chat._lock_owned), "the opened chat takes its lock back")
	chat.queue_free()
	var bare := BareGame.new()
	root.add_child(bare)
	WORLD.bind_world(bare)
	check(not WORLD.open_chat(), "a world without a chat box opens nothing")
	bare.queue_free()
	game.queue_free()
	player.queue_free()
	WORLD.unbind()


## The place reads and the ops that compose the accessor layer: a house's bed, the shop's item and
## a body's velocity.
func _check_place_and_ops() -> void:
	var game := FakeGame.new()
	root.add_child(game)
	WORLD.bind_world(game)

	var bed := Node3D.new()
	root.add_child(bed)
	var house := FakeHouse.new()
	house.bed = bed
	root.add_child(house)
	check(WORLD.ensure_bed(house) == bed, "a house's bed is read through its builder")
	check(house.kinds == [""], "the facade asks for the house's unnamed bed")
	var plain := Node.new()
	root.add_child(plain)
	check(WORLD.ensure_bed(plain) == null, "a node that is no house has no bed")

	var moving := FakeMoving.new()
	root.add_child(moving)
	WORLD.set_velocity(moving, Vector3(1.0, 2.0, 3.0))
	check(moving.velocity == Vector3(1.0, 2.0, 3.0), "a body's velocity is written")
	WORLD.set_velocity(null, Vector3.ONE)
	check(WORLD.shop_item("") == null, "the shop has no item without an id")

	plain.queue_free()
	house.queue_free()
	bed.queue_free()
	moving.queue_free()
	game.queue_free()
	WORLD.unbind()


func _check_body_lod() -> void:
	var pony := FakeBody.new()
	root.add_child(pony)
	var near_key: String = HYBRID_NEAR_MESH.key(pony)
	var far_key: String = HYBRID_FAR_MESH._id(pony)
	HYBRID_NEAR_MESH.cache[near_key] = true
	HYBRID_FAR_MESH.cache[far_key] = true
	HYBRID_FAR_MESH.shadow_cache[far_key] = true
	HYBRID_FAR_MESH.eyes_cache[far_key] = true
	WORLD.refresh_body_lod(pony)
	check(not HYBRID_NEAR_MESH.cache.has(near_key), "the near LOD cache entry is dropped")
	check(not HYBRID_FAR_MESH.cache.has(far_key), "the far LOD cache entry is dropped")
	check(not HYBRID_FAR_MESH.shadow_cache.has(far_key), "the shadow cache entry is dropped")
	check(not HYBRID_FAR_MESH.eyes_cache.has(far_key), "the eyes cache entry is dropped")
	check(pony.near_calls == [false, true], "the near mesh is re-armed off then on")
	pony.near_calls.clear()
	pony.near_mesh_enabled = false
	WORLD.refresh_body_lod(pony)
	check(pony.near_calls.is_empty(), "a body with the near mesh disabled is not re-armed")
	pony.queue_free()


func _check_desktop() -> void:
	var node := Node.new()
	root.add_child(node)
	node.add_to_group("desktop_interactions")
	var game := FakeGame.new()
	WORLD.bind_world(game)
	check(WORLD.desktop() == node, "the desktop interactions node is found by group")
	WORLD.unbind()
	node.queue_free()
	game.free()


## The one read that needs a live physics space: a mattress probe under a resting body.
func _check_bed_under() -> void:
	var bed := Node3D.new()
	bed.name = "FakeBed"
	bed.set_meta("mattress_top", 0.6)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.2, 4.0)
	shape.shape = box
	body.add_child(shape)
	bed.add_child(body)
	root.add_child(bed)
	bed.global_position = Vector3(0.0, 0.5, 0.0)
	var player := FakePlayer.new()
	root.add_child(player)
	var game := BareGame.new()
	WORLD.bind_world(game)
	WORLD.bind_player(player)
	await physics_frame
	await physics_frame
	var found := WORLD.bed_under(Vector3(0.0, 0.6, 0.0))
	check(found == bed, "the probe under a body finds the bed")
	check(WORLD.bed_under(Vector3(40.0, 0.6, 0.0)) == null, "the probe under nothing finds no bed")
	bed.queue_free()
	player.queue_free()
	game.free()
	WORLD.unbind()


## The kiss bridge and the rig readers: every member's live answer and its typed zero.
func _check_kiss_and_settings() -> void:
	var plain := Node.new()
	root.add_child(plain)

	var game := FakeGame.new()
	root.add_child(game)
	check(GAME.kisser_of(game) == null, "a scene without a kisser answers null")
	var kisser := FakeKisser.new()
	root.add_child(kisser)
	game.kisser = kisser
	check(GAME.kisser_of(game) == kisser, "the scene's kisser is read")
	var pony := FakeMare.new()
	root.add_child(pony)
	check(GAME.begin_from_pony(kisser, pony), "the kisser starts the stock kiss")
	check(kisser.begins == 1, "the kiss call reaches the kisser")
	check(not GAME.begin_from_pony(null, pony), "no kisser starts no kiss")
	check(not GAME.begin_from_pony(plain, pony), "a node without the op starts no kiss")
	kisser.accepts = false
	check(not GAME.begin_from_pony(kisser, pony), "a refusing kisser answers false")
	GAME.clear_kisser(kisser)
	check(kisser._active == null and not kisser._her_kiss and not kisser._used_hold,
		"the kisser latch is cleared")
	GAME.clear_kisser(null)

	var affection := FakeAffection.new()
	root.add_child(affection)
	GAME.feed_affection(affection, Vector3.ONE, Vector3.UP, Basis.IDENTITY)
	check(affection.target == Vector3.ONE and affection.eye == Vector3.UP,
		"the affection takes Anon's live mouth and eye")
	check(affection.face.is_equal_approx(Basis.IDENTITY), "the affection takes the face basis")
	GAME.feed_affection(null, Vector3.ZERO, Vector3.ZERO, Basis.IDENTITY)
	GAME.end_affection(affection)
	GAME.cancel_afterglow(affection)
	check(affection.ended == 1 and affection.cancelled == 1, "the kiss release reaches the affection")
	GAME.end_affection(null)
	GAME.cancel_afterglow(plain)
	check(GAME.mouth_point(affection) == Vector3.ONE, "her mouth point is read")
	check(not GAME.mouth_point(plain).is_finite(), "a body without the op has no mouth point")
	check(not GAME.mouth_point(null).is_finite(), "no body has no mouth point")

	var pose := FakeKissPose.new()
	root.add_child(pose)
	check(not GAME.kiss_side_known(pose), "an unpinned kiss pose has no side")
	GAME.pin_kiss_side(pose, 1.0, 9999.0)
	check(GAME.kiss_side_known(pose) and is_equal_approx(pose._side_now, 1.0) and is_equal_approx(pose._side_wait, 9999.0),
		"the kiss pose side is pinned and held")
	GAME.release_kiss_side(pose)
	check(is_equal_approx(pose._side_wait, 0.0), "the kiss pose side hold is released")
	GAME.pin_kiss_side(null, 1.0, 1.0)
	GAME.release_kiss_side(null)
	var bare_pose := BareKissPose.new()
	root.add_child(bare_pose)
	check(not GAME.kiss_side_known(bare_pose), "a pose without the member has no side")
	GAME.pin_kiss_side(bare_pose, 1.0, 9999.0)
	GAME.release_kiss_side(bare_pose)

	var excitement := FakeExcitement.new()
	root.add_child(excitement)
	GAME.settle_excitement(excitement)
	check(is_equal_approx(excitement._until, 0.0), "the excitement hold is settled")
	GAME.settle_excitement(null)

	var mouth := FakeExpressionMouth.new()
	root.add_child(mouth)
	GAME.set_expression(mouth, "pout", 0.2)
	check(mouth.faces == ["pout"], "the mouth expression reaches the rig")
	GAME.set_expression(plain, "pout", 0.2)
	GAME.set_expression(null, "pout", 0.2)


## The turn and wing accessors the standing invitation and the wing controller read.
func _check_turn_and_wing_accessors() -> void:
	var plain := Node.new()
	root.add_child(plain)
	var nav := FakeNavigator.new()
	root.add_child(nav)
	GAME.set_face_point(nav, Vector3.ONE)
	check(nav.face_point == Vector3.ONE, "the navigator's face point takes the write")
	GAME.set_face_point(plain, Vector3.ONE)
	check(not "face_point" in plain, "a node without the face point takes no write")
	GAME.set_face_point(null, Vector3.ONE)
	nav.conversation_target = nav
	nav.conversation_hold = true
	GAME.clear_conversation_target(nav)
	check(nav.conversation_target == null and not nav.conversation_hold,
		"the navigator's conversation facing is cleared without the hold")
	GAME.clear_conversation_target(plain)
	GAME.clear_conversation_target(null)

	var pony := FakeTurnPony.new()
	root.add_child(pony)
	GAME.face_direction(pony, Vector3.RIGHT)
	check(pony.facings == [Vector3.RIGHT], "her own locomotion turn takes the direction")
	var bare := FakeMare.new()
	root.add_child(bare)
	GAME.face_direction(bare, Vector3.RIGHT)
	GAME.face_direction(null, Vector3.RIGHT)
	check(pony.facings.size() == 1, "a body without the turn takes no direction")

	var winged := FakeWingedIdentity.new()
	check(GAME.identity_has_wings(winged), "a winged identity answers its own op")
	check(not GAME.identity_has_wings(FakeIdentity.new()),
		"an identity without the op has no wings")
	check(not GAME.identity_has_wings(null), "no identity has no wings")

	var wings := FakeWings.new()
	root.add_child(wings)
	var excitement := FakeWingedExcitement.new()
	root.add_child(excitement)
	excitement.wings = wings
	check(GAME.wings_of(excitement) == wings, "the Beat's private wing node is read")
	var plain_excitement := FakeExcitement.new()
	root.add_child(plain_excitement)
	check(GAME.wings_of(plain_excitement) == null, "a Beat without the member has no wing node")
	check(GAME.wings_of(null) == null, "no Beat has no wing node")

	check(GAME.wing_hold_at(wings, "unfplap", 0.4), "the wing node takes the hold")
	check(wings.holds == [["unfplap", 0.4]], "the hold reaches the wing node at the value")
	check(not GAME.wing_hold_at(plain, "unfplap", 0.4), "a node without the hold answers false")
	check(not GAME.wing_hold_at(null, "unfplap", 0.4), "no node takes no hold")
	GAME.wing_release_hold(wings, "unfplap")
	check(wings.releases == ["unfplap"], "the hold release reaches the wing node")
	GAME.wing_release_hold(plain, "unfplap")
	GAME.wing_release_hold(null, "unfplap")
	GAME.wing_set_open(wings, false)
	check(wings.opens == [false], "the open switch reaches the wing node")
	GAME.wing_set_open(plain, true)
	GAME.wing_set_open(null, true)
	GAME.wing_spread(excitement, 4.0)
	check(excitement.spreads == [4.0], "the stock spread reaches the Beat")
	GAME.wing_spread(plain_excitement, 4.0)
	GAME.wing_spread(null, 4.0)
	GAME.wing_flutter(excitement)
	check(excitement.flutters == 1, "the flutter reaches the Beat")
	GAME.wing_flutter(plain_excitement)
	GAME.wing_flutter(null)
	check(excitement.flutters == 1, "a Beat without the flutter stays still")

	check(not GAME.wing_opened(wings), "a folded wing node reads closed")
	GAME.set_wing_opened(wings, true)
	check(GAME.wing_opened(wings), "the open meshes follow the write")
	GAME.set_wing_tuck(wings, 0.75)
	GAME.set_wing_half(wings, 0.25)
	check(is_equal_approx(wings.tuck, 0.75) and is_equal_approx(wings.half, 0.25),
		"the fold blends take the writes")
	check(not GAME.wing_opened(plain), "a node without the flag reads closed")
	GAME.set_wing_opened(plain, true)
	GAME.set_wing_tuck(plain, 0.5)
	GAME.set_wing_half(plain, 0.5)
	GAME.set_wing_opened(null, true)
	GAME.set_wing_tuck(null, 0.5)
	GAME.set_wing_half(null, 0.5)
	check(not "opened" in plain and not "tuck" in plain and not "half" in plain,
		"a node without the blends takes no write")
	wings.queue_free()
	excitement.queue_free()
	plain_excitement.queue_free()
	pony.queue_free()
	bare.queue_free()
	nav.queue_free()
	plain.queue_free()


## The pose accessors the Anon body, the pose recipes and the pose rig read: the desktop driver and
## its ops, her awareness facing and the joint-limit clamp.
func _check_pose_accessors() -> void:
	var plain := Node.new()
	root.add_child(plain)
	var driver := FakePoseDriver.new()
	root.add_child(driver)
	var left := Node3D.new()
	var right := Node3D.new()
	root.add_child(left)
	root.add_child(right)

	GAME.apply_torso_pose(driver, left, Basis.IDENTITY)
	check(driver.torsos.size() == 1 and driver.torsos[0][0] == left,
		"the torso pose reaches the body's own driver")
	GAME.apply_torso_pose(plain, left, Basis.IDENTITY)
	GAME.apply_torso_pose(null, left, Basis.IDENTITY)
	check(driver.torsos.size() == 1, "a driver without the torso pose takes no call")
	GAME.set_rest_hand_targets(driver, left, right)
	check(driver.rest.size() == 1 and driver.rest[0] == [left, right],
		"the rest-hand pair reaches the body's own driver")
	GAME.set_rest_hand_targets(plain, left, right)
	GAME.set_rest_hand_targets(null, left, right)
	check(driver.rest.size() == 1, "a driver without the rest-hand pair takes no call")
	GAME.clear_rest_hand_targets(driver, left, right)
	check(driver.clears.size() == 1 and driver.clears[0] == [left, right],
		"the rest-hand release reaches the body's own driver")
	GAME.clear_rest_hand_targets(plain, left, right)
	GAME.clear_rest_hand_targets(null, left, right)
	check(driver.clears.size() == 1, "a driver without the release takes no call")

	var frame := Transform3D(Basis.IDENTITY, Vector3.ONE)
	GAME.set_hold_target(driver, "left", frame, "rub")
	check(driver.holds.size() == 1 and driver.holds[0] == ["left", frame, "rub"],
		"the palm hold reaches the body's own driver")
	GAME.set_hold_target(plain, "left", frame, "rub")
	GAME.set_hold_target(null, "left", frame, "rub")
	check(driver.holds.size() == 1, "a driver without the palm hold takes no call")
	GAME.clear_hold_target(driver, "left")
	check(driver.releases == ["left"], "the palm release reaches the body's own driver")
	GAME.clear_hold_target(plain, "left")
	GAME.clear_hold_target(null, "left")
	check(driver.releases.size() == 1, "a driver without the palm release takes no call")
	check(GAME.hand_frame(driver, "right").origin.is_finite(), "the rig's live palm frame is read")
	check(not GAME.hand_frame(plain, "right").origin.is_finite(),
		"a driver without the palm frame answers an infinite origin")
	check(not GAME.hand_frame(null, "right").origin.is_finite(),
		"no driver answers no palm frame")

	var avatar := FakeAvatar.new()
	root.add_child(avatar)
	check(GAME.desktop_pose_driver(avatar) == null, "a body with no driver answers null")
	avatar.desktop_pose_driver = driver
	check(GAME.desktop_pose_driver(avatar) == driver, "the body's own pose driver is read")
	check(GAME.desktop_pose_driver(null) == null, "no body has no pose driver")
	GAME.set_desktop_pose_driver(avatar, null)
	check(GAME.desktop_pose_driver(avatar) == null, "the parked driver write lands on the body")
	GAME.set_desktop_pose_driver(avatar, driver)
	check(GAME.desktop_pose_driver(avatar) == driver, "the restore write lands on the body")
	GAME.set_desktop_pose_driver(plain, driver)
	GAME.set_desktop_pose_driver(null, driver)
	check(not "desktop_pose_driver" in plain, "a body without the member takes no write")

	var aware := FakeAwarePony.new()
	root.add_child(aware)
	check(GAME.awareness_forward(aware) == Vector3.FORWARD, "her awareness facing is read")
	check(GAME.awareness_forward(plain) == Vector3.ZERO,
		"a body without the op has no awareness facing")
	check(GAME.awareness_forward(null) == Vector3.ZERO, "no body has no awareness facing")

	var limits := FakeLimits.new()
	var held := GAME.joint_constrain(limits, 2, Basis.IDENTITY)
	check(held.is_equal_approx(Basis(Vector3.UP, 0.5)), "the pony's own limit clamps the basis")
	check(limits.clamps.size() == 1 and int(limits.clamps[0][0]) == 2,
		"the clamp reaches the limits with the bone")
	check(GAME.joint_constrain(plain, 2, Basis.IDENTITY) == Basis.IDENTITY,
		"limits without the op answer the input basis")
	check(GAME.joint_constrain(null, 2, Basis.IDENTITY) == Basis.IDENTITY,
		"no limits answer the input basis")

	avatar.queue_free()
	aware.queue_free()
	driver.queue_free()
	left.queue_free()
	right.queue_free()
	plain.queue_free()


## The bound views: one cached handle per node, the accessor answer on the live node, the typed
## zero on an absent one, and the cache dropped by every bind.
func _check_views() -> void:
	WORLD.unbind()
	var pony := FakeBody.new()
	root.add_child(pony)
	var mouth := FakeFullMouth.new()
	var head := FakeHead.new()
	root.add_child(head)
	head.add_child(mouth)
	head.mouth = mouth
	pony.head = head
	var skeleton := Skeleton3D.new()
	pony.add_child(skeleton)
	pony.skeleton = skeleton
	var boop := FakeBoop.new()
	pony.add_child(boop)
	pony.boop_node = boop
	var eye := SkeletonModifier3D.new()
	pony.add_child(eye)
	pony.eye_motion = eye
	pony.body_scale = 1.25
	var expressions := FakeExpressions.new()
	pony.expressions = expressions

	var view := WORLD.pony(pony)
	check(view == WORLD.pony(pony), "a pony view is cached per bound node")
	check(view.identity() == pony.identity, "the view reads her identity")
	check(not view.has_wings(), "a plain identity has no wings")
	check(view.skeleton() == skeleton, "the view reads her skeleton")
	check(view.head() == head, "the view reads her head")
	check(view.mouth() == mouth, "the view finds her mouth through the head")
	check(view.boop() == boop, "the view reads her blush sustainer")
	check(view.eye_motion() == eye, "the view reads her gaze controller")
	check(is_equal_approx(view.body_scale(), 1.25), "the view reads her body scale")
	check(not view.hair_link_ready(), "a body without a hair link is not ready")
	check(not view.can_hear(null) and not view.can_see(null),
		"a partner that is not a node is out of earshot and sight")
	var plain_partner := Node.new()
	root.add_child(plain_partner)
	check(not view.can_hear(plain_partner) and not view.can_see(plain_partner),
		"a partner that is not a body is out of earshot and sight")
	plain_partner.free()
	check(not view.is_held() and not view.grounded(), "a still body is neither held nor grounded")
	check(view.posture_requested() == "" and view.interruption_reason() == "",
		"a body without a posture answers empty")
	check(not view.eye_transform().origin.is_finite(), "a body without the eye read answers INF")
	view.set_viseme("D")
	check(mouth.visemes == ["D"], "the viseme reaches her mouth through the view")
	view.clear_viseme()
	check(mouth.clears == 1, "the viseme clear reaches her mouth through the view")
	view.set_near_mesh(false)
	check(pony.near_calls == [false], "the near-mesh switch reaches her body through the view")
	view.request_posture("stand")
	view.stop_speaking()
	view.set_motion_paused(true)

	var nav := FakeNavigator.new()
	nav.name = "Navigator"
	pony.add_child(nav)
	var nav_view := WORLD.navigator(pony)
	check(nav_view == WORLD.navigator(pony), "a navigator view is cached per bound node")
	nav.command_owner = "life:graze"
	nav.reserved_by = "someone"
	nav._has_target = true
	check(nav_view.owner() == "life:graze" and nav_view.reserved() == "someone"
		and nav_view.has_target(), "the view reads her leases and her route")
	nav_view.set_owner("unfplap:test")
	nav_view.set_reserved("")
	nav_view.set_wander(false)
	check(nav.command_owner == "unfplap:test" and nav.reserved_by == ""
		and not nav.wander_enabled and not nav_view.wander(),
		"the lease writes reach her navigator")
	nav_view.stay()
	check(nav.stays == 1, "the stay reaches her navigator")
	nav_view.set_speed_limit(1.5)
	nav_view.set_pace_target(0.25)
	check(is_equal_approx(nav_view.speed_limit(), 1.5)
		and is_equal_approx(nav_view.pace_target(), 0.25), "the speed and pace take the writes")
	nav_view.set_face_point(Vector3.ONE)
	check(nav.face_point == Vector3.ONE, "the face point reaches her navigator")
	nav.conversation_target = nav
	nav_view.clear_facing()
	check(nav.face_point == Vector3.INF and nav.conversation_target == null,
		"the facing clear drops both stale writes")
	var turning := FakeTurnPony.new()
	root.add_child(turning)
	WORLD.navigator(turning).set_facing(Vector3.RIGHT)
	check(turning.facings == [Vector3.RIGHT], "her own turn takes the facing through the view")

	var face_view := WORLD.face(pony)
	check(face_view == WORLD.face(pony), "a face view is cached per bound node")
	check(face_view.controller() == expressions, "the view reads her expression controller")
	check(face_view.line_faces().has("shy"), "the view hands back the game's line-face table")
	face_view.touch("unfplap", 0.4, 0.1)
	check(expressions.touches == [["unfplap", 0.4, 0.1]], "the touch reaches her controller")
	face_view.release_touch("unfplap")
	check(expressions.releases == ["unfplap"], "the touch release reaches her controller")
	face_view.stare(true, 0.2)
	check(expressions.stares == [[true, 0.2]], "the stare reaches her controller")
	face_view.fluster(1.5, false)
	check(expressions.flusters == [[1.5, false]], "the fluster reaches her controller")
	expressions.fluster_amount = 0.6
	check(is_equal_approx(face_view.fluster_amount(), 0.6), "the fluster amount is read")
	face_view.set_dialogue("smile")
	check(face_view.dialogue_face() == "smile", "a dialogue face is set and read")
	face_view.finish_dialogue(2.5)
	check(is_equal_approx(expressions.finished, 2.5), "the dialogue finish reaches her controller")
	face_view.clear_dialogue()
	check(expressions.cleared == 1, "the dialogue clear reaches her controller")
	face_view.set_expression("pout", 0.2)
	check(mouth.faces == ["pout"], "the mouth expression reaches her rig")
	face_view.sustain_blush(0.5)
	check(is_equal_approx(boop.amount, 0.5), "the blush reaches her sustainer")
	check(not face_view.celebrate(), "a sustainer without the op answers false")

	var wing_node := FakeWings.new()
	root.add_child(wing_node)
	var excitement := FakeWingedExcitement.new()
	root.add_child(excitement)
	excitement.wings = wing_node
	var wing_view := WORLD.wings(excitement)
	check(wing_view == WORLD.wings(excitement), "a wings view is cached per bound node")
	check(wing_view.node() == wing_node, "the view reads her wing node off the Beat")
	wing_view.spread(4.0)
	check(excitement.spreads == [4.0], "the stock spread reaches the Beat")
	wing_view.flutter()
	check(excitement.flutters == 1, "the flutter reaches the Beat")
	var node_view := WORLD.wings(wing_node)
	check(node_view != wing_view, "the wing node gets its own view")
	check(node_view.hold("unfplap", 0.4), "the view takes the wing hold")
	check(wing_node.holds == [["unfplap", 0.4]], "the hold reaches her wing node")
	node_view.set_opened(true)
	check(node_view.opened(), "the open write and read reach her wing node")
	node_view.set_tuck(0.75)
	node_view.set_half(0.25)
	check(is_equal_approx(wing_node.tuck, 0.75) and is_equal_approx(wing_node.half, 0.25),
		"the fold blends reach her wing node")
	node_view.release_hold("unfplap")
	check(wing_node.releases == ["unfplap"], "the hold release reaches her wing node")
	node_view.set_open(false)
	check(wing_node.opens.back() == false, "the open switch reaches her wing node")

	var flank := FakeFlankTouch.new()
	root.add_child(flank)
	var flank_view := WORLD.flank(flank)
	check(flank_view == WORLD.flank(flank), "a flank view is cached per bound node")
	flank_view.impact(1, Vector3.ONE, 0.5)
	check(flank.impacts == [[1, Vector3.ONE, 0.5]], "the impact reaches her flank")
	flank_view.wake_tick()
	check(flank.wakes == 1, "the wake tick reaches her flank")
	check(flank_view.start_jiggle(0, 0.8), "the jiggle starts on her flank")
	check(flank.jiggles == [[0, 0.8]], "the jiggle reaches her flank")
	flank_view.process(0.016)
	check(flank.frames >= 1, "the jiggle frame reaches her flank")
	flank_view.set_jiggle_amount(0.3)
	check(is_equal_approx(flank_view.jiggle_amount(), 0.3), "the jiggle amount is written and read")
	var surface := FakeSurface.new()
	flank_view.update_surface(surface, skeleton, Transform3D.IDENTITY)
	check(surface.skins.size() == 1 and surface.skins[0][0] == skeleton,
		"the patch is skinned through the view")
	var touch := FakeTouchBody.new()
	root.add_child(touch)
	WORLD.flank(touch).sync(2)
	check(touch.synced == [2], "the hull sync reaches her touch body")

	var second := FakeBody.new()
	root.add_child(second)
	check(WORLD.pony(second) != view, "a second body gets its own view")
	check(WORLD.pony(null).identity() == null, "a null pony answers no identity")
	check(not WORLD.pony(null).has_wings(), "a null pony has no wings")
	check(WORLD.navigator(null).owner() == "", "a null pony has no navigator lease")
	check(is_nan(WORLD.navigator(null).speed_limit()), "a null pony has no speed override")
	check(WORLD.face(null).dialogue_face() == "", "a null pony has no dialogue face")
	check(WORLD.wings(null).node() == null, "a null Beat has no wing node")
	check(is_nan(WORLD.flank(null).jiggle_amount()), "a null flank answers NAN")
	var gone := FakeBody.new()
	root.add_child(gone)
	gone.free()
	check(WORLD.pony(null).identity() == null, "no pony answers no identity through the view")
	var game := FakeGame.new()
	root.add_child(game)
	WORLD.bind_world(game)
	check(WORLD.pony(pony) != view, "a bind drops the cached views")
	check(WORLD.navigator(pony) != nav_view, "a bind drops the cached navigator views")
	check(WORLD.pony(pony) == WORLD.pony(pony), "the new bind caches its own view")
	WORLD.unbind()

	pony.queue_free()
	head.queue_free()
	boop.queue_free()
	eye.queue_free()
	second.queue_free()
	turning.queue_free()
	game.queue_free()
	wing_node.queue_free()
	excitement.queue_free()
	flank.queue_free()
	touch.queue_free()


## Anon's bound view: the facade's player handle behind every player member, the cached handle, the
## typed zero once unbound, and the form readers the facade and the act gates delegate to.
func _check_anon_view() -> void:
	WORLD.unbind()
	var game := FakeGame.new()
	root.add_child(game)
	var player := FakeAnonPlayer.new()
	root.add_child(player)
	var avatar := FakeAvatar.new()
	avatar.name = "AnonBody"
	player.add_child(avatar)
	var seat := FakeSeat.new()
	root.add_child(seat)
	player.seat = seat
	var form := FakeFormDriver.new()
	form.form = {"kind": "pony", "age": "young"}
	root.add_child(form)
	form.add_to_group("player_pony_form")
	player.form_driver = form
	var knockdown := FakeKnockdown.new()
	player.knockdown = knockdown
	WORLD.bind_world(game)
	WORLD.bind_player(player)

	var view := WORLD.anon()
	check(view == WORLD.anon(), "an Anon view is cached for the bound rig")
	check(view.seat() == seat, "the view reads his seat")
	check(not view.controls_locked(), "a released rig reads unlocked")
	view.set_controls_locked(true)
	check(player.controls_locked, "the controls lock reaches his rig")
	view.force_stand_up()
	check(player.stand_ups == 1, "the stand-up reaches his rig")
	check(is_equal_approx(view.eye_height(), player.eye_line), "the view reads his eye line")
	view.set_eye_y(1.3)
	view.set_stand_eye(1.4)
	view.set_eye_height(1.45)
	check(is_equal_approx(player.eye_y, 1.3) and is_equal_approx(player._stand_eye, 1.4)
		and is_equal_approx(player._eye_height, 1.45), "the eye writes reach his rig")
	view.set_pitch(0.4)
	check(is_equal_approx(view.pitch(), 0.4), "the look pitch is written and read")
	check(view.form() == form, "the view reads his form driver")
	check(view.form_is_pony() and view.form_is_young(), "the live form is a pony and young")
	check(WORLD.player_is_pony(), "the facade reads the same form through the view")
	form.form = {"kind": "pony", "age": "adult"}
	check(view.form_is_pony() and not view.form_is_young(), "an adult pony is not young")
	form.form = {"kind": "human"}
	check(not view.form_is_pony() and not WORLD.player_is_pony(), "a human form is not a pony")
	view.clamp_view()
	check(form.clamps == 1, "the form's own view limit takes the call")
	check(view.body() == avatar, "the view reads his body under the rig")
	check(not view.q_held(), "a rig with no Q hold reads false")
	view.set_q_held(true)
	check(view.q_held(), "the Q hold is written and read")
	view.set_space_hold(0.25)
	view.set_rest_held(true)
	check(is_equal_approx(player._space_hold, 0.25) and player._rest_held,
		"the seated holds reach his rig")

	var rest := FakeSeat.new()
	root.add_child(rest)
	check(view.sit_on(rest) and player.sits == [rest], "the seat call reaches his rig")
	check(view.toggle_couch_sleep() and player.sleeps == 1, "the recline reaches his rig")

	var driver := FakePoseDriver.new()
	root.add_child(driver)
	var left := Node3D.new()
	var right := Node3D.new()
	root.add_child(left)
	root.add_child(right)
	check(view.hand_frame(driver, "right").origin.is_finite(), "the view reads a live palm frame")
	view.set_hold_target(driver, "left", Transform3D(Basis.IDENTITY, Vector3.ONE), "rub")
	check(driver.holds.size() == 1 and driver.holds[0][0] == "left",
		"the palm hold reaches the driver")
	view.clear_hold_target(driver, "left")
	check(driver.releases == ["left"], "the palm release reaches the driver")
	view.apply_torso_pose(driver, left, Basis.IDENTITY)
	check(driver.torsos.size() == 1 and driver.torsos[0][0] == left,
		"the torso pose reaches the driver")
	view.set_rest_hand_targets(driver, left, right)
	view.clear_rest_hand_targets(driver, left, right)
	check(driver.rest.size() == 1 and driver.clears.size() == 1,
		"the rest-hand pair and its release reach the driver")
	check(view.pose_driver() == null, "a body with no driver answers null")
	avatar.desktop_pose_driver = driver
	check(view.pose_driver() == driver, "the view reads his body's pose driver")
	view.set_pose_driver(null)
	check(avatar.desktop_pose_driver == null, "the parked driver write lands on his body")
	view.set_pose_driver(driver)
	check(avatar.desktop_pose_driver == driver, "the restore write lands on his body")

	check(view.knockdown() == knockdown, "the view reads his knockdown handle")
	check(view.start_knockdown(Vector3.FORWARD), "the knockdown starts through the view")
	check(knockdown.starts.size() == 1 and knockdown.starts[0][0] == player,
		"the knockdown takes his body")

	WORLD.bind_player(player)
	check(WORLD.anon() != view, "a player bind drops the Anon view")
	check(WORLD.anon() == WORLD.anon(), "the new bind caches its own Anon view")
	WORLD.unbind()
	var gone := WORLD.anon()
	check(gone.seat() == null and gone.body() == null, "an unbound view answers no handle")
	check(not gone.controls_locked() and not gone.q_held(), "an unbound view reads false")
	check(gone.form() == null and gone.pose_driver() == null, "an unbound view has no form")
	check(is_nan(gone.pitch()) and is_nan(gone.eye_height()), "an unbound view answers NAN")
	check(not gone.sit_on(null) and not gone.toggle_couch_sleep(),
		"an unbound view takes no seat or recline")
	check(gone.knockdown() == null and not gone.start_knockdown(Vector3.UP),
		"an unbound view takes no knockdown")
	check(not gone.hand_frame(null, "right").origin.is_finite(),
		"an unbound view answers an infinite palm frame")

	form.remove_from_group("player_pony_form")
	game.queue_free()
	player.queue_free()
	avatar.queue_free()
	seat.queue_free()
	rest.queue_free()
	form.queue_free()
	driver.queue_free()
	left.queue_free()
	right.queue_free()


## The bed view: the couch, rest and seating members behind the facade's cached handle, the typed
## zero on an absent node, and the cache dropped by a bind.
func _check_bed_view() -> void:
	WORLD.unbind()
	var bed := FakeCouch.new()
	root.add_child(bed)
	var player_seat := FakeSeat.new()
	var guest_seat := FakeSeat.new()
	root.add_child(player_seat)
	root.add_child(guest_seat)
	bed.seats = [player_seat, guest_seat]
	var pony := FakeBody.new()
	root.add_child(pony)

	var view := WORLD.bed(bed)
	check(view == WORLD.bed(bed), "a bed view is cached per bound node")
	var seats := view.couch_seats()
	check(seats.size() == 2 and seats[1] == guest_seat, "the view reads the couch's seats")
	check(view.couch_open(), "the view opens the couch rest")
	check(view.couch_invite(pony, guest_seat) and bed.invites.size() == 1,
		"the guest invite reaches the couch rest")
	check(view.couch_approach(guest_seat) == Vector3(2.0, 0.0, 0.0),
		"the approach point is the couch's own")
	check(view.couch_pony_transform(guest_seat).origin == guest_seat.global_position,
		"the guest transform is the couch's own")
	check(not view.couch_mare_fits(), "an unmeasured couch does not fit a mare")
	check(view.couch_cooldown_until(pony) == 0, "a pony with no guest cooldown reads zero")
	bed._cooldowns[pony.get_instance_id()] = 4200
	check(view.couch_cooldown_until(pony) == 4200, "the view reads the pony's own cooldown")
	check(view.couch_partner(guest_seat) == player_seat, "the partner of one seat is the other")
	check(view.rest_word() == "bed", "the view reads the rest's own word")
	view.finish_guest()
	view.release_pony(7)
	check(bed.finishes == 1 and bed.releases == [7],
		"the guest end and the pony release reach the couch")

	var rest := FakeRest.new()
	root.add_child(rest)
	rest._bed = bed
	var rest_view := WORLD.bed(rest)
	check(rest_view == WORLD.bed(rest) and rest_view != view, "the rest gets its own view")
	check(rest_view.rest_bed() == bed, "the view reads the bed a rest resolves to")
	rest_view.refresh()
	check(rest.refreshes == 1, "the refresh reaches the stock rest")
	check(not rest_view.fits() and not rest_view.has_guest() and rest_view.sleeper() == null,
		"a free rest fits nobody and holds no guest")
	rest._mare_fits = true
	rest._guest = {"state": "resting"}
	rest._sleeper = pony
	check(rest_view.fits() and rest_view.has_guest() and rest_view.sleeper() == pony,
		"the view reads the rest's fit, guest row and sleeper")
	check(rest_view.front(pony) == Vector3.ONE, "the front point is the rest's own")
	check(rest_view.accepts(pony) and rest_view.willing(pony) and rest_view.eligible(pony),
		"the rest's own gates answer through the view")
	check(not rest_view.seat_free_for(player_seat, pony), "a seat held by nobody is not his")
	guest_seat.free_for_pony = pony
	check(rest_view.seat_free_for(guest_seat, pony), "the seat's own free test answers")

	var seating := FakeSeating.new()
	root.add_child(seating)
	seating._users[pony.get_instance_id()] = {"phase": "approach", "id": 7}
	var seat_view := WORLD.bed(seating)
	check(seat_view == WORLD.bed(seating), "the seating system gets its own cached view")
	check(seat_view.seating_phase(pony.get_instance_id()) == "approach",
		"the view reads the seating phase")
	seat_view.release_seat(pony.get_instance_id())
	check(seating.released == [7], "the seat release reaches the seating system")

	check(is_equal_approx(view.surface_top([bed.global_position], 0.75), 0.75),
		"a bed with no drawn bedding answers the measured top")
	check(not view.exit_point(null, Vector3.ZERO, 1.0, 0.3).is_finite(),
		"a body in no physics space has no exit floor")
	var loose := FakeCouch.new()
	check(WORLD.bed(loose).stock_rest() == null, "a bed outside the tree has no stock rest")
	loose.free()

	check(WORLD.bed(null).couch_seats().is_empty(), "no bed has no seats")
	check(not WORLD.bed(null).couch_open(), "no bed opens nothing")
	check(WORLD.bed(null).rest_word() == "" and WORLD.bed(null).rest_bed() == null,
		"no node resolves to no bed")
	check(not WORLD.bed(null).fits() and not WORLD.bed(null).has_guest()
		and WORLD.bed(null).sleeper() == null, "no rest fits nobody and holds no guest")
	check(not WORLD.bed(null).accepts(pony) and not WORLD.bed(null).willing(pony)
		and not WORLD.bed(null).eligible(pony), "no rest accepts no pony")
	check(not WORLD.bed(null).couch_pony_transform(null).origin.is_finite(),
		"no couch answers an infinite guest transform")
	check(not WORLD.bed(null).front(pony).is_finite(), "no rest answers no front point")
	check(WORLD.bed(null).seating_phase(1) == "", "no seating system has no phase")
	check(WORLD.bed(null).stock_rest() == null, "no bed has no stock rest")

	var game := FakeGame.new()
	root.add_child(game)
	WORLD.bind_world(game)
	check(WORLD.bed(bed) != view, "a bind drops the cached bed views")
	check(WORLD.bed(bed) == WORLD.bed(bed), "the new bind caches its own bed view")
	WORLD.unbind()

	bed.queue_free()
	rest.queue_free()
	seating.queue_free()
	player_seat.queue_free()
	guest_seat.queue_free()
	pony.queue_free()
	game.queue_free()


## Her AI's live routing and the world context's story rows: the two views, their members and the
## cache each bind owns.
func _check_director_and_story() -> void:
	WORLD.unbind()
	var context := FakeContext.new()
	var impressions := FakeImpressions.new()
	impressions.profiles["rarity"] = {"mood": "happy"}
	var journal := FakeStory.new()
	var store := FakeStoryStore.new()
	store.rows = [{"id": "1", "kind": "say", "text": "hello", "speaker": "player",
		"listener": "rarity"}]
	store.seen = [{"id": "2", "kind": "say", "text": "again", "speaker": "rarity",
		"listener": "player"}]
	journal.store = store
	context.story = journal
	context.impressions = impressions
	context.events = [{"id": "e1", "kind": "intimacy", "text": "one"}]
	context.state = {"bond_levels": {"rarity": {"friendship": 3, "love": 0}}}
	root.add_child(context)
	root.add_child(impressions)

	var game := FakeGame.new()
	game.world_context = context
	root.add_child(game)
	var director := FakeDirector.new()
	director.characters = {"fluttershy": {"profile": {
		"voice_status": "character voice", "tts_speaker_id": 5}}}
	director.add_to_group("conversation_director")
	root.add_child(director)
	var tts := FakeTts.new()
	root.add_child(tts)
	director.tts = tts
	var vocal := FakeVocal.new()
	root.add_child(vocal)
	director.vocal = vocal
	var boop := FakeKissBoop.new()
	root.add_child(boop)
	WORLD.bind_world(game)
	check(WORLD.bond_level("rarity").found and WORLD.bond_level("rarity").love == 0,
		"the facade reads the world's cached bond level")
	check(not WORLD.bond_level("fluttershy").found,
		"a pony the cache does not hold reads unfound")

	var view := WORLD.director()
	check(view == WORLD.director(), "a director view is cached per bound director")
	check(not view.speaking(), "an idle director is not speaking")
	director.state = "speaking"
	check(view.speaking(), "the view reads the director's speaking state")
	view.interrupt()
	check(director.interrupts == 1, "the interrupt reaches the director")
	director.state = "idle"
	check(is_equal_approx(view.clock(), 42.0), "the clock is the director's own")
	check(not view.subsystem_active(null), "no subsystem is not active")
	var approaches := FakeSubsystem.new()
	approaches.live = true
	check(view.subsystem_active(approaches), "an active subsystem reports active")
	check(view.lines().greet("rarity", "hello"), "the greeting reaches the director's host")
	check(view.lines().queue("rarity", "say", "k", Callable(), false),
		"the authored queue reaches the director's host")
	view.lines().cancel("k")
	check(director.cancelled == ["k"], "the authored cancel reaches the director's host")
	director.config = FakeConfig.new()
	director._section = {"model": "m"}
	var llm := FakeLlm.new()
	llm.status_path = "user://llm.json"
	root.add_child(llm)
	director.llm = llm
	var model := view.llm_config()
	check(model.enabled and model.section == {"model": "m"},
		"the model config is the director's own section")
	check(model.status_path == "user://llm.json", "the model status path is the director's")
	view.prepare_vocal("rarity")
	check(vocal.prepared == ["rarity"], "the vocal cache prepares for her id")

	check(view.world_context() == context, "the view reads the bound world's context")
	view.record_event("intimacy", "a line", ["rarity"], ["rarity"], "e2", "town")
	check(context.records.size() == 1 and context.records[0]["place"] == "town",
		"the world event reaches the context")
	view.record_situation("sitting", ["rarity"], "s1")
	check(context.records.size() == 2 and context.records[1]["kind"] == "situation",
		"a situation is one context event")
	check(view.impressions() == impressions, "the view reads the context's store")
	check(view.impression_mood("rarity") == "happy", "the committed mood is read")
	check(view.impression_mood("cadance", "?") == "?", "an absent profile answers the caller's word")
	check(view.set_impression_mood("rarity", "sad", "m1"), "a mood write reaches the store")
	check(view.commit_impression("rarity", "happy", 2, "thought", "e3"),
		"a row commit reaches the store")
	check(impressions.commits.size() == 2, "both impressions writes reach the store")
	check(view.standing_line("rarity") == "steady", "the standing line is the store's own")

	check(view.tts() == tts, "the view reads the director's TTS node")
	check(view.tts_running(tts), "a live TTS node reports its server")
	tts.live = false
	check(not view.tts_running(tts), "a node without a server reports no server")
	check(not view.tts_running(null), "no TTS node reports no server")
	check(view.play_vocal(vocal, "rarity", "m", null, -6.0), "the generated vocal plays")
	check(view.play_kiss(boop, -22.0, true) and boop.kisses == 1, "the stock kiss plays")

	tts.live = true
	var facts: VOICE.Facts = view.voice_facts("fluttershy", true)
	check(facts.profile == director.characters["fluttershy"]["profile"],
		"the voice facts carry the director's profile")
	check(facts.server and facts.tts_enabled and facts.global_mode == "auto",
		"the voice facts carry the server, the switch and the TTS mode")
	check(not facts.ponese and not facts.chatter, "the game's routing keeps her on TTS")
	var routed: Dictionary = VOICE.classify(facts)
	check(bool(routed.get("generated", false)) and not bool(routed.get("effective_ponese", true)),
		"the voice facts classify as the game routes her")
	check(VOICE.status_line(facts).begins_with("voice "), "the debug line names the routing")

	var story := WORLD.story()
	check(story == WORLD.story(), "a story view is cached per bound context")
	check(story.journal() == journal, "the view reads the context's journal")
	check(story.store() == store, "the journal's line store is read")
	check(story.open(), "an open journal answers open")
	check(story.last_line_id() == 7, "the newest line id is the store's")
	var found := story.search("rarity", ["hello"], 8, 8)
	check(found.size() == 1 and found[0].text == "hello", "a stored line is a typed row")
	var seen := story.witnessed("rarity", 24, 0, ["say"])
	check(seen.size() == 1 and seen[0].id == "2", "a witnessed line is a typed row")
	check(story.line_text(found[0], "rarity", true) == "1:rarity:true",
		"the line text is the journal's own")
	check(story.events("rarity", 10).size() == 1, "the context's events are read")

	WORLD.unbind()
	check(WORLD.director() != view, "an unbind drops the cached director view")
	var gone := WORLD.director()
	check(gone.world_context() == null and gone.impressions() == null,
		"an unbound director has no world context or store")
	check(gone.impression_mood("rarity") == "" and gone.standing_line("rarity") == "",
		"an unbound director answers no mood")
	check(not gone.play_kiss(null, -20.0, true), "an unbound director plays no kiss")
	var gone_story := WORLD.story()
	check(gone_story != story, "an unbind drops the cached story view")
	check(gone_story.journal() == null and gone_story.store() == null,
		"an unbound story has no journal or store")
	check(not gone_story.open() and gone_story.last_line_id() == -1,
		"an unbound story is closed and has no line id")
	check(gone_story.search("rarity", [], 0, 8).is_empty()
		and gone_story.witnessed("rarity", 8, 0, []).is_empty()
		and gone_story.events("rarity", 8).is_empty(), "an unbound story answers no rows")

	context.queue_free()
	impressions.queue_free()
	director.config.free()
	director.queue_free()
	tts.queue_free()
	vocal.queue_free()
	boop.queue_free()
	llm.queue_free()
	game.queue_free()


## The inventory and menu views: one cached handle each, the live answers and the typed zeroes.
func _check_inventory_and_menu() -> void:
	WORLD.unbind()
	var game := FakeGame.new()
	root.add_child(game)
	var store := FakeStore.new()
	store.slots = [{"id": "goods:footstool", "count": 2}, {}]
	var bar := FakeHotbar.new()
	root.add_child(bar)
	var layer := CanvasLayer.new()
	bar.add_child(layer)
	bar._hud = layer
	var inventory := FakeInventoryNode.new()
	root.add_child(inventory)
	inventory.inventory = store
	inventory.hotbar = bar
	game.inventory = inventory
	WORLD.bind_world(game)

	var view := WORLD.inventory()
	check(view == WORLD.inventory(), "an inventory view is cached for the bound world")
	check(view.store() == store, "the view reads the briefcase store")
	check(view.slots(store).size() == 2, "the view copies the store's slot rows")
	inventory.held = {"right": "goods:footstool"}
	inventory.holding_case = "goods:footstool"
	check(view.held_count() == 1, "the view counts the held item rows")
	check(view.holding_case() == "goods:footstool", "the view reads the held case id")
	check(view.loans(store).is_empty(), "a store with no loans answers empty")
	check(view.available(store, 0) == 2, "the view reads a slot's availability")
	check(view.writable(store), "the view reads the store's writable flag")
	check(view.take(store, 0) == "token-0" and store.taken == [0], "the take reaches the store")
	check(view.put(store, "token-0", 0) and store.put_back == [["token-0", 0]],
		"the put reaches the store")
	check(view.grant(store, "goods:footstool", 1) == 3
		and store.granted == [["goods:footstool", 1]], "the grant reaches the store")
	var drop := view.spawn_drop("goods:footstool", Transform3D.IDENTITY)
	check(is_instance_valid(drop) and inventory.dropped.size() == 1,
		"the view drops an owned item through the inventory")
	if is_instance_valid(drop):
		drop.free()
	check(view.hotbar() == bar, "the view reads the inventory's quick-slot bar")
	check(view.hotbar_visible(bar), "the bar reads visible")
	view.set_hotbar_visible(bar, false)
	check(not bar.visible, "the visible write reaches the bar")
	check(view.hotbar_layer(bar) == layer, "the view reads the bar's HUD layer")
	view.set_hotbar_layer_visible(bar, false)
	check(bar.hud_calls == [false], "the bar's own HUD switch is called")
	check(not view.hud_hidden(), "a fresh inventory's card is not hidden")
	view.set_hud_hidden(true)
	check(inventory.hud_hidden, "the hidden flag reaches the inventory")
	view.place_hotbar()
	check(inventory.placed == 1, "the inventory's own hotbar placement is called")

	var menu := WORLD.menu()
	check(menu == WORLD.menu(), "a menu view is cached for the bound world")
	var panel := FakePanel.new()
	panel.opened = true
	panel.name = "pause_menu"
	game.pause_menu = panel
	root.add_child(panel)
	check(menu.panel("pause_menu") == panel, "the view reads a named panel")
	check(menu.panel("save_menu") == null, "an absent panel reads null")
	var sink := FakeToast.new()
	root.add_child(sink)
	menu.show_toast(sink, "hello", 1.5)
	check(sink.shown == [["hello", 1.5]], "the toast reaches its sink")
	menu.show_toast(null, "nobody", 1.0)
	check(sink.shown.size() == 1, "no sink is a quiet no-op")
	menu.sound("prop_ui_confirm", null, Vector3.ZERO)

	WORLD.bind_world(null)
	check(WORLD.inventory() != view and WORLD.menu() != menu,
		"a bind drops the cached inventory and menu views")
	var gone := WORLD.inventory()
	check(gone.store() == null and gone.hotbar() == null, "an unbound inventory has no store or bar")
	check(not gone.hud_hidden() and gone.slots(store).size() == 2,
		"an unbound inventory answers the store's own rows")
	check(gone.held_count() == 0 and gone.holding_case().is_empty(),
		"an unbound inventory holds nothing")
	var gone_menu := WORLD.menu()
	check(gone_menu.panel("pause_menu") == null, "an unbound menu has no panel")

	root.remove_child(bar)
	bar.queue_free()
	inventory.queue_free()
	panel.queue_free()
	sink.queue_free()
	game.queue_free()


## The relationship, mods and affection views: their receivers, members, typed zeroes and cache.
func _check_relationship_mods_affection() -> void:
	WORLD.unbind()
	var runtime := FakeRelationRuntime.new()
	var bonds := FakeBonds.new()
	runtime.bonds = bonds
	runtime.ladders["rarity"] = {"friendship": {"name": "close", "level": 3},
		"love": {"name": "dating", "level": 2}}
	root.add_child(runtime)
	bonds.rows["rarity"] = {"stage": "dating", "anger": 0.5, "affection": 7}
	var pony := FakeBody.new()
	root.add_child(pony)
	pony.set_meta("relationship_runtime", runtime)
	var stranger := FakeBody.new()
	var game := FakeGame.new()
	root.add_child(game)
	game.relationship_runtime = runtime
	var kisser := FakeKisser.new()
	root.add_child(kisser)
	game.kisser = kisser
	WORLD.bind_world(game)

	var relations := WORLD.relationship()
	check(relations == WORLD.relationship(), "a relationship view is cached per runtime")
	check(relations.runtime() == runtime, "the view reads the scene's runtime")
	check(relations.bonds() == bonds, "the view reads the runtime's bond store")
	var ladder := relations.ladder("rarity")
	check(ladder.friendship_found and ladder.love_found and ladder.love_name == "dating",
		"the view reads one pony's ladder")
	check(relations.love_name(pony, "rarity") == "dating", "the view reads her love stage name")
	check(relations.love_name(stranger, "rarity") == "?",
		"a pony with no relationship runtime answers ?")
	check(relations.bonds_of(pony) == bonds, "the view reads the store she carries")
	check(relations.bonds_of(stranger) == null, "a pony with no store answers null")
	var record := relations.record(bonds, "rarity")
	check(record.stage == "dating" and is_equal_approx(record.anger, 0.5),
		"the view reads one bond record")
	check(relations.eligible_for_romance(bonds, "rarity"), "the store's romance test answers")
	check(relations.welcomes(bonds, "rarity", "kiss"), "the store's welcome answers")
	check(not relations.welcomes(bonds, "rarity", "smack"), "another kind is not welcomed")
	check(is_equal_approx(relations.day(bonds), 12.5), "the store's day is read")
	check(relations.mark_met(bonds, "rarity") and bonds.met == ["rarity"],
		"the met mark reaches the store")
	relations.request_space(pony, "rarity")
	check(bonds.spaces == ["rarity"], "the space request reaches the store")

	var existing: Node = root.get_node_or_null("Mods")
	if existing != null:
		existing.name = "ModsTestHidden"
	var host := FakeModsHost.new()
	host.name = "Mods"
	host.rows = [{"id": "unfplap", "version": "1.0.0"}]
	root.add_child(host)
	var mods := WORLD.mods()
	check(mods == WORLD.mods(), "a mods view is cached for the registry")
	check(mods.state("unfplap").rows.is_empty(), "an untouched section starts empty")
	mods.state("unfplap").rows["serial"] = 3
	check(int(host.data["unfplap"].get("serial", 0)) == 3,
		"the state section is the registry's live dictionary")
	check(mods.active("dance_mod") and not mods.active("other"),
		"the registry answers which pack is on")
	check(mods.list().size() == 1 and str(mods.list()[0].get("id", "")) == "unfplap",
		"the installed rows are a typed copy")
	mods.save()
	check(host.saves == 1, "the save reaches the registry")
	root.remove_child(host)
	host.free()
	var orphan := WORLD.mods()
	check(orphan.state("unfplap").rows.is_empty(), "no registry answers empty rows")
	check(not orphan.active("dance_mod"), "no registry reports no pack active")
	check(orphan.list().is_empty(), "no registry lists no pack")

	var affection_view := WORLD.affection()
	check(affection_view == WORLD.affection(), "an affection view is cached for the kisser")
	check(affection_view.kisser() == kisser, "the view holds the scene's kisser")
	check(affection_view.begin_from_pony(pony) and kisser.begins == 1,
		"the view starts the stock kiss")
	kisser.accepts = false
	check(not affection_view.begin_from_pony(pony), "a refusing kisser answers false")
	kisser.accepts = true
	affection_view.clear_kisser()
	check(kisser._active == null and not kisser._her_kiss and not kisser._used_hold,
		"the view clears the kisser's latch")

	var affection := FakeAffection.new()
	root.add_child(affection)
	affection_view.feed(affection, Vector3.ONE, Vector3.UP, Basis.IDENTITY)
	check(affection.target == Vector3.ONE and affection.eye == Vector3.UP,
		"the view feeds the live mouth and eye")
	affection_view.end(affection)
	affection_view.cancel_afterglow(affection)
	check(affection.ended == 1 and affection.cancelled == 1,
		"the view ends the affection and its afterglow")
	check(affection_view.buck(affection, pony) and affection.bucks == 1,
		"the view lets her buck")

	var pose := FakeKissPose.new()
	root.add_child(pose)
	check(not affection_view.side_known(pose), "an unpinned pose has no side")
	affection_view.pin_side(pose, -1.0, 9999.0)
	check(affection_view.side_known(pose) and is_equal_approx(pose._side_now, -1.0),
		"the view pins the kiss side")
	affection_view.release_side(pose)
	check(is_equal_approx(pose._side_wait, 0.0), "the view releases the side hold")

	var excitement := FakeExcitement.new()
	root.add_child(excitement)
	affection_view.settle_excitement(excitement)
	check(is_equal_approx(excitement._until, 0.0), "the view settles the Beat")

	var session := FakeCuddle.new()
	root.add_child(session)
	affection_view.end_cuddle(session)
	check(session.ended == 1, "the view ends the cuddle session")
	check(affection_view.hoof_active(FakeHoof.new()), "the view reads an active hoof")

	var actions := FakeActions.new()
	root.add_child(actions)
	var reach := FakeReach.new()
	reach.held = pony
	reach.cradled = true
	reach.desktop_actions = actions
	root.add_child(reach)
	check(affection_view.carry_ours(reach, pony), "the view recognises our carry")
	affection_view.clear_carry(reach)
	check(reach.held == null and not reach.cradled, "the view clears the carry flags")
	affection_view.carry_released(affection_view.carry_actions(reach))
	check(actions.released == 1, "the release reaches the desktop actions")
	var held := FakeEndPony.new()
	root.add_child(held)
	affection_view.end_interaction(held)
	check(held.endings == 1, "the view ends her hold interaction")

	WORLD.bind_world(game)
	check(WORLD.relationship() != relations and WORLD.affection() != affection_view,
		"a bind drops the cached relationship and affection views")

	WORLD.unbind()
	var bare := WORLD.relationship()
	check(bare.runtime() == null and bare.bonds() == null and not bare.ladder("rarity").love_found,
		"an unbound relationship answers no runtime, store or ladder")
	check(bare.bonds_of(pony) == bonds and bare.love_name(pony, "rarity") == "dating",
		"the pony-keyed reads still answer while she carries the store")
	check(bare.record(null, "rarity").rows.is_empty()
		and not bare.eligible_for_romance(null, "rarity"), "no store answers an empty record")
	check(not bare.welcomes(null, "rarity", "kiss") and is_nan(bare.day(null)),
		"no store welcomes nothing and has no day")
	check(not bare.mark_met(null, "rarity"), "no store takes no met mark")
	bare.request_space(null, "rarity")

	var bare_affection := WORLD.affection()
	check(bare_affection.kisser() == null and not bare_affection.begin_from_pony(pony),
		"no kisser starts no kiss")
	bare_affection.clear_kisser()
	bare_affection.end(null)
	bare_affection.cancel_afterglow(null)
	bare_affection.feed(null, Vector3.ZERO, Vector3.ZERO, Basis.IDENTITY)
	check(not bare_affection.side_known(null) and not bare_affection.buck(null, pony),
		"no node answers the typed zeroes")
	bare_affection.pin_side(null, 1.0, 1.0)
	bare_affection.release_side(null)
	bare_affection.settle_excitement(null)
	bare_affection.end_cuddle(null)
	check(not bare_affection.hoof_active(null) and not bare_affection.carry_ours(null, pony),
		"no node carries nothing")
	check(bare_affection.carry_actions(null) == null, "no reach has no desktop actions")
	bare_affection.clear_carry(null)
	bare_affection.carry_released(null)
	bare_affection.end_interaction(null)

	affection.queue_free()
	pose.queue_free()
	excitement.queue_free()
	session.queue_free()
	actions.queue_free()
	reach.queue_free()
	held.queue_free()
	pony.queue_free()
	stranger.free()
	kisser.queue_free()
	runtime.queue_free()
	game.queue_free()
	if existing != null and is_instance_valid(existing):
		existing.name = "Mods"
