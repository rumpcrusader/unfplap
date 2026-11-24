@abstract
extends RefCounted
## The handover's read side: act values, dialogue calls and scene reads. The runtime implements it,
## and the handover only calls it.

const DIALOGUE := preload("res://mods/unfplap/dialogue/api.gd")


@abstract func runtime() -> Node


@abstract func pony() -> Node3D


@abstract func id() -> String


@abstract func act_live() -> bool


@abstract func restoring() -> bool


@abstract func state() -> int


@abstract func event_id() -> String


@abstract func depth() -> float


@abstract func climaxes() -> int


@abstract func max_climaxes() -> int


@abstract func satisfaction() -> float


@abstract func cue() -> String


@abstract func pose_view() -> Variant


@abstract func start_pose_id() -> String


@abstract func shape_name(shape_id: String) -> String


@abstract func reaction_line(reaction: int, event_id: String, fallback: String,
		valid: DIALOGUE.Validity) -> String


@abstract func validity(rule: Callable) -> DIALOGUE.Validity


@abstract func note_reaction(key: String, cue_text: String, until: float) -> void


@abstract func add_heat(amount: float) -> void


@abstract func set_cue_override(text: String) -> void


@abstract func set_face(smile: float) -> void


@abstract func status(text: String) -> void


@abstract func now() -> float


@abstract func reaction_max_age() -> float
