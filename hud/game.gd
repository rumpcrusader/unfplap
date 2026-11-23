extends RefCounted
## The game's speech caption node, reduced to the fields the caption move reads and writes.


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
