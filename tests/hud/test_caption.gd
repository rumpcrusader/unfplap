extends SceneTree
## The caption move, the toast sink and the one-time Dance Mod key notice. The caption needs the
## game's speech setting and the game's mods host, so both are faked under `/root` here.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/hud/test_caption.gd

const HUD := preload("res://mods/unfplap/hud/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ACT_KEYS := preload("res://mods/unfplap/shared/act_keys.gd")

## Where the suite leaves the caption card before a move: any place but the top margin.
const BOTTOM_Y := 640.0

var failures := 0
var checks := 0


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


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	_check_caption_conditions()
	_check_caption_scale()
	_check_toast_duration()
	await _check_toast_line()
	_check_dance_notice()
	print("CAPTION_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("CAPTION_PASS")
	quit(0 if failures == 0 else 1)


## The five conditions: the player's mode, an act in POSING_IN/ACTIVE/CLIMAX, the game's explicit
## bottom caption, a card that is not the settings-page preview, and a live card to move.
func _check_caption_conditions() -> void:
	var real_settings := _hide("Settings")
	var game := FakeGameSettings.new()
	game.name = "Settings"
	root.add_child(game)
	var hud: CanvasLayer = HUD.new()
	root.add_child(hud)
	HUD.instance = hud
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

	HUD.instance = null
	root.remove_child(caption)
	caption.free()
	root.remove_child(hud)
	hud.free()
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
	var sink := ToastSink.new()
	root.add_child(sink)
	HUD.instance = sink
	HUD.toast("blocked")
	HUD.toast("short", 1.5)
	HUD.toast("")
	HUD.anatomy_status("status")
	HUD.anatomy_status("long", 3.0)
	check(sink.shown == [["blocked", 4.0], ["short", 1.5], ["status", 2.0], ["long", 3.0]],
		"the toast lasts 4 s and the anatomy status 2 s unless the caller says otherwise")
	HUD.instance = null
	HUD.toast("no hud")
	HUD.anatomy_status("no hud")
	check(sink.shown.size() == 4, "a toast with no HUD is a quiet no-op")
	root.remove_child(sink)
	sink.free()


## The toast line itself: shown at once and hidden when its own duration runs out.
func _check_toast_line() -> void:
	var hud: CanvasLayer = HUD.new()
	root.add_child(hud)
	HUD.instance = hud
	HUD.toast("Find a footstool in a house.", 0.1)
	var label := hud.get("_toast_label") as Label
	check(label != null and label.visible, "the toast shows the moment it is set")
	check(label != null and label.text == "Find a footstool in a house.",
		"the toast carries the caller's line")
	await create_timer(0.25).timeout
	check(label != null and not label.visible, "the toast hides when its duration runs out")
	HUD.instance = null
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

	hud.call("on_world")
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
	hud.call("on_world")
	hud.call("on_player", null)
	check(int(hud.get("_toast_serial")) == shown + 1, "a new world shows the notice once more")

	# The Dance Mod off: nothing to warn about.
	mods.active = []
	hud.call("on_world")
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
