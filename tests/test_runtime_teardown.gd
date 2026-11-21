extends "res://mods/unfplap/tests/support/suite.gd"
## Act exit paths: one teardown, every borrowed value restored, safe to call twice.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_runtime_teardown.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const MISSIONARY_ANON := preload("res://mods/unfplap/poses/missionary_anon.gd")
const POSES := preload("res://mods/unfplap/poses/service.gd")
const FRAME := preload("res://mods/unfplap/act/frame.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const ACT_AGREEMENT := preload("res://mods/unfplap/act/agreement.gd")
const AGREEMENT := preload("res://mods/unfplap/negotiation/agreement.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const CATALOG_STANDING := "standing"
const CATALOG_STANDING_TEST := "standing_test"


class FakePony extends Node3D:
	var face_turn_rate := 0.45
	var sleeping := false
	var body_scale := 1.0
	var identity: Variant = null
	var skeleton: Variant = null
	var posture: Variant = null
	var expressions: Variant = null
	var posture_requests: Array[String] = []
	var reset_transforms: Array[Transform3D] = []
	var motion_paused := false
	var actual_speed := 0.0

	func posture_status() -> Dictionary:
		return {"requested": "stand", "settled": true}

	func is_held() -> bool:
		return false

	func grounded() -> bool:
		return true

	func action_interruption_reason() -> String:
		return ""

	func request_posture(name: String) -> bool:
		posture_requests.append(name)
		return true

	func reset_motion(transform: Transform3D) -> void:
		reset_transforms.append(transform)
		global_transform = transform


class FakeNav extends "res://mods/unfplap/tests/support/fakes/fake_nav.gd":
	pass


class FakePlayer extends Node3D:
	var _pitch := 0.0
	var _stand_eye := 1.6
	var _eye_height := 1.6
	var controls_locked := false
	var form_driver: Variant = null
	var seat: Variant = null
	var eye_pushes: Array[float] = []

	func eye_height() -> float:
		return _stand_eye

	func _set_eye_y(value: float) -> void:
		eye_pushes.append(value)


class FakeInventory extends RefCounted:
	var hud_hidden := false
	var hotbar: Variant = null
	var placed := 0
	var held := {}
	var holding_case := ""

	func _place_hotbar() -> void:
		placed += 1


class FakeGame extends Node:
	var inventory: Variant = null
	var headset_view := false


class FakeMemory extends Node:
	func cancel_act(_event_id: Variant = null, _keep_speaking: Variant = null) -> int:
		return 0

	func cancel_line(_key: Variant = null) -> void:
		pass

	func note(_kind: Variant = null, _id: Variant = null, _event_id: Variant = null,
			_reason: Variant = null) -> void:
		pass

	func line_state(_key: Variant = null) -> int:
		return 0

	func observers(_partner: Variant = null) -> Array:
		return []


class FakeMain extends Node:
	var player: Variant = null
	var hud: Variant = null
	var game: Variant = null
	var memory: Variant = null
	var view: Camera3D = null
	var anatomy: Variant = null
	var eligibility: Variant = null

	func camera() -> Camera3D:
		return view


class FakeEligibility extends "res://mods/unfplap/tests/support/fakes/fake_eligibility.gd":
	pass


class FakeAnatomyService extends "res://mods/unfplap/anatomy/service.gd":
	var consents: Array[String] = []
	var allow := true
	var reset_calls := 0

	func consent(_pony: Node, key: String) -> bool:
		consents.append(key)
		return allow

	func player_reset_pelvis() -> void:
		reset_calls += 1


func _fixture() -> Dictionary:
	var memory := FakeMemory.new()
	var hud: CanvasLayer = HUD.new()
	hud.name = "UnfplapHUD"
	var runtime: Node = RUNTIME.new(hud, memory)
	var pony: FakePony = FakePony.new()
	pony.posture = Node.new()
	pony.add_child(pony.posture)
	var nav: FakeNav = FakeNav.new()
	var scene_nav: FakeNav = FakeNav.new()
	scene_nav.name = "Navigator"
	pony.add_child(scene_nav)
	var player: FakePlayer = FakePlayer.new()
	var main: FakeMain = FakeMain.new()
	var game: FakeGame = FakeGame.new()
	game.inventory = FakeInventory.new()
	main.player = player
	WORLD.bind_player(main.player)
	main.game = game
	WORLD.bind_world(main.game)
	runtime.add_child(pony)
	runtime.add_child(nav)
	runtime.add_child(main)
	main.add_child(player)
	main.add_child(game)
	main.add_child(hud)
	runtime.pony = pony
	runtime.act.pony_id = "test_mare"
	runtime.act.pony_id = "test_mare"
	runtime._bundle.hold.face_turn_rate_saved = 0.45
	runtime._bundle.hold.face_turn_rate_owned = true
	pony.face_turn_rate = 0.0
	runtime._bundle.hold.locked_player = true
	runtime._bundle.hold.had_kiss_hold = false
	player.set_meta("kiss_hold", true)
	pony.set_meta("sex_active", true)
	runtime.act.posture_owned = true
	runtime.act.pose_id = CATALOG_STANDING
	runtime.act.source = "test"
	runtime.act._set_state(2)
	PONIES.set_active(runtime)
	runtime.act.input.toggle_auto_thrust()
	runtime._bundle.hold.nav = nav
	nav.command_owner = "unfplap:test_mare"
	nav.wander_enabled = false
	runtime._bundle.hold.nav_old_wander = false
	runtime._bundle.hold.token = "unfplap:test_mare"
	hud.set_inventory_hidden(true)
	return {"runtime": runtime, "pony": pony, "player": player, "main": main, "hud": hud}


class FakeHandle extends AGREEMENT.Handle:
	func _init() -> void:
		id = 1
		generation = 1
		cancel = func(_reason: String) -> bool: return true


func run() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var pony: FakePony = f["pony"]
	var player: FakePlayer = f["player"]
	var main: FakeMain = f["main"]
	var nav: FakeNav = runtime._bundle.hold.nav
	var inventory: FakeInventory = main.game.inventory

	# The scene-only Agreement start's guard rails: no handle, no option, and the aftercare clear.
	check(runtime.gate.start_agreement(null) == ACT_AGREEMENT.AGREEMENT_FAILED,
		"a missing Agreement handle fails the start")
	check(runtime.gate.start_agreement(FakeHandle.new()) == ACT_AGREEMENT.AGREEMENT_FAILED,
		"an Agreement without an option fails the start")
	check(runtime.gate.agreement_ready("missionary", "bed_side", null, null) == false,
		"a missing Agreement capability is never ready")
	pony.set_meta("sex_aftercare", true)
	runtime.act.clear_aftercare()
	check(not pony.has_meta("sex_aftercare"), "the Agreement start clears aftercare")

	runtime.act.exit.run(false)
	check(pony.face_turn_rate == 0.45, "face-turn rate restored")
	check(not runtime._bundle.hold.face_turn_rate_owned, "face-turn ownership cleared")
	check(nav.command_owner == "", "navigator ownership released")
	check(nav.wander_enabled == false, "navigator gives back the saved wander flag")
	check(not runtime._bundle.hold.locked_player, "player lock released")
	check(not player.has_meta("kiss_hold"), "kiss hold removed when the act set it")
	check(not pony.has_meta("sex_active"), "sex_active cleared")
	check(not (f["hud"] as CanvasLayer).inventory_hidden(), "inventory HUD restored")
	check(not inventory.hud_hidden, "inventory hud_hidden restored")
	check(inventory.placed == 1, "inventory re-places the hotbar")
	check(pony.posture_requests.size() == 1 and pony.posture_requests[0] == "stand",
		"standing posture requested once")
	check(not runtime.act.posture_owned, "posture ownership cleared")
	check(not runtime.act.input.auto_active(), "teardown clears auto thrust")
	check(int(runtime.act.state) == 0, "state returns to IDLE")
	check(runtime.act.pose_id == "" and runtime.act.source == "" and runtime.act.bed == null,
		"act ids cleared")
	check(not PONIES.act_running(), "the one exit clears the active runtime")

	# A second teardown is a no-op, not a second restore.
	runtime.act.exit.run(false)
	check(pony.face_turn_rate == 0.45, "double teardown keeps the saved face-turn rate")
	check(not pony.has_meta("sex_active"), "double teardown is safe")
	check(inventory.placed == 1, "double teardown does not re-place the hotbar")

	# Every hint scan reads Base clearance; a failing scene reads none.
	var eligibility := FakeEligibility.new()
	PONIES.eligibility = eligibility
	runtime.act._set_state(0)
	check(bool(runtime.gate.hotkey_ready(CATALOG_STANDING, "")),
		"the idle hint passes with the scene rows ready")
	check(eligibility.eligible_calls == 1 and eligibility.relationship_calls == 1,
		"the hint reads Base clearance")
	var hint_stool: Dictionary = runtime.gate.hint_stool()
	check(int(hint_stool.get("need", -1)) == 0 and int(hint_stool.get("have", -1)) == 0,
		"the hint reports the gate's footstool pair")
	check(bool(runtime.gate.hotkey_ready(CATALOG_STANDING, "")),
		"the next hint scan passes")
	check(eligibility.eligible_calls == 2 and eligibility.relationship_calls == 2,
		"the next hint scan reads Base clearance again")
	pony.set_meta("seated", true)
	check(not bool(runtime.gate.hotkey_ready(CATALOG_STANDING, "")),
		"a seated pony fails the standing hint")
	check(eligibility.eligible_calls == 2,
		"a failed scene row reads no Base clearance")
	pony.remove_meta("seated")
	check(bool(runtime.gate.hotkey_ready(CATALOG_STANDING, "")),
		"the standing hint recovers")
	check(eligibility.eligible_calls == 3 and eligibility.relationship_calls == 3,
		"the recovered scene reads Base clearance once")
	PONIES.eligibility = null

	# A forced stop at IDLE must not touch the player's captured look.
	var f2 := _fixture()
	var runtime2: Node = f2["runtime"]
	var player2: FakePlayer = f2["player"]
	runtime2.act._set_state(0)
	player2.rotation.y = 0.7
	runtime2.act.force_stop()
	check(absf(player2.rotation.y - 0.7) < 0.0001,
		"IDLE force_stop leaves the player yaw alone")

	# A failed standing start gives back the eye line the frame captured.
	var f3 := _fixture()
	var runtime3: Node = f3["runtime"]
	var player3: FakePlayer = f3["player"]
	player3._stand_eye = 1.6
	player3._eye_height = 1.6
	runtime3._bundle.frame.begin(FRAME.pose("standing"))
	player3._stand_eye = 2.1
	player3._eye_height = 2.1
	runtime3.act.exit.run(false)
	check(absf(player3._stand_eye - 1.6) < 0.0001, "aborted start restores the eye line")
	check(absf(player3._eye_height - 1.6) < 0.0001, "aborted start restores the eye height")

	# An invalid pony still releases the player, navigator and active runtime.
	var f4 := _fixture()
	var runtime4: Node = f4["runtime"]
	var main4: FakeMain = f4["main"]
	var nav4: FakeNav = runtime4._bundle.hold.nav
	runtime4.pony = null
	runtime4.act._set_state(4)
	runtime4.act.exit.finish_restore()
	check(not runtime4._bundle.hold.locked_player, "invalid pony still unlocks the player")
	check(nav4.command_owner == "", "invalid pony still releases the navigator")
	check(int(runtime4.act.state) == 0, "invalid pony ends in IDLE")
	check(not PONIES.act_running(), "invalid pony still clears the active runtime")

	# Finalize is idempotent.
	var f5 := _fixture()
	var runtime5: Node = f5["runtime"]
	runtime5.act.exit.finalize(false)
	check(runtime5.act.finalized, "finalize marks the session done")
	runtime5.act.exit.finalize(false)
	check(runtime5.act.finalized, "double finalize is a no-op")

	# Desktop standing start keeps her in place and places Anon behind her; act end restores him.
	var f6 := _fixture()
	var runtime6: Node = f6["runtime"]
	root.add_child(runtime6)
	var pony6: FakePony = f6["pony"]
	var player6: FakePlayer = f6["player"]
	pony6.global_position = Vector3(3.0, 0.0, 4.0)
	pony6.rotation.y = 0.7
	player6.global_position = Vector3(3.0, 0.0, 5.0)
	player6.rotation.y = 0.1
	var pony_start: Transform3D = pony6.global_transform
	var player_start: Transform3D = player6.global_transform
	var plan6: Variant = runtime6._bundle.frame.begin(FRAME.pose("standing"))
	check(pony6.global_transform.is_equal_approx(pony_start),
		"standing start keeps her in place")
	var gap6: float = float(runtime6.act.swap.standing_gap())
	var behind6: Vector3 = pony6.global_position + pony6.global_basis.z.normalized() * gap6
	behind6.y = player_start.origin.y
	check((plan6 as FRAME.PlayerPlan).root_transform.origin.is_equal_approx(behind6),
		"the standing plan places Anon behind her at the act gap")
	check(player6.global_position.is_equal_approx(behind6),
		"standing start places Anon behind her at the act gap")
	# A princess body's entrance sits further back than the mare's, so the same start keeps Anon
	# the same distance from her entrance.
	pony6.identity = {"id": "celestia"}
	var princess_gap: float = float(runtime6.act.swap.standing_gap())
	check(absf((princess_gap - gap6) - 0.0368) < 0.0001,
		"a princess entrance adds its back offset to the standing gap")
	pony6.identity = null
	var placed6: Transform3D = player6.global_transform
	var placed_yaw6 := player6.rotation.y
	runtime6._bundle.frame.end()
	check(player6.global_position.is_equal_approx(placed6.origin),
		"standing end leaves Anon in place")
	check(is_equal_approx(player6.rotation.y, placed_yaw6),
		"standing end leaves Anon's yaw alone")

	# The standing start leaves Anon behind her at the gap and clears the part's old handshake.
	# The contact is the per-frame pelvis offset's job; the start never measures the animated part.
	var f6b := _fixture()
	var runtime6b: Node = f6b["runtime"]
	root.add_child(runtime6b)
	var pony6b: FakePony = f6b["pony"]
	var player6b: FakePlayer = f6b["player"]
	pony6b.global_position = Vector3(3.0, 0.0, 4.0)
	pony6b.rotation.y = 0.0
	player6b.global_position = Vector3(3.0, 0.0, 5.0)
	var anatomy6b := FakeAnatomyService.new()
	PONIES.anatomy = anatomy6b
	var gap6b: float = float(runtime6b.act.swap.standing_gap())
	runtime6b._bundle.frame.begin(FRAME.pose("standing"))
	var base6b := Vector3(pony6b.global_position.x, 0.0, pony6b.global_position.z + gap6b)
	check(anatomy6b.reset_calls >= 1, "a standing start clears the part's old pelvis handshake")
	check(player6b.global_position.is_equal_approx(base6b),
		"the standing start leaves Anon behind her at the gap")

	# An idle sibling runtime must not take the borrowed quick slots from the act.
	var f7 := _fixture()
	var hud7: CanvasLayer = f7["hud"]
	var acting7: Node = RUNTIME.new()
	acting7.act._set_state(2) # ACTIVE
	PONIES.set_active(acting7)
	hud7.ensure_act_inventory_visible(PONIES.active())
	check(hud7.inventory_hidden(), "idle sibling leaves the active act's inventory HUD hidden")
	acting7.act._set_state(0) # IDLE
	hud7.ensure_act_inventory_visible(PONIES.active())
	check(not hud7.inventory_hidden(), "idle safety restores the HUD once no act is active")
	hud7.set_inventory_hidden(true)
	PONIES.clear_active(acting7)
	hud7.ensure_act_inventory_visible(PONIES.active())
	check(not hud7.inventory_hidden(), "idle safety restores the HUD with no active runtime")
	acting7.free()

	# The pose teardown detaches the act's modifiers before freeing them, so the skeleton has no
	# live act child when `_free_pose()` returns.
	var f8 := _fixture()
	var runtime8: Node = f8["runtime"]
	root.add_child(runtime8)
	var pony8: FakePony = f8["pony"]
	var body8 := Skeleton3D.new()
	body8.add_bone("pony_hips")
	pony8.skeleton = body8
	runtime8.act.start._build_pose()
	var built := 0
	for child: Node in body8.get_children():
		if str(child.name).begins_with("Unfplap"):
			built += 1
	check(built == 1, "the act installs its pose modifier on the body skeleton")
	check(runtime8._bundle.pose.view().id == CATALOG_STANDING
		and runtime8._bundle.pose.view().pose_state == 2,
		"the act fills the pose view")
	runtime8.act.exit.free_pose()
	check(runtime8._bundle.pose.view().id == ""
		and runtime8._bundle.pose.view().pose_state == 0,
		"the act teardown clears the pose view")
	var left := 0
	for child: Node in body8.get_children():
		if str(child.name).begins_with("Unfplap"):
			left += 1
	check(left == 0, "the pose teardown leaves no act modifier on the body skeleton")

	# The one act exit runs the same pose ledger: the view returns to IDLE and a second exit is
	# safe with no pose left behind.
	runtime8.act.start._build_pose()
	check(runtime8._bundle.pose.view().pose_state == 2, "a new act fills the pose view again")
	runtime8.act.exit.run(false)
	var after_exit := 0
	for child: Node in body8.get_children():
		if str(child.name).begins_with("Unfplap"):
			after_exit += 1
	check(runtime8._bundle.pose.view().id == ""
		and runtime8._bundle.pose.view().pose_state == 0,
		"the act exit leaves the pose view idle")
	check(after_exit == 0, "the act exit leaves no act modifier on the body skeleton")
	runtime8.act.exit.run(false)
	after_exit = 0
	for child: Node in body8.get_children():
		if str(child.name).begins_with("Unfplap"):
			after_exit += 1
	check(runtime8._bundle.pose.view().pose_state == 0 and after_exit == 0,
		"a second act exit is safe with no pose left behind")

	# An edge aborted by the one act exit: the run is dropped, the view returns to IDLE and the
	# pose node, the extra modifiers and the service-owned act body are freed, with no second exit
	# path.
	runtime8.act.pose_id = CATALOG_STANDING
	runtime8.act._set_state(2)
	runtime8.act.features = {"standing_body_sway": true}
	runtime8.act.start._build_pose()
	var act_body8 := MISSIONARY_ANON.new()
	runtime8._bundle.pose.act_body = act_body8
	check(runtime8._bundle.pose.body_sway != null,
		"the act body test installs the standing body sway")
	var edge: POSES.PoseResult = runtime8.act.input.request_pose(CATALOG_STANDING_TEST, "test")
	check(edge.code == "ok", "the runtime starts the debug edge")
	check(runtime8._bundle.pose.view().pose_state == 3,
		"the running edge puts the view in the transition state")
	runtime8.act.exit.run(false)
	check(runtime8._bundle.pose._run == null, "the act exit aborts the running edge")
	check(runtime8._bundle.pose.view().id == ""
		and runtime8._bundle.pose.view().pose_state == 0,
		"the act exit leaves the transition view idle")
	check(runtime8._bundle.pose.pose_node == null, "the act exit frees the edge's pose node")
	check(runtime8._bundle.pose.body_sway == null and runtime8._bundle.pose.act_body == null,
		"the act exit frees the extra modifier and the act body once")
	check(act_body8.is_queued_for_deletion(), "the act body is detached before it is freed")

	# The oral command requests the authored edge with the per-mare consent, and the one act exit
	# aborts it: the root and the facing come back once and the view is idle.
	runtime8.act.pose_id = CATALOG_STANDING
	runtime8.act._set_state(2)
	runtime8.act.features = {"anatomy_oral": true}
	var anatomy8 := FakeAnatomyService.new()
	PONIES.anatomy = anatomy8
	pony8.global_position = Vector3(2.0, 0.0, 3.0)
	var oral_from: Vector3 = pony8.global_position
	runtime8.act.start._build_pose()
	runtime8.act.toggle_anatomy_oral()
	check(anatomy8.consents == ["oral"], "the oral command asks the anatomy service for consent")
	check(runtime8._bundle.pose.view().pose_state == 3
		and runtime8._bundle.pose.view().edge_id == "standing__standing_oral",
		"the oral command starts the authored forward edge")
	runtime8._bundle.pose.tick(0.8)
	check(pony8.global_position.distance_to(oral_from) > 0.001,
		"the oral turn moves her during the edge")
	runtime8.act.exit.run(false)
	check(runtime8._bundle.pose._run == null, "the act exit aborts the oral edge")
	check(pony8.global_position.is_equal_approx(oral_from),
		"the act exit restores the captured oral root once")
	check(runtime8._bundle.pose.view().id == ""
		and runtime8._bundle.pose.view().pose_state == 0,
		"the act exit leaves the oral view idle")
	check(not runtime8._bundle.pose.pose_config.has("oral_pitch"),
		"the act exit erases the oral keys")

	# A missing consent or feature refuses before the edge starts and leaves her where she is.
	runtime8.act.pose_id = CATALOG_STANDING
	runtime8.act._set_state(2)
	runtime8.act.features = {"anatomy_oral": true}
	runtime8.act.start._build_pose()
	anatomy8.allow = false
	var refused_from: Vector3 = pony8.global_position
	runtime8.act.toggle_anatomy_oral()
	check(runtime8._bundle.pose._run == null
		and runtime8._bundle.pose.view().id == CATALOG_STANDING,
		"the missing oral consent starts no edge")
	check(pony8.global_position.is_equal_approx(refused_from),
		"the missing oral consent moves nothing")
	anatomy8.allow = true
	runtime8.act.features = {}
	runtime8.act.toggle_anatomy_oral()
	check(runtime8._bundle.pose._run == null,
		"the oral feature gate refuses before the edge starts")
	runtime8.act.exit.run(false)

	# AnonPony and headset/VR move her in front of the player; the player stays where he is.
	var f9 := _fixture()
	var runtime9: Node = f9["runtime"]
	root.add_child(runtime9)
	var pony9: FakePony = f9["pony"]
	var player9: FakePlayer = f9["player"]
	var main9: FakeMain = f9["main"]
	main9.game.headset_view = true
	var cam9 := Camera3D.new()
	main9.add_child(cam9)
	cam9.global_position = Vector3(5.0, 1.6, 6.0)
	cam9.rotation.y = 1.1
	main9.view = cam9
	pony9.global_position = Vector3(3.0, 0.0, 4.0)
	pony9.rotation.y = 0.7
	player9.global_position = Vector3(5.0, 0.2, 6.0)
	player9.rotation.y = 1.1
	var player_start9: Transform3D = player9.global_transform
	var headset9: Transform3D = \
		(runtime9._bundle.frame.begin(FRAME.pose("standing")) as FRAME.PlayerPlan).root_transform
	var gap9: float = float(runtime9.act.swap.standing_gap())
	var forward9: Vector3 = -cam9.global_basis.z
	forward9.y = 0.0
	forward9 = forward9.normalized()
	var expected9: Vector3 = player9.global_position + forward9 * gap9
	expected9.y = player9.global_position.y
	check(headset9.origin.is_equal_approx(expected9),
		"headset start moves her in front of the player at the act gap")
	check(pony9.reset_transforms.size() == 1
		and pony9.reset_transforms[0].is_equal_approx(headset9),
		"headset start applies the act transform to her")
	check(player9.global_transform.is_equal_approx(player_start9),
		"headset start leaves the player in place")

	# The one exit leaves no suspended typed change or adopted body behind.
	var f10 := _fixture()
	var runtime10: Node = f10["runtime"]
	var suspended := BODY_CHANGE.new()
	suspended.state = BODY_CHANGE.State.ADOPTED
	runtime10._bundle.handover.begin(suspended)
	runtime10._bundle.handover.adopt(f10["pony"])
	runtime10._bundle.handover.elapsed = 1.0
	runtime10.act.exit.run(false)
	check(runtime10._bundle.handover.change == null and not runtime10.act.suspended()
		and int(runtime10.act.state) == ACT_STATE.State.IDLE,
		"the one exit clears a suspended typed body change")

	# The body-change binding path refreshes the runtime without an act exit or a resume.
	var f11 := _fixture()
	var runtime11: Node = f11["runtime"]
	root.add_child(runtime11)
	var pony11: FakePony = f11["pony"]
	var main11: FakeMain = f11["main"]
	runtime11.act._set_state(2)
	runtime11.act.pose_id = CATALOG_STANDING
	var form11 := BODY_FORM.default_form(pony11)
	runtime11.act.bind_body_services(pony11, form11)
	check(int(runtime11.act.state) == 2, "a body bind leaves a live act live")
	check(not runtime11.act.suspended(), "a body bind never suspends the act")
	check(runtime11._bundle.pose.pony == pony11, "the body bind binds the pose session")
	check(runtime11._bundle.face.pony == pony11, "the body bind binds the face")
	check(PONIES.active() == runtime11, "a body bind never runs the act exit")
	form11.form_id = "rarity"
	form11.fit_id = "rarity"
	form11.revision = 1
	runtime11.act.refresh_body_services(pony11, form11)
	check(int(runtime11.act.state) == 2, "a same-node refresh leaves a live act live")
	check(float(runtime11._bundle.facts.player_eye_height) > 0.0,
		"a same-node refresh reapplies the stance")
	check(PONIES.active() == runtime11, "a same-node refresh never runs the act exit")
	runtime11._bundle.handover.context.form = form11
	runtime11._bundle.handover.context.change = BODY_CHANGE.new()
	runtime11.act.exit.run(false)
	check(runtime11._bundle.handover.context.form == null
		and runtime11._bundle.handover.context.change == null,
		"the one exit clears the reused policy context")

	for item: Dictionary in [f, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11]:
		(item["runtime"] as Node).free()
	if failures == 0:
		print("RUNTIME_TEARDOWN_PASS")
	finish()