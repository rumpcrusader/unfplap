extends SceneTree
## The idle offer service: the one-second scan cadence, the standing cone target, the standing
## gate's reuse window, the footstool block and its one toast, the hint row in the game's prompt
## row and the HUD fallback, the live Agreement offer, the pure `offer_target()` read and the offer
## cleared while an act is live.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/offer/test_offer.gd

const OFFER := preload("res://mods/unfplap/offer/service.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const AGREEMENT := preload("res://mods/unfplap/negotiation/agreement.gd")

var failures := 0
var checks := 0
var sink := LogSink.new()


class LogSink extends RefCounted:
	var lines: Array[String] = []

	func write(text: String) -> void:
		lines.append(text)


class FakeHints extends Node:
	var xr := false
	var _prompt2d: Variant = null


class FakeGame extends Node:
	var mares: Array = []
	var headset_view := false


class FakePlayer extends Node3D:
	var seat: Variant = null
	var camera: Variant = null


class FakeMare extends Node3D:
	var requested := "stand"

	func posture_status() -> Dictionary:
		return {"requested": requested}


class FakeRuntime extends Node:
	var rump := Vector3.ZERO
	var gate_ready := true
	var hotkey_calls := 0
	var stool := {"need": 0, "have": 0}
	var gap: Variant = 0.0
	var case_count := 0
	var agreement_ready := true

	func rump_anchor() -> Vector3:
		return rump

	func hotkey_ready(_pose: String, _source: String, _bed: Variant) -> bool:
		hotkey_calls += 1
		return gate_ready

	func hint_stool() -> Dictionary:
		return stool

	func stool_gap_m() -> Variant:
		return gap

	func stool_case_count() -> int:
		return case_count

	func agreement_offer_ready(_handle: Variant) -> bool:
		return agreement_ready


class FakeNegotiation extends Node:
	var live: Variant = null
	var hots: Array = []

	func handle() -> Variant:
		return live

	func hotkey_handle(runtime: Node, option: POSE_OPTIONS.Option) -> Variant:
		hots.append([runtime, option])
		return null


class FakeHud extends Node:
	var toasts: Array[String] = []
	var prompts: Array[String] = []
	var hides := 0

	func _show_toast(text: String, _seconds := 2.0) -> void:
		toasts.append(text)

	func show_prompt(text: String, _icon_name := "", _cap := "") -> void:
		prompts.append(text)

	func hide_prompt() -> void:
		hides += 1


## The entry's runtime read over a fixture dictionary.
class Runtimes extends RefCounted:
	var by_pony: Dictionary = {}

	func of(pony: Node) -> Node:
		var runtime: Variant = by_pony.get(pony)
		return runtime if is_instance_valid(runtime) else null


## The entry's act-target rule: the ponies this fixture allows.
class Targets extends RefCounted:
	var allowed: Array = []

	func allows(pony: Variant) -> bool:
		return allowed.has(pony)


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	SETTINGS.load_settings()
	LOG.debug_logs = true
	LOG.sink = Callable(sink, "write")
	_check_cadence_and_cone()
	await _check_gate_reuse()
	_check_blocked_stool()
	_check_blocked_need_two()
	_check_hint_row()
	_check_hud_fallback()
	_check_agreement_first()
	_check_hide_while_act_live()
	LOG.debug_logs = false
	print("OFFER_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("OFFER_PASS")
	quit(0 if failures == 0 else 1)


## Two standing mares inside the cone, with a stallion nearer inside it and a mare outside it: the
## nearest act target wins, and the scan waits for the one-second cadence.
func _check_cadence_and_cone() -> void:
	var made := _fixture()
	var service: OFFER = made["service"]
	var near: FakeMare = made["near"]
	var stallion: FakeMare = made["stallion"]
	var runtime: FakeRuntime = made["near_runtime"]
	near.requested = "lie_down"
	service.tick(0.5)
	check(service.current() == null, "no offer before the cadence")
	check(runtime.hotkey_calls == 0, "no gate read before the cadence")
	near.requested = "stand"
	service.tick(0.6)
	check(service.current() != null, "the scan runs at the one-second cadence")
	check(service.current().pony == near, "the nearest act target in the cone wins")
	check(service.current().pose == CATALOG.STANDING, "the standing pose is offered")
	check(stallion.global_position.z > near.global_position.z,
		"the stallion stands nearer than the winner")
	check(service.offer_target() == near, "offer_target names the offered pony")
	check(_count("OFFER pony=Near pose=standing source= bed=") == 1,
		"one OFFER line per new offer")
	service.tick(1.0)
	check(_count("OFFER pony=Near") == 1, "the same offer logs once while it stays")
	_free(made)


## The standing gate is reused while the same mare stays the cone target and refreshed after
## `GATE_REFRESH_S` of real time.
func _check_gate_reuse() -> void:
	var made := _fixture()
	var service: OFFER = made["service"]
	var runtime: FakeRuntime = made["near_runtime"]
	service.scan()
	check(runtime.hotkey_calls == 1, "the first scan runs the gate")
	service.scan()
	check(runtime.hotkey_calls == 1, "a second scan reuses the gate verdict")
	await create_timer(OFFER.GATE_REFRESH_S + 0.2).timeout
	service.scan()
	check(runtime.hotkey_calls == 2, "the gate is refreshed after its window")
	_free(made)


## A standing gate that wants a footstool Anon does not carry blocks the offer: the hint names the
## need, one toast explains it and one log line records it.
func _check_blocked_stool() -> void:
	var made := _fixture()
	var service: OFFER = made["service"]
	var hud: FakeHud = made["hud"]
	var runtime: FakeRuntime = made["near_runtime"]
	var row: HBoxContainer = made["row"]
	runtime.gate_ready = false
	runtime.stool = {"need": 1, "have": 0}
	runtime.gap = 0.12
	runtime.case_count = 0
	service.tick(OFFER.OFFER_SCAN_S)
	check(service.current() == null, "a blocked gate offers nothing")
	check(service.blocked() != null, "a blocked gate records the block")
	check(service.blocked().blocked_hint() == OFFER.NEEDS_STOOL_HINT,
		"the blocked hint names one footstool")
	check(int(service.blocked().blocked.get("need", 0)) == 1, "the block carries the need")
	check(hud.toasts == ["Find a footstool in a house."], "the block toasts once")
	check(_count("OFFER blocked pony=Near reason=needs_stool gap=0.120 need=1 have=0") == 1,
		"the block logs once with its gap")
	service.tick(OFFER.OFFER_SCAN_S)
	check(hud.toasts.size() == 1, "the same block does not toast twice")
	check(_count("OFFER blocked ") == 1, "the same block does not log twice")
	check(_unit_text(row.get_child(0)) == OFFER.NEEDS_STOOL_HINT,
		"the blocked hint reaches the prompt row")
	check(not row.get_child(0).get_child(0) is PanelContainer,
		"the blocked hint carries no act key cap")
	_free(made)


## Two footstools read as a count in both texts, with a fresh one-shot toast after a world reset.
func _check_blocked_need_two() -> void:
	var made := _fixture()
	var service: OFFER = made["service"]
	var hud: FakeHud = made["hud"]
	var runtime: FakeRuntime = made["near_runtime"]
	runtime.gate_ready = false
	runtime.stool = {"need": 2, "have": 1}
	runtime.case_count = 1
	runtime.gap = INF
	service.tick(OFFER.OFFER_SCAN_S)
	check(service.blocked() != null, "two footstools still block the offer")
	check(service.blocked().blocked_hint() == "Needs 2 footstools",
		"the hint counts two footstools")
	check(hud.toasts == ["Find 2 footstools in a house."], "the toast counts two footstools")
	check(_count("gap=n/a need=2 have=1") == 1, "an infinite gap logs as n/a")
	service.reset()
	service.tick(OFFER.OFFER_SCAN_S)
	check(hud.toasts.size() == 2, "a world reset re-arms the one-shot toast")
	_free(made)


## The hint is one more unit in the game's own prompt row, with the act key's cap, and the row's
## holder is shown while it holds it.
func _check_hint_row() -> void:
	var made := _fixture()
	var service: OFFER = made["service"]
	var row: HBoxContainer = made["row"]
	var holder: Control = made["holder"]
	var hud: FakeHud = made["hud"]
	service.tick(OFFER.OFFER_SCAN_S)
	check(row.get_child_count() == 1, "the hint is one more unit in the prompt row")
	check(holder.visible, "the prompt row holder is shown with the hint")
	check(hud.prompts.is_empty() and hud.hides > 0,
		"the native row keeps the HUD prompt hidden")
	var unit: Node = row.get_child(0)
	check(_unit_text(unit) == OFFER.OFFER_HINT, "the row reads the offer hint")
	check(unit.get_child(0) is PanelContainer, "the offer hint carries the act key cap")
	service.apply_settings()
	check(row.get_child_count() == 0, "a settings edit drops the row for a rebuild")
	service.tick(OFFER.OFFER_SCAN_S)
	check(row.get_child_count() == 1, "the next scan rebuilds the row")
	_free(made)


## VR and a world without the game's prompt row fall back to the HUD prompt, and the fallback is
## hidden again with no offer.
func _check_hud_fallback() -> void:
	var made := _fixture(false)
	var service: OFFER = made["service"]
	var hud: FakeHud = made["hud"]
	var runtime: FakeRuntime = made["near_runtime"]
	service.tick(OFFER.OFFER_SCAN_S)
	check(hud.prompts == [OFFER.OFFER_HINT], "the HUD prompt is the fallback hint")
	var hides := hud.hides
	var near: FakeMare = made["near"]
	var far: FakeMare = made["far"]
	near.requested = "lie_down"
	far.requested = "lie_down"
	service.tick(OFFER.OFFER_SCAN_S)
	check(hud.prompts.size() == 1 and hud.hides > hides, "no offer hides the fallback prompt")
	_free(made)


## A live Agreement is the act key's offer before the scene scan, through the typed handle.
func _check_agreement_first() -> void:
	var made := _fixture()
	var service: OFFER = made["service"]
	var negotiation: FakeNegotiation = made["negotiation"]
	var near: FakeMare = made["near"]
	var runtime: FakeRuntime = made["near_runtime"]
	var handle := AGREEMENT.Handle.new()
	handle.pony = near
	var option := POSE_OPTIONS.Option.new()
	option.pose = CATALOG.MISSIONARY
	option.source = "bed_side"
	handle.option = option
	negotiation.live = handle
	service.scan()
	check(service.current() != null and service.current().pony == near,
		"the live Agreement is offered")
	check(service.current().trigger == "agreement", "the Agreement trigger is carried")
	check(runtime.hotkey_calls == 0, "the Agreement skips the scene gate")
	runtime.agreement_ready = false
	service.scan()
	check(service.current() != null and service.current().trigger.is_empty(),
		"an Agreement that is not ready falls back to the scene scan")
	negotiation.live = null
	_free(made)


## `offer_target()` reads the scan result instead of rescanning, and an act takes the hint away.
func _check_hide_while_act_live() -> void:
	var made := _fixture()
	var service: OFFER = made["service"]
	var runtime: FakeRuntime = made["near_runtime"]
	var near: FakeMare = made["near"]
	var row: HBoxContainer = made["row"]
	var holder: Control = made["holder"]
	service.tick(OFFER.OFFER_SCAN_S)
	runtime.hotkey_calls = 0
	check(service.offer_target() == near, "offer_target reads the current scan result")
	check(runtime.hotkey_calls == 0, "offer_target never rescans")
	check(service.current() != null, "the read leaves the offer in place")
	near.requested = "lie_down"
	var far: FakeMare = made["far"]
	far.requested = "lie_down"
	service.tick(OFFER.OFFER_SCAN_S)
	check(service.offer_target() == null, "a scan without an offer clears the target")
	check(service.current() == null, "the scan dropped the offer")
	near.requested = "stand"
	far.requested = "stand"
	service.tick(OFFER.OFFER_SCAN_S)
	check(service.current() != null, "the offer returns on the next scan")
	service.clear_current()
	check(service.current() == null, "clear_current drops the offer")
	service.hide_hint()
	check(service.current() == null and service.blocked() == null, "an act clears the offer")
	check(row.get_child_count() == 0 and not holder.visible,
		"an act takes the hint out of the prompt row")
	_free(made)


## A world with the game's prompt row, one nearest standing mare and a nearer stallion.
func _fixture(with_row := true) -> Dictionary:
	var game := FakeGame.new()
	game.name = "FakeGame"
	var player := FakePlayer.new()
	player.name = "FakePlayer"
	var view := Camera3D.new()
	view.name = "FakeView"
	player.add_child(view)
	player.camera = view
	root.add_child(player)
	player.global_position = Vector3(0.0, 0.0, 3.0)
	var near := _mare("Near", Vector3(0.0, 0.0, 2.2))
	var far := _mare("Far", Vector3(0.0, 0.0, 1.2))
	var stallion := _mare("Stallion", Vector3(0.0, 0.0, 2.6))
	var outside := _mare("Outside", Vector3(0.0, 0.0, 1.6))
	# Her backward axis faces away from Anon, so he is outside her rear fan.
	outside.basis = Basis(Vector3.UP, PI)
	game.mares = [near, far, stallion, outside]
	var runtimes := Runtimes.new()
	var targets := Targets.new()
	targets.allowed = [near, far, outside]
	var runtime_nodes: Array[Node] = []
	for mare: FakeMare in [near, far, stallion, outside]:
		var runtime := FakeRuntime.new()
		runtime.name = "Runtime"
		runtime.rump = mare.global_position
		runtimes.by_pony[mare] = runtime
		runtime_nodes.append(runtime)
	var holder: Control = null
	var row: HBoxContainer = null
	if with_row:
		var hints := FakeHints.new()
		hints.name = "InteractionHints"
		holder = Control.new()
		row = HBoxContainer.new()
		hints.add_child(holder)
		holder.add_child(row)
		hints._prompt2d = row
		game.add_child(hints)
	var hud := FakeHud.new()
	var negotiation := FakeNegotiation.new()
	var service := OFFER.new()
	service.name = "UnfplapOffer"
	service.runtime_for = Callable(runtimes, "of")
	service.act_target = Callable(targets, "allows")
	service.negotiation = negotiation
	service.hud = hud
	HUD.instance = hud
	root.add_child(game)
	root.add_child(hud)
	root.add_child(negotiation)
	root.add_child(service)
	for runtime: Node in runtime_nodes:
		root.add_child(runtime)
	WORLD.bind_world(game)
	WORLD.bind_player(player)
	return {"service": service, "game": game, "player": player, "hud": hud,
		"negotiation": negotiation, "near": near, "far": far, "stallion": stallion,
		"near_runtime": runtimes.by_pony[near], "row": row, "holder": holder,
		"runtimes": runtime_nodes, "registry": runtimes, "targets": targets}


func _mare(mare_name: String, at: Vector3) -> FakeMare:
	var mare := FakeMare.new()
	mare.name = mare_name
	root.add_child(mare)
	mare.global_position = at
	return mare


func _free(made: Dictionary) -> void:
	var service: Node = made["service"]
	service.reset()
	WORLD.unbind()
	HUD.instance = null
	var nodes: Array[Node] = [made["negotiation"], made["hud"], made["player"], made["game"],
		made["far"], made["stallion"], made["near"]]
	nodes.append_array(made["runtimes"])
	for node: Node in nodes:
		root.remove_child(node)
		node.free()
	root.remove_child(service)
	service.free()


func _count(needle: String) -> int:
	var total := 0
	for line: String in sink.lines:
		if line.contains(needle):
			total += 1
	return total


## The words of one prompt-row unit: its last label, after an optional key cap.
func _unit_text(unit: Node) -> String:
	var text := ""
	for child: Node in unit.find_children("*", "Label", true, false):
		text = str((child as Label).text)
	return text
