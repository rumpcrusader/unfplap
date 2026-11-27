extends RefCounted
## The game's speech caption node, reduced to the fields the caption move reads and writes, and the
## corner control card the offer hint's row goes on.

const CONTROL_CARD := preload("res://world/ui/control_card.gd")


## True only for the settings page's preview copy, which the move leaves alone.
static func caption_preview(node: Node) -> bool:
	return is_instance_valid(node) and node.get("preview") == true


## The caption's card, the control the move places; null without one.
static func caption_card(node: Node) -> Control:
	if not is_instance_valid(node):
		return null
	var card: Variant = node.get("_card")
	if card is Control and is_instance_valid(card):
		return card
	return null


## The caption's own UI scale, which the move multiplies the margin by; 1.0 without the field.
static func caption_scale(node: Node) -> float:
	if not is_instance_valid(node):
		return 1.0
	var value: Variant = node.get("_scale")
	return float(value) if value != null else 1.0


## Place the card at the top margin, rounded, at the caption's own scale.
static func place_caption(card: Control, top_margin: float, scale: float) -> void:
	if not is_instance_valid(card):
		return
	card.position.y = roundf(top_margin * maxf(scale, 0.01))


## The game's corner control card, held as the script's own type so every call into it is typed.
class Card:
	var card: CONTROL_CARD

	## Whether the game still holds the card.
	func valid() -> bool:
		return is_instance_valid(card)

	## Show, update or fade one named section; a row is [keys, mode, words].
	func section(key: String, on: bool, rows: Array, delta: float) -> void:
		if valid():
			card.section(key, on, "", rows, delta)


## The game's one corner control card, made under `from` when the world has none yet; null when
## `from` is out of the tree or this build has no card script.
static func control_card(from: Node) -> Card:
	if not is_instance_valid(from) or not from.is_inside_tree():
		return null
	var found: Variant = CONTROL_CARD.shared(from)
	if not found is CanvasLayer or not is_instance_valid(found):
		return null
	var out := Card.new()
	out.card = found as CONTROL_CARD
	return out
