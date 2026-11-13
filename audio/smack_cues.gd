extends RefCounted
## Curated hand-on-flank smack variants. These stay out of the act cue table: the act
## installs one on the native `FlankTouch` sound player so the decal, blush,
## jiggle and reaction suppression stay on the stock impact. `hands/service.gd` lazy-loads
## the paths on the first smack, so an act with no smack loads no pack stream.
## A smack picks a variant at random and never repeats the previous one.

const PATHS := [
	"res://mods/unfplap/assets/audio/smack/hand_02.wav",
	"res://mods/unfplap/assets/audio/smack/hand_03.wav",
]
