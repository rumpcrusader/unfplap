extends Node
## Shared hud fake: the toast, offer hint and prompt recorder the suites drive.

var toasts: Array[String] = []
var prompts: Array[String] = []
## Every non-empty offer hint, in order, and the live one with its cap ("" when none is shown).
var hints: Array[String] = []
var hint := ""
var hint_key := ""
var hides := 0

func _show_toast(text: String, _seconds := 2.0) -> void:
	toasts.append(text)

func toast(text: String, seconds := 4.0) -> void:
	_show_toast(text, seconds)

func anatomy_status(text: String, seconds := 2.0) -> void:
	_show_toast(text, seconds)

func show_prompt(text: String, _icon_name := "", _cap := "") -> void:
	prompts.append(text)

func hide_prompt() -> void:
	hides += 1

func offer_hint(text: String, key_label := "", _delta := 0.0) -> void:
	if text.is_empty():
		hides += 1
		hint = ""
		hint_key = ""
		return
	# The card is told the words again every frame so it can fade; only a change is a new hint.
	if text == hint and key_label == hint_key:
		return
	hint = text
	hint_key = key_label
	hints.append(text)
