extends RefCounted
## Shared face-points fake: the mutable mouth and opening pair the pose suites drive.

var mouth := Vector3.ZERO
var opening := Vector3.ZERO

func mouth_point() -> Vector3:
	return mouth

func opening_point() -> Vector3:
	return opening
