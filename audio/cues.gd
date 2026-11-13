extends RefCounted
## Curated act cue table. Generated from audio/cue_sources.json.
## Keep the arrays in filename order so the variant bags stay stable.

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

const CLIMAX_WET := [
	preload("res://mods/unfplap/assets/audio/climax/wet_01.wav"),
	preload("res://mods/unfplap/assets/audio/climax/wet_02.wav"),
	preload("res://mods/unfplap/assets/audio/climax/wet_03.wav"),
	preload("res://mods/unfplap/assets/audio/climax/wet_04.wav"),
]

## group: foley | climax. volume_db is the full-strength level; act_audio scales down
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
	"climax_wet": {
		"group": "climax", "streams": CLIMAX_WET, "voices": 2,
		"volume_db": -18.0, "cooldown": 0.5, "distance": 10.0,
		"pitch_min": 0.94, "pitch_max": 1.06,
	},
}
