@abstract
extends RefCounted
## The per-pony presentation handle: the footstool reads, the scene hold and the standing
## presentation the offer reads and clears.

## The default "no stool pair" for a call that found no per-act handle.
const NO_STOOL_PAIR := Vector2i(-1, -1)


@abstract func stool_pair(pose: String) -> Vector2i


@abstract func stool_gap_m() -> float


@abstract func stool_needed_count() -> int


@abstract func stool_case_count() -> int


@abstract func stool_state_text() -> String


@abstract func hold_handle() -> Node


@abstract func present_standing() -> bool


@abstract func presentation_active() -> bool


@abstract func presentation_settled() -> bool


@abstract func clear_presentation() -> void


@abstract func rump_anchor() -> Vector3
