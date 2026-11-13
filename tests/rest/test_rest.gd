extends SceneTree
## The bed/couch rest and cuddle rejoin facade: the bed anchor, the shared bed rest lookup, the
## rejoin decision and note, the restore posture and the early rejoin exits.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/rest/test_rest.gd

const REST := preload("res://mods/unfplap/rest/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

var failures := 0
var checks := 0


class FakePony extends CharacterBody3D:
	var grounded_state := true
	var posture: Variant = null
	var profile: Variant = null

	func grounded() -> bool:
		return grounded_state

	func reset_motion(pose: Transform3D) -> void:
		global_transform = pose

	func posture_status() -> Dictionary:
		return {"requested": "stand"}

	func request_posture(name: String) -> bool:
		if posture != null and posture.has_method("request_posture"):
			posture.call("request_posture", name)
		return true


class FakePosture extends Node:
	var requested: Array[String] = []

	func request_posture(name: String) -> bool:
		requested.append(name)
		return true


class FakePlayer extends CharacterBody3D:
	var seat: Variant = null
	var sleeping := false
	var sat_on: Array = []

	func sit_on(node: Node) -> bool:
		sat_on.append(node)
		seat = node
		return true

	func toggle_couch_sleep() -> bool:
		sleeping = true
		set_meta("couch_sleeping", true)
		return true


class FakeMain extends Node:
	var player: Variant = null


class FakeNav extends Node:
	var command_owner := "life:idle"


class FakeCouch extends Node3D:
	var bed_node: Variant = null
	var seats: Array = []
	var opened := true
	var invited: Array = []
	var _mare_fits := true
	var _cooldowns: Dictionary = {}
	var refusals := 0

	func pony_transform(seat: Variant) -> Transform3D:
		return Transform3D(Basis.IDENTITY, (seat as Node3D).global_position)

	func invite(actor: Node, seat: Node3D) -> bool:
		invited.append([actor, seat])
		return true

	func open() -> bool:
		return opened

	func approach(_seat: Node3D) -> Vector3:
		return global_position + Vector3(0.0, 0.0, -1.0)


class FakeRest extends Node3D:
	var seats: Array = []
	var _bed: Variant = null
	var _mare_fits := true
	var _cooldowns: Dictionary = {}

	func approach(_seat: Node3D) -> Vector3:
		return Vector3(0.0, 0.0, -1.0)

	func open() -> bool:
		return false

	func invite(_actor: Node, _seat: Node3D) -> bool:
		return false


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _fixture() -> Dictionary:
	var facade: RefCounted = REST.new()
	var pony := FakePony.new()
	pony.posture = FakePosture.new()
	var nav := FakeNav.new()
	nav.name = "Navigator"
	pony.add_child(nav)
	var player := FakePlayer.new()
	var main := FakeMain.new()
	main.player = player
	var bed := Node3D.new()
	bed.name = "GuestBed"
	bed.set_meta("mattress_top", 0.6)
	root.add_child(main)
	root.add_child(pony)
	root.add_child(player)
	root.add_child(bed)
	facade.bind(main, pony, bed)
	facade.context = Callable(self, "ctx")
	return {
		"facade": facade, "pony": pony, "player": player, "main": main, "bed": bed, "nav": nav,
	}


## The live act values the facade reads. The tests replace the returned dictionary as needed.
var current_context := {
	"serial": 7,
	"state": 0,
	"player_pony": false,
	"headset": false,
	"summary": {},
	"satisfaction": 40.0,
	"aftercare_min": 10,
}


func ctx() -> Dictionary:
	return current_context


func _free(made: Dictionary) -> void:
	var pony: FakePony = made["pony"]
	var player: FakePlayer = made["player"]
	var main: FakeMain = made["main"]
	var bed: Node3D = made["bed"]
	for child: Node in pony.get_children():
		child.free()
	root.remove_child(pony)
	pony.free()
	root.remove_child(player)
	player.free()
	root.remove_child(main)
	main.free()
	root.remove_child(bed)
	bed.free()


func run() -> void:
	_check_wanted()
	_check_anchor()
	_check_rest_lookup()
	_check_note()
	_check_restore()
	await _check_place()
	_check_early_rejoin()

	print("REST_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("REST_PASS")
	quit(0 if failures == 0 else 1)


func _check_wanted() -> void:
	var made := _fixture()
	var facade: RefCounted = made["facade"]
	current_context["satisfaction"] = 40.0
	check(bool(facade.call("rejoin_wanted", current_context)),
		"a good act with readiness above the aftercare floor wants the cuddle")
	current_context["satisfaction"] = 4.0
	check(not bool(facade.call("rejoin_wanted", current_context)),
		"a low readiness act stays standing")
	current_context["summary"] = {"grade": "bad"}
	check(not bool(facade.call("rejoin_wanted", current_context)),
		"a bad summary never cuddles")
	current_context["summary"] = {"grade": "good"}
	check(bool(facade.call("rejoin_wanted", current_context)),
		"a good summary cuddles regardless of the readiness floor")
	current_context["player_pony"] = true
	check(not bool(facade.call("rejoin_wanted", current_context)),
		"AnonPony never uses the human bed rejoin")
	current_context["player_pony"] = false
	current_context["headset"] = true
	check(not bool(facade.call("rejoin_wanted", current_context)),
		"a headset rig never uses the desktop rejoin")
	current_context["headset"] = false
	_free(made)


func _check_anchor() -> void:
	var made := _fixture()
	var facade: RefCounted = made["facade"]
	var bed: Node3D = made["bed"]
	var player: FakePlayer = made["player"]
	player.global_position = Vector3(1.0, 1.0, 0.0)
	var anchor: Transform3D = facade.call("bed_anchor")
	check(is_equal_approx(anchor.origin.y, 0.62), "the fallback anchor sits on the mattress top")
	check(anchor.basis.is_finite(), "the anchor basis is finite")
	check(anchor.origin.x > 0.0, "the fallback anchor shifts to Anon's side")
	# A live couch rest wins over the fallback.
	var couch := FakeCouch.new()
	couch.name = "SharedBed"
	couch.bed_node = bed
	var seat := Node3D.new()
	var seat_a := Node3D.new()
	couch.seats = [seat_a, seat]
	couch.add_child(seat_a)
	couch.add_child(seat)
	couch.add_to_group("couches")
	root.add_child(couch)
	seat.global_position = Vector3(2.0, 0.6, 3.0)
	var shared: Variant = facade.call("shared_bed_rest", bed)
	check(shared is Transform3D and (shared as Transform3D).origin.is_equal_approx(
		seat.global_position), "the shared bed rest returns the guest seat transform")
	var shared_anchor: Transform3D = facade.call("bed_anchor")
	check(shared_anchor.origin.is_equal_approx(seat.global_position),
		"the live bed rest wins over the fallback anchor")
	couch.remove_from_group("couches")
	root.remove_child(couch)
	couch.free()
	_free(made)


func _check_rest_lookup() -> void:
	var made := _fixture()
	var facade: RefCounted = made["facade"]
	var bed: Node3D = made["bed"]
	var rest := FakeRest.new()
	rest.name = "Rest"
	var seat_a := Node3D.new()
	var seat_b := Node3D.new()
	rest.seats = [seat_a, seat_b]
	rest.add_child(seat_a)
	rest.add_child(seat_b)
	rest.add_to_group("couches")
	root.add_child(rest)
	check(facade.call("bed_rest_for", bed) == null,
		"a crate without an invite entry is not the bed rest")
	rest.set("_bed", bed)
	check(facade.call("bed_rest_for", bed) == rest,
		"the couch with the invite entry and seats is the bed rest")
	rest.seats = [seat_a]
	check(facade.call("bed_rest_for", bed) == null,
		"a rest without two seats is refused")
	rest.remove_from_group("couches")
	root.remove_child(rest)
	rest.free()
	_free(made)


func _check_note() -> void:
	var made := _fixture()
	var facade: RefCounted = made["facade"]
	var pony: FakePony = made["pony"]
	var rest := FakeRest.new()
	rest._mare_fits = true
	rest._cooldowns = {pony.get_instance_id(): Time.get_ticks_msec() + 4000}
	var note := str(facade.call("rejoin_note", rest))
	check(note.contains("posture=stand"), "the note reports the posture")
	check(note.contains("grounded=true"), "the note reports grounded")
	check(note.contains("nav=life:idle"), "the note reports the navigator owner")
	check(note.contains("cooldown="), "the note reports the guest cooldown")
	check(note.contains("fits=true"), "the note reports the bed fit")
	rest.free()
	_free(made)


func _check_restore() -> void:
	var made := _fixture()
	var facade: RefCounted = made["facade"]
	var pony: FakePony = made["pony"]
	var calls := [0]
	facade.restore_scene = func() -> void: calls[0] += 1
	facade.call("restore_posture", CATALOG.MISSIONARY, true)
	check(calls[0] == 1, "the missionary restore restores the scene")
	check((pony.posture as FakePosture).requested.has("stand"),
		"the restore stands her")
	facade.call("restore_posture", CATALOG.STANDING, true)
	check(calls[0] == 1, "the standing restore leaves the scene alone")
	_free(made)


func _check_place() -> void:
	var made := _fixture()
	var facade: RefCounted = made["facade"]
	var pony: FakePony = made["pony"]
	current_context["state"] = 2
	var anchor := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	await facade.call("place_on_bed", anchor)
	current_context["state"] = 0
	check(pony.global_position.is_equal_approx(anchor.origin),
		"the placement puts her on the bed anchor")
	check((pony.posture as FakePosture).requested.has("stand"),
		"the placement settles her upright")
	_free(made)


func _check_early_rejoin() -> void:
	var made := _fixture()
	var facade: RefCounted = made["facade"]
	var logs: Array[String] = []
	facade.log = func(text: String) -> void: logs.append(text)
	var bed: Node3D = made["bed"]
	current_context["serial"] = 8
	facade.call("rejoin_bed_cuddle", bed, 7)
	check(logs.is_empty(), "a stale act serial leaves the rejoin alone")
	current_context["serial"] = 7
	facade.call("rejoin_bed_cuddle", bed, 7)
	check(logs.size() == 1 and logs[0].contains("no_bed_rest"),
		"a bed with no rest logs and leaves her standing")
	_free(made)
