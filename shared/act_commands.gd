extends RefCounted
## The act's command vocabulary: one stable id per act command. Pure data: no scene, no service,
## no settings read, no file and no clock. `shared/pose_specs.gd` builds each pose's control profile
## from these ids, `input/service.gd` emits the discrete ones and `runtime.gd` dispatches them.

const THRUST := "thrust"
const LEAN := "lean"
const CARESS := "caress"
const KISS := "kiss"
const ORAL := "oral"
const HOLE := "hole"
const POSE_BACK := "pose_back"
const POSE_FORWARD := "pose_forward"
const END := "end"

## The whole vocabulary. `CONTINUOUS` and `DISCRETE` partition it.
const ALL := [THRUST, LEAN, CARESS, KISS, ORAL, HOLE, POSE_BACK, POSE_FORWARD, END]
## The ids the act samples every frame; they are not dispatched through `runtime.command()`.
const CONTINUOUS := [THRUST, LEAN, CARESS, KISS]
## The ids one key press or one request emits.
const DISCRETE := [ORAL, HOLE, POSE_BACK, POSE_FORWARD, END]


## True for a known id.
static func is_command(id: String) -> bool:
	return id in ALL


## True for a per-frame sampled id.
static func is_continuous(id: String) -> bool:
	return id in CONTINUOUS


## True only for `end`. The act-key hold, not this command, owns the act exit.
static func is_reserved(id: String) -> bool:
	return id == END
