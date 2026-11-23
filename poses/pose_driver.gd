extends RefCounted
## The base the pose recipes and the oral delta extend.


## True when the driver splits its base from its overlays, so a pose with a delta runs the base,
## the delta and the overlay in that order. A whole-pose driver leaves this false.
func splits_base() -> bool:
	return false


## The whole pose at `weight`; a driver that splits its base overrides `apply_base` instead.
func apply(_rig, _sk: Skeleton3D, _weight: float, _state: Dictionary) -> void:
	pass


## The base half of a split driver. False when its asset or frame is unavailable, which skips the
## delta and leaves the overlay off the pose the base did not write.
func apply_base(_rig, _sk: Skeleton3D, _weight: float, _state: Dictionary) -> bool:
	return true


## The moveable overlay pass, after the base and its delta.
func apply_overlay(_rig, _sk: Skeleton3D, _weight: float, _state: Dictionary) -> void:
	pass


## The procedural delta that follows a base; only a delta driver overrides it.
func apply_delta(_rig, _sk: Skeleton3D, _weight: float, _state: Dictionary) -> void:
	pass
