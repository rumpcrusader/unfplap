extends RefCounted
## Curated OpenNSFW hand-on-flank smack variants. These stay out of the act cue table: the act
## installs one on the native `FlankTouch` sound player so the decal, blush,
## jiggle and reaction suppression stay on the stock impact. `caress_control.gd` lazy-loads
## the paths on the first smack, so an act with no smack loads no pack stream.
## A smack picks a variant at random and never repeats the previous one.

const PATHS := [
	"res://mods/unfplap/audio/act/smack/hand_02.wav",
	"res://mods/unfplap/audio/act/smack/hand_03.wav",
]
