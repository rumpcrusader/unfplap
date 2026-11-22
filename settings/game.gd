extends RefCounted
## Service: settings
## Contract: docs/settings.md `## Base-game access`
## Scope: settings
## Import: base-game modules only
## Base-game boundary for the settings autoload, its page and the menu chrome.

const MENU_STYLE := preload("res://world/ui/menu_style.gd")
const MENU_PICKER := preload("res://world/ui/menu_picker.gd")

## The page's builder requires a live callback; the caller connects the handler it switches with.
static var _unbound := func() -> void: pass


## The game's menu style, reduced to the members the mod's settings pages name.
class MenuStyle:
	## A label in the style's type variations; zero keeps the variation's own size.
	static func label(text: String, variation: String = "", size: int = 0) -> Label:
		return MENU_STYLE.label(text, variation, size)

	## A rounded box: fill, border and its width, corner radius, then inner margins.
	static func box(bg: Color, border: Color = Color.TRANSPARENT, width: int = 0,
			radius: int = 14, margin_x: int = 16, margin_y: int = 8) -> StyleBoxFlat:
		return MENU_STYLE.box(bg, border, width, radius, margin_x, margin_y)

	## A flat style with its corners capped so a pill or circle stays round.
	static func rounded(style: StyleBox) -> StyleBox:
		return MENU_STYLE.rounded(style)

	## The style's sky blue.
	static func sky() -> Color:
		return MENU_STYLE.SKY

	## The style's pink accent.
	static func pink() -> Color:
		return MENU_STYLE.PINK

	## The style's rose, one step deeper than the accent.
	static func rose() -> Color:
		return MENU_STYLE.ROSE

	## The style's muted text colour.
	static func muted() -> Color:
		return MENU_STYLE.MUTED

	## The style's cream body text colour.
	static func cream() -> Color:
		return MENU_STYLE.CREAM

	## The style's bold reading font.
	static func bold() -> Font:
		return MENU_STYLE.BOLD


## The game's settings autoload under the given root; null when the tree is not ready.
static func settings_node(root: Node) -> Node:
	if not is_instance_valid(root):
		return null
	return root.get_node_or_null("Settings")


## The game's mods registry autoload under the given root; null when the tree is not ready.
static func mods_node(root: Node) -> Node:
	if not is_instance_valid(root):
		return null
	return root.get_node_or_null("Mods")


## One game setting by its dotted key; empty when the settings node has no reader.
static func setting_string(settings: Node, key: String) -> String:
	if not is_instance_valid(settings) or not settings.has_method("get_value"):
		return ""
	return str(settings.call("get_value", key))


## One mod's data folder from the registry; empty when the host has no folder reader.
static func mods_data_folder(mods: Node, id: String) -> String:
	if not is_instance_valid(mods) or not mods.has_method("data_folder"):
		return ""
	return str(mods.call("data_folder", id))


## The game's own tab button, unconnected; the caller connects the handler it switches with.
static func settings_page_button(page: Node, parent: Node, text: String) -> Button:
	if not is_instance_valid(page) or not page.has_method("_button"):
		return null
	var button: Variant = page.call("_button", parent, text, _unbound)
	if button is Button and is_instance_valid(button):
		return button
	return null


## One icon texture from the game's settings page; null when the page has no texture op.
static func settings_page_icon(page: Node, kind: String) -> Texture2D:
	if not is_instance_valid(page) or not page.has_method("_icon_texture"):
		return null
	var icon: Variant = page.call("_icon_texture", kind)
	if icon is Texture2D:
		return icon
	return null


## Ask the game's settings page to repaint; nothing happens without its own redraw.
static func settings_page_redraw(page: Node) -> void:
	if is_instance_valid(page) and page.has_method("_redraw"):
		page.call("_redraw")


## Set the picture on one of the game's menu icons; a control without the field is left alone.
static func set_menu_icon_kind(icon: Control, kind: String) -> void:
	if is_instance_valid(icon):
		icon.set("kind", kind)


## A new in-page dropdown for the game's pages; each one keeps its own entries.
static func menu_picker() -> Control:
	return MENU_PICKER.new()
