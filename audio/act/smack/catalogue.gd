extends RefCounted
## Curated OpenNSFW hand-on-flank smack variants. These stay out of the optional act cue
## table: the act installs one on the native `FlankTouch` sound player so the decal, blush,
## jiggle and reaction suppression stay on the stock impact. `standing_caress.gd` lazy-loads
## the paths only when `act_foley` is on, so an act with pack foley off loads no pack stream.
## A smack picks a variant at random and never repeats the previous one.

const PATHS := [
	"res://mods/unfplap/audio/act/smack/hand_01.wav",
	"res://mods/unfplap/audio/act/smack/hand_02.wav",
	"res://mods/unfplap/audio/act/smack/hand_03.wav",
]
