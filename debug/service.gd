extends RefCounted
## The Debug block's action buttons. An action is one entry in `ACTIONS`; `method` is called on the
## entry node. Actions are not settings: they run a one-off debug operation.

## Debug actions. `method` is called on the entry node. `tab` places the button in that tab's
## Debug block (`general` by default, or `anatomy`/`world`); a missing tab means General.
## Add an action here; it becomes a button in the matching Debug block automatically. Actions that share a
## `row` are drawn compactly on one line, captioned with `short`; consecutive entries with the same
## row must stay adjacent. The mod claims no global debug hotkeys: the game's F4/F9/F10/F11 dev
## tools stay usable, and a Debug block button is the only trigger.
const ACTIONS := {
	"reload_pose": {
		"label": "Reload posed base",
		"help": "Re-read poses/missionary_pose.json without restarting the game. A running act picks it up.",
		"method": "action_reload_pose",
	},
	"bed_offer": {
		"label": "Trigger bed offer",
		"help": "Force a missionary offer for the aimed or nearest mare.",
		"method": "action_bed_offer",
	},
	"standing_offer": {
		"label": "Trigger standing offer",
		"help": "Force a standing offer for the aimed or nearest mare.",
		"method": "action_standing_offer",
	},
	"force_heat": {
		"label": "Force heat",
		"help": "Put the aimed or nearest mare in heat for this session.",
		"method": "action_force_heat",
		"tab": "world",
		"row": "Cycle",
		"short": "Heat",
	},
	"force_diestrus": {
		"label": "Force diestrus",
		"help": "Turn the aimed or nearest mare off for this session.",
		"method": "action_force_diestrus",
		"tab": "world",
		"row": "Cycle",
		"short": "Diestrus",
	},
	"clear_cycle_override": {
		"label": "Clear forced cycle",
		"help": "Resume the aimed or nearest mare's automatic estrus cycle.",
		"method": "action_clear_cycle_override",
		"tab": "world",
		"row": "Cycle",
		"short": "Clear",
	},
	"reset_act_history": {
		"label": "Reset act history",
		"help": "Clear the aimed or nearest mare's long-term act history and hurt.",
		"method": "action_reset_act_history",
		"tab": "world",
		"row": "Act history",
		"short": "Reset",
	},
	"show_act_history": {
		"label": "Show act history",
		"help": "Print the aimed or nearest mare's act history to the debug log.",
		"method": "action_show_act_history",
		"tab": "world",
		"row": "Act history",
		"short": "Show",
	},
	"show_prompt_context": {
		"label": "Show prompt context",
		"help": "Print the mod's normal-dialogue, memory and relationship context for the aimed or nearest mare.",
		"method": "action_show_prompt_context",
	},
	"give_stool": {
		"label": "Give footstool",
		"help": "Add a footstool to Anon's briefcase.",
		"method": "action_give_stool",
	},
	"show_stool": {
		"label": "Show stool state",
		"help": "Print the aimed or nearest mare's live reach gap and footstool state.",
		"method": "action_show_stool",
	},
	"reset_act_prompts": {
		"label": "Reset act prompts",
		"help": "Remove saved act-line prompt overrides and return to the built-in prompts.",
		"method": "action_reset_act_prompts",
	},
	"force_tolerance_warning": {
		"label": "Force neglect warning",
		"help": "Trigger the active act's next neglect warning.",
		"method": "action_force_tolerance_warning",
		"tab": "world",
		"row": "Neglect",
		"short": "Warning",
	},
	"force_tolerance_stop": {
		"label": "Force neglect stop",
		"help": "Make the active mare stop the act through the neglect path.",
		"method": "action_force_tolerance_stop",
		"tab": "world",
		"row": "Neglect",
		"short": "Stop",
	},
	"pose_state": {
		"label": "Show pose state",
		"help": "Print which missionary base pose is in charge and where it put her.",
		"method": "action_show_pose_state",
	},
	"force_act_face": {
		"label": "Force act face",
		"help": "Cycle the game's expression faces on the active act or the aimed mare.",
		"method": "action_force_act_face",
		"row": "Act face",
		"short": "Next",
	},
	"show_act_face": {
		"label": "Show act face",
		"help": "Print the act face, director face, climax mode and mood face.",
		"method": "action_show_act_face",
		"row": "Act face",
		"short": "Inspect",
	},
	"skeleton_overlay": {
		"label": "Skeleton overlay",
		"help": "Toggle the skeleton overlay for nearby ponies.",
		"method": "toggle_skeleton_debug",
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
