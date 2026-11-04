extends RefCounted
## Curated OpenNSFW hand-on-flank smack variants. These stay out of the optional act cue
## table: the act installs one on the native `FlankTouch` sound player so the decal, blush,
## jiggle and reaction suppression stay on the stock impact. `standing_caress.gd` lazy-loads
## the paths only when `act_foley` is on, so an act with pack foley off loads no pack stream.
##
## `presentation.standing.smack.sound` picks one of these. The original mix keeps the three
## existing hand variants and stays the default; the alternatives are dry cuts from the pack's
## spank and skin-slap sources for trying out.

const DEFAULT_ID := "pack"

const OPTIONS := [
	{
		"id": "pack",
		"label": "Original mix",
		"paths": [
			"res://mods/unfplap/audio/act/smack/hand_01.wav",
			"res://mods/unfplap/audio/act/smack/hand_02.wav",
			"res://mods/unfplap/audio/act/smack/hand_03.wav",
		],
	},
	{
		"id": "spank_021",
		"label": "Spank 021",
		"paths": ["res://mods/unfplap/audio/act/smack/alt_spank_021.wav"],
	},
	{
		"id": "spank_020",
		"label": "Spank 020",
		"paths": ["res://mods/unfplap/audio/act/smack/alt_spank_020.wav"],
	},
	{
		"id": "spank_025",
		"label": "Spank 025",
		"paths": ["res://mods/unfplap/audio/act/smack/alt_spank_025.wav"],
	},
	{
		"id": "skin_14",
		"label": "Solid skin 14",
		"paths": ["res://mods/unfplap/audio/act/smack/alt_skin_14.wav"],
	},
	{
		"id": "skin_09",
		"label": "Solid skin 09",
		"paths": ["res://mods/unfplap/audio/act/smack/alt_skin_09.wav"],
	},
	{
		"id": "spank_21",
		"label": "SpankSlap 21",
		"paths": ["res://mods/unfplap/audio/act/smack/alt_spank_21.wav"],
	},
]


static func valid_id(id: String) -> bool:
	for option: Dictionary in OPTIONS:
		if str(option.get("id", "")) == id:
			return true
	return false


static func paths_for(id: String) -> Array:
	for option: Dictionary in OPTIONS:
		if str(option.get("id", "")) == id:
			return option.get("paths", [])
	return (OPTIONS[0] as Dictionary).get("paths", [])


static func label_for(id: String) -> String:
	for option: Dictionary in OPTIONS:
		if str(option.get("id", "")) == id:
			return str(option.get("label", id))
	return str((OPTIONS[0] as Dictionary).get("label", DEFAULT_ID))
