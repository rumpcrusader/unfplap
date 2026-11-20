extends RefCounted
## The typed anatomy context: one per pony, rewritten as the state changes.
## The controller and the act read only this object, never the runtime node.
## Host callbacks are the boundary for logging, the perf probe and the body-coat hook.
## See `docs/anatomy.md` (`## Architecture`).

var state := 0
## The runtime's pose read model; null outside an act.
var pose_view: Variant = null
var depth := 0.0
var penetration_m := 0.0
var climaxes := 0
var size_scale := 1.0
var auto_pace := 1.0
var fluid_ground_y := 0.0
var penetration_reach := 0.2
## Null outside a missionary act.
var bed_frame: Variant = null
var cycle_phase := "normal"
## Host callbacks; a missing one is a no-op.
var perf_note := Callable()
## No idle perf clock while this is false.
var perf_on := false
var body_coat_smack := Callable()


func perf(chunk: String, usec: int) -> void:
	if perf_note.is_valid():
		perf_note.call(chunk, usec)


func smack_body_coat() -> void:
	if body_coat_smack.is_valid():
		body_coat_smack.call()


func contact_kind() -> String:
	return str(pose_view.contact_kind) if pose_view != null else ""


func family() -> String:
	return str(pose_view.family) if pose_view != null else ""


func frame() -> String:
	return str(pose_view.frame) if pose_view != null else ""


func mouth_contact() -> bool:
	return contact_kind() == "mouth"


func face_contact() -> bool:
	return contact_kind() == "face"


## The frame drives the part inset and the family drives the trims, so a pose may share one
## without the other.
func bed_pose() -> bool:
	return frame() == "bed"


func missionary() -> bool:
	return family() == "bed"
