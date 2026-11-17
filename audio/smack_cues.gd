extends RefCounted
## Curated hand-on-flank smack variants. These stay out of the act cue table: the act
## installs one on the native `FlankTouch` sound player so the decal, blush,
## jiggle and reaction suppression stay on the stock impact, and the outside-act layer wraps
## both in one randomizer on the same player. `hands/smack.gd` lazy-loads the paths on the first
## smack, so an act with no smack loads no pack stream. A smack picks a variant at random and
## never repeats the previous one.

const PATHS := [
	"res://mods/unfplap/assets/audio/smack/hand_02.wav",
	"res://mods/unfplap/assets/audio/smack/hand_03.wav",
]
const VOLUME_DB := -7.0
const PITCH_MIN := 0.97
const PITCH_MAX := 1.03
