extends Node
## Unfplap: adult intimacy for consenting adult ponies at the Marefriend stage.
## The entry node owns the player HUD/input and one lightweight runtime per pony. It never edits
## game files; it only reads the game's pony, relationship, memory and bed APIs.

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const HUD := preload("res://mods/unfplap/hud.gd")
const INPUT := preload("res://mods/unfplap/input.gd")
const INITIATION := preload("res://mods/unfplap/initiation.gd")
const ACT_HISTORY := preload("res://mods/unfplap/act_history.gd")
const CLASSIFIER := preload("res://mods/unfplap/consent_classifier.gd")
const DIALOGUE_CONSENT := preload("res://mods/unfplap/dialogue_consent.gd")
const DEBUG_SKELETON := preload("res://mods/unfplap/debug_skeleton.gd")
const ANON_PART := preload("res://mods/unfplap/anon_part.gd")
const PLACEMENT := preload("res://mods/unfplap/anatomy_placement.gd")
const TAIL_VISIBILITY := preload("res://mods/unfplap/tail_visibility.gd")
const TAIL_SEAT := preload("res://mods/unfplap/tail_seat.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const SETTINGS_UI := preload("res://mods/unfplap/settings_ui.gd")
const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const CYCLE := preload("res://mods/unfplap/cycle.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const RUMP_CONE := preload("res://mods/unfplap/rump_cone.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
const INTERACTOR_PATH := "res://player/interactor.gd"
const PONY_PATH := "res://world/characters/locomotion/pony_locomotion.gd"
const SETTINGS_PAGE_PATH := "res://world/ui/settings_page.gd"
const CAPTION_PATH := "res://world/ui/speech_caption.gd"
## The game's one menu look (type variations, boxes, palette), so the injected settings page is
## built from the same pieces as the page that hosts it.
const STYLE := preload("res://world/ui/menu_style.gd")
## The tri-state preference row: one pill per state.
const PREFERENCE_STATES := ["dislike", "none", "like"]
const PREFERENCE_STATE_LABELS := {
	"dislike": "Dislikes",
	"none": "No preference",
	"like": "Likes",
}
## The game's own bottom-caption margin; the mod keeps its card at this distance from the top.
const CAPTION_TOP_MARGIN := 26.0
## The offer hint beside the game's prompt row: a single Y press starts the act, so it reads like
## the base game's tap prompts ("G · Carry"), not a hold. Only Y during an act is a hold.
const OFFER_HINT := "Make love"
## Mod setting: DEBUG LOGS. Persisted in user://mods/data/unfplap/settings.json.
## Default OFF. Toggle in the Debug settings tab.
var debug_logs := false
var debug_perf := false

var game
var player
var hud
var input
## integration: the optional player anatomy part is created once per player.
var anon_part: Node
## Debug: the global hide-tails toggle lives outside every pony runtime.
var tail_visibility: Node
## Anatomy: seats every adult mare's hair tail at the reference dock and moves the dock with it.
var tail_seat: Node
var _anatomy_status_label: Label
var initiation
var classifier
var dialogue_consent
var active_runtime

var _runtimes: Dictionary = {}
var _offer: Dictionary = {}
var _offer_clock := 0.0
## Lover-bond maintenance: clear a stored bond once the loaded mare is no longer romantic.
var _sex_bond_clock := 0.0
var _interactor: Node
var _desktop: Node
var _camera_cache: Camera3D
var _camera_cache_at := 0.0
var _last_offer_key := ""
var _native_hint_label: Control
var _debug_skeleton: Node3D
var _injected_settings: Array = []
## The Debug block of each injected settings tab, toggled live by `debug_mode`.
var _debug_sections: Array = []
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
			var note := str(runtime.call("prompt_note"))
			if note.is_empty():
				note = str(runtime.call("lover_prompt_note"))
			var cycle := str(runtime.call("cycle_note"))
			if not cycle.is_empty():
				note = cycle if note.is_empty() else note + " " + cycle
			return note
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
	debug_logs = SETTINGS.debug_mode.get_bool()
	debug_perf = SETTINGS.debug_perf.get_bool()
	_captions_on_top = SETTINGS.captions_on_top.get_bool()
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
	tail_visibility = TAIL_VISIBILITY.new()
	tail_visibility.name = "UnfplapTailVisibility"
	add_child(tail_visibility)
	tail_seat = TAIL_SEAT.new()
	tail_seat.name = "UnfplapTailSeat"
	tail_seat.set("main", self)
	add_child(tail_seat)
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
	game = host
	_interactor = null
	_desktop = null
	_camera_cache = null
	_camera_cache_at = 0.0
	_offer = {}
	_sex_bond_clock = 0.0
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
	if is_instance_valid(anon_part):
		anon_part.call("encounter", false)
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
	_captions_on_top = SETTINGS.captions_on_top.get_bool()
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
	if is_instance_valid(active_runtime) and active_runtime.has_method("apply_live_settings"):
		active_runtime.call("apply_live_settings")


## One path for every control edit: refresh the cached flags, the caption position and the live
## act. Every tunable change goes through here, so a control never needs its own handler.
func _apply_settings_changed() -> void:
	debug_logs = SETTINGS.debug_mode.get_bool()
	debug_perf = SETTINGS.debug_perf.get_bool()
	var debug_on := SETTINGS.debug_mode.get_bool()
	for section: Variant in _debug_sections:
		if is_instance_valid(section):
			(section as Control).visible = debug_on
	_apply_caption_top()
	_apply_live_settings()
	# integration: anatomy switches are live outside acts too.
	refresh_anatomy()
	if is_instance_valid(tail_seat):
		tail_seat.call("refresh_all")


## The anatomy controller owns the genitals material; refresh the dock after it attaches, changes
## tone or detaches.
func refresh_dock_color(pony: Node) -> void:
	if is_instance_valid(tail_seat):
		tail_seat.call("refresh_dock_color", pony)


func _on_player(body: Node) -> void:
	player = body
	_debug("player ready")
	if not is_instance_valid(hud):
		hud = HUD.new()
		hud.name = "UnfplapHUD"
		add_child(hud)
	# integration: the Anon part exists only with the anatomy feature and the local assets.
	if not is_instance_valid(anon_part) and SETTINGS.anatomy_on() \
			and ANON_PART.assets_exist():
		anon_part = ANON_PART.new()
		anon_part.name = "UnfplapAnonPart"
		anon_part.set("main", self)
		add_child(anon_part)
	if not is_instance_valid(input):
		input = INPUT.new()
		input.name = "UnfplapInput"
		input.main = self
		add_child(input)


func _on_pony(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	# The player's own AnonPony is a pony_locomotion too. Never attach an intimacy runtime to her.
	if pony.name == "PlayerPony" or is_instance_valid(pony.get("rig")):
		return
	if is_instance_valid(tail_seat):
		tail_seat.call("attach", pony)
	if _runtimes.has(pony):
		return
	var runtime: Node = RUNTIME.new()
	runtime.name = "UnfplapRuntime"
	runtime.set("pony", pony)
	runtime.set("main", self)
	pony.add_child(runtime)
	_runtimes[pony] = runtime
	_debug("runtime attached %s id=%s" % [str(pony.name), str(pony.get_meta("relationship_id", ""))])
	pony.tree_exiting.connect(func() -> void: _runtimes.erase(pony))


## Runtime-injected Unfplap tab. No game-script extension is used. The title and pause hosts add
## the page to the tree before calling setup(), so the actual injection is deferred and retries
## for a few frames.
func _on_settings_page(page: Node) -> void:
	# Opening the page re-reads settings.json, so hand-edited values apply without a restart.
	SETTINGS.reload_file()
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


## No game-script extension is used. If the page's internals are unavailable it skips rather
## than risking a release-breaking extension.
func _inject_settings_page_now(page: Node) -> void:
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
	# The page captions its GROUPS sections; the injected row gets one too, so it does not float
	# under the last sidebar group.
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	(side as VBoxContainer).add_child(gap)
	var caption := STYLE.label("Add-ons".to_upper(), "Faint", maxi(12, font_size - 7))
	caption.add_theme_constant_override("line_spacing", 0)
	(side as VBoxContainer).add_child(caption)
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
	# The page's title row already reads "Unfplap" with its gem icon, so the panel starts with
	# the sub-tabs instead of a second heading or intro card.
	var tabs_box := TabContainer.new()
	tabs_box.name = "UnfplapTabs"
	tabs_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.add_child(tabs_box)
	var changed := Callable(self, "_apply_settings_changed")
	var general_list := _settings_tab_list("General", tabs_box)
	_collect_debug_section(SETTINGS_UI.build(general_list, SETTINGS.GENERAL, font_size, page,
		changed, self))
	var anatomy_list := _settings_tab_list("Anatomy", tabs_box)
	_collect_debug_section(SETTINGS_UI.build(anatomy_list, SETTINGS.ANATOMY, font_size, page,
		changed, self))
	var world_list := _settings_tab_list("World", tabs_box)
	_collect_debug_section(SETTINGS_UI.build(world_list, SETTINGS.WORLD, font_size, page,
		changed, self))
	# Character preference is a per-mare profile form, not a global setting, so it keeps its own
	# hand-built Characters tab instead of a schema section.
	var char_list := _settings_tab_list("Characters", tabs_box)
	_add_preference_form(char_list, font_size)
	# Style the bar after it exists with its tabs: the container re-applies its theme to the
	# internal TabBar when the tree changes, which would shadow overrides set before that.
	_style_tabs(tabs_box, font_size)
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
	_injected_settings.append({"page": page, "button": button, "ui": ui, "sidebar": [gap, caption]})
	_debug("settings tab injected")


## Keep the Debug block a build returned, so `debug_mode` can show or hide it live.
func _collect_debug_section(control: Variant) -> void:
	if control is Control:
		_debug_sections.append(control)


func _settings_tab_list(title: String, tabs_box: TabContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs_box.add_child(scroll)
	# Room for a hovered row card's border inside the scroll's clip, as the page does for its rows.
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("margin_left", 6)
	holder.add_theme_constant_override("margin_top", 4)
	holder.add_theme_constant_override("margin_bottom", 4)
	holder.add_theme_constant_override("margin_right", 14)
	scroll.add_child(holder)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	holder.add_child(list)
	return list


## The sub-tabs wear the page's "Segment" look: the chosen tab is a lit pill, the
## other a quiet one, and there is no tab strip or default panel behind either. The internal TabBar
## is a separate control, so its tab items are set on it directly (a theme resource would be
## inherited, but per-node overrides on the TabContainer are not).
func _style_tabs(tabs: TabContainer, font_size: int) -> void:
	var empty := STYLE.rounded(StyleBoxEmpty.new())
	tabs.add_theme_stylebox_override("panel", empty)
	tabs.add_theme_stylebox_override("tabbar_background", empty)
	tabs.add_theme_constant_override("side_margin", 0)
	var bar := tabs.get_tab_bar()
	bar.add_theme_stylebox_override("tabbar_background", empty)
	var quiet := STYLE.rounded(STYLE.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 99, 14, 5))
	bar.add_theme_stylebox_override("tab_unselected", quiet)
	bar.add_theme_stylebox_override("tab_disabled", quiet)
	bar.add_theme_stylebox_override("tab_hovered", STYLE.rounded(STYLE.box(
		Color(1, 1, 1, 0.1), Color(STYLE.PINK, 0.5), 1, 99, 14, 5)))
	var lit := STYLE.box(STYLE.ROSE, Color(1, 1, 1, 0.55), 1, 99, 14, 5)
	lit.shadow_color = Color(STYLE.ROSE, 0.35)
	lit.shadow_size = 10
	lit.shadow_offset = Vector2(0, 2)
	bar.add_theme_stylebox_override("tab_selected", STYLE.rounded(lit))
	var ring := STYLE.box(Color.TRANSPARENT, Color(STYLE.PINK, 0.8), 2, 101)
	ring.set_expand_margin_all(2)
	bar.add_theme_stylebox_override("tab_focus", STYLE.rounded(ring))
	bar.add_theme_font_override("font", STYLE.BOLD)
	bar.add_theme_font_size_override("font_size", font_size - 3)
	bar.add_theme_color_override("font_selected_color", Color.WHITE)
	bar.add_theme_color_override("font_unselected_color", STYLE.MUTED)
	bar.add_theme_color_override("font_hovered_color", STYLE.CREAM)
	bar.add_theme_constant_override("tab_separation", 4)


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


## The per-mare preference profile is the one hand-built form; it borrows the setting rows' card,
## switch and pill pieces so it does not read as a different panel. It fills its own Characters
## sub-tab, so the tab bar supplies the heading. Edits are staged in the form and written only by
## Save preset; Reset to default restores the character's own preference template.
func _add_preference_form(list: VBoxContainer, font_size: int) -> void:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	list.add_child(stack)
	var intro := STYLE.label("Saved preset changes apply live during an act.", "Faint", font_size - 5)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(intro)
	var filter := LineEdit.new()
	filter.placeholder_text = "Find a pony"
	filter.clear_button_enabled = true
	filter.add_theme_font_size_override("font_size", font_size - 2)
	stack.add_child(filter)
	var selector := OptionButton.new()
	selector.add_theme_font_size_override("font_size", font_size - 2)
	stack.add_child(selector)
	var last_id := ""

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	stack.add_child(buttons)
	var save := Button.new()
	save.text = "Save preset"
	save.theme_type_variation = "Primary"
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.add_theme_font_size_override("font_size", font_size - 2)
	buttons.add_child(save)
	var reset := Button.new()
	reset.text = "Reset to default"
	reset.theme_type_variation = "Danger"
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.add_theme_font_size_override("font_size", font_size - 2)
	buttons.add_child(reset)
	var status := STYLE.label("", "Faint", font_size - 6)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(status)

	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 16)
	form.add_theme_constant_override("v_separation", 8)
	stack.add_child(form)
	var intensity := _preference_pills(form, "Intensity", PREFERENCES.INTENSITIES, font_size)
	var pattern := _preference_pills(form, "Pattern", PREFERENCES.PATTERNS, font_size)
	var warmth := _preference_pills(form, "Warmth", PREFERENCES.WARMTHS, font_size, {},
		"How fast arousal builds.")
	var tolerance := _preference_pills(form, "Neglect tolerance", PREFERENCES.TOLERANCES, font_size, {},
		"How she responds to things she dislikes.")
	var touch: Dictionary = {}
	for action: String in PREFERENCES.TOUCHES:
		touch[action] = _preference_pills(form, action.capitalize(), PREFERENCE_STATES, font_size,
			PREFERENCE_STATE_LABELS)
	var talk: Dictionary = {}
	for action: String in PREFERENCES.TALKS:
		var label := "Dirty talk" if action == "dirty" else action.capitalize()
		talk[action] = _preference_pills(form, label, PREFERENCE_STATES, font_size,
			PREFERENCE_STATE_LABELS)
	# integration: per-mare consent for the optional anatomy actions.
	# One row of checks, the same widget the list settings (Ignore body parts) use.
	var consent_public := CheckButton.new()
	consent_public.text = "Public"
	var consent_anal := CheckButton.new()
	consent_anal.text = "Anal"
	var consent_oral := CheckButton.new()
	consent_oral.text = "Oral"
	var consent_row := HBoxContainer.new()
	consent_row.add_theme_constant_override("separation", 10)
	consent_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for button: CheckButton in [consent_public, consent_anal, consent_oral]:
		button.add_theme_font_size_override("font_size", font_size - 3)
		consent_row.add_child(button)
	form.add_child(_form_label("Okay with", font_size))
	form.add_child(consent_row)
	var notes := TextEdit.new()
	notes.custom_minimum_size = Vector2(0.0, 76.0)
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes.add_theme_font_size_override("font_size", font_size - 2)
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(_form_label("Notes", font_size))
	stack.add_child(notes)

	var refs := {
		"selector": selector,
		"intensity": intensity,
		"pattern": pattern,
		"warmth": warmth,
		"tolerance": tolerance,
		"touch": touch,
		"talk": talk,
		"notes": notes,
		"consent_public": consent_public,
		"consent_anal": consent_anal,
		"consent_oral": consent_oral,
		"status": status,
		"reset": reset,
		"refreshing": false,
	}
	selector.item_selected.connect(func(index: int) -> void:
		last_id = str(selector.get_item_metadata(index))
		_refresh_preference_form(refs))
	for pills: HBoxContainer in [intensity, pattern, warmth, tolerance]:
		for pill: Node in pills.get_children():
			(pill as Button).pressed.connect(_choose_preference_pill.bind(
				pills, str(pill.get_meta("value")), refs))
	for group: Dictionary in [touch, talk]:
		for action: String in group:
			var pills: HBoxContainer = group[action]
			for pill: Node in pills.get_children():
				(pill as Button).pressed.connect(_choose_preference_pill.bind(
					pills, str(pill.get_meta("value")), refs))
	# integration: consent edits stage with the rest of the preset.
	for button: CheckButton in [consent_public, consent_anal, consent_oral]:
		button.toggled.connect(func(_on: bool) -> void: _mark_preference_dirty(refs))
	notes.text_changed.connect(func() -> void: _mark_preference_dirty(refs))
	notes.focus_exited.connect(func() -> void: _mark_preference_dirty(refs))
	save.pressed.connect(func() -> void: _save_preference_form(refs))
	reset.pressed.connect(func() -> void: _reset_preference_form(refs))
	var fill_selector := func(query: String) -> void:
		var current := _selected_preference_id(refs)
		if current.is_empty():
			current = last_id
		selector.clear()
		for id: String in SETTINGS.CHARACTER_ORDER:
			var display := SETTINGS.character_name(id)
			if query.is_empty() or display.to_lower().contains(query) or id.contains(query):
				selector.add_item(display)
				selector.set_item_metadata(selector.get_item_count() - 1, id)
				if id == current:
					selector.select(selector.get_item_count() - 1)
		if selector.selected < 0 and selector.get_item_count() > 0:
			selector.select(0)
		if selector.get_item_count() == 0:
			if status is Label:
				(status as Label).text = "No pony matches that name."
			_update_preference_reset(refs)
		else:
			_refresh_preference_form(refs)
	filter.text_changed.connect(func(text: String) -> void:
		fill_selector.call(text.to_lower().strip_edges()))
	fill_selector.call("")


## A form row's name, in the same type as a setting row's name. It takes the row's spare width so
## the control sits at the right edge, as a setting row does. It must not autowrap: in a
## GridContainer an autowrap label reports a one-character minimum, which collapses its column.
func _form_label(text: String, font_size: int) -> Label:
	var label := STYLE.label(text, "", font_size)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## A few short values as the page's Segment pills in one track; the chosen one is lit. A row label
## and an optional hint stack in the first grid cell so the help sits under its control's name.
func _preference_pills(parent: GridContainer, label_text: String, values: Array,
		font_size: int, pill_labels: Dictionary = {}, hint: String = "") -> HBoxContainer:
	var label_box := VBoxContainer.new()
	label_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label_box.add_theme_constant_override("separation", 2)
	var label := _form_label(label_text, font_size)
	label_box.add_child(label)
	if not hint.is_empty():
		var help := STYLE.label(hint, "Faint", font_size - 6)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label_box.add_child(help)
	parent.add_child(label_box)
	var track := PanelContainer.new()
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	track.add_theme_stylebox_override("panel", STYLE.rounded(STYLE.box(
		Color(0.05, 0.02, 0.09, 0.4), Color(1, 1, 1, 0.1), 1, 99, 4, 4)))
	parent.add_child(track)
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 4)
	track.add_child(pills)
	for value: Variant in values:
		var pill := Button.new()
		pill.text = str(pill_labels.get(str(value), str(value).capitalize()))
		pill.theme_type_variation = "Segment"
		pill.toggle_mode = true
		pill.custom_minimum_size = Vector2(0, font_size * 1.75)
		pill.add_theme_font_size_override("font_size", font_size - 3)
		pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		pill.set_meta("value", str(value))
		pills.add_child(pill)
	return pills


## One pill of a preference row picks the value for the whole row and stages the edit.
func _choose_preference_pill(pills: HBoxContainer, value: String, refs: Dictionary) -> void:
	for pill: Node in pills.get_children():
		(pill as Button).set_pressed_no_signal(str(pill.get_meta("value")) == value)
	_mark_preference_dirty(refs)


## Set every action row's tri-state pill from the saved likes and dislikes.
func _set_preference_actions(control: Variant, likes: Variant, values: Array, dislikes: Variant) -> void:
	if not control is Dictionary:
		return
	var groups: Dictionary = control
	var liked: Array = likes if likes is Array else []
	var disliked: Array = dislikes if dislikes is Array else []
	for value: Variant in values:
		var key := str(value)
		var state := "none"
		if key in liked:
			state = "like"
		elif key in disliked:
			state = "dislike"
		var pills: Variant = groups.get(key)
		if pills is HBoxContainer:
			_select_preference_value(pills, state)


func _selected_preference_id(refs: Dictionary) -> String:
	var selector: Variant = refs.get("selector")
	if not selector is OptionButton or (selector as OptionButton).selected < 0:
		return ""
	return str((selector as OptionButton).get_item_metadata((selector as OptionButton).selected))


func _refresh_preference_form(refs: Dictionary) -> void:
	var id := _selected_preference_id(refs)
	if id.is_empty():
		refs["refreshing"] = false
		return
	refs["refreshing"] = true
	var preferences := SETTINGS.preferences(id)
	_select_preference_value(refs.get("intensity"), str(preferences.get("intensity", "firm")))
	_select_preference_value(refs.get("pattern"), str(preferences.get("pattern", "steady")))
	_select_preference_value(refs.get("warmth"), str(preferences.get("warmth", "normal")))
	_select_preference_value(refs.get("tolerance"), str(preferences.get("tolerance", "normal")))
	_set_preference_actions(refs.get("touch"), preferences.get("touch", []), PREFERENCES.TOUCHES,
		preferences.get("dislikes", []))
	_set_preference_actions(refs.get("talk"), preferences.get("talk", []), PREFERENCES.TALKS,
		preferences.get("dislikes", []))
	var notes: Variant = refs.get("notes")
	if notes is TextEdit:
		(notes as TextEdit).text = str(preferences.get("notes", ""))
	var consent := SETTINGS.consent(id)
	if refs.get("consent_public") is CheckButton:
		(refs.get("consent_public") as CheckButton).set_pressed_no_signal(bool(consent.get("public", false)))
	if refs.get("consent_anal") is CheckButton:
		(refs.get("consent_anal") as CheckButton).set_pressed_no_signal(bool(consent.get("anal", false)))
	if refs.get("consent_oral") is CheckButton:
		(refs.get("consent_oral") as CheckButton).set_pressed_no_signal(bool(consent.get("oral", false)))
	var status: Variant = refs.get("status")
	if status is Label:
		(status as Label).text = "Editing %s" % SETTINGS.character_name(id)
	refs["refreshing"] = false
	_update_preference_reset(refs)


func _select_preference_value(control: Variant, selected_value: String) -> void:
	if not control is HBoxContainer:
		return
	for pill: Node in (control as HBoxContainer).get_children():
		(pill as Button).set_pressed_no_signal(str(pill.get_meta("value")) == selected_value)


func _mark_preference_dirty(refs: Dictionary) -> void:
	if bool(refs.get("refreshing", false)):
		return
	var status: Variant = refs.get("status")
	if status is Label:
		(status as Label).text = "Unsaved changes"


## Disable Reset while the saved preset already matches her own character template.
func _update_preference_reset(refs: Dictionary) -> void:
	var reset: Variant = refs.get("reset")
	if not reset is Button:
		return
	var id := _selected_preference_id(refs)
	var disabled := id.is_empty() or SETTINGS.preferences_match(
		SETTINGS.preferences(id), SETTINGS.default_preferences(id))
	(reset as Button).disabled = disabled


func _preference_form_values(refs: Dictionary) -> Dictionary:
	var touch: Variant = refs.get("touch")
	var talk: Variant = refs.get("talk")
	var touch_groups: Dictionary = touch if touch is Dictionary else {}
	var talk_groups: Dictionary = talk if talk is Dictionary else {}
	var touch_likes: Array = []
	var talk_likes: Array = []
	var dislikes: Array = []
	for action: String in PREFERENCES.TOUCHES:
		var state := _picked_preference_value(touch_groups.get(action), "none")
		if state == "like":
			touch_likes.append(action)
		elif state == "dislike":
			dislikes.append(action)
	for action: String in PREFERENCES.TALKS:
		var state := _picked_preference_value(talk_groups.get(action), "none")
		if state == "like":
			talk_likes.append(action)
		elif state == "dislike":
			dislikes.append(action)
	var notes: Variant = refs.get("notes")
	return {
		"intensity": _picked_preference_value(refs.get("intensity"), "firm"),
		"pattern": _picked_preference_value(refs.get("pattern"), "steady"),
		"touch": touch_likes,
		"dislikes": dislikes,
		"talk": talk_likes,
		"warmth": _picked_preference_value(refs.get("warmth"), "normal"),
		"tolerance": _picked_preference_value(refs.get("tolerance"), "normal"),
		"notes": str((notes as TextEdit).text).strip_edges() if notes is TextEdit else "",
	}


func _preference_consent_values(refs: Dictionary) -> Dictionary:
	var public := false
	var public_button: Variant = refs.get("consent_public")
	if public_button is CheckButton:
		public = (public_button as CheckButton).button_pressed
	var anal := false
	var anal_button: Variant = refs.get("consent_anal")
	if anal_button is CheckButton:
		anal = (anal_button as CheckButton).button_pressed
	var oral := false
	var oral_button: Variant = refs.get("consent_oral")
	if oral_button is CheckButton:
		oral = (oral_button as CheckButton).button_pressed
	return {"public": public, "anal": anal, "oral": oral}


func _save_preference_form(refs: Dictionary) -> void:
	if bool(refs.get("refreshing", false)):
		return
	var id := _selected_preference_id(refs)
	if id.is_empty():
		return
	var preferences := _preference_form_values(refs)
	# A preset identical to her own character default needs no saved override.
	if SETTINGS.preferences_match(preferences, SETTINGS.default_preferences(id)):
		SETTINGS.reset_preferences(id)
	else:
		SETTINGS.save_preferences(id, preferences)
	SETTINGS.save_consent(id, _preference_consent_values(refs))
	_apply_live_settings()
	refresh_anatomy()
	_refresh_preference_form(refs)
	var status: Variant = refs.get("status")
	if status is Label:
		(status as Label).text = "Saved %s" % SETTINGS.character_name(id)
	_debug("preference saved id=%s" % id)


func _reset_preference_form(refs: Dictionary) -> void:
	var id := _selected_preference_id(refs)
	if id.is_empty():
		return
	SETTINGS.reset_preferences(id)
	_refresh_preference_form(refs)
	_apply_live_settings()
	var status: Variant = refs.get("status")
	if status is Label:
		(status as Label).text = "Reset %s to its character default" % SETTINGS.character_name(id)
	_debug("preference reset id=%s" % id)


## The lit pill of a preference choice row, or the fallback when the row is not built yet.
func _picked_preference_value(control: Variant, fallback: String) -> String:
	if not control is HBoxContainer:
		return fallback
	for pill: Node in (control as HBoxContainer).get_children():
		if (pill as Button).button_pressed:
			return str(pill.get_meta("value"))
	return fallback


func _clear_injected_settings() -> void:
	for entry: Dictionary in _injected_settings:
		var page: Variant = entry.get("page")
		var ui: Variant = entry.get("ui")
		var button: Variant = entry.get("button")
		if is_instance_valid(ui) and (ui as Node).get_parent() != null:
			(ui as Node).queue_free()
		if is_instance_valid(button) and (button as Node).get_parent() != null:
			(button as Node).queue_free()
		var sidebar: Variant = entry.get("sidebar", [])
		if sidebar is Array:
			for node: Variant in sidebar:
				if is_instance_valid(node) and (node as Node).get_parent() != null:
					(node as Node).queue_free()
		if is_instance_valid(page):
			(page as Node).remove_meta("unfplap_tab")
			(page as Node).remove_meta("unfplap_ui")
			(page as Node).remove_meta("unfplap_button")
	_injected_settings.clear()
	_debug_sections.clear()


var _yaw_skeleton: Skeleton3D
var _yaw_base := 0.0
var _yaw_base_taken := false
var _yaw_applied := 0.0


## Debug: yaw Anon's whole body around its own vertical axis. The skeleton node pose turns the
## visible body; the camera, the IK targets and the bone poses are untouched.
func _body_yaw_tick() -> void:
	var deg := SETTINGS.body_yaw_deg.get_num()
	if is_zero_approx(deg) and is_zero_approx(_yaw_applied):
		return
	if not is_instance_valid(_yaw_skeleton):
		_yaw_skeleton = _body_skeleton()
		_yaw_base_taken = false
		if not is_instance_valid(_yaw_skeleton):
			return
	if not _yaw_base_taken:
		_yaw_base = _yaw_skeleton.rotation.y
		_yaw_base_taken = true
	if is_equal_approx(deg, _yaw_applied):
		return
	_yaw_applied = deg
	_yaw_skeleton.rotation.y = _yaw_base + deg_to_rad(deg)


func _body_skeleton() -> Skeleton3D:
	if not is_instance_valid(player):
		return null
	var body := player.find_child("AnonBody", true, false) as Node3D
	if not is_instance_valid(body):
		return null
	return body.find_child("Skeleton3D", true, false) as Skeleton3D


func _process(delta: float) -> void:
	_caption_top_tick()
	_body_yaw_tick()
	_sex_bond_clock += delta
	if _sex_bond_clock >= 2.0:
		_sex_bond_clock = 0.0
		for runtime: Variant in _runtimes.values():
			if is_instance_valid(runtime) and runtime.has_method("refresh_sex_bond"):
				runtime.call("refresh_sex_bond")
	if not is_instance_valid(player) and is_instance_valid(game):
		var body: Variant = game.get("player")
		if is_instance_valid(body):
			_on_player(body)
	if is_instance_valid(active_runtime):
		var camera_started := Time.get_ticks_usec()
		active_runtime.apply_camera_motion()
		active_runtime.call("perf_note", "camera_motion", Time.get_ticks_usec() - camera_started)
		if is_instance_valid(hud):
			var show_readouts := true
			if active_runtime.has_method("hud_readouts"):
				show_readouts = bool(active_runtime.call("hud_readouts"))
			var hud_started := Time.get_ticks_usec()
			hud.update_from(active_runtime, show_readouts)
			active_runtime.call("perf_note", "hud", Time.get_ticks_usec() - hud_started)
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
	if DisplayServer.get_name() != "headless" and not headset_view() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var view: Camera3D = camera()
	if view == null:
		return
	var form: Dictionary = PLAYER_FORM.active(get_tree())
	var pony_form: bool = PLAYER_FORM.is_pony(form)

	# Missionary now requires Anon to be seated/lying on the bed with a pony lying there. A
	# standing or cradling Anon has no valid missionary camera, so that entry is not offered.
	if not pony_form and is_instance_valid(player) and player.get("seat") != null:
		var lying: Node = _bedside_pony(view)
		if is_instance_valid(lying):
			var runtime: Node = runtime_for(lying)
			if is_instance_valid(runtime):
				var bed: Node3D = runtime.find_bed_under()
				if bed != null and runtime.can_start(CATALOG.MISSIONARY, "bed_side", bed):
					_offer = {"runtime": runtime, "pony": lying, "pose": CATALOG.MISSIONARY,
						"source": "bed_side", "bed": bed}
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
					_offer = {"runtime": runtime, "pony": lying, "pose": CATALOG.MISSIONARY,
						"source": "already_lying", "bed": bed}
					_log_offer()
					return

	# Standing: Anon must stand in the cone behind her rump. No crosshair aim is needed.
	var standing: Node = _rump_cone_target(view)
	if is_instance_valid(standing):
		var runtime: Node = runtime_for(standing)
		if is_instance_valid(runtime) and runtime.can_start(CATALOG.STANDING, "", null):
			_offer = {"runtime": runtime, "pony": standing, "pose": CATALOG.STANDING,
				"source": "", "bed": null}
			_log_offer()


## The standing Y zone: the nearest standing mare whose rear cone holds Anon. The cone alone
## decides, so the crosshair can point anywhere as long as he stands behind her rump.
func _rump_cone_target(view: Camera3D) -> Node:
	if not is_instance_valid(view):
		return null
	var eye: Vector3 = view.global_position
	var best: Node = null
	var best_distance := RUMP_CONE.REACH_M
	for node: Variant in mares():
		if not is_instance_valid(node):
			continue
		var actor: Node3D = node as Node3D
		if actor == null or not actor.has_method("posture_status"):
			continue
		if str(actor.posture_status().get("requested", "")) != "stand":
			continue
		var runtime: Node = runtime_for(actor)
		if not is_instance_valid(runtime):
			continue
		var anchor: Variant = runtime.call("rump_anchor")
		if not anchor is Vector3:
			continue
		var rump: Vector3 = anchor
		if not rump.is_finite():
			continue
		if not RUMP_CONE.contains(actor.global_basis.z, rump, eye):
			continue
		var flat := Vector3(eye.x - rump.x, 0.0, eye.z - rump.z)
		if flat.length() < best_distance:
			best_distance = flat.length()
			best = actor
	return best


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
	var pose := str(_offer.get("pose", ""))
	var bed = _offer.get("bed")
	if is_instance_valid(initiation) and is_instance_valid(target):
		initiation.cancel_for(target)
	if runtime.has_method("history_blocks_start") and bool(runtime.call("history_blocks_start")):
		runtime.call("refuse_from_history", pose, source, bed)
		_offer = {}
		if is_instance_valid(hud):
			hud.hide_prompt()
		return true
	var started: bool = runtime.start(pose, bed, source)
	if started:
		if is_instance_valid(classifier):
			classifier.call("cancel_scope", "dialogue:")
		if is_instance_valid(dialogue_consent):
			dialogue_consent.call("clear_all")
		_offer = {}
		if is_instance_valid(hud):
			hud.hide_prompt()
	return started


## Debug Actions entries (`DEBUG_ACTIONS.ACTIONS`). The offer helper forces a proactive request for
## the aimed (or nearest) mare, bypassing the quiet/cooldown/AI-usage checks so the lab can test
## requests with ai_usage=talk.
func action_bed_offer() -> String:
	return _debug_offer_request(CATALOG.MISSIONARY)


func action_standing_offer() -> String:
	return _debug_offer_request(CATALOG.STANDING)


## Debug-only estrus phase controls. The override is session-only and per pony; passing "" resumes
## the automatic day/id cycle.
func action_force_heat() -> String:
	return _debug_cycle_request(CYCLE.HEAT)


func action_force_diestrus() -> String:
	return _debug_cycle_request(CYCLE.DIESTRUS)


func action_clear_cycle_override() -> String:
	return _debug_cycle_request("")


func _debug_cycle_request(phase_name: String) -> String:
	if not is_instance_valid(player):
		return "Player not ready."
	var view: Camera3D = camera()
	var target: Node = _debug_target(view) if is_instance_valid(view) else null
	if not is_instance_valid(target):
		target = _nearest_pony(view)
	if not is_instance_valid(target):
		return "No mare under the crosshair or nearby."
	var runtime: Variant = runtime_for(target)
	if not is_instance_valid(runtime) or not runtime.has_method("set_cycle_override"):
		return "No runtime for %s." % str(target.name)
	runtime.call("set_cycle_override", phase_name)
	var label := "automatic" if phase_name.is_empty() else phase_name
	_debug("cycle override %s=%s" % [str(target.name), label])
	return "Cycle for %s: %s." % [str(target.name), label]


## Shared by the Debug actions.
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
	var reason := str(initiation.call("last_reject_reason"))
	if reason.is_empty():
		reason = "unknown"
	_debug("request button reject %s%s reason=%s" % [str(target.name), label, reason])
	return "Offer rejected for %s%s: %s." % [str(target.name), label, reason]


func action_grant_lover_bond() -> String:
	return _debug_bond_request(true)


func action_clear_lover_bond() -> String:
	return _debug_bond_request(false)


## Debug: re-read the hand-authored missionary base pose without restarting. A running act picks
## the new pose up on its next frame, so the lab (export) -> game (reload) loop works while posing.
func action_reload_pose() -> String:
	var error: String = AUTHORED.reload_file()
	if not error.is_empty():
		_debug("pose reload failed: %s" % error)
		return "Pose reload failed: %s" % error
	if is_instance_valid(active_runtime) and active_runtime.has_method("_sync_missionary_pose_config"):
		active_runtime.call("_sync_missionary_pose_config")
	_debug("pose reloaded")
	return "Reloaded the missionary posed base."


## Debug: which missionary base pose is in charge, and where it actually put her.
func action_show_pose_state() -> String:
	if not is_instance_valid(active_runtime):
		return "No act running."
	var rows: Variant = active_runtime.call("pose_state_rows")
	_debug_block("pose state", rows if rows is Array else [])
	return "Pose state written to the debug log."


## Debug: clear the aimed or nearest mare's long-term act history.
func action_reset_act_history() -> String:
	if not is_instance_valid(player):
		return "Act system not ready."
	var target := _debug_history_target()
	if not is_instance_valid(target):
		return "No pony under the crosshair or nearby."
	var id := _debug_pony_id(target)
	if id.is_empty():
		return "No relationship id for %s." % str(target.name)
	var section: Dictionary = ACT_HISTORY.section()
	if not ACT_HISTORY.reset(section, id):
		return "No act history for %s." % str(target.name)
	ACT_HISTORY.save()
	_debug("act history reset for %s" % id)
	return "Act history cleared for %s." % str(target.name)


## Debug: print the aimed or nearest mare's stored act history.
func action_show_act_history() -> String:
	if not is_instance_valid(player):
		return "Act system not ready."
	var target := _debug_history_target()
	if not is_instance_valid(target):
		return "No pony under the crosshair or nearby."
	var id := _debug_pony_id(target)
	if id.is_empty():
		return "No relationship id for %s." % str(target.name)
	var row := ACT_HISTORY.effective_row(ACT_HISTORY.section(), id, ACT_HISTORY.day_now())
	var rows: Array[String] = ["pony=%s id=%s" % [str(target.name), id]]
	var acts := int(row.get("acts", 0))
	if acts <= 0 and int(row.get("hurt", 0)) <= 0 and int(row.get("comfort", 0)) <= 0:
		rows.append("no history stored")
		_debug_block("ACT HISTORY", rows)
		return "No act history for %s." % str(target.name)
	rows.append("tier=%s hurt=%d comfort=%d acts=%d good=%d bad=%d neutral=%d" % [
		ACT_HISTORY.tier_name(row), int(row.get("hurt", 0)), int(row.get("comfort", 0)),
		acts, int(row.get("good", 0)), int(row.get("bad", 0)), int(row.get("neutral", 0))])
	rows.append("streaks good=%d bad=%d announced=%d" % [
		int(row.get("streak_good", 0)), int(row.get("streak_bad", 0)),
		int(row.get("announced_tier", 0))])
	var reason_values: Array = row.get("last_reasons", [])
	var reason_text := ",".join(PackedStringArray(reason_values))
	rows.append("last grade=%s quality=%.2f reasons=%s" % [
		str(row.get("last_grade", "")), float(row.get("last_quality", 0.0)), reason_text])
	var text := str(row.get("last_text", "")).strip_edges()
	var wants := str(row.get("last_wants", "")).strip_edges()
	rows.append("last text=%s" % (text if not text.is_empty() else "none"))
	rows.append("wants=%s" % (wants if not wants.is_empty() else "none"))
	var stop_until := float(row.get("stop_until", 0.0))
	var now := Time.get_unix_time_from_system()
	if stop_until > now:
		rows.append("stop_until=%.0fs left (%s)" % [
			stop_until - now, str(row.get("last_stop_kind", ""))])
	var pending := ACT_HISTORY.pending_line(row)
	rows.append("pending=%s" % (pending if not pending.is_empty() else "none"))
	var recent: Variant = row.get("recent", [])
	if recent is Array and not (recent as Array).is_empty():
		rows.append("recent:")
		for entry: Variant in recent:
			if not entry is Dictionary:
				continue
			var item: Dictionary = entry
			var stamp := Time.get_datetime_string_from_unix_time(int(item.get("at", 0.0)), true)
			rows.append("- %s %.2f %s %s" % [
				str(item.get("grade", "")), float(item.get("quality", 0.0)), stamp,
				str(item.get("text", "")).strip_edges()])
	_debug_block("ACT HISTORY", rows)
	return "Act history printed for %s." % str(target.name)


## The mod-owned parts of the next dialogue request, so a "too eager" or "too quiet" report can
## be checked against the actual text instead of guessed at.
func action_show_prompt_context() -> String:
	if not is_instance_valid(player):
		return "Player not ready."
	var target := _debug_history_target()
	if not is_instance_valid(target):
		return "No pony under the crosshair or nearby."
	var id := _debug_pony_id(target)
	if id.is_empty():
		return "No relationship id for %s." % str(target.name)
	var runtime: Variant = runtime_for(target)
	if not is_instance_valid(runtime):
		return "No runtime for %s." % str(target.name)
	var rows: Array[String] = ["pony=%s id=%s" % [str(target.name), id]]
	rows.append("prompt_note: " + str(runtime.call("prompt_note")))
	rows.append("lover_prompt_note: " + str(runtime.call("lover_prompt_note")))
	rows.append("cycle_note: " + str(runtime.call("cycle_note")))
	var history_row := ACT_HISTORY.effective_row(ACT_HISTORY.section(), id, ACT_HISTORY.day_now())
	var history_note := ACT_HISTORY.prompt_note(history_row)
	rows.append("history_note: " + (history_note if not history_note.is_empty() else "none"))
	var ctx: Variant = game.get("world_context") if is_instance_valid(game) else null
	if ctx != null and is_instance_valid(ctx):
		var events: Array = ctx.call("events_for", id, 10) if ctx.has_method("events_for") else []
		rows.append("recent events:")
		for event: Variant in events:
			if event is Dictionary:
				var item: Dictionary = event
				rows.append("  %s: %s" % [str(item.get("kind", "")), str(item.get("text", ""))])
		var impressions: Variant = ctx.get("impressions")
		if impressions != null and is_instance_valid(impressions) \
				and impressions.has_method("standing_line"):
			rows.append("standing_line: " + str(impressions.call("standing_line", id)))
	_debug_block("PROMPT CONTEXT", rows)
	return "Prompt context printed for %s." % str(target.name)


func action_reset_act_prompts() -> String:
	SETTINGS.reset_act_prompts()
	return "Act prompts reset to defaults."


func _debug_history_target() -> Node:
	var view: Camera3D = camera()
	var target: Node = _debug_target(view) if is_instance_valid(view) else null
	if not is_instance_valid(target):
		target = _nearest_pony(view)
	return target


func _debug_pony_id(target: Node) -> String:
	var id := str(target.get_meta("relationship_id", ""))
	if id.is_empty():
		var identity: Variant = target.get("identity")
		if identity != null:
			id = str(identity.get("id"))
	return id


func action_force_tolerance_warning() -> String:
	return _debug_force_tolerance("warning")


func action_force_tolerance_stop() -> String:
	return _debug_force_tolerance("stop")


func _debug_force_tolerance(kind: String) -> String:
	if not is_instance_valid(active_runtime):
		return "No act is active."
	if not active_runtime.has_method("debug_force_tolerance"):
		return "The act cannot force a neglect warning."
	if not bool(active_runtime.call("debug_force_tolerance", kind)):
		return "Neglect forcing is only available during a live act."
	return "Neglect %s queued. Close this panel to let the act apply it." % kind


## Shared by the Debug actions: grant or clear the mod lover bond on the aimed or nearest mare.
func _debug_bond_request(grant: bool) -> String:
	if not is_instance_valid(player):
		return "Act system not ready."
	var view: Camera3D = camera()
	var target: Node = _debug_target(view) if is_instance_valid(view) else null
	if not is_instance_valid(target):
		target = _nearest_pony(view)
	if not is_instance_valid(target):
		return "No pony under the crosshair or nearby."
	var runtime: Variant = runtime_for(target)
	if not is_instance_valid(runtime):
		return "No runtime for %s." % str(target.name)
	var ok := false
	if grant:
		ok = bool(runtime.call("grant_sex_bond", "debug", ""))
	else:
		ok = bool(runtime.call("end_sex_bond", "debug", ""))
	var verb := "granted" if grant else "cleared"
	if ok:
		_debug("lover bond %s for %s" % [verb, str(target.name)])
		return "Lover bond %s for %s." % [verb, str(target.name)]
	return "Could not %s the lover bond for %s (relationship, consent or no bond)." % [
		"grant" if grant else "clear", str(target.name)]


## integration: anatomy hooks used by the runtime and input.
func anon_encounter(on: bool) -> void:
	if is_instance_valid(anon_part):
		anon_part.call("encounter", on)


func anon_track(target: Vector3, rear: Vector3, up: Vector3, bed: bool, penetration_m: float,
		delta: float, mare_anchor: Node3D, attached := true) -> void:
	if is_instance_valid(anon_part):
		anon_part.call("track", target, rear, up, bed, penetration_m, delta, mare_anchor,
			attached)


func anatomy_status(text: String, seconds := 2.0) -> void:
	if is_instance_valid(hud) and hud.has_method("toast"):
		hud.call("toast", text, seconds)
	else:
		_debug(text)


## integration: gate for the per-mare public consent.
func public_offers_enabled() -> bool:
	return SETTINGS.act_public_offer.get_bool()


## integration: keep the anatomy feature live when the player edits a flag.
func refresh_anatomy() -> void:
	var enabled := SETTINGS.anatomy_on()
	if enabled and not is_instance_valid(anon_part) and is_instance_valid(player) \
			and ANON_PART.assets_exist():
		anon_part = ANON_PART.new()
		anon_part.name = "UnfplapAnonPart"
		anon_part.set("main", self)
		add_child(anon_part)
	elif not enabled and is_instance_valid(anon_part):
		anon_part.call("encounter", false)
		anon_part.queue_free()
		anon_part = null
	for runtime: Variant in _runtimes.values():
		if is_instance_valid(runtime) and runtime.has_method("apply_live_settings"):
			runtime.call("apply_live_settings")
	if is_instance_valid(anon_part) and anon_part.has_method("apply_live"):
		anon_part.call("apply_live")


## integration: the chat box refuses while the act holds the controls; open it past that lock.
func open_act_chat() -> bool:
	if not is_instance_valid(game) or not is_instance_valid(player):
		return false
	var chat: Node = game.get_node_or_null("ChatBox")
	if chat == null or not chat.has_method("_open"):
		return false
	var held: Variant = player.get("controls_locked")
	player.set("controls_locked", false)
	var opened := bool(chat.call("_open"))
	player.set("controls_locked", held)
	if opened:
		chat.set("_lock_owned", false)
	return opened


## integration: debug placement controls for the local anatomy assets.
func _anatomy_debug(op: String, value := 0.0) -> String:
	var text := ""
	if SETTINGS.edit_target.get_choice() == "default":
		text = _anatomy_default_debug(op, value)
	else:
		text = _anatomy_mare_debug(op, value)
	_debug("anatomy %s %s" % [op, text])
	return text


## Edit the global default preview. Nudges and Reset stage the values; Save writes the settings.
func _anatomy_default_debug(op: String, value := 0.0) -> String:
	var placement := SETTINGS.anatomy_placement_draft_values()
	match op:
		"save":
			SETTINGS.save_anatomy_placement_default(placement)
			_apply_settings_changed()
			return "default saved " + PLACEMENT.text(placement)
		"reset":
			SETTINGS.reset_anatomy_placement_default()
			refresh_anatomy()
			return "default " + PLACEMENT.text(SETTINGS.anatomy_placement_draft_values())
		"text":
			return "default " + PLACEMENT.text(placement)
		_:
			if not _nudge_placement(placement, op, value):
				return "Unknown anatomy place action."
			SETTINGS.set_anatomy_placement_draft(placement)
			refresh_anatomy()
			return "default " + PLACEMENT.text(placement)


func _anatomy_mare_debug(op: String, value := 0.0) -> String:
	var view: Camera3D = camera()
	var target: Node = _debug_target(view) if is_instance_valid(view) else null
	if not is_instance_valid(target):
		target = _nearest_pony(view)
	var runtime: Variant = runtime_for(target) if is_instance_valid(target) else null
	if not is_instance_valid(runtime):
		return "No anatomy pony targeted."
	return str(runtime.call("anatomy_place", op, value))


static func _nudge_placement(placement: Dictionary, op: String, value: float) -> bool:
	match op:
		"x":
			placement["offset_x"] = float(placement.get("offset_x", 0.0)) + value
		"y":
			placement["offset_y"] = float(placement.get("offset_y", 0.0)) + value
		"z":
			placement["offset_z"] = float(placement.get("offset_z", 0.0)) + value
		"pitch":
			placement["pitch_deg"] = float(placement.get("pitch_deg", 0.0)) + value
		"scale":
			placement["scale"] = maxf(0.05, float(placement.get("scale", 1.0)) + value)
		_:
			return false
	return true


func action_anatomy_up() -> String:
	return _anatomy_debug("y", 0.005)


func action_anatomy_down() -> String:
	return _anatomy_debug("y", -0.005)


func action_anatomy_forward() -> String:
	return _anatomy_debug("z", 0.005)


func action_anatomy_back() -> String:
	return _anatomy_debug("z", -0.005)


func action_anatomy_pitch_up() -> String:
	return _anatomy_debug("pitch", 1.0)


func action_anatomy_pitch_down() -> String:
	return _anatomy_debug("pitch", -1.0)


func action_anatomy_scale_up() -> String:
	return _anatomy_debug("scale", 0.02)


func action_anatomy_scale_down() -> String:
	return _anatomy_debug("scale", -0.02)


func action_anatomy_save() -> String:
	return _anatomy_debug("save")


func action_anatomy_reset() -> String:
	return _anatomy_debug("reset")


## integration: per-mare tail seat exceptions. The default is the exact reference anchor.
func _tail_seat_target() -> Node:
	var view: Camera3D = camera()
	var target: Node = _debug_target(view) if is_instance_valid(view) else null
	if not is_instance_valid(target):
		target = _nearest_pony(view)
	return target


func _tail_seat_debug(op: String, value := 0.005) -> String:
	if not is_instance_valid(tail_seat):
		return "Tail seat is unavailable."
	var target := _tail_seat_target()
	if not is_instance_valid(target):
		return "No tail-seat pony targeted."
	var text := str(tail_seat.call("place", target, op, value))
	_debug("tail seat %s %s" % [op, text])
	return text


func action_tail_seat_up() -> String:
	return _tail_seat_debug("up")


func action_tail_seat_down() -> String:
	return _tail_seat_debug("down")


func action_tail_dock_up() -> String:
	return _tail_seat_debug("dock_up")


func action_tail_dock_down() -> String:
	return _tail_seat_debug("dock_down")


func action_tail_dock_scale_up() -> String:
	return _tail_seat_debug("dock_scale_up", 0.05)


func action_tail_dock_scale_down() -> String:
	return _tail_seat_debug("dock_scale_down", 0.05)


func action_tail_seat_forward() -> String:
	return _tail_seat_debug("forward")


func action_tail_seat_back() -> String:
	return _tail_seat_debug("back")


func action_tail_seat_save() -> String:
	return _tail_seat_debug("save")


func action_tail_seat_reset() -> String:
	return _tail_seat_debug("reset")


func action_show_tail_seats() -> String:
	if not is_instance_valid(tail_seat):
		return "Tail seat is unavailable."
	return str(tail_seat.call("report_all"))


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
	if DisplayServer.get_name() != "headless" and not headset_view() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
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
	var standing: Node = _rump_cone_target(view)
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


## True while a menu or panel owns the mouse: the tree is paused or a known UI panel is open.
## Deliberately excludes "the mouse is visible" so a menu that leaves the cursor visible cannot
## keep offers and act input dead after it closes. Use menu_open() for "can he interact now".
func menu_panel_open() -> bool:
	if get_tree().paused:
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


## True when the player should not interact with the world right now. Adds the mouse state to
## menu_panel_open(): the base game leaves the cursor visible while a menu owns the mouse.
func menu_open() -> bool:
	if menu_panel_open():
		return true
	return Input.mouse_mode != Input.MOUSE_MODE_CAPTURED


## The eye is in a headset. There is no desktop cursor to capture, and the stock game leaves the
## mouse visible, so the "cursor is visible" gates must not read that as a menu owning the input.
func headset_view() -> bool:
	return is_instance_valid(game) and bool(game.get("headset_view"))


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
