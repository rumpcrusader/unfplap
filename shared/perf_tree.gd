extends RefCounted
## The shared display layout for the two debug perf probes: rows arrive flat with a parent table
## and leave depth-first, every level largest total first, with a parent's unmeasured cost as its
## own `self` row. Pure and static, so a probe can lay a window out without a scene. See
## `docs/perf.md`.

## The smallest residual worth a row, in milliseconds inside the probe's one-second window.
const MIN_SELF_MS := 0.01

const BAR := "│  "
const GAP := "   "
const BRANCH := "├─ "
const LAST := "└─ "


## Lay `rows` out as a tree. `rows` maps a chunk key to `[total_ms, calls]`; `parents` maps a child
## key to its parent key. A chunk whose parent is absent from this window is a root, so a chunk
## that printed without its parent still shows. Returns dictionaries in display order with `key`,
## `depth`, `prefix`, `self`, `total`, `calls` and `parent` (empty unless the row is a residual).
static func layout(rows: Dictionary, parents: Dictionary) -> Array:
	var children: Dictionary = {}
	var roots: Array = []
	for key: String in rows:
		var parent := str(parents.get(key, ""))
		if parent.is_empty() or not rows.has(parent):
			roots.append(key)
			continue
		var siblings: Array = children.get(parent, [])
		siblings.append(key)
		children[parent] = siblings
	_sort_keys(roots, rows)
	var out: Array = []
	for key: String in roots:
		_emit(key, "", "", 0, false, rows, children, out)
	return out


## One measured chunk, then its children and the parent's own residual, siblings largest first.
static func _emit(key: String, lead: String, marker: String, depth: int, more: bool,
		rows: Dictionary, children: Dictionary, out: Array) -> void:
	var row: Array = rows[key]
	out.append({
		"key": key,
		"depth": depth,
		"prefix": lead + marker,
		"self": false,
		"total": float(row[0]),
		"calls": int(row[1]),
		"parent": "",
	})
	var kids: Array = children.get(key, [])
	if kids.is_empty():
		return
	var entries: Array = []
	var child_total := 0.0
	for kid: String in kids:
		var kid_row: Array = rows[kid]
		child_total += float(kid_row[0])
		entries.append([float(kid_row[0]), kid, false])
	var residual := float(row[0]) - child_total
	if residual >= MIN_SELF_MS:
		entries.append([residual, "", true])
	_sort_entries(entries)
	var child_lead := lead
	if not marker.is_empty():
		child_lead += BAR if more else GAP
	for index in entries.size():
		var entry: Array = entries[index]
		var last := index == entries.size() - 1
		if bool(entry[2]):
			out.append({
				"key": "self",
				"depth": depth + 1,
				"prefix": child_lead + (LAST if last else BRANCH),
				"self": true,
				"total": float(entry[0]),
				"calls": 0,
				"parent": key,
			})
			continue
		_emit(str(entry[1]), child_lead, LAST if last else BRANCH, depth + 1, not last,
			rows, children, out)


static func _sort_keys(keys: Array, rows: Dictionary) -> void:
	for index in range(1, keys.size()):
		var key: String = keys[index]
		var total := float((rows[key] as Array)[0])
		var at := index - 1
		while at >= 0 and float((rows[keys[at]] as Array)[0]) < total:
			keys[at + 1] = keys[at]
			at -= 1
		keys[at + 1] = key


static func _sort_entries(entries: Array) -> void:
	for index in range(1, entries.size()):
		var entry: Array = entries[index]
		var total := float(entry[0])
		var at := index - 1
		while at >= 0 and float(entries[at][0]) < total:
			entries[at + 1] = entries[at]
			at -= 1
		entries[at + 1] = entry
