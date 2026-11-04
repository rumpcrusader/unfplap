extends Node
## Unfplap: adult intimacy for consenting adult ponies at the Marefriend stage.
## The entry node owns the player HUD/input and one lightweight runtime per pony. It never edits
## game files; it only reads the game's pony, relationship, memory and bed APIs.

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const HUD := preload("res://mods/unfplap/hud.gd")
const INPUT := preload("res://mods/unfplap/input.gd")
const INITIATION := preload("res://mods/unfplap/initiation.gd")
const CLASSIFIER := preload("res://mods/unfplap/consent_classifier.gd")
const DIALOGUE_CONSENT := preload("res://mods/unfplap/dialogue_consent.gd")
const DEBUG_SKELETON := preload("res://mods/unfplap/debug_skeleton.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const SCHEMA := preload("res://mods/unfplap/tunables_schema.gd")
const TUNABLES := preload("res://mods/unfplap/tunables.gd")
const TUNABLES_UI := preload("res://mods/unfplap/tunables_ui.gd")
const TASTE := preload("res://mods/unfplap/preferences.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const INTERACTOR_PATH := "res://player/interactor.gd"
const PONY_PATH := "res://world/characters/locomotion/pony_locomotion.gd"
const SETTINGS_PAGE_PATH := "res://world/ui/settings_page.gd"
const CAPTION_PATH := "res://world/ui/speech_caption.gd"
## The game's own bottom-caption margin; the mod keeps its card at this distance from the top.
const CAPTION_TOP_MARGIN := 26.0
## The offer hint beside the game's prompt row: a single Y press starts the act, so it reads like
## the base game's tap prompts ("G · Carry"), not a hold. Only Y during an act is a hold.
const OFFER_HINT := "Make love"
## Mod setting: DEBUG LOGS. Persisted in user://mods/data/unfplap/settings.json.
## Default OFF. Toggle in the Debug settings tab.
var debug_logs := false
## Cached feature flags read outside an act; a settings edit refreshes them.
var press_y_starts_sex := false

var game
var player
var hud
var input
var initiation
var classifier
var dialogue_consent
var active_runtime

var _runtimes: Dictionary = {}
var _offer: Dictionary = {}
var _offer_clock := 0.0
var _interactor: Node
var _desktop: Node
var _camera_cache: Camera3D
var _camera_cache_at := 0.0
## -1 = nothing pending; 0/1 = the controls_locked value to restore once menus close.
var pending_unlock := -1
var _last_offer_key := ""
var _native_hint_label: Control
var _debug_skeleton: Node3D
var _injected_settings: Array = []
var _settings_switch_guard := false
## instance id -> WeakRef for every SpeechCaption the mod may move to the top.
var _captions: Dictionary = {}
## Cached captions_on_top so the per-frame caption tick never rereads settings.json.
var _captions_on_top := false


func debug(text: String) -> void:
	if debug_logs:
		print("[unfplap] " + text)


## Live act/afterglow context for the game's normal dialogue prompt (pony_prompt_notes).
func prompt_note(pony: String) -> String:
	if pony.is_empty():
		return ""
	for runtime: Variant in _runtimes.values():
		if is_instance_valid(runtime) and str(runtime.get("_id")) == pony:
			return str(runtime.call("prompt_note"))
	return ""


func _debug(text: String) -> void:
	debug(text)


## One entry per diagnostic action: identification first, then tab-indented rows.
func _debug_block(title: String, rows: Array) -> void:
	var text := title
	for row: Variant in rows:
		var line := str(row)
		if line.is_empty():
			continue
		text += "\n\t" + line
	debug(text)


func _ready() -> void:
	process_priority = 100
	set_process(true)
	add_to_group("pony_prompt_notes")
	debug_logs = TUNABLES.get_bool("debug_logs")
	press_y_starts_sex = TUNABLES.get_bool("features.press_y_starts_sex")
	_captions_on_top = TUNABLES.get_bool("features.captions_on_top")
	classifier = CLASSIFIER.new()
	classifier.name = "UnfplapClassifier"
	add_child(classifier)
	dialogue_consent = DIALOGUE_CONSENT.new()
	dialogue_consent.name = "UnfplapDialogueConsent"
	dialogue_consent.main = self
	add_child(dialogue_consent)
	initiation = INITIATION.new()
	initiation.name = "UnfplapInitiation"
	initiation.main = self
	add_child(initiation)
	# Proves which build is live: a real source file has a non-zero mtime; a pack/PCK reports 0.
	var source_mtime := 0
	for path: String in [
			"res://mods/unfplap/runtime.gd",
			"res://mods/unfplap/thrust.gd",
			"res://mods/unfplap/preferences.gd",
			"res://mods/unfplap/utterance.gd",
			"res://mods/unfplap/poses/skeleton_pose.gd",
			"res://mods/unfplap/poses/missionary_recipe.gd",
			"res://mods/unfplap/poses/standing_recipe.gd",
	]:
		source_mtime = maxi(source_mtime, FileAccess.get_modified_time(path))
	_debug("entry ready (debug logs %s) runtime_mtime=%d" % [
		"ON" if debug_logs else "OFF", source_mtime])
	Mods.world_ready.connect(_on_world)
	Mods.world_closed.connect(_on_world_closed)
	Mods.player_ready.connect(_on_player)
	Mods.on_node(PONY_PATH, _on_pony)
	Mods.on_node(SETTINGS_PAGE_PATH, _on_settings_page)
	Mods.on_node(CAPTION_PATH, _on_caption)
	var settings := get_node_or_null("/root/Settings")
	if settings != null and settings.has_signal("changed") \
			and not settings.changed.is_connected(_on_game_setting_changed):
		settings.changed.connect(_on_game_setting_changed)
	_apply_caption_top.call_deferred()
	# Switched on mid-game: the world and player already exist.
	if is_instance_valid(Mods.game):
		_on_world(Mods.game)
		var existing: Variant = Mods.game.get("player")
		if is_instance_valid(existing):
			_on_player(existing)


func _on_world(host: Node) -> void:
	_clear_native_hint()
	press_y_starts_sex = TUNABLES.get_bool("features.press_y_starts_sex")
	game = host
	_interactor = null
	_desktop = null
	_camera_cache = null
	_camera_cache_at = 0.0
	_offer = {}
	if is_instance_valid(initiation):
		initiation.reset()
	if is_instance_valid(classifier):
		classifier.call("cancel_all")
	if is_instance_valid(dialogue_consent):
		dialogue_consent.call("reset")
	if is_instance_valid(hud):
		hud.hide_all()


func _on_world_closed(_host: Node) -> void:
	_debug("world closed")
	_clear_native_hint()
	if is_instance_valid(initiation):
		initiation.reset()
	if is_instance_valid(classifier):
		classifier.call("cancel_all")
	if is_instance_valid(dialogue_consent):
		dialogue_consent.call("reset")
	if is_instance_valid(active_runtime):
		active_runtime.force_stop()
	active_runtime = null
	game = null
	player = null
	_offer = {}
	if is_instance_valid(hud):
		hud.hide_all()


## Move the game's bottom dialogue caption to the top only when the player chose the explicit
## bottom-caption mode. "Over the pony's head" and "auto" are left untouched.
func _caption_top_enabled() -> bool:
	if not _captions_on_top:
		return false
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return false
	return str(settings.call("get_value", "access/speech_text")) == "caption"


func _on_caption(node: Node) -> void:
	if not is_instance_valid(node):
		return
	_captions[node.get_instance_id()] = weakref(node)
	_caption_top_tick()


func _apply_caption_top() -> void:
	if not is_inside_tree():
		return
	_captions_on_top = TUNABLES.get_bool("features.captions_on_top")
	_caption_top_tick()


## Move the game's caption card after its own layout pass. The stock caption keeps its text,
## wrapping, roll and fade; only its y position changes. Runs at process priority 100, after
## the caption's own _process, and skips the settings-page preview.
func _caption_top_tick() -> void:
	if not _caption_top_enabled():
		return
	for id: int in _captions.keys():
		var ref: Variant = _captions[id]
		var node: Variant = ref.get_ref() if ref is WeakRef else null
		if not is_instance_valid(node):
			_captions.erase(id)
			continue
		if bool(node.get("preview")):
			continue
		var card: Variant = node.get("_card")
		if not card is Control:
			continue
		var scale_value: Variant = node.get("_scale")
		var scale := float(scale_value) if scale_value != null else 1.0
		(card as Control).position.y = roundf(CAPTION_TOP_MARGIN * maxf(scale, 0.01))


func _on_game_setting_changed(key: String) -> void:
	if key == "access/speech_text":
		_apply_caption_top()


func _apply_live_settings() -> void:
	press_y_starts_sex = TUNABLES.get_bool("features.press_y_starts_sex")
	if is_instance_valid(active_runtime) and active_runtime.has_method("apply_live_settings"):
		active_runtime.call("apply_live_settings")


## One path for every control edit: refresh the cached flags, the caption position and the live
## act. Every tunable change goes through here, so a control never needs its own handler.
func _apply_settings_changed() -> void:
	debug_logs = TUNABLES.get_bool("debug_logs")
	_apply_caption_top()
	_apply_live_settings()


func _on_player(body: Node) -> void:
	player = body
	_debug("player ready")
	if not is_instance_valid(hud):
		hud = HUD.new()
		hud.name = "UnfplapHUD"
		add_child(hud)
	if not is_instance_valid(input):
		input = INPUT.new()
		input.name = "UnfplapInput"
		input.main = self
		add_child(input)


func _on_pony(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	if _runtimes.has(pony):
		return
	# The player's own AnonPony is a pony_locomotion too. Never attach an intimacy runtime to her.
	if pony.name == "PlayerPony" or is_instance_valid(pony.get("rig")):
		return
	var runtime: Node = RUNTIME.new()
	runtime.name = "UnfplapRuntime"
	runtime.set("pony", pony)
	runtime.set("main", self)
	pony.add_child(runtime)
	_runtimes[pony] = runtime
	_debug("runtime attached %s id=%s" % [str(pony.name), str(pony.get_meta("relationship_id", ""))])
	pony.tree_exiting.connect(func() -> void: _runtimes.erase(pony))


## Runtime-injected Unfplap tab. No game-script extension is used: if `settings_tab` is false,
## this returns before touching the page. The title and pause hosts add the page to the tree
## before calling setup(), so the actual injection is deferred and retries for a few frames.
func _on_settings_page(page: Node) -> void:
	# Opening the page re-reads settings.json, so hand-edited values apply without a restart.
	TUNABLES.reload()
	if not TUNABLES.get_bool("features.settings_tab"):
		return
	if not is_instance_valid(page) or page.has_meta("unfplap_tab") or page.has_meta("unfplap_pending"):
		return
	page.set_meta("unfplap_pending", true)
	_inject_settings_page.call_deferred(page)


func _inject_settings_page(page: Node) -> void:
	for attempt: int in 10:
		if not is_instance_valid(page):
			return
		if page.has_meta("unfplap_tab"):
			page.remove_meta("unfplap_pending")
			return
		var side_scroll: Variant = page.get("_side_scroll")
		var content: Variant = page.get("_content")
		var tabs: Variant = page.get("_tabs")
		var scroll: Variant = page.get("_scroll")
		var title: Variant = page.get("_tab_title")
		var icon: Variant = page.get("_tab_icon")
		if side_scroll is ScrollContainer and content is VBoxContainer and tabs is Array \
				and scroll is ScrollContainer and title is Label and icon is Control:
			page.remove_meta("unfplap_pending")
			_inject_settings_page_now(page)
			return
		await get_tree().process_frame
	if is_instance_valid(page):
		page.remove_meta("unfplap_pending")
	_debug("settings tab: page internals unavailable; skipped")


## No game-script extension is used. If `settings_tab` is false this never runs; if the page's
## internals are unavailable it skips rather than risking a release-breaking extension.
func _inject_settings_page_now(page: Node) -> void:
	if not TUNABLES.get_bool("features.settings_tab"):
		return
	if not is_instance_valid(page) or page.has_meta("unfplap_tab"):
		return
	var side_scroll: Variant = page.get("_side_scroll")
	var content: Variant = page.get("_content")
	var tabs: Variant = page.get("_tabs")
	var scroll: Variant = page.get("_scroll")
	var title: Variant = page.get("_tab_title")
	var icon: Variant = page.get("_tab_icon")
	if not (side_scroll is ScrollContainer and content is VBoxContainer and tabs is Array \
			and scroll is ScrollContainer and title is Label and icon is Control):
		_debug("settings tab: page internals unavailable; skipped")
		return
	if not page.has_method("_button") or not page.has_method("_redraw"):
		_debug("settings tab: page API unavailable; skipped")
		return
	if (side_scroll as ScrollContainer).get_child_count() == 0:
		_debug("settings tab: sidebar unavailable; skipped")
		return
	var side: Variant = (side_scroll as ScrollContainer).get_child(0)
	if not side is VBoxContainer:
		_debug("settings tab: sidebar layout unavailable; skipped")
		return
	var font_size := int(page.get("font_size"))
	if font_size <= 0:
		font_size = 20
	var button: Button = page.call("_button", side, "Unfplap",
		Callable(self, "_show_settings_tab").bind(page))
	button.theme_type_variation = "Tab"
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, font_size * 2.05)
	button.add_theme_font_size_override("font_size", font_size - 2)
	button.expand_icon = false
	if page.has_method("_icon_texture"):
		button.icon = page.call("_icon_texture", "gem")
	var ui := VBoxContainer.new()
	ui.name = "UnfplapSettings"
	ui.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.add_theme_constant_override("separation", 10)
	ui.visible = false
	(content as VBoxContainer).add_child(ui)
	var heading := Label.new()
	heading.text = "Unfplap"
	heading.add_theme_font_size_override("font_size", font_size + 6)
	ui.add_child(heading)
	var note := Label.new()
	note.text = "Player settings and character taste in Settings; pose tuning, feature flags and test controls in Debug. Changes apply live during an act."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", font_size - 4)
	ui.add_child(note)
	var tabs_box := TabContainer.new()
	tabs_box.name = "UnfplapTabs"
	tabs_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.add_child(tabs_box)
	var changed := Callable(self, "_apply_settings_changed")
	var user_list := _settings_tab_list("Settings", tabs_box)
	TUNABLES_UI.build(user_list, SCHEMA.SETTINGS_TAB, font_size, page, changed)
	# Character taste is a per-mare profile form, not a global tunable, so it stays hand-built.
	_add_taste_section(user_list, font_size)
	var debug_list := _settings_tab_list("Debug", tabs_box)
	TUNABLES_UI.build(debug_list, SCHEMA.DEBUG_TAB, font_size, page, changed)
	TUNABLES_UI.build_actions(debug_list, font_size, self)
	for tab: Variant in tabs:
		if tab is Button:
			(tab as Button).pressed.connect(_hide_settings_tab.bind(page))
	for key: String in ["_scroll", "provider", "prompts", "feedback_notes", "controls_map"]:
		var native_page: Variant = page.get(key)
		if native_page is CanvasItem:
			(native_page as CanvasItem).visibility_changed.connect(_native_settings_shown.bind(page))
	page.set_meta("unfplap_tab", true)
	page.set_meta("unfplap_ui", ui)
	page.set_meta("unfplap_button", button)
	_injected_settings.append({"page": page, "button": button, "ui": ui})
	_debug("settings tab injected")


func _settings_tab_list(title: String, tabs_box: TabContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	tabs_box.add_child(scroll)
	return list


func _show_settings_tab(page: Node) -> void:
	if not is_instance_valid(page):
		return
	var ui: Variant = page.get_meta("unfplap_ui")
	var button: Variant = page.get_meta("unfplap_button")
	if not ui is Control or not button is Button:
		return
	_settings_switch_guard = true
	_set_native_settings_visible(page, false)
	(ui as Control).visible = true
	var title: Variant = page.get("_tab_title")
	if title is Label:
		(title as Label).text = "Unfplap"
	var icon: Variant = page.get("_tab_icon")
	if icon is Control:
		(icon as Control).set("kind", "gem")
	var tabs: Variant = page.get("_tabs")
	if tabs is Array:
		for tab: Variant in tabs:
			if tab is Button:
				(tab as Button).set_pressed_no_signal(false)
	(button as Button).set_pressed_no_signal(true)
	page.call("_redraw")
	_settings_switch_guard = false


func _hide_settings_tab(page: Node) -> void:
	if _settings_switch_guard or not is_instance_valid(page):
		return
	var ui: Variant = page.get_meta("unfplap_ui")
	var button: Variant = page.get_meta("unfplap_button")
	if ui is Control:
		(ui as Control).visible = false
	if button is Button:
		(button as Button).set_pressed_no_signal(false)


func _native_settings_shown(page: Node) -> void:
	if _settings_switch_guard or not is_instance_valid(page):
		return
	var ui: Variant = page.get_meta("unfplap_ui")
	if not ui is Control or not (ui as Control).visible:
		return
	for key: String in ["_scroll", "provider", "prompts", "feedback_notes", "controls_map"]:
		var native_page: Variant = page.get(key)
		if native_page is CanvasItem and (native_page as CanvasItem).visible:
			_hide_settings_tab(page)
			return


func _set_native_settings_visible(page: Node, value: bool) -> void:
	for key: String in ["_scroll", "provider", "prompts", "feedback_notes", "controls_map"]:
		var native_page: Variant = page.get(key)
		if native_page is CanvasItem:
			(native_page as CanvasItem).visible = value


func _add_taste_section(list: VBoxContainer, font_size: int) -> void:
	list.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = "Character taste"
	heading.add_theme_font_size_override("font_size", font_size + 2)
	list.add_child(heading)
	var note := Label.new()
	note.text = "Taste changes apply live during an act."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", font_size - 4)
	list.add_child(note)
	var selector := OptionButton.new()
	for id: String in SETTINGS.CHARACTER_ORDER:
		selector.add_item(SETTINGS.character_name(id))
		selector.set_item_metadata(selector.get_item_count() - 1, id)
	list.add_child(selector)

	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 16)
	form.add_theme_constant_override("v_separation", 8)
	list.add_child(form)
	var intensity := _taste_option(form, "Intensity", TASTE.INTENSITIES, font_size)
	var pattern := _taste_option(form, "Pattern", TASTE.PATTERNS, font_size)
	var warmth := _taste_option(form, "Warmth", TASTE.WARMTHS, font_size)
	var recovery := _taste_spin(form, "Recovery (0–80)", font_size)
	var touch_likes := _taste_checks(form, "Likes touch", TASTE.TOUCHES, font_size)
	var talk_likes := _taste_checks(form, "Likes talk", TASTE.TALKS, font_size)
	var touch_dislikes := _taste_checks(form, "Dislikes touch", TASTE.TOUCHES, font_size)
	var talk_dislikes := _taste_checks(form, "Dislikes talk", TASTE.TALKS, font_size)
	var notes := TextEdit.new()
	notes.custom_minimum_size = Vector2(0.0, 76.0)
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes.add_theme_font_size_override("font_size", font_size - 2)
	var notes_label := Label.new()
	notes_label.text = "Notes"
	notes_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(notes_label)
	form.add_child(notes)

	var reset := Button.new()
	reset.text = "Reset to default"
	list.add_child(reset)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", font_size - 4)
	list.add_child(status)

	var refs := {
		"selector": selector,
		"intensity": intensity,
		"pattern": pattern,
		"warmth": warmth,
		"recovery": recovery,
		"touch_likes": touch_likes,
		"talk_likes": talk_likes,
		"touch_dislikes": touch_dislikes,
		"talk_dislikes": talk_dislikes,
		"notes": notes,
		"status": status,
		"refreshing": false,
	}
	selector.item_selected.connect(func(_index: int) -> void: _refresh_taste_form(refs))
	for control: OptionButton in [intensity, pattern, warmth]:
		control.item_selected.connect(func(_index: int) -> void:
			_save_taste_form(refs))
	recovery.value_changed.connect(func(_value: float) -> void:
		_save_taste_form(refs))
	for checks: Dictionary in [touch_likes, talk_likes, touch_dislikes, talk_dislikes]:
		for key: String in checks:
			(checks[key] as CheckButton).toggled.connect(func(_on: bool) -> void:
				_save_taste_form(refs))
	var notes_timer := Timer.new()
	notes_timer.one_shot = true
	notes_timer.wait_time = 0.4
	list.add_child(notes_timer)
	notes.text_changed.connect(func() -> void:
		if not bool(refs.get("refreshing", false)):
			notes_timer.start())
	notes.focus_exited.connect(func() -> void:
		notes_timer.stop()
		_save_taste_form(refs))
	notes_timer.timeout.connect(func() -> void: _save_taste_form(refs))
	reset.pressed.connect(func() -> void: _reset_taste_form(refs))
	_refresh_taste_form(refs)


func _taste_option(parent: GridContainer, label_text: String, values: Array, font_size: int) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	var option := OptionButton.new()
	for value: Variant in values:
		option.add_item(str(value))
	option.add_theme_font_size_override("font_size", font_size - 2)
	parent.add_child(option)
	return option


func _taste_spin(parent: GridContainer, label_text: String, font_size: int) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = float(TASTE.RECOVERY_MIN)
	spin.max_value = float(TASTE.RECOVERY_MAX)
	spin.step = 1.0
	spin.add_theme_font_size_override("font_size", font_size - 2)
	parent.add_child(spin)
	return spin


func _taste_checks(parent: GridContainer, label_text: String, values: Array, font_size: int) -> Dictionary:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var checks: Dictionary = {}
	for value: Variant in values:
		var check := CheckButton.new()
		check.text = str(value)
		check.add_theme_font_size_override("font_size", font_size - 3)
		row.add_child(check)
		checks[str(value)] = check
	return checks


func _selected_taste_id(refs: Dictionary) -> String:
	var selector: Variant = refs.get("selector")
	if not selector is OptionButton or (selector as OptionButton).selected < 0:
		return ""
	return str((selector as OptionButton).get_item_metadata((selector as OptionButton).selected))


func _refresh_taste_form(refs: Dictionary) -> void:
	var id := _selected_taste_id(refs)
	if id.is_empty():
		refs["refreshing"] = false
		return
	refs["refreshing"] = true
	var taste := SETTINGS.taste(id)
	_select_taste_value(refs.get("intensity"), TASTE.INTENSITIES, str(taste.get("intensity", "firm")))
	_select_taste_value(refs.get("pattern"), TASTE.PATTERNS, str(taste.get("pattern", "steady")))
	_select_taste_value(refs.get("warmth"), TASTE.WARMTHS, str(taste.get("warmth", "normal")))
	var recovery: Variant = refs.get("recovery")
	if recovery is SpinBox:
		(recovery as SpinBox).value = float(taste.get("recovery", TASTE.RECOVERY_DEFAULT))
	_set_taste_checks(refs.get("touch_likes"), TASTE.TOUCHES, taste.get("touch", []))
	_set_taste_checks(refs.get("talk_likes"), TASTE.TALKS, taste.get("talk", []))
	_set_taste_checks(refs.get("touch_dislikes"), TASTE.TOUCHES, taste.get("dislikes", []))
	_set_taste_checks(refs.get("talk_dislikes"), TASTE.TALKS, taste.get("dislikes", []))
	var notes: Variant = refs.get("notes")
	if notes is TextEdit:
		(notes as TextEdit).text = str(taste.get("notes", ""))
	var status: Variant = refs.get("status")
	if status is Label:
		(status as Label).text = "Editing %s" % SETTINGS.character_name(id)
	refs["refreshing"] = false


func _select_taste_value(control: Variant, values: Array, selected_value: String) -> void:
	if not control is OptionButton:
		return
	var option := control as OptionButton
	for index in values.size():
		if str(values[index]) == selected_value:
			option.selected = index
			return
	option.selected = 0


func _set_taste_checks(control: Variant, values: Array, selected: Variant) -> void:
	if not control is Dictionary:
		return
	var checks: Dictionary = control
	var selected_list: Array = selected if selected is Array else []
	for value: Variant in values:
		var key := str(value)
		var check: Variant = checks.get(key)
		if check is CheckButton:
			(check as CheckButton).set_pressed_no_signal(key in selected_list)


func _checked_taste_values(control: Variant, values: Array) -> Array:
	var out: Array = []
	if not control is Dictionary:
		return out
	var checks: Dictionary = control
	for value: Variant in values:
		var check: Variant = checks.get(str(value))
		if check is CheckButton and bool((check as CheckButton).button_pressed):
			out.append(str(value))
	return out


func _save_taste_form(refs: Dictionary) -> void:
	if bool(refs.get("refreshing", false)):
		return
	var id := _selected_taste_id(refs)
	if id.is_empty():
		return
	var dislikes := _checked_taste_values(refs.get("touch_dislikes"), TASTE.TOUCHES)
	dislikes.append_array(_checked_taste_values(refs.get("talk_dislikes"), TASTE.TALKS))
	var taste := {
		"intensity": _option_taste_value(refs.get("intensity"), TASTE.INTENSITIES, "firm"),
		"pattern": _option_taste_value(refs.get("pattern"), TASTE.PATTERNS, "steady"),
		"touch": _checked_taste_values(refs.get("touch_likes"), TASTE.TOUCHES),
		"dislikes": dislikes,
		"talk": _checked_taste_values(refs.get("talk_likes"), TASTE.TALKS),
		"warmth": _option_taste_value(refs.get("warmth"), TASTE.WARMTHS, "normal"),
		"recovery": int((refs.get("recovery") as SpinBox).value) if refs.get("recovery") is SpinBox else TASTE.RECOVERY_DEFAULT,
		"notes": str((refs.get("notes") as TextEdit).text).strip_edges() if refs.get("notes") is TextEdit else "",
	}
	SETTINGS.save_taste(id, taste)
	_apply_live_settings()
	var status: Variant = refs.get("status")
	if status is Label:
		(status as Label).text = "Saved %s live." % SETTINGS.character_name(id)


func _reset_taste_form(refs: Dictionary) -> void:
	var id := _selected_taste_id(refs)
	if id.is_empty():
		return
	SETTINGS.reset_taste(id)
	_refresh_taste_form(refs)
	_apply_live_settings()
	var status: Variant = refs.get("status")
	if status is Label:
		(status as Label).text = "Reset %s to its default taste." % SETTINGS.character_name(id)
	_debug("taste reset id=%s" % id)


func _option_taste_value(control: Variant, values: Array, fallback: String) -> String:
	if not control is OptionButton:
		return fallback
	var option := control as OptionButton
	if option.selected < 0 or option.selected >= values.size():
		return fallback
	return str(values[option.selected])


func _clear_injected_settings() -> void:
	for entry: Dictionary in _injected_settings:
		var page: Variant = entry.get("page")
		var ui: Variant = entry.get("ui")
		var button: Variant = entry.get("button")
		if is_instance_valid(ui) and (ui as Node).get_parent() != null:
			(ui as Node).queue_free()
		if is_instance_valid(button) and (button as Node).get_parent() != null:
			(button as Node).queue_free()
		if is_instance_valid(page):
			(page as Node).remove_meta("unfplap_tab")
			(page as Node).remove_meta("unfplap_ui")
			(page as Node).remove_meta("unfplap_button")
	_injected_settings.clear()


func _process(delta: float) -> void:
	_caption_top_tick()
	if not is_instance_valid(player) and is_instance_valid(game):
		var body: Variant = game.get("player")
		if is_instance_valid(body):
			_on_player(body)
	if is_instance_valid(active_runtime):
		active_runtime.apply_camera_motion()
		if is_instance_valid(hud):
			var show_readouts := true
			if active_runtime.has_method("hud_readouts"):
				show_readouts = bool(active_runtime.call("hud_readouts"))
			hud.update_from(active_runtime, show_readouts)
		_offer = {}
		_sync_native_hint(false)
		return

	_offer_clock += delta
	if _offer_clock >= 0.15:
		_offer_clock = 0.0
		_refresh_offer()
	if is_instance_valid(initiation):
		initiation.tick(delta)
	if _offer.is_empty():
		_last_offer_key = ""
		_sync_native_hint(false)
	else:
		_sync_native_hint(true)


func _refresh_offer() -> void:
	_offer = {}
	if not is_instance_valid(player) or not is_instance_valid(game):
		return
	if get_tree().paused:
		return
	if DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var view: Camera3D = camera()
	if view == null:
		return
	var form: Dictionary = PLAYER_FORM.active(get_tree())
	var pony_form: bool = PLAYER_FORM.is_pony(form)
	var flag := press_y_starts_sex

	# Missionary now requires Anon to be seated/lying on the bed with a pony lying there. A
	# standing or cradling Anon has no valid missionary camera, so that entry is not offered.
	if not pony_form and is_instance_valid(player) and player.get("seat") != null:
		var lying: Node = _bedside_pony(view)
		if is_instance_valid(lying):
			var runtime: Node = runtime_for(lying)
			if is_instance_valid(runtime):
				var bed: Node3D = runtime.find_bed_under()
				if bed != null and runtime.can_start(CATALOG.MISSIONARY, "bed_side", bed):
					var scenario := _scenario_for(lying)
					if INITIATION.y_start_allowed(flag, "bed_side", scenario):
						_offer = {"runtime": runtime, "pony": lying, "pose": CATALOG.MISSIONARY,
							"source": "bed_side", "bed": bed, "scenario": scenario}
						_log_offer()
						return

	# Missionary, AnonPony: an awake pony already lying on a bed.
	if pony_form:
		var lying: Node = nearest_lying(view)
		if is_instance_valid(lying):
			var runtime: Node = runtime_for(lying)
			if is_instance_valid(runtime):
				var bed: Node3D = runtime.find_bed_under()
				if bed != null and runtime.can_start(CATALOG.MISSIONARY, "already_lying", bed):
					var scenario := _scenario_for(lying)
					if INITIATION.y_start_allowed(flag, "already_lying", scenario):
						_offer = {"runtime": runtime, "pony": lying, "pose": CATALOG.MISSIONARY,
							"source": "already_lying", "bed": bed, "scenario": scenario}
						_log_offer()
						return

	# Standing: only the base-game smack-flank aim zone, regardless of the feature flag.
	var standing: Node = _smack_flank_target(view)
	if is_instance_valid(standing) and str(standing.call("posture_status").get("requested", "")) == "stand":
		var runtime: Node = runtime_for(standing)
		if is_instance_valid(runtime) and runtime.can_start(CATALOG.STANDING, "", null):
			var scenario := _scenario_for(standing)
			if INITIATION.y_start_allowed(flag, "", scenario):
				_offer = {"runtime": runtime, "pony": standing, "pose": CATALOG.STANDING,
					"source": "", "bed": null, "scenario": scenario}
				_log_offer()


## The Y scenario for a pony: a proactive request or a verbal agreement. Bed contexts are
## allowed by source without this.
func _scenario_for(pony: Node) -> String:
	if not is_instance_valid(pony):
		return ""
	if is_instance_valid(initiation) and initiation.has_method("press_y_scenario"):
		var scenario := str(initiation.call("press_y_scenario", pony))
		if not scenario.is_empty():
			return scenario
	if is_instance_valid(dialogue_consent) and dialogue_consent.has_method("scenario_for"):
		return str(dialogue_consent.call("scenario_for", pony))
	return ""


## The base game's right-click smack selection: crosshair on the flank, TOUCH_REACH. This is
## also the only standing Y sex zone.
func _smack_flank_target(view: Camera3D) -> Node:
	if not is_instance_valid(game) or view == null:
		return null
	var interactions: Variant = game.get("desktop_interactions")
	if is_instance_valid(interactions) and interactions.has_method("_select"):
		var hit: Variant = interactions.call("_select", true)
		if hit is Dictionary and hit.get("target") is Node:
			return hit.get("target") as Node
	# Headless/VR fallback: keep the same reach and a tight crosshair cone.
	var standing: Node = nearest_standing(view)
	if not is_instance_valid(standing):
		return null
	var at: Vector3 = (standing as Node3D).global_position + Vector3.UP * 0.9
	var delta := at - view.global_position
	if delta.length() > 1.6:
		return null
	if (-view.global_basis.z).dot(delta.normalized()) < 0.96:
		return null
	return standing


func _native_row() -> HBoxContainer:
	if not is_instance_valid(game):
		return null
	var hints: Node = game.get_node_or_null("InteractionHints")
	if hints == null:
		return null
	# VR uses the world-space prompt row; the Y hint falls back to the HUD prompt there.
	if bool(hints.get("xr")):
		return null
	var row: Variant = hints.get("_prompt2d")
	if row is HBoxContainer and is_instance_valid(row):
		return row
	return null


## The offer hint is one more unit in the game's own prompt row, in that row's style and phrasing
## ("Hold G · Bridal carry" reads as "Hold: ..."), so it sits beside base prompts unnoticed.
func _make_native_hint_label() -> Control:
	return HUD.prompt_row("button_y", OFFER_HINT)


func _remove_native_hint(row: HBoxContainer = null) -> void:
	if is_instance_valid(_native_hint_label):
		var holder: Node = _native_hint_label.get_parent()
		if is_instance_valid(holder):
			holder.remove_child(_native_hint_label)
		_native_hint_label.queue_free()
	_native_hint_label = null
	if row != null and is_instance_valid(row):
		var parent: Node = row.get_parent()
		if is_instance_valid(parent) and parent is Control and row.get_child_count() == 0:
			(parent as Control).visible = false


func _clear_native_hint() -> void:
	_remove_native_hint(_native_row())


func _sync_native_hint(show_hint: bool) -> void:
	var row: HBoxContainer = _native_row()
	if row == null:
		if is_instance_valid(hud):
			if show_hint:
				hud.show_prompt(OFFER_HINT)
			else:
				hud.hide_prompt()
		return
	if not show_hint:
		_remove_native_hint(row)
		if is_instance_valid(hud):
			hud.hide_prompt()
		return
	if not is_instance_valid(_native_hint_label) or _native_hint_label.get_parent() != row or _native_hint_label.is_queued_for_deletion():
		_remove_native_hint(row)
		_native_hint_label = _make_native_hint_label()
		row.add_child(_native_hint_label)
	var parent: Node = row.get_parent()
	if parent is Control:
		(parent as Control).visible = true
	if is_instance_valid(hud):
		hud.hide_prompt()


func _log_offer() -> void:
	if _offer.is_empty():
		return
	var target: Variant = _offer.get("pony")
	var key := "%s:%s:%s" % [
		str(target.name) if is_instance_valid(target) else "?",
		str(_offer.get("pose", "")), str(_offer.get("source", ""))]
	if key == _last_offer_key:
		return
	_last_offer_key = key
	_debug("OFFER pony=%s pose=%s source=%s bed=%s" % [
		str(target.name) if is_instance_valid(target) else "?",
		str(_offer.get("pose", "")), str(_offer.get("source", "")), str(_offer.get("bed"))])


func _debug_target(view: Camera3D) -> Node:
	if not is_instance_valid(player) or not is_instance_valid(game):
		return null
	var pony_form := PLAYER_FORM.is_pony(PLAYER_FORM.active(get_tree()))
	if not pony_form:
		var reach: Node = interactor()
		if is_instance_valid(reach) and reach.get("cradled") == true:
			var held: Variant = reach.get("held")
			if held is Node3D and is_instance_valid(held):
				return held
	var forward := -view.global_basis.z
	var best = null
	var best_score := -INF
	for node: Variant in mares():
		if not is_instance_valid(node):
			continue
		var actor: Node3D = node as Node3D
		if actor == null:
			continue
		var at: Vector3 = actor.global_position + Vector3.UP * 0.9
		var delta: Vector3 = at - view.global_position
		var dist: float = delta.length()
		if dist > 6.0:
			continue
		var dot: float = forward.dot(delta.normalized()) if dist > 0.001 else 0.0
		if dot < 0.2:
			continue
		var score: float = dot - dist * 0.05
		if score > best_score:
			best_score = score
			best = actor
	return best


func try_start() -> bool:
	if is_instance_valid(active_runtime):
		return false
	_refresh_offer()
	if _offer.is_empty():
		return _try_refusal()
	var runtime: Variant = _offer.get("runtime")
	if not is_instance_valid(runtime):
		return false
	var target: Variant = _offer.get("pony")
	var source := str(_offer.get("source", ""))
	var scenario := str(_offer.get("scenario", _scenario_for(target)))
	var allowed := INITIATION.y_start_allowed(press_y_starts_sex, source, scenario)
	if not allowed:
		return false
	if is_instance_valid(initiation) and is_instance_valid(target):
		initiation.cancel_for(target)
	var started: bool = runtime.start(str(_offer.get("pose", "")), _offer.get("bed"), source, allowed)
	if started:
		if is_instance_valid(classifier):
			classifier.call("cancel_scope", "dialogue:")
		if is_instance_valid(dialogue_consent) and is_instance_valid(target):
			dialogue_consent.call("clear_for", target)
		_offer = {}
		if is_instance_valid(hud):
			hud.hide_prompt()
	return started


## Debug helper: force a proactive request for the aimed (or nearest) mare. It bypasses the
## quiet/cooldown/AI-usage checks so the lab can test requests with ai_usage=talk. An empty
## `pose` lets the mare choose; `missionary` and `standing` force that invite.
func debug_request(pose := "") -> void:
	_debug_offer_request(pose)


## Debug Actions panel entries (`TUNABLES.ACTIONS`).
func action_bed_offer() -> String:
	return _debug_offer_request(CATALOG.MISSIONARY)


func action_standing_offer() -> String:
	return _debug_offer_request(CATALOG.STANDING)


## Shared by the debug keys and the hidden settings buttons.
func _debug_offer_request(pose := "") -> String:
	if not is_instance_valid(initiation) or not is_instance_valid(player):
		return "Act system not ready."
	var view: Camera3D = camera()
	var target: Node = _debug_target(view) if is_instance_valid(view) else null
	if not is_instance_valid(target):
		target = _nearest_pony(view)
	if not is_instance_valid(target):
		_debug("request: no pony target")
		return "No mare under the crosshair or nearby."
	var runtime: Variant = runtime_for(target)
	if not is_instance_valid(runtime):
		_debug("request: no runtime for %s" % str(target.name))
		return "No runtime for %s." % str(target.name)
	var started: bool = bool(initiation.force(runtime, pose))
	var label := ""
	if pose == CATALOG.MISSIONARY:
		label = " (bed)"
	elif pose == CATALOG.STANDING:
		label = " (standing)"
	if started:
		_debug("request button: %s%s" % [str(target.name), label])
		return "Offer started for %s%s. Close settings to let her approach." % [
			str(target.name), label]
	return "Gates rejected %s%s (relationship, consent, pose or no free bed)." % [
		str(target.name), label]


## The request helper is not aim-gated: if the crosshair is not on a mare, use the nearest
## loaded one within 8 m so it works while walking around idle.
func _nearest_pony(view: Camera3D) -> Node:
	if not is_instance_valid(view):
		return null
	var best: Node = null
	var best_distance := 8.0
	for node: Variant in mares():
		if not is_instance_valid(node) or not node is Node3D:
			continue
		var actor: Node3D = node as Node3D
		var distance := actor.global_position.distance_to(view.global_position)
		if distance < best_distance:
			best_distance = distance
			best = actor
	return best


func toggle_skeleton_debug() -> void:
	if not is_instance_valid(_debug_skeleton):
		_debug_skeleton = DEBUG_SKELETON.new()
		_debug_skeleton.name = "UnfplapSkeleton"
		_debug_skeleton.set("main", self)
		add_child(_debug_skeleton)
	var enabled := not bool(_debug_skeleton.get("enabled"))
	_debug_skeleton.set("enabled", enabled)
	_debug("skeleton overlay %s" % ("ON" if enabled else "OFF"))


func skeleton_click() -> bool:
	if not is_instance_valid(_debug_skeleton) or not bool(_debug_skeleton.get("enabled")):
		return false
	return bool(_debug_skeleton.call("handle_click"))


func _try_refusal() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(game):
		return false
	if get_tree().paused:
		return false
	if DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	var view: Camera3D = camera()
	if view == null:
		return false
	var pony_form: bool = PLAYER_FORM.is_pony(PLAYER_FORM.active(get_tree()))
	if not pony_form:
		var reach: Node = interactor()
		if is_instance_valid(reach) and reach.get("cradled") == true:
			var held: Variant = reach.get("held")
			if held is Node3D and is_instance_valid(held):
				var runtime: Node = runtime_for(held)
				if is_instance_valid(runtime):
					var bed: Node3D = bed_for_cradle(held)
					if bed != null and bool(runtime.call("refuse_available", CATALOG.MISSIONARY, "cradle", bed)):
						runtime.call("refuse", CATALOG.MISSIONARY, "cradle", bed)
						return true
	if pony_form:
		var lying: Node = nearest_lying(view)
		if is_instance_valid(lying):
			var runtime: Node = runtime_for(lying)
			if is_instance_valid(runtime):
				var bed: Variant = runtime.call("find_bed_under")
				if bed is Node3D and bool(runtime.call("refuse_available", CATALOG.MISSIONARY, "already_lying", bed)):
					runtime.call("refuse", CATALOG.MISSIONARY, "already_lying", bed)
					return true
	var standing: Node = _smack_flank_target(view)
	if is_instance_valid(standing):
		var runtime: Node = runtime_for(standing)
		if is_instance_valid(runtime) and bool(runtime.call("refuse_available", CATALOG.STANDING, "", null)):
			runtime.call("refuse", CATALOG.STANDING, "", null)
			return true
	return false


func allocate_serial() -> int:
	var section: Dictionary = Mods.state("unfplap")
	var value: int = int(section.get("serial", 0)) + 1
	section["serial"] = value
	Mods.save_changed()
	return value


func set_active(runtime: Node) -> void:
	if is_instance_valid(initiation):
		var pony: Variant = runtime.get("pony") if is_instance_valid(runtime) else null
		if is_instance_valid(pony):
			initiation.cancel_for(pony)
	active_runtime = runtime
	_offer = {}


func clear_active(runtime: Node) -> void:
	if active_runtime == runtime:
		active_runtime = null


func camera() -> Camera3D:
	if not is_instance_valid(player):
		return null
	var direct: Variant = player.get("camera")
	if direct is Camera3D and is_instance_valid(direct):
		return direct
	var now := Time.get_ticks_msec() * 0.001
	if is_instance_valid(_camera_cache) and now - _camera_cache_at < 1.0:
		return _camera_cache
	if is_instance_valid(game) and game.has_method("_find_camera"):
		var found: Variant = game.call("_find_camera", player)
		if found is Camera3D and is_instance_valid(found):
			_camera_cache = found
			_camera_cache_at = now
			return found
	var current: Camera3D = get_viewport().get_camera_3d()
	_camera_cache = current
	_camera_cache_at = now
	return current


func interactor() -> Node:
	if is_instance_valid(_interactor):
		return _interactor
	if not is_instance_valid(player):
		return null
	for node: Node in player.find_children("*", "", true, false):
		var script: Variant = node.get_script()
		if script != null and str(script.resource_path) == INTERACTOR_PATH:
			_interactor = node
			return node
	return null


func desktop() -> Node:
	if is_instance_valid(_desktop):
		return _desktop
	_desktop = get_tree().get_first_node_in_group("desktop_interactions")
	return _desktop


func player_body() -> Node3D:
	if not is_instance_valid(player):
		return null
	var form: Variant = player.get("form_driver")
	if form != null and is_instance_valid(form):
		var avatar: Variant = form.get("avatar")
		if avatar is Node3D and is_instance_valid(avatar):
			return avatar
	var body: Variant = player.find_child("Body", true, false)
	if body is Node3D and is_instance_valid(body):
		return body
	return player as Node3D


func mares() -> Array:
	if is_instance_valid(game):
		var list: Variant = game.get("mares")
		if list is Array:
			return list
	return []


func runtime_for(pony: Node) -> Node:
	if not is_instance_valid(pony):
		return null
	var runtime: Variant = _runtimes.get(pony)
	if is_instance_valid(runtime):
		return runtime
	var child: Node = pony.get_node_or_null("UnfplapRuntime")
	return child if is_instance_valid(child) else null


func bed_under(point: Vector3, exclude: RID = RID()) -> Node3D:
	var world: World3D = null
	if is_instance_valid(player):
		world = player.get_world_3d()
	if world == null:
		world = get_viewport().world_3d
	if world == null:
		return null
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return null
	for lift: float in [0.6, 0.35, 0.15]:
		var from := point + Vector3.UP * lift
		var query := PhysicsRayQueryParameters3D.create(from, point + Vector3.DOWN * 2.5, 1)
		if exclude.is_valid():
			query.exclude = [exclude]
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			continue
		var bed: Node3D = MATTRESS.bed_of(hit.get("collider"))
		if bed != null:
			var real := real_bed(bed)
			if real != null:
				return real
	return null


## The actual bed/couch behind a physics hit. A `SharedTorsoSupport` is a temporary child of the
## bed that also carries `soft_support`; using it as the bed leaves the act with a freed node
## once the cuddle support is removed.
func real_bed(node: Node) -> Node3D:
	if not is_instance_valid(node):
		return null
	if node.has_meta("shared_rest_support"):
		var parent := node.get_parent() as Node3D
		if is_instance_valid(parent):
			return parent
	var walk: Node = node
	while walk != null:
		if walk is Node3D and walk.has_meta("mattress_top"):
			return walk as Node3D
		walk = walk.get_parent()
	if node is Node3D and node.has_meta("soft_support"):
		return node as Node3D
	return null


func bed_for_cradle(pony: Node3D) -> Node3D:
	if not is_instance_valid(pony):
		return null
	var exclude: RID = (pony as CollisionObject3D).get_rid() if pony is CollisionObject3D else RID()
	var down: Node3D = bed_under(pony.global_position, exclude)
	if down != null:
		return down
	var view: Camera3D = camera()
	if view == null:
		return null
	var space: PhysicsDirectSpaceState3D = view.get_world_3d().direct_space_state
	if space == null:
		return null
	var from := view.global_position
	var to := from - view.global_basis.z * 3.2
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	if exclude.is_valid():
		query.exclude = [exclude]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return null
	return real_bed(MATTRESS.bed_of(hit.get("collider")))


func bed_occupied(bed: Node3D, target: Node) -> bool:
	if not is_instance_valid(bed):
		return false
	var top := float(bed.get_meta("mattress_top", 0.6))
	var at := bed.to_global(Vector3(0.0, top, 0.0))
	for node: Variant in mares():
		if not is_instance_valid(node) or node == target:
			continue
		var actor: Node3D = node as Node3D
		if actor == null or not actor.has_method("posture_status"):
			continue
		var status: Dictionary = actor.posture_status()
		if str(status.get("requested", "")) != "lie_down":
			continue
		if absf(actor.global_position.y - at.y) > 0.55:
			continue
		if Vector2(actor.global_position.x - at.x, actor.global_position.z - at.z).length() > 1.3:
			continue
		return true
	return false


func player_beside_bed(bed: Node3D) -> bool:
	if not is_instance_valid(player):
		return false
	var seat: Variant = player.get("seat")
	if seat == null or not is_instance_valid(seat):
		return true
	if not is_instance_valid(bed):
		return true
	if seat is Node3D and (seat as Node3D).get_parent() == bed:
		return true
	if seat is Node3D and (seat as Node3D).has_meta("couch"):
		var couch: Variant = (seat as Node3D).get_meta("couch")
		if is_instance_valid(couch):
			var bed_node: Variant = couch.get("_bed") if couch.get("_bed") != null else couch.get("bed_node")
			if bed_node == bed:
				return true
			if is_instance_valid(bed_node) and (bed_node as Node3D).is_ancestor_of(seat as Node):
				return true
	return false


func menu_open() -> bool:
	if get_tree().paused:
		return true
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return true
	if not is_instance_valid(game):
		return false
	for key: String in ["save_menu", "settings_menu", "pause_menu"]:
		var panel: Variant = game.get(key)
		if is_instance_valid(panel) and bool(panel.get("opened")):
			return true
	var inventory: Variant = game.get("inventory")
	if not is_instance_valid(inventory):
		return false
	if inventory.has_method("_map_open") and bool(inventory.call("_map_open")):
		return true
	var case: Variant = inventory.get("case")
	if is_instance_valid(case) and bool(case.get("visible")):
		return true
	var customizer: Variant = inventory.get("customizer")
	if is_instance_valid(customizer) and bool(customizer.get("opened")):
		return true
	var inspector: Variant = inventory.get("inspector")
	if is_instance_valid(inspector) and bool(inspector.get("active")):
		return true
	return false


func _bedside_pony(view: Camera3D) -> Node:
	# The player's bed/couch seat knows exactly who lies beside Anon.
	if is_instance_valid(player):
		var seat: Variant = player.get("seat")
		if is_instance_valid(seat) and seat.has_meta("couch"):
			var couch: Variant = seat.get_meta("couch")
			if is_instance_valid(couch) and couch.has_method("partner"):
				var partner: Variant = couch.call("partner", seat)
				if partner is Node and is_instance_valid(partner):
					return partner
	return null


func nearest_standing(view: Camera3D) -> Node:
	if view == null:
		return null
	var best: Node
	var best_dot := 0.82
	var forward := -view.global_basis.z
	for node: Variant in mares():
		if not is_instance_valid(node):
			continue
		var actor: Node3D = node as Node3D
		if actor == null or not actor.has_method("posture_status"):
			continue
		var status: Dictionary = actor.posture_status()
		if str(status.get("requested", "")) != "stand":
			continue
		var at := actor.global_position + Vector3.UP * 0.9
		var delta := at - view.global_position
		if delta.length() > 2.5:
			continue
		var dot := forward.dot(delta.normalized())
		if dot > best_dot:
			best_dot = dot
			best = actor
	return best


func nearest_lying(view: Camera3D) -> Node:
	if view == null:
		return null
	var best: Node
	var best_dot := 0.78
	var forward := -view.global_basis.z
	for node: Variant in mares():
		if not is_instance_valid(node):
			continue
		var actor: Node3D = node as Node3D
		if actor == null or not actor.has_method("posture_status"):
			continue
		var status: Dictionary = actor.posture_status()
		if str(status.get("requested", "")) != "lie_down":
			continue
		var at := actor.global_position + Vector3.UP * 0.5
		var delta := at - view.global_position
		if delta.length() > 3.2:
			continue
		var dot := forward.dot(delta.normalized())
		if dot > best_dot:
			best_dot = dot
			best = actor
	return best


func _exit_tree() -> void:
	_clear_injected_settings()
	_clear_native_hint()
	if is_instance_valid(initiation):
		initiation.reset()
		initiation.queue_free()
	if is_instance_valid(classifier):
		classifier.call("cancel_all")
		classifier.queue_free()
	if is_instance_valid(dialogue_consent):
		dialogue_consent.call("reset")
		dialogue_consent.queue_free()
	if is_instance_valid(active_runtime):
		active_runtime.force_stop()
	active_runtime = null
	for runtime: Variant in _runtimes.values():
		if is_instance_valid(runtime):
			runtime.force_stop()
			runtime.queue_free()
	_runtimes.clear()
	_offer = {}
	if is_instance_valid(hud):
		hud.queue_free()
	if is_instance_valid(input):
		input.queue_free()
