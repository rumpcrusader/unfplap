extends RefCounted
## The pose asset cache and resolution: the candidate spec, its authored document, the live and
## effective reads and the one authored reload.

const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const POSE_SPEC := preload("res://mods/unfplap/poses/pose_spec.gd")

var _session: Variant = null
## A shared unavailable asset instance for a pose whose row supplies no asset.
var _empty_asset: AUTHORED = null


func _init(session: Variant) -> void:
	_session = session


## The spec a candidate names: the id's row, or the live view's row when the candidate is empty.
func candidate_spec(candidate: String = "") -> POSE_SPEC:
	var spec_id := candidate
	if spec_id.is_empty() and _session._view != null:
		spec_id = str(_session._view.id)
	if spec_id.is_empty():
		return null
	return _session._registry.spec(spec_id)


## The parsed asset for a candidate spec, or null when the row and its chain supply none.
func asset_for(candidate: String = "") -> AUTHORED:
	var spec: POSE_SPEC = candidate_spec(candidate)
	if spec == null:
		return null
	var path := effective_asset(spec)
	if path.is_empty():
		return null
	return AUTHORED.shared(path)


## The parsed asset for an already resolved spec.
func asset_for_spec(spec: POSE_SPEC) -> AUTHORED:
	var path := effective_asset(spec)
	return AUTHORED.shared(path) if not path.is_empty() else null


## The path the rig gate and diagnostics name for a candidate.
func asset_path_for(candidate: String = "") -> String:
	var spec: POSE_SPEC = candidate_spec(candidate)
	return effective_asset(spec) if spec != null else ""


## The authored base for a candidate spec, else the live pose's, else the default missionary asset,
## parsed once per path. A row without its own asset still reads the default for diagnostics.
func diagnostic_asset(candidate: String = "") -> AUTHORED:
	var asset: AUTHORED = asset_for(candidate)
	if asset != null:
		return asset
	# A row with no asset of its own reads the default missionary asset so diagnostics still have a
	# rig to describe; the readiness verdict stays false for such a row.
	if _empty_asset == null:
		_empty_asset = AUTHORED.shared(AUTHORED.PATH)
	return _empty_asset


## The asset the live rig is rendering: the source through an edge, the target once it settles.
func live_asset() -> AUTHORED:
	if is_instance_valid(_session._pose_node) and _session._pose_node.authored != null:
		return _session._pose_node.authored
	return diagnostic_asset("")


## Mirror the live rendered asset into the view, the one source presentation modules read.
func sync_view_asset() -> void:
	_session._view.authored = live_asset()


## The parsed authored pose for the debug action and the pose lab. With no candidate this is the
## live rendered asset, not the target of a running edge.
func readiness_asset(candidate: String = "") -> AUTHORED:
	if candidate.is_empty():
		return live_asset()
	return diagnostic_asset(candidate)


## The pose id of the live rendered side: the source while an edge runs, the view's pose otherwise.
func live_spec_id() -> String:
	if _session._run != null and not _session._from_id.is_empty():
		return _session._from_id
	return str(_session._view.id)


## The spec's driver, or the driver of a base further up; the first row that names one wins and a
## repeated base ends the search.
func effective_driver(spec: POSE_SPEC) -> String:
	var cursor: POSE_SPEC = spec
	var seen: Dictionary = {}
	while cursor != null:
		var path := str(cursor.driver)
		if not path.is_empty():
			return path
		var base := str(cursor.base)
		if base.is_empty() or seen.has(base):
			return ""
		seen[base] = true
		cursor = _session._registry.spec(base)
	return ""


## The procedural delta path; empty for a pose whose row carries no delta.
func effective_delta(spec: POSE_SPEC) -> String:
	return str(spec.delta) if spec != null else ""


## The authored pose document of a spec row, or the nearest base that supplies one. An internal row
## with no asset of its own inherits it from its base chain.
func effective_asset(spec: POSE_SPEC) -> String:
	var cursor: POSE_SPEC = spec
	var seen: Dictionary = {}
	while cursor != null:
		var path := str(cursor.asset)
		if not path.is_empty():
			return path
		var base := str(cursor.base)
		if base.is_empty() or seen.has(base):
			return ""
		seen[base] = true
		cursor = _session._registry.spec(base)
	return ""


## Re-read the live pose's asset in place, plus the running edge's target, or the default
## missionary asset when no pose is live. A running act picks the new pose up on its next frame.
func reload(candidate: String = "") -> String:
	var paths: Array[String] = []
	var seen: Dictionary = {}
	_add_reload_path(paths, seen, asset_path_for(candidate))
	if is_instance_valid(_session._pose_node) and _session._pose_node.authored != null:
		_add_reload_path(paths, seen, _session._pose_node.authored.path)
	if paths.is_empty():
		_add_reload_path(paths, seen, AUTHORED.PATH)
	for path: String in paths:
		var load_error := AUTHORED.reload_file(path)
		if not load_error.is_empty():
			return load_error
	if is_instance_valid(_session._pose_node):
		# The wrappers were reloaded in place; the pair keeps the same instances.
		_session._pose_node.authored = live_asset()
		if _session._target_spec != null:
			_session._target_asset = asset_for_spec(_session._target_spec)
			_session._pose_node.to_authored = _session._target_asset
		sync_view_asset()
	return ""


## Add one unique non-empty asset path to the reload list. The resolved path is the key, so a
## relative row path and the wrapper's `res://` path are the same file.
func _add_reload_path(paths: Array[String], seen: Dictionary, path: String) -> void:
	if path.is_empty():
		return
	var resolved := AUTHORED.resolve(path)
	if seen.has(resolved):
		return
	seen[resolved] = true
	paths.append(resolved)
