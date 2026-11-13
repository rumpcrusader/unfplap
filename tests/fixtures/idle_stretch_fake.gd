extends SkeletonModifier3D
## Test stand-in for Idle Life's `idle_pose.gd`. It exposes the five fields the stretch adapter
## drives and records nothing else; it never poses a bone.

var mare: Node3D
var idle := ""
var side := 1.0
var time := 0.0
var fade := 1.0
var passes := 0


func _process_modification_with_delta(_delta: float) -> void:
	passes += 1