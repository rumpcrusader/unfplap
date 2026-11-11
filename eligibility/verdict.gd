extends RefCounted
## Pure helpers for an eligibility verdict. Callers use these instead of indexing row dictionaries.


static func rows(verdict: Dictionary) -> Array:
	var value: Variant = verdict.get("rows", [])
	return value if value is Array else []


static func failed_rows(verdict: Dictionary) -> Array:
	var out: Array = []
	for row: Variant in rows(verdict):
		if row is Dictionary and not bool((row as Dictionary).get("ok", false)):
			out.append(row)
	return out


static func failed(verdict: Dictionary, key: String) -> bool:
	for row: Variant in rows(verdict):
		if row is Dictionary and str((row as Dictionary).get("key", "")) == key:
			return not bool((row as Dictionary).get("ok", false))
	return false


static func reasons(verdict: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for row: Variant in failed_rows(verdict):
		if row is Dictionary:
			out.append(str((row as Dictionary).get("reason", "")))
	return out


static func rows_text(verdict: Dictionary) -> String:
	var parts: PackedStringArray = []
	for row: Variant in rows(verdict):
		if not row is Dictionary:
			continue
		var data: Dictionary = row
		parts.append("%s=%s(%s)" % [
			str(data.get("key", "?")),
			"ok" if bool(data.get("ok", false)) else "FAIL",
			str(data.get("effect", ""))])
	return " ".join(parts)
