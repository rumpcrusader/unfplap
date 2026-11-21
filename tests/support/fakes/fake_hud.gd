extends Node
## Shared hud fake: the toast and prompt recorder the offer suites drive.

var toasts: Array[String] = []
var prompts: Array[String] = []
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
