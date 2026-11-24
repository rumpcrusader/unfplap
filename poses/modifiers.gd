extends RefCounted
## The act's extra scene modifiers: the tail, its lay, the body and prone sways and the ear twitch,
## with the authored profile table that decides which ones a pose change installs.

const TAIL := preload("res://mods/unfplap/poses/tail_pose.gd")
const TAIL_LAY := preload("res://mods/unfplap/poses/tail_lay.gd")
const TAIL_CHAIN := preload("res://mods/unfplap/poses/tail_chain.gd")
const BODY_SWAY := preload("res://mods/unfplap/poses/body_sway.gd")
const PRONE_SWAY := preload("res://mods/unfplap/poses/prone_sway.gd")
const EAR_TWITCH := preload("res://mods/unfplap/poses/ear_twitch.gd")
const POSE_SPEC := preload("res://mods/unfplap/poses/pose_spec.gd")

const NO_OWNERS: Array[String] = []
const MODIFIER_ORDER := ["body_sway", "prone_sway", "ear_twitch", "tail", "tail_lay"]

var _session: Variant = null
var _tail: TAIL = null
var _tail_lay: TAIL_LAY = null
var _body_sway: BODY_SWAY = null
var _prone_sway: PRONE_SWAY = null
var _ear_twitch: EAR_TWITCH = null
var _profiles: Dictionary = {}


func _init(session: Variant) -> void:
	_session = session


## The test seam: replace the authored profile table with a synthetic one.
func set_profiles(table: Dictionary) -> void:
	_profiles = table.duplicate()


## The spec's modifier profile name, or empty when the row has no block.
func profile_of(spec: POSE_SPEC) -> String:
	if spec == null:
		return ""
	return str(spec.modifiers.get("profile", ""))


## Keep the shared owners, install the target-only ones and remove the source-only ones. The act
## exit's `remove_extras()` is still the full removal; this never calls it.
func reconcile(from_profile: String, to_profile: String) -> void:
	var from_owners := _owners(from_profile)
	var to_owners := _owners(to_profile)
	var pony: Node3D = _session._pony()
	var skeleton_value: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	var skeleton := skeleton_value as Skeleton3D
	for owner: String in MODIFIER_ORDER:
		var wanted: bool = owner in to_owners
		var shared: bool = wanted and owner in from_owners
		_sync_owner(owner, wanted, shared, skeleton)


## Drop the live-installed extra modifiers, keeping the pose node, the standing tail and the config.
func remove_extras() -> void:
	if is_instance_valid(_body_sway):
		_session._drop(_body_sway)
	_body_sway = null
	if is_instance_valid(_prone_sway):
		_session._drop(_prone_sway)
	_prone_sway = null
	if is_instance_valid(_ear_twitch):
		_session._drop(_ear_twitch)
	_ear_twitch = null


## Release the bed tail lay for a pose-start leave; the standing tail stays.
func release_tail_lay() -> void:
	if is_instance_valid(_tail_lay):
		_tail_lay.restore_tail()
		_session._drop(_tail_lay)
	_tail_lay = null


## Release the standing tail for the one act exit. Safe to repeat.
func release() -> void:
	if is_instance_valid(_tail):
		_tail.restore_tail()
		_session._drop(_tail)
	_tail = null


## Replay the family's sway on top of the render-time pose write.
func apply_render(skeleton: Skeleton3D, family: String) -> void:
	if family == "standing":
		if is_instance_valid(_body_sway):
			_body_sway.apply_render(skeleton)
	elif family == "bed":
		if is_instance_valid(_prone_sway):
			_prone_sway.apply_render(skeleton)


## The tail handle's one write: the lift/flick weight the afterglow sets.
func tail_target(value: float) -> void:
	if is_instance_valid(_tail):
		_tail.target_amount = value


func flick(count: int) -> void:
	if is_instance_valid(_tail):
		_tail.flick(count)


## The tail handle's thrust wave, scaled by the caller.
func thrust(weight: float) -> void:
	if is_instance_valid(_tail):
		_tail.thrust(weight)


## One thrust's ear flick; a released pose or a disabled feature ignores it.
func ear_twitch(impact: float) -> void:
	if is_instance_valid(_ear_twitch):
		_ear_twitch.try_trigger(impact)


func reset_sway() -> void:
	if is_instance_valid(_body_sway):
		_body_sway.reset_base()


## Retarget the live standing tail with the current pose config's angles.
func apply_config() -> void:
	if is_instance_valid(_tail):
		_tail.aside_angle = float(_session._pose_config.get("tail_aside", 0.0))
		_tail.lift_angle = float(_session._pose_config.get("tail_lift", 0.0))


## A rebuilt pose starts settled, so the start ramp is not a visible second entrance.
func settle() -> void:
	if is_instance_valid(_tail):
		_tail.amount = 1.0
		_tail.target_amount = 1.0


func install_tail() -> void:
	var pony: Node3D = _session._pony()
	if is_instance_valid(_tail) or not is_instance_valid(pony):
		return
	var found: Dictionary = TAIL_CHAIN.resolve(pony)
	var custom := TAIL_CHAIN.custom_root(pony)
	if found.is_empty() and custom == null:
		return
	var skeleton: Skeleton3D = found.get("skeleton") as Skeleton3D
	if skeleton == null:
		skeleton = pony.get("skeleton") as Skeleton3D
	if skeleton == null:
		return
	_tail = TAIL.new()
	_tail.name = "UnfplapTail"
	_tail.mare = pony
	_tail.facts = _session._facts
	_tail.aside_angle = float(_session._pose_config.get("tail_aside", 0.0))
	_tail.lift_angle = float(_session._pose_config.get("tail_lift", 0.0))
	_tail.amount = 0.0
	_tail.target_amount = 1.0
	var side_anchor: Variant = _session._tail_anchor
	if not side_anchor is Vector3:
		side_anchor = Vector3.INF
	_tail.choose_side(side_anchor)
	_tail.process_priority = 20
	skeleton.add_child(_tail)


func install_tail_lay() -> void:
	var pony: Node3D = _session._pony()
	if not is_instance_valid(pony):
		return
	var found: Dictionary = TAIL_CHAIN.resolve(pony)
	var custom := TAIL_CHAIN.custom_root(pony)
	if found.is_empty() and custom == null:
		return
	var skeleton: Skeleton3D = found.get("skeleton") as Skeleton3D
	if skeleton == null:
		skeleton = pony.get("skeleton") as Skeleton3D
	if skeleton == null:
		return
	_tail_lay = TAIL_LAY.new()
	_tail_lay.name = "UnfplapTailLay"
	_tail_lay.mare = pony
	_tail_lay.facts = _session._facts
	_tail_lay.process_priority = 20
	skeleton.add_child(_tail_lay)


func install_body_sway(skeleton: Skeleton3D) -> void:
	var pony: Node3D = _session._pony()
	if not _session._feature("standing_body_sway"):
		return
	_body_sway = BODY_SWAY.new()
	_body_sway.name = "UnfplapBodySway"
	_body_sway.mare = pony
	_body_sway.facts = _session._facts
	skeleton.add_child(_body_sway)
	reset_sway()


func install_prone_sway(skeleton: Skeleton3D) -> void:
	var pony: Node3D = _session._pony()
	_prone_sway = PRONE_SWAY.new()
	_prone_sway.name = "UnfplapProneSway"
	_prone_sway.mare = pony
	_prone_sway.facts = _session._facts
	skeleton.add_child(_prone_sway)


func install_ear_twitch() -> void:
	var pony: Node3D = _session._pony()
	if not _session._feature("thrust_ear_twitch"):
		return
	var head := _head_skeleton(pony.get("boop_node"))
	if head == null:
		return
	_ear_twitch = EAR_TWITCH.new()
	_ear_twitch.name = "UnfplapEarTwitch"
	_ear_twitch.mare = pony
	_ear_twitch.facts = _session._facts
	head.add_child(_ear_twitch)


## The owner list of an authored profile. An unknown profile is the empty set.
func _owners(profile: String) -> Array:
	var value: Variant = _profiles.get(profile, NO_OWNERS)
	return value as Array if value is Array else NO_OWNERS


## Install, keep and retarget, or remove one owner. A shared keep calls the owner's own idempotent
## `pose_changed()`; a feature edit that turns the owner off removes it even on a shared keep.
func _sync_owner(owner: String, wanted: bool, retarget: bool, skeleton: Skeleton3D) -> void:
	var keep := wanted and _owner_feature(owner)
	match owner:
		"body_sway":
			if keep:
				if not is_instance_valid(_body_sway):
					if skeleton != null:
						install_body_sway(skeleton)
				elif retarget:
					_body_sway.pose_changed(_session._view)
			elif is_instance_valid(_body_sway):
				_session._drop(_body_sway)
				_body_sway = null
		"prone_sway":
			if keep:
				if not is_instance_valid(_prone_sway):
					if skeleton != null:
						install_prone_sway(skeleton)
				elif retarget:
					_prone_sway.pose_changed(_session._view)
			elif is_instance_valid(_prone_sway):
				_session._drop(_prone_sway)
				_prone_sway = null
		"ear_twitch":
			if keep:
				if not is_instance_valid(_ear_twitch):
					install_ear_twitch()
				elif retarget:
					_ear_twitch.pose_changed(_session._view)
			elif is_instance_valid(_ear_twitch):
				_session._drop(_ear_twitch)
				_ear_twitch = null
		"tail":
			if keep:
				if not is_instance_valid(_tail):
					install_tail()
				elif retarget:
					_tail.pose_changed(_session._view)
			elif is_instance_valid(_tail):
				_tail.restore_tail()
				_session._drop(_tail)
				_tail = null
		"tail_lay":
			if keep:
				if not is_instance_valid(_tail_lay):
					install_tail_lay()
				elif retarget:
					_tail_lay.pose_changed(_session._view)
			elif is_instance_valid(_tail_lay):
				_tail_lay.restore_tail()
				_session._drop(_tail_lay)
				_tail_lay = null


## The feature gate an owner installs behind. The tails have none.
func _owner_feature(owner: String) -> bool:
	match owner:
		"body_sway":
			return _session._feature("standing_body_sway")
		"prone_sway":
			return _session._feature("missionary_body_motion")
		"ear_twitch":
			return _session._feature("thrust_ear_twitch")
	return true


## The head skeleton the ear twitch rides, or null.
func _head_skeleton(boop: Node) -> Skeleton3D:
	if boop == null:
		return null
	var head: Variant = boop.get("head_skeleton")
	return head as Skeleton3D
