extends RefCounted
## Typed `camera_thrust` values.


## The two amplitudes the thrust shot scales by, read once at the act start.
class Config extends RefCounted:
	var surge := 1.0
	var bob := 1.0

	## Read the complete block; a missing key is a wiring bug, not a fallback case.
	static func from_dict(block: Dictionary) -> Config:
		var out := Config.new()
		out.surge = float(block["surge"])
		out.bob = float(block["bob"])
		return out
