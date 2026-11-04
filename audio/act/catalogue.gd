extends RefCounted
## Curated OpenNSFW act cues. Generated from audio/act/sources.json.
## Keep the arrays in filename order so the variant bags stay stable.

const PLAP_FIRM := [
	preload("res://mods/unfplap/audio/act/plap/firm_01.wav"),
	preload("res://mods/unfplap/audio/act/plap/firm_02.wav"),
	preload("res://mods/unfplap/audio/act/plap/firm_03.wav"),
	preload("res://mods/unfplap/audio/act/plap/firm_04.wav"),
	preload("res://mods/unfplap/audio/act/plap/firm_05.wav"),
	preload("res://mods/unfplap/audio/act/plap/firm_06.wav"),
	preload("res://mods/unfplap/audio/act/plap/firm_07.wav"),
]

const PLAP_ROUGH := [
	preload("res://mods/unfplap/audio/act/plap/rough_01.wav"),
	preload("res://mods/unfplap/audio/act/plap/rough_02.wav"),
	preload("res://mods/unfplap/audio/act/plap/rough_03.wav"),
	preload("res://mods/unfplap/audio/act/plap/rough_04.wav"),
	preload("res://mods/unfplap/audio/act/plap/rough_05.wav"),
	preload("res://mods/unfplap/audio/act/plap/rough_06.wav"),
	preload("res://mods/unfplap/audio/act/plap/rough_07.wav"),
]

const PLAP_STANDING := [
	preload("res://mods/unfplap/audio/act/plap/standing_01.wav"),
	preload("res://mods/unfplap/audio/act/plap/standing_02.wav"),
	preload("res://mods/unfplap/audio/act/plap/standing_03.wav"),
	preload("res://mods/unfplap/audio/act/plap/standing_04.wav"),
	preload("res://mods/unfplap/audio/act/plap/standing_05.wav"),
	preload("res://mods/unfplap/audio/act/plap/standing_06.wav"),
	preload("res://mods/unfplap/audio/act/plap/standing_07.wav"),
	preload("res://mods/unfplap/audio/act/plap/standing_08.wav"),
]

const SLIDE_IN := [
	preload("res://mods/unfplap/audio/act/slide/in_01.wav"),
	preload("res://mods/unfplap/audio/act/slide/in_02.wav"),
	preload("res://mods/unfplap/audio/act/slide/in_03.wav"),
	preload("res://mods/unfplap/audio/act/slide/in_04.wav"),
	preload("res://mods/unfplap/audio/act/slide/in_05.wav"),
	preload("res://mods/unfplap/audio/act/slide/in_06.wav"),
]

const SLIDE_OUT := [
	preload("res://mods/unfplap/audio/act/slide/out_01.wav"),
	preload("res://mods/unfplap/audio/act/slide/out_02.wav"),
	preload("res://mods/unfplap/audio/act/slide/out_03.wav"),
	preload("res://mods/unfplap/audio/act/slide/out_04.wav"),
	preload("res://mods/unfplap/audio/act/slide/out_05.wav"),
	preload("res://mods/unfplap/audio/act/slide/out_06.wav"),
]

const BED_IN := [
	preload("res://mods/unfplap/audio/act/bed/wood_in_01.wav"),
	preload("res://mods/unfplap/audio/act/bed/wood_in_02.wav"),
	preload("res://mods/unfplap/audio/act/bed/wood_in_03.wav"),
	preload("res://mods/unfplap/audio/act/bed/wood_in_04.wav"),
	preload("res://mods/unfplap/audio/act/bed/wood_in_05.wav"),
]

const BED_OUT := [
	preload("res://mods/unfplap/audio/act/bed/wood_out_01.wav"),
	preload("res://mods/unfplap/audio/act/bed/wood_out_02.wav"),
	preload("res://mods/unfplap/audio/act/bed/wood_out_03.wav"),
	preload("res://mods/unfplap/audio/act/bed/wood_out_04.wav"),
	preload("res://mods/unfplap/audio/act/bed/wood_out_05.wav"),
]

const FABRIC := [
	preload("res://mods/unfplap/audio/act/fabric/01.wav"),
	preload("res://mods/unfplap/audio/act/fabric/02.wav"),
	preload("res://mods/unfplap/audio/act/fabric/03.wav"),
	preload("res://mods/unfplap/audio/act/fabric/04.wav"),
	preload("res://mods/unfplap/audio/act/fabric/05.wav"),
	preload("res://mods/unfplap/audio/act/fabric/06.wav"),
	preload("res://mods/unfplap/audio/act/fabric/07.wav"),
	preload("res://mods/unfplap/audio/act/fabric/08.wav"),
]

const MOUTH_KISS := [
	preload("res://mods/unfplap/audio/act/mouth/kiss_01.wav"),
	preload("res://mods/unfplap/audio/act/mouth/kiss_02.wav"),
	preload("res://mods/unfplap/audio/act/mouth/kiss_03.wav"),
	preload("res://mods/unfplap/audio/act/mouth/kiss_04.wav"),
	preload("res://mods/unfplap/audio/act/mouth/kiss_05.wav"),
	preload("res://mods/unfplap/audio/act/mouth/kiss_06.wav"),
	preload("res://mods/unfplap/audio/act/mouth/kiss_07.wav"),
	preload("res://mods/unfplap/audio/act/mouth/kiss_08.wav"),
]

const CLIMAX_WET := [
	preload("res://mods/unfplap/audio/act/climax/wet_01.wav"),
	preload("res://mods/unfplap/audio/act/climax/wet_02.wav"),
	preload("res://mods/unfplap/audio/act/climax/wet_03.wav"),
	preload("res://mods/unfplap/audio/act/climax/wet_04.wav"),
]

const CLIMAX_VOICE := [
	preload("res://mods/unfplap/audio/act/voice/climax_01.wav"),
	preload("res://mods/unfplap/audio/act/voice/climax_02.wav"),
	preload("res://mods/unfplap/audio/act/voice/climax_03.wav"),
]

## group: foley | vocals. volume_db is the full-strength level; act_audio scales down
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
	"plap_standing": {
		"group": "foley", "streams": PLAP_STANDING, "voices": 4,
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
	"bed_wood_in": {
		"group": "foley", "streams": BED_IN, "voices": 3,
		"volume_db": -23.0, "cooldown": 0.1, "distance": 8.0,
		"pitch_min": 0.94, "pitch_max": 1.06,
	},
	"bed_wood_out": {
		"group": "foley", "streams": BED_OUT, "voices": 3,
		"volume_db": -23.0, "cooldown": 0.1, "distance": 8.0,
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
	"climax_wet": {
		"group": "climax", "streams": CLIMAX_WET, "voices": 2,
		"volume_db": -18.0, "cooldown": 0.5, "distance": 10.0,
		"pitch_min": 0.94, "pitch_max": 1.06,
	},
	"climax_voice": {
		"group": "vocals", "streams": CLIMAX_VOICE, "voices": 2,
		"volume_db": -18.0, "cooldown": 0.5, "distance": 10.0,
		"pitch_min": 0.94, "pitch_max": 1.06,
	},
}
