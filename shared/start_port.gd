@abstract
extends RefCounted
## The per-pony start handle: the hotkey and Agreement starts and the footstool hint. The runtime
## implements it; `offer`, `negotiation` and `initiation` read it. See `docs/runtime.md`.


@abstract func start_hotkey(pose: String, bed_in: Variant, act_source: String,
		skip_presentation: bool = false) -> bool


@abstract func start_agreement(handle: Object, skip_presentation: bool = false) -> int


@abstract func hint_stool() -> Dictionary
