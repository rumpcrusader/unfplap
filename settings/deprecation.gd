extends RefCounted
## One retired settings key: where its stored value moves, or the converter that replaces it.

class Rule extends RefCounted:
	var path: String
	## Where a plain value moves; empty when `map` decides instead.
	var target: String = ""
	## The converter for a value whose shape changes.
	var map: Callable


	func _init(retired_path: String) -> void:
		path = retired_path


	func into(target_path: String) -> Rule:
		target = target_path
		return self


	func mapped(converter: Callable) -> Rule:
		map = converter
		return self


	## The document to merge into the file, or an empty one when the value is dropped.
	func apply(value: Variant) -> Dictionary:
		if map.is_valid():
			var result: Variant = map.call(value)
			return result if result is Dictionary else {}
		return {} if target.is_empty() else {target: value}
