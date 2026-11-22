extends RefCounted
## Service: debug
## Contract: docs/debug.md `## Base-game access`
## Scope: debug
## Import: base-game modules only
## The game's menu chrome, reduced to the members the Debug block draws.

const MENU_STYLE := preload("res://world/ui/menu_style.gd")


## The game's menu style, reduced to the three builders the Debug block draws with.
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
