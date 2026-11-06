extends RefCounted
## Tunable schema: every global setting the mod stores in settings.json, one entry per line.
##
## The key **is** the settings.json path (`thrust.travel`, `presentation.standing.smack.raise_m`).
## That is deliberate: no migration, and reading a value is one call in `tunables.gd`.
##
## Adding a tunable is one line here:
##   - `flag`   a boolean switch;
##   - `num`    an unbounded debug number (never clamped when read);
##   - `user_num` a player-facing number whose `low`/`high` are part of the contract and clamp;
##   - `choice` a string from a fixed list;
##   - `list`   a set of options stored as an array.
##
## `group` is the panel section. `"Standing › Smack"` renders as section `Standing` with the
## subheading `Smack`; entries render in the order they are written here, so put a line where it
## belongs. `tab` is `"settings"` for the player-facing page and `"debug"` otherwise.
##
## This file only holds data. Read and write through `tunables.gd`, draw through
## `tunables_ui.gd`; no other file may declare a settings widget.
## See TUNING.md.

const SETTINGS_TAB := "settings"
const DEBUG_TAB := "debug"

static var _cache: Dictionary = {}


## The whole schema in render order.
static func all() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	_cache = {
		# General
		"debug_logs": flag(false, "Debug logs",
			"Print the mod's diagnostics to the console.", "General"),

		# Player-facing controls (Settings tab).
		"features.hud_readouts": flag(true, "HUD readouts",
			"Show the mood cue and Wants/You line. Hearts and the afterglow close prompt stay visible.",
			"Controls", SETTINGS_TAB),
		"features.act_controls": flag(true, "Control hints",
			"Show the act's control list. Off keeps the cue and climax readouts.",
			"Controls", SETTINGS_TAB),
		"features.act_lines": flag(true, "Act lines",
			"Let her speak unprompted lines during sex. Off keeps normal dialogue and the HUD cue.",
			"Controls", SETTINGS_TAB),
		"features.act_history": flag(true, "Long-term history",
			"Remember how each act went; repeated good sex builds trust and desire, while repeated neglect makes her reluctant.",
			"Controls", SETTINGS_TAB),
		"features.captions_on_top": flag(true, "Captions on top",
			"Move the explicit bottom dialogue caption to the top. Overhead and auto captions are unchanged.",
			"Controls", SETTINGS_TAB),
		"relationship.promiscuity": choice("marefriend",
			["soulmates", "head_over_hooves", "marefriend", "new_couple", "crush", "any"],
			["Soulmates", "Head Over Hooves", "Marefriend / Coltfriend", "New Couple", "Crush", "Any Adult"],
			"Promiscuity", "Lowest relationship level for a lover bond and sex.",
			"Controls", SETTINGS_TAB),
		"relationship.sex_start": choice("when_available", ["when_available", "try_luck"],
			["When Available", "Try Your Luck"],
			"Starting Sex", "When Anon can start sex.",
			"Controls", SETTINGS_TAB),
		"features.mute_ponese_audio": flag(true, "Mute Ponese audio",
			"Keep the act's generated text but silence the Ponese voice for that act.",
			"Controls", SETTINGS_TAB),
		"thrust.orientation": choice("up", ["up", "down"], ["Deepens", "Shallows"],
			"Mouse up", "Mouse up deepens the thrust.", "Thrust", SETTINGS_TAB),
		"thrust.pixels_per_full": user_num(1000.0, "Sensitivity",
			"Mouse travel for one full thrust.", "Thrust", "px per full thrust",
			20.0, 1.0, 240.0, 1200.0, SETTINGS_TAB),
		"thrust.travel": user_num(0.5, "Hip back-off",
			"How far the hips retreat between thrusts.", "Thrust", "×",
			0.05, 1.0, 0.25, 2.0, SETTINGS_TAB),
		"auto_thrust.pace": user_num(1.5, "Auto pace",
			"Starting auto-thrust pace in thrusts per second. The mouse wheel changes it during an act.",
			"Thrust", "/s", 0.25, 1.0, 1.0, 4.5, SETTINGS_TAB),
		"auto_thrust.max_depth": user_num(0.9, "Auto depth",
			"Starting auto-thrust peak depth. Mouse up/down sets it during an act.",
			"Thrust", "%", 5.0, 100.0, 0.20, 1.0, SETTINGS_TAB),

		# Debug: features.
		"features.act_foley": flag(true, "Act foley",
			"Use the pack's thrust, slide, bed/fabric, mouth-kiss and flank-smack sounds. Off restores the current kiss-sample plap and the stock flank slap.",
			"Audio"),
		"features.act_vocals": flag(false, "Act vocals",
			"Add the pack moan only at her climax. Off keeps the pony breath, Ponese voice and current climax squeak unchanged.",
			"Audio"),
		"features.act_climax": flag(false, "Wet climax layer",
			"Add the pack wet finish sound at her climax. Off keeps only the current climax squeak.",
			"Audio"),
		"features.allow_act_during_cuddle": flag(true, "Allow acts during cuddles",
			"End an active cuddle when an act starts instead of blocking it.",
			"Act flow"),
		"features.act_ear_pin": flag(false, "Pinned act ears",
			"Debug: pin her ears back during acts. Off keeps the normal ear pose and still applies the act's blush, gaze and ear twitch.",
			"Act flow"),

		# Debug: camera and wobble.
		"features.idle_camera_sway": flag(false, "Idle camera sway",
			"Add a slow sway when you are not leaning.", "Camera"),
		"camera_thrust.surge": user_num(1.0, "Surge",
			"Forward camera travel on the inward stroke.", "Camera", "%",
			5.0, 100.0, 0.0, 1.0),
		"camera_thrust.bob": user_num(0.35, "Bob",
			"Vertical camera dip on the inward stroke.", "Camera", "%",
			5.0, 100.0, 0.0, 1.0),
		"jiggle.radius": num(0.26, "Radius",
			"Spread of the rump wobble across the flank.", "Thrust jiggle", "cm", 1.0, 100.0),
		"jiggle.intensity": num(0.25, "Intensity",
			"Thrust amount of the rump wobble.", "Thrust jiggle", "×", 0.05),
		"jiggle.smack_intensity": num(0.45, "Smack intensity",
			"Act-smack amount of the rump wobble.", "Thrust jiggle", "×", 0.05),

		# Debug: missionary.
		"presentation.missionary.forward": num(0.30, "Missionary forward",
			"Shift the frozen shot forward along her body.", "Missionary", "m", 0.01),
		"presentation.missionary.height": num(0.25, "Missionary height",
			"Raise the frozen shot.", "Missionary", "m", 0.01),
		"presentation.missionary.side": num(0.0, "Missionary side",
			"Shift the frozen shot sideways; positive is her right.", "Missionary", "m", 0.01),
		"presentation.missionary.pullback": num(0.22, "Missionary pullback",
			"Pull the shot back along its own view axis.", "Missionary", "m", 0.01),
		"presentation.missionary.side_lean": num(0.10, "Side lean forward",
			"Extra travel toward her head on a side lean.", "Missionary", "m", 0.01),
		"presentation.missionary.pitch_deg": num(-15.0, "Missionary pitch",
			"Tilt the frozen view; positive looks up.", "Missionary", "°", 0.5),
		"presentation.missionary.neck1_deg": num(0.0, "Neck 1 angle",
			"Bend pony_neck1 about the body right axis.", "Missionary › Neck angles", "°", 1.0),
		"presentation.missionary.neck2_deg": num(0.0, "Neck 2 angle",
			"Bend pony_neck2 about the body right axis.", "Missionary › Neck angles", "°", 1.0),
		"presentation.missionary.neck_roll_deg": num(0.0, "Neck roll",
			"Roll both neck bones about the body forward axis.", "Missionary › Neck angles", "°",
			1.0),
		"presentation.missionary.head_pitch_deg": num(0.0, "Head pitch",
			"Tilt the head about the body right axis after the gaze solve.",
			"Missionary › Neck angles", "°", 1.0),
		"presentation.missionary.head_roll_deg": num(13.0, "Head roll",
			"Roll the head last, in degrees.", "Missionary › Neck angles", "°", 1.0),
		"features.missionary_body_motion": flag(true, "Missionary body motion",
			"Slide her body along the bed and nod her head on the thrust.",
			"Missionary › Motion"),

		# Debug: standing.
		"presentation.standing.glance_back_speed": user_num(2.0, "Glance-back speed",
			"How fast a look-back glance eases in and out.",
			"Standing › Motion", "×", 0.05, 1.0, 0.25, 3.0),
		"presentation.standing.torso_angle_deg": num(6.0, "Anon torso lean",
			"Hinge Anon's upper body forward over her; the lower body stays planted.",
			"Standing › Motion", "°", 1.0),
		"presentation.standing.neck_down_deg": num(30.0, "Neck down",
			"Standing neck reach down/forward.", "Standing › Neck", "°", 1.0),
		"presentation.standing.chin_up_deg": num(30.0, "Chin up",
			"Standing head lift at the chin.", "Standing › Neck", "°", 1.0),
		"presentation.standing.tail.yaw_deg": num(31.5, "Tail aside (yaw)",
			"How far the standing tail sweeps aside from her centreline.", "Standing › Tail",
			"°", 1.0, 1.0, 0.0, 90.0),
		"presentation.standing.tail.pitch_deg": num(24.1, "Tail lift (pitch)",
			"How far the standing tail lifts up. Pairs with Tail aside.", "Standing › Tail",
			"°", 1.0, 1.0, 0.0, 90.0),
		"features.standing_body_sway": flag(true, "Standing body sway",
			"Move her upper body with the thrust while the forehooves stay planted.",
			"Standing › Motion"),
		"features.thrust_ear_twitch": flag(true, "Thrust ear twitch",
			"Flick both ears on some thrusts.", "Standing › Motion"),
		"features.standing_plant_feet": flag(true, "Plant Anon's lower body",
			"Hold Anon's hips and both feet at their act-start positions, 15 cm behind him. Off restores the game's stepping and lean foot motion.",
			"Standing › Motion"),
		"presentation.standing.kiss.mouth_right": num(0.0, "Kiss mouth right",
			"Anon's mouth target sideways at the kiss.", "Standing › Kiss", "cm", 0.5, 100.0),
		"presentation.standing.kiss.mouth_drop": num(0.0, "Kiss mouth down",
			"Anon's mouth target drop at the kiss.", "Standing › Kiss", "cm", 0.5, 100.0),
		"presentation.standing.kiss.mouth_forward": num(0.0, "Kiss mouth forward",
			"Anon's mouth target forward at the kiss.", "Standing › Kiss", "cm", 0.5, 100.0),
		"presentation.standing.kiss.camera_yaw_deg": num(7.0, "Kiss camera yaw",
			"Over-the-shoulder yaw toward her at the kiss.", "Standing › Kiss", "°", 1.0),
		"presentation.standing.kiss.lean_side": num(0.46, "Kiss side lean",
			"Sideways kiss lean toward the shoulder side.", "Standing › Kiss", "cm", 0.5, 100.0),
		"presentation.standing.kiss.lean_forward": num(0.03, "Kiss forward lean",
			"Forward kiss lean.", "Standing › Kiss", "cm", 0.5, 100.0),
		"presentation.standing.kiss.lean_drop": num(0.09, "Kiss lean drop",
			"How far he drops over her at the kiss.", "Standing › Kiss", "cm", 0.5, 100.0),
		"presentation.standing.caress.palm_distance": num(0.02, "Palm distance",
			"Palm centre distance from the coat.", "Standing › Caress", "cm", 0.5, 100.0),
		"presentation.standing.caress.oval_across_m": num(0.01, "Oval across",
			"Caress stroke length along the body.", "Standing › Caress", "cm", 0.5, 100.0),
		"presentation.standing.caress.oval_up_m": num(0.02, "Oval up",
			"Caress stroke height.", "Standing › Caress", "cm", 0.5, 100.0),
		"presentation.standing.caress.palm_scale.canon": num(0.75, "Palm scale (Canon)",
			"Standing hand scale for Canon-size Anon.", "Standing › Caress", "×", 0.01),
		"presentation.standing.caress.palm_scale.mounting": num(0.9,
			"Palm scale (Mounting)", "Standing hand scale for mounting size.",
			"Standing › Caress", "×", 0.01),
		"presentation.standing.caress.palm_scale.same height": num(1.0,
			"Palm scale (Same height)", "Standing hand scale at Anon's own height.",
			"Standing › Caress", "×", 0.01),
		"presentation.standing.caress.palm_scale.hoers": num(1.0, "Palm scale (Hoers)",
			"Standing hand scale for the Hoers size.", "Standing › Caress", "×", 0.01),
		"presentation.standing.caress.ignore": list(["tail", "wing"],
			["tail", "mane", "wing", "leg"], "Ignore body parts",
			"Regions the caress contact query skips.", "Standing › Caress"),
		"presentation.standing.smack.raise_m": num(0.30, "Max raise",
			"Hand lift at the top of the wind-up.", "Standing › Smack", "cm", 0.5, 100.0),
		"presentation.standing.smack.hind_m": num(0.09, "Hind offset",
			"Move the target toward her rump.", "Standing › Smack", "cm", 0.5, 100.0),
		"presentation.standing.smack.height_m": num(0.05, "Height",
			"Move the target up or down the cheek.", "Standing › Smack", "cm", 0.5, 100.0),
		"presentation.standing.smack.arc_m": num(0.1, "Palm arc",
			"Bow of the lift path toward her rump.", "Standing › Smack", "cm", 0.5, 100.0),
		"presentation.standing.smack.pitch_deg": num(0.0, "Palm pitch",
			"Pitch the raised palm down from the contact basis.", "Standing › Smack", "°", 1.0),
		"presentation.standing.smack.raise_speed": num(1.5, "Raise speed",
			"Wind-up speed in metres per second.", "Standing › Smack", "m/s", 0.1),
		"presentation.standing.smack.return_speed": num(3.0, "Return speed",
			"Strike speed in metres per second.", "Standing › Smack", "m/s", 0.1),

		# Debug: act history.
		"history.good_min": num(0.80, "Good threshold",
			"Fraction of the applicable actions that must go right for a good act.",
			"History › Score", "", 0.01, 1.0, 0.0, 1.0),
		"history.bad_max": num(0.20, "Bad threshold",
			"Fraction of the applicable actions at or below which an act is bad.",
			"History › Score", "", 0.01, 1.0, 0.0, 1.0),
		"history.w_climax": num(0.30, "Climax weight",
			"Score weight for her reaching climax.", "History › Score", "", 0.01, 1.0, 0.0, 1.0),
		"history.w_talk": num(0.20, "Talk weight",
			"Score weight for a talk-seeking mare hearing what she likes.",
			"History › Score", "", 0.01, 1.0, 0.0, 1.0),
		"history.w_touch": num(0.20, "Touch weight",
			"Score component for touch that matches her taste.", "History › Score", "", 0.01, 1.0, 0.0, 1.0),
		"history.w_motion": num(0.15, "Motion weight",
			"Weight for matching both of her motion preferences.", "History › Score", "", 0.01, 1.0, 0.0, 1.0),
		"history.w_not_early": num(0.15, "Not-early weight",
			"Weight for not ending before she finishes.", "History › Score", "", 0.01, 1.0, 0.0, 1.0),
		"history.p_dislike": num(0.10, "Dislike penalty",
			"Subtract per scored disliked touch or talk.", "History › Score", "", 0.01, 1.0, 0.0, 1.0),
		"history.p_severe": num(0.15, "Severe penalty",
			"Extra penalty for repeated disliked handling.", "History › Score", "", 0.01, 1.0, 0.0, 1.0),
		"history.p_silence": num(0.15, "Silence penalty",
			"Extra penalty for silent sex with a mare who likes to talk.", "History › Score", "", 0.01, 1.0, 0.0, 1.0),
		"history.p_miss": num(0.10, "Missed-preference penalty",
			"Extra penalty for a missed touch or movement preference.", "History › Score", "", 0.01, 1.0, 0.0, 1.0),
		"history.early_grace_s": num(20.0, "Early grace",
			"Seconds before an intentional early end counts as a summary.", "History › Score", "s", 1.0),
		"history.min_thrusts": num(2.0, "Minimum thrusts",
			"Real thrusts that make a very short act scoreable.", "History › Score", "", 1.0),

		"history.reminder_hurt": num(2.0, "Reminder at",
			"Hurt points at which she starts reminding Anon.", "History › Points", "", 1.0),
		"history.offer_block_hurt": num(4.0, "No offers at",
			"Hurt points at which she stops asking for sex.", "History › Points", "", 1.0),
		"history.withdraw_hurt": num(6.0, "Not tonight at",
			"Hurt points at which she gently refuses an act.", "History › Points", "", 1.0),
		"history.max_hurt": num(8.0, "Hurt cap", "Maximum stored hurt points.",
			"History › Points", "", 1.0),
		"history.max_comfort": num(8.0, "Comfort cap", "Maximum stored comfort points.",
			"History › Points", "", 1.0),
		"history.bad_hurt": num(1.0, "Bad hurt", "Hurt added by a bad act.",
			"History › Points", "", 1.0),
		"history.mild_hurt": num(1.0, "Early-end hurt",
			"Hurt added by a neutral early end.", "History › Points", "", 1.0),
		"history.severe_hurt": num(2.0, "Severe hurt", "Hurt added by a severe act.",
			"History › Points", "", 1.0),
		"history.good_comfort": num(1.0, "Good comfort", "Comfort added by a good act.",
			"History › Points", "", 1.0),
		"history.great_comfort": num(2.0, "Great comfort", "Comfort added by a great act.",
			"History › Points", "", 1.0),
		"history.good_repair": num(1.0, "Good repair", "Hurt removed by a good act.",
			"History › Points", "", 1.0),
		"history.great_repair": num(2.0, "Great repair", "Hurt removed by a great act.",
			"History › Points", "", 1.0),
		"history.apology_repair": num(1.0, "Apology repair",
			"Hurt removed by one sincere apology per day.", "History › Points", "", 1.0),
		"history.decay_days": num(2.0, "Decay days", "In-game days per hurt decay step.",
			"History › Points", "days", 0.5),
		"history.decay_amount": num(1.0, "Decay amount", "Hurt removed by one decay step.",
			"History › Points", "", 1.0),
		"history.offer_base_s": num(600.0, "Offer cooldown",
			"Base seconds between proactive offers.", "History › Offers", "s", 10.0),
		"history.offer_min_s": num(300.0, "Cooldown floor",
			"Shortest cooldown at high comfort.", "History › Offers", "s", 10.0),
		"history.offer_comfort_scale": num(0.05, "Comfort cooldown",
			"Cooldown reduction per comfort point.", "History › Offers", "", 0.01),
		"history.offer_weight_base": num(0.70, "Offer weight",
			"Base chance weight for a proactive offer.", "History › Offers", "", 0.01),
		"history.offer_weight_comfort": num(0.05, "Comfort weight",
			"Offer weight added per comfort point.", "History › Offers", "", 0.01),
		"history.offer_weight_hurt": num(0.12, "Hurt weight",
			"Offer weight removed per hurt point.", "History › Offers", "", 0.01),

		# Debug: tolerance (the per-mare tier is in Characters).
		"tolerance.timid_warning": num(4.0, "Timid warning",
			"Distress at which a timid mare gives her one warning.", "Tolerance", "", 1.0),
		"tolerance.neutral_warning_1": num(1.0, "Neutral warning 1",
			"First warning for a neutral mare.", "Tolerance", "", 1.0),
		"tolerance.neutral_warning_2": num(4.0, "Neutral warning 2",
			"Second warning for a neutral mare.", "Tolerance", "", 1.0),
		"tolerance.neutral_stop": num(10.0, "Neutral stop",
			"Distress at which a neutral mare stops the act.", "Tolerance", "", 1.0),
		"tolerance.strict_warning": num(1.0, "Strict warning",
			"Warning threshold for a strict mare.", "Tolerance", "", 1.0),
		"tolerance.strict_stop": num(3.0, "Strict stop",
			"Distress at which a strict mare stops the act.", "Tolerance", "", 1.0),
		"tolerance.dislike_amount": num(1.0, "Dislike amount",
			"Distress added by each actual disliked touch or talk.", "Tolerance", "", 0.1),
		"tolerance.like_relief": num(1.0, "Like relief",
			"Distress removed by each actual liked touch or talk.", "Tolerance", "", 0.1),
		"tolerance.decay_seconds": num(25.0, "Decay interval",
			"Seconds per passive distress decay step.", "Tolerance", "s", 1.0),
		"tolerance.decay_amount": num(1.0, "Decay amount",
			"Distress removed per decay step.", "Tolerance", "", 0.1),
		"tolerance.neutral_cooldown_s": num(300.0, "Neutral cooldown",
			"Sex-only cooldown after a neutral mare stops.", "Tolerance", "s", 10.0),
		"tolerance.strict_cooldown_s": num(600.0, "Strict cooldown",
			"Sex-only cooldown after a strict mare stops.", "Tolerance", "s", 10.0),

	}
	return _cache


static func has(path: String) -> bool:
	return all().has(path)


static func entry(path: String) -> Dictionary:
	var value: Variant = all().get(path, {})
	return value if value is Dictionary else {}


## The stored default, or null for an unknown path.
static func default_value(path: String) -> Variant:
	if not has(path):
		return null
	var value: Variant = entry(path).get("default")
	return (value as Array).duplicate() if value is Array else value


## Nested defaults under a dotted prefix, e.g. `default_block("presentation.standing.")`.
static func default_block(prefix: String) -> Dictionary:
	var out: Dictionary = {}
	for path: String in all():
		if path.begins_with(prefix):
			write_path(out, path.substr(prefix.length()), default_value(path))
	return out


## Section names for one tab, in schema order.
static func groups(tab: String) -> Array:
	var seen: Array = []
	for path: String in all():
		var item := entry(path)
		if str(item.get("tab", DEBUG_TAB)) != tab:
			continue
		var group := str(item.get("group", ""))
		if not group.is_empty() and not seen.has(group):
			seen.append(group)
	return seen


static func flag(on: bool, label: String, help: String, group: String,
		tab := DEBUG_TAB) -> Dictionary:
	return {"kind": "bool", "default": on, "label": label, "help": help,
		"group": group, "tab": tab}


## A debug number. `low`/`high` only shape the spin box; the stored value is never clamped.
## `scale` converts the stored value to the shown unit (metres shown as cm = 100).
static func num(value: float, label: String, help: String, group: String,
		unit := "", step := 0.0, scale := 1.0, low := -1000000.0, high := 1000000.0,
		tab := DEBUG_TAB) -> Dictionary:
	return {"kind": "num", "default": value, "label": label, "help": help, "group": group,
		"tab": tab, "unit": unit, "step": step, "scale": scale, "low": low, "high": high,
		"clamp": false}


## A player-facing number whose bounds are part of the setting's contract, so they clamp.
static func user_num(value: float, label: String, help: String, group: String,
		unit := "", step := 0.0, scale := 1.0, low := -1000000.0, high := 1000000.0,
		tab := DEBUG_TAB) -> Dictionary:
	var out := num(value, label, help, group, unit, step, scale, low, high, tab)
	out["clamp"] = true
	return out


static func choice(value: String, options: Array, labels: Array, label: String,
		help: String, group: String, tab := DEBUG_TAB) -> Dictionary:
	return {"kind": "choice", "default": value, "label": label, "help": help,
		"group": group, "tab": tab, "options": options, "labels": labels}


static func list(value: Array, options: Array, label: String, help: String,
		group: String) -> Dictionary:
	return {"kind": "list", "default": value, "label": label, "help": help,
		"group": group, "tab": DEBUG_TAB, "options": options}


## Write one dotted path into a nested dictionary, creating intermediate dictionaries.
static func write_path(root: Dictionary, path: String, value: Variant) -> void:
	var parts := path.split(".", false)
	if parts.is_empty():
		return
	var node: Dictionary = root
	for index: int in parts.size() - 1:
		var key := parts[index]
		var child: Variant = node.get(key)
		if not child is Dictionary:
			child = {}
			node[key] = child
		node = child
	node[parts[parts.size() - 1]] = value
