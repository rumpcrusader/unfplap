extends RefCounted
## The act snapshot's reaction tuning; `configure()` reads one instance per act.

var pose_family := ""
var size_scale := 1.0
var climax_seconds := 5.0
var jiggle_radius := 0.0
var jiggle_center_height := 0.0
var jiggle_center_back := 0.0
var jiggle_intensity := 0.0
var jiggle_smack_intensity := 0.0


## Read one act snapshot: the settings block plus the camera size and the act's climax length.
func fill(block: Dictionary, family: String, size: float, climax: float) -> void:
	pose_family = family
	size_scale = size
	climax_seconds = climax
	jiggle_radius = float(block["radius"])
	jiggle_center_height = float(block["center_height_m"])
	jiggle_center_back = float(block["center_back_m"])
	jiggle_intensity = float(block["intensity"])
	jiggle_smack_intensity = float(block["smack_intensity"])
