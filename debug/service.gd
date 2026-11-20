extends RefCounted
## Service: debug
## Contract: docs/debug.md
## Scope: process
## Import: debug/service.gd only
## An action is one table entry that runs a one-off operation, never a setting.

const WORLD := preload("res://mods/unfplap/world/service.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const ACTIONS_NODE := preload("res://mods/unfplap/debug/actions.gd")

## The aimed mare: the mare closest to the camera's aim ray, inside this tube and range.
const AIM_RANGE_M := 8.0
const AIM_TUBE_M := 1.5

## The node that runs the actions; it publishes itself here on entry, so no caller passes it.
static var target: ACTIONS_NODE = null

## Debug actions; `method` runs on `target`. The registry claims no global hotkeys, so only a
## settings button or a wheel slot fires one; entries sharing a `row` must stay adjacent.
const ACTIONS := {
	"reload_pose": {
		"label": "Reload posed base",
		"help": "Re-read the active pose's authored JSON without restarting the game. A running act picks it up.",
		"method": "action_reload_pose",
	},
	"pose_test_variant": {
		"label": "Pose: test variant",
		"help": "Toggle the internal standing_test pose in a live standing act. Logs the edge result; never ends the act.",
		"method": "action_pose_test_variant",
	},
	"facesit_variant": {
		"label": "Pose: face-sit",
		"help": "Toggle the internal bed face-sit in a live missionary act. Refuses while the pose changes, a kiss runs or the anatomy body is unavailable; never ends the act.",
		"method": "action_facesit_variant",
	},
	"bed_offer": {
		"label": "Trigger bed offer",
		"help": "Force a missionary offer for the aimed mare.",
		"method": "action_bed_offer",
		"panel": false,
		"short": "Bed offer",
	},
	"standing_offer": {
		"label": "Trigger standing offer",
		"help": "Force a standing offer for the aimed mare.",
		"method": "action_standing_offer",
		"panel": false,
		"short": "Standing offer",
	},
	"anon_offer": {
		"label": "Trigger Anon offer",
		"help": "Form an Anon offer for the aimed mare as if Anon had just asked her.",
		"method": "action_anon_offer",
		"panel": false,
		"short": "Anon offer",
	},
	"show_data": {
		"label": "Show data",
		"help": "Print the aimed mare's target, cycle, gate, act, stool, history, prompt and bed data to the debug log.",
		"method": "action_show_data",
		"panel": false,
		"short": "Show data",
	},
	"bed_cuddle": {
		"label": "Bed cuddle",
		"help": "Sit or lie Anon on the bed and invite the aimed mare to the stock cuddle.",
		"method": "action_bed_cuddle",
		"panel": false,
		"short": "Bed cuddle",
	},
	"sex_ready": {
		"label": "Make sex-ready",
		"help": "Clear the aimed mare's busy state, give her a dating record and a neutral mood so the act gate opens. Her romance tier is untouched.",
		"method": "action_sex_ready",
		"panel": false,
		"short": "Sex ready",
	},
	"deep_stretch": {
		"label": "Force deep stretch",
		"help": "Play Idle Life's deep stretch on the aimed mare, or on the live act's pony. It interrupts her current idle and plays to the end.",
		"method": "action_deep_stretch",
		"panel": false,
		"short": "Deep stretch",
	},
	"give_stool": {
		"label": "Give footstool",
		"help": "Add a footstool to Anon's briefcase.",
		"method": "action_give_stool",
	},
	"reset_act_prompts": {
		"label": "Reset act prompts",
		"help": "Remove saved act-line prompt overrides and return to the built-in prompts.",
		"method": "action_reset_act_prompts",
	},
	"pantyhose_rebuild": {
		"label": "Pantyhose: rebuild hull",
		"help": "Rebuild the worn-garment depth field from the anatomy mesh after changing its precision.",
		"method": "action_pantyhose_rebuild",
		"tab": "integrations",
	},
	"cycle_heat": {
		"label": "Force heat",
		"help": "Put the aimed mare in heat for this session, or clear heat when she is already in it.",
		"method": "action_toggle_heat",
		"panel": false,
		"tab": "world",
		"row": "Cycle",
		"short": "Force heat",
		"phase": "heat",
		"match_label": "Clear heat",
		"match_short": "Clear heat",
	},
	"cycle_diestrus": {
		"label": "Force diestrus",
		"help": "Turn the aimed mare off for this session, or clear diestrus when she is already in it.",
		"method": "action_toggle_diestrus",
		"panel": false,
		"tab": "world",
		"row": "Cycle",
		"short": "Force diestrus",
		"phase": "diestrus",
		"match_label": "Clear diestrus",
		"match_short": "Clear diestrus",
	},
	"cycle_auto": {
		"label": "Resume automatic cycle",
		"help": "Clear the aimed mare's session override and resume her automatic estrus cycle.",
		"method": "action_cycle_auto",
		"tab": "world",
		"row": "Cycle",
		"short": "Resume auto",
	},
	"reset_act_history": {
		"label": "Reset act history",
		"help": "Clear the aimed mare's long-term act history and hurt.",
		"method": "action_reset_act_history",
		"tab": "world",
		"row": "Act history",
		"short": "Reset",
	},
	"clear_cooldown": {
		"label": "Clear offer cooldown",
		"help": "Clear the aimed mare's proactive-offer cooldown and short retry.",
		"method": "action_clear_cooldown",
		"tab": "world",
		"row": "Offers",
		"short": "Clear cooldown",
	},
	"force_tolerance_warning": {
		"label": "Force neglect warning",
		"help": "Trigger the active act's next neglect warning.",
		"method": "action_force_tolerance_warning",
		"panel": false,
		"tab": "world",
		"row": "Neglect",
		"short": "Neglect warning",
	},
	"force_tolerance_stop": {
		"label": "Force neglect stop",
		"help": "Make the active mare stop the act through the neglect path.",
		"method": "action_force_tolerance_stop",
		"panel": false,
		"tab": "world",
		"row": "Neglect",
		"short": "Neglect stop",
	},
	"force_act_face": {
		"label": "Force act face",
		"help": "Cycle the game's expression faces on the active act or the aimed mare.",
		"method": "action_force_act_face",
		"panel": false,
		"row": "Act face",
		"short": "Next face",
	},
	# integration: the generic form change. The buttons appear only while an installed source is
	# active; the act's own request keeps the runtime, and the idle action only tests the source.
	"form_true": {
		"label": "Form: true form",
		"help": "Ask the active shape-changing mare to show her own form. In an act the body swaps and the act continues; outside one it only changes her.",
		"method": "action_form_true",
		"tab": "world",
		"row": "Form",
		"short": "True form",
		"requires": "shape_source",
	},
	"form_name": {
		"label": "Form: next named shape",
		"help": "Change her to the next shipped adult mare's shape. In an act the body swaps and the act continues; outside one it only changes her.",
		"method": "action_form_name",
		"tab": "world",
		"row": "Form",
		"short": "Named shape",
		"requires": "shape_source",
	},
	"form_idle": {
		"label": "Form: bring her out",
		"help": "Bring an away shape-changing mare out as she is. No act is needed; use it before a lab act.",
		"method": "action_form_idle",
		"tab": "world",
		"row": "Form",
		"short": "Bring out",
		"requires": "shape_source",
	},
	# integration: one placement editor for anatomy, tail and dock. The target pill above the
	# actions selects the global default or the pointed mare.
	"anatomy_up": {"label": "Placement up", "help": "Move the selected placement up 5 mm.",
		"method": "action_anatomy_up", "tab": "anatomy",
		"row": "Placement", "short": "Up"},
	"anatomy_down": {"label": "Placement down", "help": "Move the selected placement down 5 mm.",
		"method": "action_anatomy_down", "tab": "anatomy",
		"row": "Placement", "short": "Down"},
	"anatomy_forward": {"label": "Placement forward", "help": "Move the selected placement forward 5 mm.",
		"method": "action_anatomy_forward", "tab": "anatomy",
		"row": "Placement", "short": "Forward"},
	"anatomy_back": {"label": "Placement back", "help": "Move the selected placement back 5 mm.",
		"method": "action_anatomy_back", "tab": "anatomy",
		"row": "Placement", "short": "Back"},
	"anatomy_pitch_up": {"label": "Placement pitch up", "help": "Pitch the selected placement up 1 degree.",
		"method": "action_anatomy_pitch_up", "tab": "anatomy",
		"row": "Placement pitch", "short": "Pitch +"},
	"anatomy_pitch_down": {"label": "Placement pitch down", "help": "Pitch the selected placement down 1 degree.",
		"method": "action_anatomy_pitch_down", "tab": "anatomy",
		"row": "Placement pitch", "short": "Pitch −"},
	"anatomy_scale_up": {"label": "Placement bigger", "help": "Scale the selected placement up by 0.02.",
		"method": "action_anatomy_scale_up", "tab": "anatomy",
		"row": "Placement pitch", "short": "Bigger"},
	"anatomy_scale_down": {"label": "Placement smaller", "help": "Scale the selected placement down by 0.02.",
		"method": "action_anatomy_scale_down", "tab": "anatomy",
		"row": "Placement pitch", "short": "Smaller"},
	"tail_seat_up": {"label": "Tail placement up", "help": "Move the selected tail seat 5 mm up.",
		"method": "action_tail_seat_up", "tab": "anatomy",
		"row": "Placement tail", "short": "Up"},
	"tail_seat_down": {"label": "Tail placement down", "help": "Move the selected tail seat 5 mm down.",
		"method": "action_tail_seat_down", "tab": "anatomy",
		"row": "Placement tail", "short": "Down"},
	"tail_seat_forward": {"label": "Tail placement forward", "help": "Move the selected tail seat 5 mm toward her head.",
		"method": "action_tail_seat_forward", "tab": "anatomy",
		"row": "Placement tail", "short": "Fwd"},
	"tail_seat_back": {"label": "Tail placement back", "help": "Move the selected tail seat 5 mm toward her rump.",
		"method": "action_tail_seat_back", "tab": "anatomy",
		"row": "Placement tail", "short": "Back"},
	"tail_tilt_left": {"label": "Tail tilt left", "help": "Tilt the selected tail 1 degree left.",
		"method": "action_tail_tilt_left", "tab": "anatomy",
		"row": "Placement tail tilt", "short": "Left"},
	"tail_tilt_right": {"label": "Tail tilt right", "help": "Tilt the selected tail 1 degree right.",
		"method": "action_tail_tilt_right", "tab": "anatomy",
		"row": "Placement tail tilt", "short": "Right"},
	"tail_dock_up": {"label": "Dock placement up", "help": "Move the selected dock 5 mm toward her tail.",
		"method": "action_tail_dock_up", "tab": "anatomy",
		"row": "Placement dock", "short": "Up"},
	"tail_dock_down": {"label": "Dock placement down", "help": "Move the selected dock 5 mm away from her tail.",
		"method": "action_tail_dock_down", "tab": "anatomy",
		"row": "Placement dock", "short": "Down"},
	"tail_dock_scale_up": {"label": "Dock placement bigger", "help": "Grow the selected dock 5%.",
		"method": "action_tail_dock_scale_up", "tab": "anatomy",
		"row": "Placement dock", "short": "Larger"},
	"tail_dock_scale_down": {"label": "Dock placement smaller", "help": "Shrink the selected dock 5%.",
		"method": "action_tail_dock_scale_down", "tab": "anatomy",
		"row": "Placement dock", "short": "Smaller"},
	"placement_save": {"label": "Save placement", "help": "Save the selected global default or pointed mare placement.",
		"method": "action_placement_save", "tab": "anatomy",
		"row": "Placement file", "short": "Save"},
	"placement_reset": {"label": "Reset placement", "help": "Reset the selected placement to its default.",
		"method": "action_placement_reset", "tab": "anatomy",
		"row": "Placement file", "short": "Reset"},
	"placement_show": {"label": "Show placement", "help": "Log the selected placement and every live tail seat.",
		"method": "action_placement_show", "tab": "anatomy",
		"row": "Placement file", "short": "Show"},
}

## The wheel's two context pages, clockwise from the top; the live act chooses one.
const WHEEL_PAGES := {
	"mare": {
		"title": "Mare",
		"actions": ["show_data", "bed_offer", "bed_cuddle", "standing_offer", "anon_offer",
			"cycle_heat", "cycle_diestrus", "sex_ready", "deep_stretch"],
	},
	"act": {
		"title": "Act",
		"actions": ["show_data", "form_true", "form_name", "force_tolerance_warning",
			"force_tolerance_stop", "force_act_face", "deep_stretch"],
	},
}
const WHEEL_MAX_SLOTS := 9


## The wheel's root page for the current act state.
static func wheel_root(act_live: bool) -> String:
	return "act" if act_live else "mare"


## The action ids on one wheel page, in clockwise order. An action whose `requires` gate is
## closed is left off the wheel, the same rule the settings block uses.
static func wheel_actions(page: String, node: Node = null) -> Array[String]:
	var out: Array[String] = []
	var entry: Variant = WHEEL_PAGES.get(page)
	if not entry is Dictionary:
		return out
	var actions: Variant = (entry as Dictionary).get("actions", [])
	if actions is Array:
		for name: Variant in actions:
			if _action_available(str(name), _node(node)):
				out.append(str(name))
	return out


## The action's optional runtime gate. Only `shape_source` exists today: its buttons stay off
## every surface while no shape-changing source is installed.
static func action_available(name: String, node: Node = null) -> bool:
	return _action_available(name, _node(node))


static func _action_available(name: String, node: Node) -> bool:
	var entry: Variant = ACTIONS.get(name)
	if not entry is Dictionary:
		return false
	if str((entry as Dictionary).get("requires", "")) != "shape_source":
		return true
	if not is_instance_valid(node):
		return false
	# The actions node is the only target with this gate; the label seam takes any node.
	var gate: Variant = node
	return gate.has_method("shape_source_active") and bool(gate.shape_source_active())


static func wheel_title(page: String) -> String:
	var entry: Variant = WHEEL_PAGES.get(page)
	return str((entry as Dictionary).get("title", page)) if entry is Dictionary else page


## The action's full label, or the match label when the target is already in its `phase`.
static func action_label(name: String, node: Node = null) -> String:
	return _action_text(name, _node(node), "label", "match_label")


## The action's compact label, or the match label when the target is already in its `phase`.
static func action_short(name: String, node: Node = null) -> String:
	return _action_text(name, _node(node), "short", "match_short")


static func _action_text(name: String, node: Node, key: String, match_key: String) -> String:
	var entry: Variant = ACTIONS.get(name)
	if not entry is Dictionary:
		return name
	var action: Dictionary = entry
	var text := str(action.get(key, action.get("label", name)))
	var phase := str(action.get("phase", ""))
	if phase.is_empty():
		return text
	if not is_instance_valid(node):
		return text
	# The label seam takes the actions node or any node that answers the phase read.
	var phase_node: Variant = node
	if not phase_node.has_method("debug_cycle_phase"):
		return text
	if str(phase_node.debug_cycle_phase()) != phase:
		return text
	return str(action.get(match_key, text))


## The action bound to a physical key code, or "" when none is; no entry declares one today.
static func hotkey_action(keycode: int) -> String:
	for name: String in ACTIONS:
		if int(ACTIONS[name].get("hotkey", 0)) == keycode:
			return name
	return ""


## Run one action on `node`, or on the actions node when none is named. Returns its message, or ""
## when it cannot run.
static func run_action(name: String, node: Node = null) -> String:
	if not ACTIONS.has(name):
		return ""
	var actions := _node(node)
	var method := str(ACTIONS[name].get("method", ""))
	if not is_instance_valid(actions) or not actions.has_method(method):
		return ""
	var result: Variant = actions.call(method)
	return str(result) if result is String else ""


## The wheel's open gate for one frame's facts: debug on, desktop, in a world, unpaused, desktop
## eye, focused window, captured cursor, no menu, no text field and the left button released.
static func wheel_gate(debug_on: bool, headless: bool, in_world: bool, paused: bool,
		headset: bool, focused: bool, captured: bool, menu_open: bool, typing: bool,
		left_held: bool) -> bool:
	if not debug_on or headless or not in_world or paused or headset or not focused:
		return false
	return captured and not menu_open and not typing and not left_held


## One input event for the wheel. False when the mod has no actions node or the event is not the
## wheel's.
static func wheel_input(event: InputEvent) -> bool:
	var actions := _node(null) as ACTIONS_NODE
	if actions == null:
		return false
	return actions.debug_wheel_input(event)


## True while the action wheel is open.
static func wheel_open() -> bool:
	var actions := _node(null) as ACTIONS_NODE
	if actions == null:
		return false
	return actions.debug_wheel_open()


## One left click for the skeleton overlay; false when no joint is under the pointer.
static func skeleton_click() -> bool:
	var actions := _node(null) as ACTIONS_NODE
	if actions == null:
		return false
	return actions.skeleton_click()


## The aimed mare: the mare closest to the camera's aim ray, or a cradled prop in Anon's arms
## while he is not in pony form. `debug/actions.gd` and the placement editor share this rule.
static func aimed_pony(view: Camera3D) -> Node:
	if not is_instance_valid(WORLD.player) or not is_instance_valid(WORLD.game):
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if not PLAYER_FORM.is_pony(PLAYER_FORM.active(tree)):
		var reach: Node = WORLD.interactor()
		if is_instance_valid(reach) and reach.get("cradled") == true:
			var held: Variant = reach.get("held")
			if held is Node3D and is_instance_valid(held):
				return held
	if not is_instance_valid(view):
		return null
	var forward := -view.global_basis.z
	var best: Node = null
	var best_perp := INF
	for node: Variant in WORLD.mares():
		if not is_instance_valid(node):
			continue
		var actor: Node3D = node as Node3D
		if actor == null:
			continue
		var at: Vector3 = actor.global_position + Vector3.UP * 0.9
		var delta: Vector3 = at - view.global_position
		var along := forward.dot(delta)
		if along <= 0.0 or along > AIM_RANGE_M:
			continue
		var perp := (delta - forward * along).length()
		if perp > AIM_TUBE_M:
			continue
		if perp < best_perp:
			best_perp = perp
			best = actor
	return best


## The mare nearest the camera, inside `AIM_RANGE_M`; the placement editor's fallback aim.
static func nearest_pony(view: Camera3D) -> Node:
	if not is_instance_valid(view):
		return null
	var best: Node = null
	var best_distance := AIM_RANGE_M
	for node: Variant in WORLD.mares():
		if not is_instance_valid(node) or not node is Node3D:
			continue
		var actor: Node3D = node as Node3D
		var distance := actor.global_position.distance_to(view.global_position)
		if distance < best_distance:
			best_distance = distance
			best = actor
	return best


## The explicit node, else the live actions node.
static func _node(node: Node) -> Node:
	if is_instance_valid(node):
		return node
	return target if is_instance_valid(target) else null
