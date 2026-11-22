extends RefCounted
## Curated act cue table: the preloaded streams, each cue's level, cooldown, distance and pitch,
## and the pure rules that turn the stroke facts into one cue call. Generated from
## `audio/cue_sources.json`.

const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")

# Keep the arrays in filename order so the variant bags stay stable.
const PLAP_FIRM := [
	preload("res://mods/unfplap/assets/audio/plap/firm_01.wav"),
	preload("res://mods/unfplap/assets/audio/plap/firm_02.wav"),
	preload("res://mods/unfplap/assets/audio/plap/firm_03.wav"),
	preload("res://mods/unfplap/assets/audio/plap/firm_04.wav"),
	preload("res://mods/unfplap/assets/audio/plap/firm_05.wav"),
	preload("res://mods/unfplap/assets/audio/plap/firm_06.wav"),
	preload("res://mods/unfplap/assets/audio/plap/firm_07.wav"),
]

const PLAP_ROUGH := [
	preload("res://mods/unfplap/assets/audio/plap/rough_01.wav"),
	preload("res://mods/unfplap/assets/audio/plap/rough_02.wav"),
	preload("res://mods/unfplap/assets/audio/plap/rough_03.wav"),
	preload("res://mods/unfplap/assets/audio/plap/rough_04.wav"),
	preload("res://mods/unfplap/assets/audio/plap/rough_05.wav"),
	preload("res://mods/unfplap/assets/audio/plap/rough_06.wav"),
	preload("res://mods/unfplap/assets/audio/plap/rough_07.wav"),
]

const SLIDE_IN := [
	preload("res://mods/unfplap/assets/audio/slide/in_01.wav"),
	preload("res://mods/unfplap/assets/audio/slide/in_02.wav"),
	preload("res://mods/unfplap/assets/audio/slide/in_03.wav"),
	preload("res://mods/unfplap/assets/audio/slide/in_04.wav"),
	preload("res://mods/unfplap/assets/audio/slide/in_05.wav"),
	preload("res://mods/unfplap/assets/audio/slide/in_06.wav"),
]

const SLIDE_OUT := [
	preload("res://mods/unfplap/assets/audio/slide/out_01.wav"),
	preload("res://mods/unfplap/assets/audio/slide/out_02.wav"),
	preload("res://mods/unfplap/assets/audio/slide/out_03.wav"),
	preload("res://mods/unfplap/assets/audio/slide/out_04.wav"),
	preload("res://mods/unfplap/assets/audio/slide/out_05.wav"),
	preload("res://mods/unfplap/assets/audio/slide/out_06.wav"),
]

const FABRIC := [
	preload("res://mods/unfplap/assets/audio/fabric/01.wav"),
	preload("res://mods/unfplap/assets/audio/fabric/02.wav"),
	preload("res://mods/unfplap/assets/audio/fabric/03.wav"),
	preload("res://mods/unfplap/assets/audio/fabric/04.wav"),
	preload("res://mods/unfplap/assets/audio/fabric/05.wav"),
	preload("res://mods/unfplap/assets/audio/fabric/06.wav"),
	preload("res://mods/unfplap/assets/audio/fabric/07.wav"),
	preload("res://mods/unfplap/assets/audio/fabric/08.wav"),
]

const MOUTH_KISS := [
	preload("res://mods/unfplap/assets/audio/mouth/kiss_01.wav"),
	preload("res://mods/unfplap/assets/audio/mouth/kiss_02.wav"),
	preload("res://mods/unfplap/assets/audio/mouth/kiss_03.wav"),
	preload("res://mods/unfplap/assets/audio/mouth/kiss_04.wav"),
	preload("res://mods/unfplap/assets/audio/mouth/kiss_05.wav"),
	preload("res://mods/unfplap/assets/audio/mouth/kiss_06.wav"),
	preload("res://mods/unfplap/assets/audio/mouth/kiss_07.wav"),
	preload("res://mods/unfplap/assets/audio/mouth/kiss_08.wav"),
]

## group: foley. volume_db is the full-strength level; act_audio scales down
## with strength. voices is the number of overlapping 3D players for that cue.
const CUES := {
	"plap_firm": {
		"group": "foley", "streams": PLAP_FIRM, "voices": 4,
		"volume_db": -12.0, "cooldown": 0.05, "distance": 6.0,
		"pitch_min": 0.98, "pitch_max": 1.02,
	},
	"plap_rough": {
		"group": "foley", "streams": PLAP_ROUGH, "voices": 4,
		"volume_db": -12.0, "cooldown": 0.05, "distance": 6.0,
		"pitch_min": 0.98, "pitch_max": 1.02,
	},
	"slide_in": {
		"group": "foley", "streams": SLIDE_IN, "voices": 3,
		"volume_db": -30.0, "cooldown": 0.08, "distance": 6.0,
		"pitch_min": 0.94, "pitch_max": 1.06,
	},
	"slide_out": {
		"group": "foley", "streams": SLIDE_OUT, "voices": 3,
		"volume_db": -28.0, "cooldown": 0.08, "distance": 6.0,
		"pitch_min": 0.94, "pitch_max": 1.06,
	},
	"fabric": {
		"group": "foley", "streams": FABRIC, "voices": 3,
		"volume_db": -28.0, "cooldown": 0.12, "distance": 6.0,
		"pitch_min": 0.94, "pitch_max": 1.06,
	},
	"mouth_kiss": {
		"group": "foley", "streams": MOUTH_KISS, "voices": 2,
		"volume_db": -24.0, "cooldown": 0.3, "distance": 4.0,
		"pitch_min": 0.94, "pitch_max": 1.06,
	},
}

## The defaulted-plap argument's contact window: his skin must reach her coat.
const CONTACT_GAP_M := 0.0
## The withdraw cue fires when the depth crosses back out.
const WITHDRAW_DEPTH := 0.22
## Full-strength cue level is lowered by this much at strength 0.
const STRENGTH_GAIN_DB := 10.0
## The oral turn's kiss cue level, matching the stock soft kiss.
const ORAL_KISS_DB := -22.0
## One generated vocal per this many seconds of act, however fast the stroke.
const VOCAL_COOLDOWN_S := 3.0
## Her body's own vocal level under the spoken line.
const VOCAL_DB := -34.0


static func tier_for(strength: float) -> String:
	return PREFERENCES.intensity_for(strength)


static func cue_for_plap(tier: String) -> String:
	if tier.is_empty():
		return ""
	return "plap_" + tier


## Bed and fabric only belong to the bed profile; standing plays none.
static func uses_bed(profile: String) -> bool:
	return profile == "missionary"


## Couch, sofa and cloth are the soft surfaces that get the fabric layer.
static func soft_surface(name_lower: String) -> bool:
	return "couch" in name_lower or "sofa" in name_lower or "cloth" in name_lower


## Plap level follows the physical strength; the tier already carries speed and contact.
static func plap_volume_db(strength: float) -> float:
	return lerpf(-10.0, 0.0, clampf(strength, 0.0, 1.0))


## A body slap that only reaches her coat sits this many dB under a bottomed-out one; `contact`
## is 0 at the window's edge and 1 at the deepest point.
static func plap_contact_db(contact: float) -> float:
	return lerpf(-8.0, 0.0, clampf(contact, 0.0, 1.0))


static func pitch_for(strength: float) -> float:
	return clampf(1.0 + (clampf(strength, 0.0, 1.0) - 0.5) * 0.10, 0.9, 1.1)
