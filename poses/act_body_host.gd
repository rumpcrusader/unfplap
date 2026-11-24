extends RefCounted
## The act's own Anon body and its `anon` channel: the adapter on the runtime host, its authored
## asset pair and the placement the render frame applies.

const MISSIONARY_ANON := preload("res://mods/unfplap/poses/missionary_anon.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const POSE_VIEW := preload("res://mods/unfplap/shared/pose_view.gd")

const NO_CHANNEL := {}

var _session: Variant = null
var _body: MISSIONARY_ANON = null


func _init(session: Variant) -> void:
	_session = session


## Apply the `act_body` specs' Anon channel (`hold`, `blend`, `switch`) and bind the authored asset
## pair for it; the player-body specs never install the adapter.
func apply_channel(view: POSE_VIEW) -> void:
	var anon := view.anon
	if str(anon.get("mode", "")) != "act_body":
		return
	_install()
	if not is_instance_valid(_body):
		return
	if _session._run == null:
		# Outside an edge the spec's profile is the hold and both assets are the live one.
		var live: AUTHORED = _session._live_asset()
		_body.set_pose_assets(live, live, 1.0)
		_body.pose_changed(str(anon.get("profile", "")), 1.0)
		return
	var channel := _anon_channel()
	match str(channel.get("kind", "hold")):
		"blend":
			_body.set_pose_assets(_session._from_asset, _session._target_asset,
				clampf(view.weight, 0.0, 1.0))
			_body.set_weight(clampf(view.weight, 0.0, 1.0))
		"switch":
			var switched := str(channel.get("profile", ""))
			if switched.is_empty():
				switched = str(channel.get("set", ""))
			if switched.is_empty():
				switched = str(anon.get("profile", ""))
			_body.set_pose_assets(_session._target_asset, _session._target_asset, 1.0)
			_body.pose_changed(switched, 1.0)
		_:
			# A hold keeps the adapter's current profile, weight and asset pair.
			pass


## Clear the bridge handle first, then restore and free the act body once. A transition never
## reaches this.
func release() -> void:
	if not is_instance_valid(_body):
		_body = null
		return
	_body.remove()
	_session._drop(_body)
	_body = null


## Place the installed adapter for one render frame, when the live space is real.
func apply_render(frame: Transform3D, body_scale: float) -> void:
	if is_instance_valid(_body) and frame.origin.is_finite():
		_body.apply(frame, body_scale)


## Point an installed adapter at one live asset pair, at full weight.
func sync_assets(asset: AUTHORED) -> void:
	if is_instance_valid(_body):
		_body.set_pose_assets(asset, asset, 1.0)


## True while the act body is installed and its adapter is active.
func live() -> bool:
	return is_instance_valid(_body) and bool(_body.get("active"))


## The act body's authored mouth point; INF when it is missing, inactive or non-finite.
func mouth_point() -> Vector3:
	if not live():
		return Vector3.INF
	var value: Variant = _body.mouth_point()
	return value if value is Vector3 and (value as Vector3).is_finite() else Vector3.INF


## The act body's authored eye point; INF when it is missing, inactive or non-finite.
func eye_point() -> Vector3:
	if not live():
		return Vector3.INF
	var value: Variant = _body.eye_point()
	return value if value is Vector3 and (value as Vector3).is_finite() else Vector3.INF


## The act body's placed avatar transform, or the identity when no body is installed.
func transform() -> Transform3D:
	if not is_instance_valid(_body):
		return Transform3D.IDENTITY
	var avatar: Variant = _body.get("avatar")
	return (avatar as Node3D).global_transform if avatar is Node3D else Transform3D.IDENTITY


## The act body's debug row, or "" when no body is installed.
func diag_row(face: Vector3, vulva: Vector3) -> String:
	if not is_instance_valid(_body):
		return ""
	return str(_body.diag_row(face, vulva))


func refresh_palm() -> void:
	if is_instance_valid(_body):
		_body.refresh_palm()


## The act body's node, or null when none is installed.
func node() -> Node:
	return _body if is_instance_valid(_body) else null


## The live edge's `anon` channel, or the empty hold. Outside an edge the spec's profile holds.
func _anon_channel() -> Dictionary:
	if _session._run == null:
		return NO_CHANNEL
	var channels_value: Variant = _session._run.edge.get("channels", {})
	if not channels_value is Dictionary:
		return NO_CHANNEL
	var value: Variant = (channels_value as Dictionary).get("anon")
	return value as Dictionary if value is Dictionary else NO_CHANNEL


## True on a bed spec's `act_body` mode for desktop human Anon.
func _wanted() -> bool:
	var facts: Variant = _session._facts
	if facts == null or str(_session._view.anon.get("mode", "")) != "act_body":
		return false
	return not facts.player_pony and not facts.headset_view


## The act's own Anon body, created on the runtime host. The pose service owns it and frees it.
func _install() -> void:
	if is_instance_valid(_body):
		return
	var host: Node = _session.get_parent()
	if host == null or not _wanted():
		return
	var body := MISSIONARY_ANON.new()
	body.name = "UnfplapMissionaryAnon"
	host.add_child(body)
	if not body.install(_session._facts):
		host.remove_child(body)
		body.queue_free()
		return
	body.set_pose_assets(_session._live_asset(), _session._live_asset(), 1.0)
	_body = body
