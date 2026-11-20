extends RefCounted
## Typed read-only views of the settings documents, so a caller never indexes a raw dictionary.
## Contract: `docs/settings.md` (`## Internal API`).
##
## `of` and `raw` are the JSON edge: the service stores plain dictionaries and wraps them here.

class Rows extends RefCounted:
	## The wrapped document; shared, never copied, and treated as read-only.
	var _data: Dictionary


	static func of(data: Dictionary) -> Rows:
		var out := Rows.new()
		out._data = data
		return out


	func raw() -> Dictionary:
		return _data


	func has(key: String) -> bool:
		return _data.has(key)


	func bool_value(key: String, fallback := false) -> bool:
		var value: Variant = _data.get(key)
		return value if value is bool else fallback


	func num(key: String, fallback := 0.0) -> float:
		var value: Variant = _data.get(key)
		return float(value) if value is float or value is int else fallback


	func str_value(key: String, fallback := "") -> String:
		var value: Variant = _data.get(key)
		return str(value) if value is String else fallback


	## A nested document, or an empty view when the key is absent or not a document.
	func rows(key: String) -> Rows:
		var value: Variant = _data.get(key)
		return Rows.of(value if value is Dictionary else {})


	func keys() -> Array[String]:
		var out: Array[String] = []
		for key: Variant in _data.keys():
			out.append(str(key))
		return out
