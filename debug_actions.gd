extends RefCounted
## The Debug block's action buttons and their hotkeys. An action is one entry in `ACTIONS`; `method`
## is called on the entry node. Actions are not settings: they run a one-off debug operation.
## Add a hotkey only when the action must fire while the world is unpaused.

## Debug actions. `method` is called on the entry node. `tab` places the button in that tab's
## Debug block (`general` by default, or `anatomy`/`world`); a missing tab means General.
## Add an action here; it becomes a button in the matching Debug block automatically. Actions that share a
## `row` are drawn compactly on one line, captioned with `short`; consecutive entries with the same
## row must stay adjacent. A hotkey is the exception, not the default: only add one when the action
## must fire while the world is unpaused and you are looking at the scene (the skeleton overlay is
## the example). `panel: false` keeps a hotkey-only action out of the button list.
const ACTIONS := {
	"reload_pose": {
		"label": "Reload posed base",
		"help": "Re-read poses/missionary_pose.json without restarting the game. A running act picks it up.",
		"method": "action_reload_pose",
		"hotkey": KEY_F4,
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
	"grant_lover_bond": {
		"label": "Grant lover bond",
		"help": "Give the aimed or nearest eligible mare the mod lover bond.",
		"method": "action_grant_lover_bond",
		"tab": "world",
		"row": "Lover bond",
		"short": "Grant",
	},
	"clear_lover_bond": {
		"label": "Clear lover bond",
		"help": "Clear the aimed or nearest mare's mod lover bond.",
		"method": "action_clear_lover_bond",
		"tab": "world",
		"row": "Lover bond",
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
	"skeleton_overlay": {
		"label": "Skeleton overlay",
		"help": "Toggle the F10 skeleton overlay.",
		"method": "toggle_skeleton_debug",
		"hotkey": KEY_F10,
		"panel": false,
	},
	# integration: local anatomy placement calibration.
	"anatomy_up": {"label": "Anatomy up", "help": "Move the aimed mare's anatomy up 5 mm.",
		"method": "action_anatomy_up",
		"tab": "anatomy",
		"row": "Anatomy place", "short": "Up"},
	"anatomy_down": {"label": "Anatomy down", "help": "Move the aimed mare's anatomy down 5 mm.",
		"method": "action_anatomy_down",
		"tab": "anatomy",
		"row": "Anatomy place", "short": "Down"},
	"anatomy_forward": {"label": "Anatomy forward", "help": "Move the anatomy forward 5 mm.",
		"method": "action_anatomy_forward",
		"tab": "anatomy",
		"row": "Anatomy place", "short": "Forward"},
	"anatomy_back": {"label": "Anatomy back", "help": "Move the anatomy back 5 mm.",
		"method": "action_anatomy_back",
		"tab": "anatomy",
		"row": "Anatomy place", "short": "Back"},
	"anatomy_pitch_up": {"label": "Anatomy pitch up", "help": "Pitch the anatomy up 1 degree.",
		"method": "action_anatomy_pitch_up",
		"tab": "anatomy",
		"row": "Pitch and size", "short": "Pitch +"},
	"anatomy_pitch_down": {"label": "Anatomy pitch down", "help": "Pitch down 1 degree.",
		"method": "action_anatomy_pitch_down",
		"tab": "anatomy",
		"row": "Pitch and size", "short": "Pitch −"},
	"anatomy_scale_up": {"label": "Anatomy bigger", "help": "Scale the anatomy up by 0.02.",
		"method": "action_anatomy_scale_up",
		"tab": "anatomy",
		"row": "Pitch and size", "short": "Bigger"},
	"anatomy_scale_down": {"label": "Anatomy smaller", "help": "Scale the anatomy down by 0.02.",
		"method": "action_anatomy_scale_down",
		"tab": "anatomy",
		"row": "Pitch and size", "short": "Smaller"},
	"anatomy_save": {"label": "Save anatomy place", "help": "Save this mare's placement.",
		"method": "action_anatomy_save",
		"tab": "anatomy",
		"row": "Anatomy file", "short": "Save"},
	"anatomy_reset": {"label": "Reset anatomy place", "help": "Restore the default placement.",
		"method": "action_anatomy_reset",
		"tab": "anatomy",
		"row": "Anatomy file", "short": "Reset"},
}


## The action bound to a physical key code, or "" when none is.
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
