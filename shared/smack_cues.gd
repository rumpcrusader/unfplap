extends RefCounted
## Hand-smack variants shared by the act and the outside-act layer: paths, levels and pitch.

const PATHS := [
	"res://mods/unfplap/assets/audio/smack/hand_02.wav",
	"res://mods/unfplap/assets/audio/smack/hand_03.wav",
]
const VOLUME_DB := -7.0
## The outside-act layer plays above the act's own hand smack level.
const STOCK_VOLUME_DB := -4.0
const PITCH_MIN := 0.97
const PITCH_MAX := 1.03
