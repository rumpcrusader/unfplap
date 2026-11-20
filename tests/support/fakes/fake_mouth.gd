extends Node
## Shared mouth fake: the viseme recorder the anatomy and world suites drive.

var visemes: Array[String] = []
var clears := 0

func set_viseme(letter: String, _blend := -1.0) -> void:
	visemes.append(letter)

func clear() -> void:
	clears += 1
