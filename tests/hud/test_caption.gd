extends "res://mods/unfplap/tests/support/suite.gd"
## The caption move, the toast sink and the one-time Dance Mod key notice. The caption needs the
## game's speech setting and the game's mods host, so both are faked under `/root` here.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/hud/test_caption.gd

const HUD := preload("res://mods/unfplap/hud/service.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const ACT_KEYS := preload("res://mods/unfplap/shared/act_keys.gd")

## Where the suite leaves the caption card before a move: any place but the top margin.
const BOTTOM_Y := 640.0



## The game's settings autoload: one speech setting and the change signal the HUD subscribes to.
class FakeGameSettings extends Node:
	signal changed(key: String)
	var speech := "caption"

	func get_value(path: String) -> Variant:
		return speech if path == "access/speech_text" else null


## The game's mods host: which packs are on.
class FakeMods extends Node:
	var active: Array[String] = []

	func is_active(id: String) -> bool:
		return id in active


## The game's speech caption: the mod moves `_card` and reads `preview` and `_scale`.
class FakeCaption extends Control:
	var preview := false
	var _card: Control = null
	var _scale := 1.0

	func _init() -> void:
		_card = Control.new()
		add_child(_card)


## A sink that records what the toast facade would show.
class ToastSink extends Node:
	var shown: Array = []

	func _show_toast(text: String, seconds: float) -> void:
		shown.append([text, seconds])


## A real HUD with its toast label replaced by the same recorder, for the duration defaults.
class SinkHud extends "res://mods/unfplap/hud/service.gd":
	var shown: Array = []

	func _show_toast(text: String, seconds := 2.0) -> void:
		shown.append([text, seconds])


## The game's quick-slot inventory and its bar, for the HUD's borrowed-card accessors.
class FakeInventory extends Node:
	var hud_hidden := false
	var hotbar: Node = null
	var place_calls := 0

	func _place_hotbar() -> void:
		place_calls += 1


class FakeHotbar extends Control:
	var hud_calls: Array[bool] = []
	var _hud: CanvasLayer = null

	func set_hud_visible(on: bool) -> void:
		hud_calls.append(on)


## The world root the inventory view resolves its node from.
class FakeWorld extends Node:
	var inventory: Node = null


func run() -> void:
	_check_caption_conditions()
	_check_caption_scale()
	_check_toast_duration()
	_check_accessors()
	await _check_toast_line()
	_check_dance_notice()
	_check_live_settings()
	if failures == 0:
		print("CAPTION_PASS")
	finish()


## The five conditions: the player's mode, an act in POSING_IN/ACTIVE/CLIMAX, the game's explicit
## bottom caption, a card that is not the settings-page preview, and a live card to move.
func _check_caption_conditions() -> void:
	var real_settings := _hide("Settings")
	var game := FakeGameSettings.new()
	game.name = "Settings"
	root.add_child(game)
	var hud: CanvasLayer = HUD.new()
	root.add_child(hud)
	hud.set("_captions_on_top", true)
	var caption := FakeCaption.new()
	caption.name = "SpeechCaption"
	root.add_child(caption)
	var card: Control = caption.get("_card")
	hud.call("caption_node", caption)

	card.position.y = BOTTOM_Y
	hud.call("caption_tick", HUD.STATE_IDLE)
	check(card.position.y == BOTTOM_Y, "idle leaves the caption at the bottom")
	hud.call("caption_tick", HUD.STATE_RESTORE)
	check(card.position.y == BOTTOM_Y, "the restore state leaves the caption at the bottom")
	hud.call("caption_tick", HUD.STATE_AFTERGLOW)
	check(card.position.y == BOTTOM_Y, "afterglow returns the caption to the bottom")

	for state: int in [HUD.STATE_POSING_IN, HUD.STATE_ACTIVE, HUD.STATE_CLIMAX]:
		card.position.y = BOTTOM_Y
		hud.call("caption_tick", state)
		check(card.position.y == HUD.CAPTION_TOP_MARGIN,
			"state %d moves the caption to the top margin" % state)

	# The player chose the mode: off leaves the caption alone whatever the act does.
	hud.set("_captions_on_top", false)
	card.position.y = BOTTOM_Y
	hud.call("caption_tick", HUD.STATE_ACTIVE)
	check(card.position.y == BOTTOM_Y, "the mode being off leaves the caption at the bottom")
	hud.call("apply_settings")
	check(bool(hud.get("_captions_on_top")) == SETTINGS.captions_on_top.get_bool(),
		"a settings edit caches the player's caption mode")
	hud.set("_captions_on_top", true)

	# The game's own speech setting decides whether this caption is the explicit bottom one.
	game.speech = "over_head"
	card.position.y = BOTTOM_Y
	hud.call("caption_tick", HUD.STATE_ACTIVE)
	check(card.position.y == BOTTOM_Y, "an overhead caption is never moved")
	game.speech = "caption"
	game.changed.emit("access/speech_text")
	check(card.position.y == HUD.CAPTION_TOP_MARGIN,
		"the HUD reacts to the game's speech setting itself")

	# The settings-page preview is the page's own copy of the card, not the live caption.
	caption.preview = true
	card.position.y = BOTTOM_Y
	hud.call("caption_tick", HUD.STATE_ACTIVE)
	check(card.position.y == BOTTOM_Y, "the settings-page preview is skipped")
	caption.preview = false

	# A caption created mid-act is placed at once; a freed one is dropped from the tracking.
	var late := FakeCaption.new()
	root.add_child(late)
	hud.call("caption_node", late)
	check((late.get("_card") as Control).position.y == HUD.CAPTION_TOP_MARGIN,
		"a caption that appears during an act is moved at once")
	var tracked: Dictionary = hud.get("_captions")
	var before := tracked.size()
	root.remove_child(late)
	late.free()
	hud.call("caption_tick", HUD.STATE_ACTIVE)
	check((hud.get("_captions") as Dictionary).size() == before - 1,
		"a freed caption is dropped from the tracking")

	root.remove_child(caption)
	caption.free()
	root.remove_child(hud)
	hud.free()
	root.remove_child(game)
	game.free()
	_restore(real_settings, "Settings")


## The settings notification reaches the live node without the entry: one apply_live() re-reads the
## caption mode, and a freed HUD leaves the list.
func _check_live_settings() -> void:
	var base := CHANGE.listener_count()
	var real_settings := _hide("Settings")
	var game := FakeGameSettings.new()
	game.name = "Settings"
	root.add_child(game)
	var hud: CanvasLayer = HUD.new()
	root.add_child(hud)
	check(CHANGE.listener_count() == base + 1, "the HUD joins the settings notification")
	var saved := SETTINGS.captions_on_top.get_bool()
	hud.set("_captions_on_top", saved)
	SETTINGS.captions_on_top.set_bool(not saved)
	SETTINGS.apply_live()
	check(bool(hud.get("_captions_on_top")) == (not saved),
		"apply_live() re-reads the caption mode on the live HUD")
	SETTINGS.captions_on_top.set_bool(saved)
	root.remove_child(hud)
	hud.free()
	check(CHANGE.listener_count() == base, "a freed HUD leaves the settings notification")
	SETTINGS.apply_live()
	root.remove_child(game)
	game.free()
	_restore(real_settings, "Settings")


## The caption's own scale multiplies the margin, rounded, and never divides by zero.
func _check_caption_scale() -> void:
	var real_settings := _hide("Settings")
	var game := FakeGameSettings.new()
	game.name = "Settings"
	root.add_child(game)
	var hud: CanvasLayer = HUD.new()
	root.add_child(hud)
	hud.set("_captions_on_top", true)
	var caption := FakeCaption.new()
	root.add_child(caption)
	var card: Control = caption.get("_card")
	hud.call("caption_node", caption)
	var cases := [[1.0, 26.0], [1.5, 39.0], [0.5, 13.0], [2.0, 52.0], [0.0, 0.0]]
	for entry: Array in cases:
		caption.set("_scale", float(entry[0]))
		card.position.y = BOTTOM_Y
		hud.call("caption_tick", HUD.STATE_ACTIVE)
		check(card.position.y == float(entry[1]),
			"scale %s keeps the margin at %s" % [str(entry[0]), str(entry[1])])
	root.remove_child(caption)
	caption.free()
	root.remove_child(hud)
	hud.free()
	root.remove_child(game)
	game.free()
	_restore(real_settings, "Settings")


## The sink's two defaults: four seconds for the toast, two for an anatomy status line.
func _check_toast_duration() -> void:
	var hud := SinkHud.new()
	root.add_child(hud)
	hud.toast("blocked")
	hud.toast("short", 1.5)
	hud.toast("")
	hud.anatomy_status("status")
	hud.anatomy_status("long", 3.0)
	check(hud.shown == [["blocked", 4.0], ["short", 1.5], ["status", 2.0], ["long", 3.0]],
		"the toast lasts 4 s and the anatomy status 2 s unless the caller says otherwise")
	root.remove_child(hud)
	hud.free()


## The inventory and menu views the HUD now routes through: the live answer and the absent one.
func _check_accessors() -> void:
	var sink := ToastSink.new()
	root.add_child(sink)
	WORLD.menu().show_toast(sink, "hello", 1.5)
	check(sink.shown == [["hello", 1.5]], "the toast view reaches the sink")
	WORLD.menu().show_toast(null, "nobody", 1.0)
	var plain := Node.new()
	root.add_child(plain)
	WORLD.menu().show_toast(plain, "nobody", 1.0)
	check(sink.shown.size() == 1, "a null or plain toast target is a quiet no-op")

	var game := FakeWorld.new()
	root.add_child(game)
	var inventory := FakeInventory.new()
	root.add_child(inventory)
	game.inventory = inventory
	WORLD.bind_world(game)

	var briefcase := WORLD.inventory()
	check(not briefcase.hud_hidden(), "the inventory's hidden flag reads false")
	briefcase.set_hud_hidden(true)
	check(inventory.hud_hidden, "the inventory's hidden flag is written")
	check(briefcase.hotbar() == null, "an inventory without a hotbar answers null")
	var bar := FakeHotbar.new()
	root.add_child(bar)
	inventory.hotbar = bar
	check(briefcase.hotbar() == bar, "the inventory's hotbar is read")
	check(briefcase.hotbar_visible(bar), "the hotbar's visible flag reads true")
	bar.visible = false
	check(not briefcase.hotbar_visible(bar), "the hotbar's visible flag reads false")
	briefcase.set_hotbar_visible(bar, true)
	check(bar.visible, "the hotbar's visible flag is written")
	check(briefcase.hotbar_layer(bar) == null, "a hotbar without a layer answers null")
	var layer := CanvasLayer.new()
	bar.add_child(layer)
	bar._hud = layer
	check(briefcase.hotbar_layer(bar) == layer, "the hotbar's HUD layer is read")
	briefcase.set_hotbar_layer_visible(bar, false)
	check(bar.hud_calls == [false], "the hotbar's own HUD switch is called")
	briefcase.place_hotbar()
	check(inventory.place_calls == 1, "the inventory's own hotbar placement is called")

	# Absent members answer the typed zero and are never created.
	var plain_inventory := Node.new()
	root.add_child(plain_inventory)
	game.inventory = plain_inventory
	briefcase = WORLD.inventory()
	check(not briefcase.hud_hidden(), "a plain inventory answers false")
	briefcase.set_hud_hidden(true)
	check(plain_inventory.get("hud_hidden") == null,
		"a plain inventory is never given the hidden flag")
	check(briefcase.hotbar() == null, "a plain inventory answers no hotbar")
	check(not briefcase.hotbar_visible(plain_inventory), "a plain node answers not visible")
	briefcase.set_hotbar_visible(plain_inventory, true)
	check(plain_inventory.get("visible") == null, "a plain node is never given a visible flag")
	check(briefcase.hotbar_layer(plain_inventory) == null, "a plain node answers no HUD layer")
	briefcase.set_hotbar_layer_visible(plain_inventory, true)
	briefcase.place_hotbar()
	WORLD.unbind()

	plain_inventory.queue_free()
	plain.queue_free()
	layer.queue_free()
	bar.queue_free()
	inventory.queue_free()
	sink.queue_free()
	game.queue_free()


## The toast line itself: shown at once and hidden when its own duration runs out.
func _check_toast_line() -> void:
	var hud: CanvasLayer = HUD.new()
	root.add_child(hud)
	hud.toast("Find a footstool in a house.", 0.1)
	var label := hud.get("_toast_label") as Label
	check(label != null and label.visible, "the toast shows the moment it is set")
	check(label != null and label.text == "Find a footstool in a house.",
		"the toast carries the caller's line")
	await create_timer(0.25).timeout
	check(label != null and not label.visible, "the toast hides when its duration runs out")
	root.remove_child(hud)
	hud.free()


## The Dance Mod note: once per world, only while the act key is another key.
func _check_dance_notice() -> void:
	var real_mods := _hide("Mods")
	var mods := FakeMods.new()
	mods.name = "Mods"
	mods.active = ["dance_mod"]
	root.add_child(mods)
	var hud: CanvasLayer = HUD.new()
	root.add_child(hud)
	var label := hud.get("_toast_label") as Label
	var key_label := ACT_KEYS.label(int(SETTINGS.act_key.get_num()))

	hud.call("on_world", null)
	hud.call("on_player", null)
	var shown: int = int(hud.get("_toast_serial"))
	hud.call("on_player", null)
	check(int(hud.get("_toast_serial")) == shown, "the key notice is one per world")
	if int(SETTINGS.act_key.get_num()) == KEY_Y:
		check(not label.visible, "no notice while the act key is the Dance Mod's own Y")
	else:
		check(label.visible and label.text == "Dance Mod uses Y; %s starts the act." % key_label,
			"the notice names the act key")

	# A world re-enter arms the note again.
	hud.call("on_world", null)
	hud.call("on_player", null)
	check(int(hud.get("_toast_serial")) == shown + 1, "a new world shows the notice once more")

	# The Dance Mod off: nothing to warn about.
	mods.active = []
	hud.call("on_world", null)
	var quiet: int = int(hud.get("_toast_serial"))
	hud.call("on_player", null)
	check(int(hud.get("_toast_serial")) == quiet, "no notice without the Dance Mod")

	root.remove_child(hud)
	hud.free()
	mods.active = []
	root.remove_child(mods)
	mods.free()
	_restore(real_mods, "Mods")


## The game's autoloads run in a suite too, so a fake stands in under the real name while the
## real node waits aside; the caller restores it with `_restore()`.
func _hide(name: String) -> Node:
	var existing: Node = root.get_node_or_null(name)
	if existing != null:
		existing.name = name + "TestHidden"
	return existing


func _restore(existing: Node, name: String) -> void:
	if existing != null and is_instance_valid(existing):
		existing.name = name
