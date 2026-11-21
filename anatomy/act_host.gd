@abstract
extends RefCounted
## The typed host boundary for one act's anatomy bridge: the runtime implements these reads and
## commands once per pony. The bridge receives the anatomy and eligibility facades separately.


@abstract func pony() -> Node


@abstract func runtime() -> Node


@abstract func reactions() -> Variant


## The world facades the bridge asks; the runtime returns the live instances.
@abstract func anatomy_service() -> Variant


@abstract func eligibility_service() -> Variant


@abstract func state() -> int


@abstract func pose_view() -> Variant


@abstract func depth() -> float


@abstract func penetration_m() -> float


@abstract func penetration_reach() -> float


@abstract func climaxes() -> int


@abstract func size_scale() -> float


@abstract func auto_pace() -> float


@abstract func fluid_ground_y() -> float


@abstract func cycle_phase() -> String


@abstract func bed_frame() -> Variant


@abstract func body_coat_smack() -> Callable


@abstract func status() -> Callable


@abstract func command() -> Callable


@abstract func missionary_camera() -> Variant


@abstract func kiss_controller() -> Variant


@abstract func pose() -> Variant


@abstract func thrust_move() -> Callable


@abstract func now_s() -> float


@abstract func set_penetration_m() -> Callable


@abstract func align() -> Callable


@abstract func touch() -> Callable


@abstract func vr_scene() -> Variant


@abstract func pony_callable() -> Callable
