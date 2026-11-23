extends RefCounted
## Service: world
## Contract: docs/world.md
## Scope: world
## Import: world/api.gd only
## Anon's rig, form driver, controls, eye line and seated state, bound to his node.

const GAME := preload("res://mods/unfplap/world/game.gd")

var _player: Node3D


func _init(player: Node3D) -> void:
	_player = player


func _bound() -> Node:
	return _player


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## The seat his rig is held on; null when he stands.
func seat() -> Node:
	return GAME.seat_of(_player)


## Whether the game holds his controls; an absent flag reads as unlocked.
func controls_locked() -> bool:
	return GAME.controls_locked(_player)


## Release or hold his controls; nothing happens without a rig.
func set_controls_locked(locked: bool) -> void:
	GAME.set_controls_locked(_player, locked)


## The desktop presentation's own show switch; a node without the op is left alone.
func set_presentation_enabled(presentation: Node, on: bool) -> void:
	GAME.set_presentation_enabled(presentation, on)


## Make a reclined Anon stand up; nothing happens without the rig's own op.
func force_stand_up() -> void:
	GAME.force_stand_up(_player)


## The eye line his rig reports; NAN when the rig cannot answer.
func eye_height() -> float:
	return GAME.eye_height(_player)


## Write the rig's private eye placement through its own setter.
func set_eye_y(y: float) -> void:
	GAME.set_eye_y(_player, y)


## Write the rig's standing eye line; a rig without the member is left alone.
func set_stand_eye(y: float) -> void:
	GAME.set_stand_eye(_player, y)


## Write the rig's own eye height; a rig without the member is left alone.
func set_eye_height(y: float) -> void:
	GAME.set_eye_height(_player, y)


## The rig's private look pitch; NAN when the rig has no such member.
func pitch() -> float:
	return GAME.pitch(_player)


## Write the rig's look pitch; an absent member stays untouched.
func set_pitch(pitch: float) -> void:
	GAME.set_pitch(_player, pitch)


## The form driver the rig shows; null for a plain body.
func form() -> Node:
	return GAME.form_of(_player)


## Let the live form driver apply its own view limit; a plain body keeps the camera as it is.
func clamp_view() -> void:
	GAME.clamp_view(GAME.form_of(_player))


## The live player form's age; the human default when no form driver is live.
func form_is_young() -> bool:
	return GAME.player_form_is_young(_tree())


## The live player form's kind; false for the human default.
func form_is_pony() -> bool:
	return GAME.player_form_is_pony(_tree())


## His body under the rig; null when the rig has none.
func body() -> Node3D:
	return GAME.anon_body_of(_player)


## Keep one of Anon's meshes out of the game's outline pass.
func exclude_from_outline(mesh: MeshInstance3D) -> void:
	GAME.exclude_from_outline(mesh)


## The seated player's Q hold; false when the rig has no such member.
func q_held() -> bool:
	return GAME.q_held(_player)


## Hold the seated player's Q action; a rig without the member is left alone.
func set_q_held(held: bool) -> void:
	GAME.set_q_held(_player, held)


## Clear the seated player's own space hold; a rig without the member is left alone.
func set_space_hold(seconds: float) -> void:
	GAME.set_space_hold(_player, seconds)


## Set the seated player's rest hold; a rig without the member is left alone.
func set_rest_held(held: bool) -> void:
	GAME.set_rest_held(_player, held)


## Seat him on a rest seat; false when the rig refuses or has no seat op.
func sit_on(seat: Node3D) -> bool:
	return GAME.player_sit_on(_player, seat)


## Recline him on his couch seat; false without the op.
func toggle_couch_sleep() -> bool:
	return GAME.player_toggle_couch_sleep(_player)


## Hand the desktop rig one palm target; a driver without the holder is left alone.
func set_hold_target(driver: Node, side: String, frame: Transform3D,
		kind: String = "hold") -> void:
	GAME.set_hold_target(driver, side, frame, kind)


## Release one palm target; a driver without the holder is left alone.
func clear_hold_target(driver: Node, side: String) -> void:
	GAME.clear_hold_target(driver, side)


## The driver's live palm frame; an infinite transform when it cannot answer.
func hand_frame(driver: Node, side: String) -> Transform3D:
	return GAME.hand_frame(driver, side)


## Forward one desktop torso pose to the body's own driver.
func apply_torso_pose(driver: Node, hip: Node3D, facing: Basis) -> void:
	GAME.apply_torso_pose(driver, hip, facing)


## Hand both rest-hand targets to the body's own driver; without the op they keep their own.
func set_rest_hand_targets(driver: Node, left: Node3D, right: Node3D) -> void:
	GAME.set_rest_hand_targets(driver, left, right)


## Release both rest-hand targets; a driver without the op is left alone.
func clear_rest_hand_targets(driver: Node, left: Node3D, right: Node3D) -> void:
	GAME.clear_rest_hand_targets(driver, left, right)


## His body's desktop pose driver; null when the body has none.
func pose_driver() -> Node:
	return GAME.desktop_pose_driver(GAME.anon_body_of(_player))


## Replace his body's desktop pose driver; a body without the member is left alone.
func set_pose_driver(driver: Node) -> void:
	GAME.set_desktop_pose_driver(GAME.anon_body_of(_player), driver)


## The knockdown handle his body carries; null when it has none.
func knockdown() -> Object:
	return GAME.knockdown_of(_player)


## Push Anon down along `direction`; false without a live knockdown handle.
func start_knockdown(direction: Vector3) -> bool:
	return GAME.start_knockdown(GAME.knockdown_of(_player), _player, direction)
