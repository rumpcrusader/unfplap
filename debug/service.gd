extends RefCounted
## The Debug block's action buttons and the debug action wheel's pages. An action is one entry in
## `ACTIONS`; `method` is called on the entry node. Actions are not settings: they run a one-off
## debug operation.

## Debug actions. `method` is called on the entry node. `tab` places the button in that tab's
## Debug block (`general` by default, or `anatomy`/`world`); a missing tab means General.
## `panel: false` keeps an action off every settings block but leaves it available to the wheel;
## every action on a wheel page sets it, so settings draw only the settings-only actions.
## Add an action here; it becomes a button in the matching Debug block automatically. Actions that
## share a `row` are drawn compactly on one line, captioned with `short`; consecutive entries with
## the same row must stay adjacent. A `phase` entry also carries `match_label`/`match_short`, used
## by `action_label`/`action_short` when the target is already in that phase.
## The mod claims no global debug hotkeys: the game's F4/F9/F10/F11 dev tools stay usable, and a
## Debug block button or the action wheel is the only trigger.
const ACTIONS := {
	"reload_pose": {
		"label": "Reload posed base",
		"help": "Re-read poses/missionary_pose.json without restarting the game. A running act picks it up.",
		"method": "action_reload_pose",
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

## The wheel's two context pages, clockwise from the top. `wheel_root` chooses the page; there are
## no subpages, so every action is at most one click from the open wheel.
const WHEEL_PAGES := {
	"mare": {
		"title": "Mare",
		"actions": ["show_data", "bed_offer", "bed_cuddle", "standing_offer", "cycle_heat",
			"cycle_diestrus"],
	},
	"act": {
		"title": "Act",
		"actions": ["show_data", "force_tolerance_warning", "force_tolerance_stop",
			"force_act_face"],
	},
}
const WHEEL_MAX_SLOTS := 6


## The wheel's root page for the current act state.
static func wheel_root(act_live: bool) -> String:
	return "act" if act_live else "mare"


## The action ids on one wheel page, in clockwise order.
static func wheel_actions(page: String) -> Array[String]:
	var out: Array[String] = []
	var entry: Variant = WHEEL_PAGES.get(page)
	if not entry is Dictionary:
		return out
	var actions: Variant = (entry as Dictionary).get("actions", [])
	if actions is Array:
		for name: Variant in actions:
			out.append(str(name))
	return out


static func wheel_title(page: String) -> String:
	var entry: Variant = WHEEL_PAGES.get(page)
	return str((entry as Dictionary).get("title", page)) if entry is Dictionary else page


## The action's full label, or the match label when the target is already in its `phase`.
static func action_label(name: String, main: Node) -> String:
	return _action_text(name, main, "label", "match_label")


## The action's compact label, or the match label when the target is already in its `phase`.
static func action_short(name: String, main: Node) -> String:
	return _action_text(name, main, "short", "match_short")


static func _action_text(name: String, main: Node, key: String, match_key: String) -> String:
	var entry: Variant = ACTIONS.get(name)
	if not entry is Dictionary:
		return name
	var action: Dictionary = entry
	var text := str(action.get(key, action.get("label", name)))
	var phase := str(action.get("phase", ""))
	if phase.is_empty():
		return text
	if not is_instance_valid(main) or not main.has_method("debug_cycle_phase"):
		return text
	if str(main.call("debug_cycle_phase")) != phase:
		return text
	return str(action.get(match_key, text))


## The action bound to a physical key code, or "" when none is. No action declares one today; the
## route stays for a future action that must fire while the world is unpaused.
static func hotkey_action(keycode: int) -> String:
	for name: String in ACTIONS:
		if int(ACTIONS[name].get("hotkey", 0)) == keycode:
			return name
	return ""


## Run one action on `target`. Returns its message, or "" when it cannot run.
static func run_action(name: String, target: Node) -> String:
	if not ACTIONS.has(name):
		return ""
	var method := str(ACTIONS[name].get("method", ""))
	if not is_instance_valid(target) or not target.has_method(method):
		return ""
	var result: Variant = target.call(method)
	return str(result) if result is String else ""


## The debug chin readout for one pony: her name and the applied angle, the head bone's world
## origin and direction, the chin bone and the snout. Pure formatting; the runtime applies the
## pose and prints the block.
static func chin_rows(pony: Node, angle_deg: float) -> Array[String]:
	var rows: Array[String] = []
	if not is_instance_valid(pony):
		return rows
	rows.append("pony=%s angle=%+.1f\u00b0" % [str(pony.name), angle_deg])
	var body: Variant = pony.get("skeleton")
	if body is Skeleton3D:
		var head_bone := (body as Skeleton3D).find_bone("pony_head")
		if head_bone >= 0:
			var head_pose := (body as Skeleton3D).get_bone_global_pose(head_bone)
			rows.append("head origin=%s dir=%s" % [
				str((body as Skeleton3D).global_transform * head_pose.origin),
				str(head_pose.basis.z)])
	var boop: Variant = pony.get("boop_node")
	var head_sk: Variant = boop.get("head_skeleton") if boop != null else null
	if head_sk is Skeleton3D:
		var chin_bone := (head_sk as Skeleton3D).find_bone("mFaceChin")
		if chin_bone >= 0:
			var chin_pose := (head_sk as Skeleton3D).get_bone_global_pose(chin_bone)
			rows.append("chin world=%s" % str((head_sk as Skeleton3D).global_transform * chin_pose.origin))
		if boop.has_method("nose_world"):
			rows.append("snout world=%s" % str(boop.call("nose_world")))
	return rows
