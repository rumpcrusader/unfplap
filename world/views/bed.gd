extends RefCounted
## One rest-family node and the rows it answers. A member is bound to whichever of the bed, the
## couch or rest that owns it, one of its seats, or the seating system actually holds that row, so
## one view spans the family and each call names only the nodes that are not the receiver.

const GAME := preload("res://mods/unfplap/world/game.gd")

var _bed: Node


func _init(bed: Node) -> void:
	_bed = bed


func _bound() -> Node:
	return _bed


## The guest-seat transform a couch rest lays a pony at; an infinite origin when it cannot.
func couch_pony_transform(seat: Node3D) -> Transform3D:
	return GAME.couch_pony_transform(_bed as Node3D, seat)


## A couch rest's seats, as a typed copy; empty when it has fewer than two.
func couch_seats() -> Array[Node3D]:
	return GAME.couch_seats(_bed as Node3D)


## Open the couch rest for a guest; false without the op.
func couch_open() -> bool:
	return GAME.couch_open(_bed as Node3D)


## Invite a pony to the guest seat; false without the op or when it refuses.
func couch_invite(pony: Node3D, seat: Node3D) -> bool:
	return GAME.couch_invite(_bed as Node3D, pony, seat)


## The front stand point a couch rest reports; `Vector3.INF` without the op.
func couch_approach(seat: Node3D) -> Vector3:
	return GAME.couch_approach(_bed as Node3D, seat)


## Whether the couch rest measured that this mare fits.
func couch_mare_fits() -> bool:
	return GAME.couch_mare_fits(_bed as Node3D)


## When this pony's guest cooldown ends, in engine milliseconds; 0 when there is none.
func couch_cooldown_until(pony: Node3D) -> int:
	return GAME.couch_cooldown_until(_bed as Node3D, pony)


## The pony lying beside Anon on one couch seat; null without a partner or a live one.
func couch_partner(seat: Node) -> Node:
	return GAME.couch_partner(_bed, seat)


## A couch or rest node's own word for what it is; empty when it has no op.
func rest_word() -> String:
	return GAME.rest_word(_bed)


## The bed a couch or rest node resolves to; null when it has none.
func rest_bed() -> Node3D:
	return GAME.rest_bed_of(_bed)


## Let a bed rest re-measure its bed, seats and sleeper; nothing happens without the op.
func refresh() -> void:
	GAME.bed_rest_refresh(_bed)


## Whether the rest measured that this mare fits; false without the member.
func fits() -> bool:
	return GAME.bed_rest_fits(_bed)


## Whether the rest already holds a guest row; false without the member.
func has_guest() -> bool:
	return GAME.bed_rest_has_guest(_bed)


## The rest's current sleeper; null when the bed is free or the member is absent.
func sleeper() -> Node3D:
	return GAME.bed_rest_sleeper(_bed)


## The rest's front stand point for one pony; `Vector3.INF` when it cannot report one.
func front(pony: Node3D) -> Vector3:
	return GAME.bed_rest_front(_bed, pony)


## Whether the bed rest accepts this pony through its own gate; false without the op.
func accepts(pony: Node3D) -> bool:
	return GAME.bed_rest_accept(_bed, pony)


## Whether the bed rest judged this pony willing; false without the op.
func willing(pony: Node3D) -> bool:
	return GAME.bed_rest_willing(_bed, pony)


## Whether the bed rest judges this pony eligible; false without the op.
func eligible(pony: Node3D) -> bool:
	return GAME.bed_rest_eligible(_bed, pony)


## Whether a rest seat is free for this pony; false without the seat's op.
func seat_free_for(seat: Node, pony: Node3D) -> bool:
	return GAME.seat_free_for(seat, pony)


## The seating system's phase for this pony; empty when it has no entry.
func seating_phase(id: int) -> String:
	return GAME.seating_phase(_bed, id)


## Release this pony's seating entry; nothing happens without one.
func release_seat(id: int) -> void:
	GAME.seating_release_entry(_bed, id)


## End a couch's guest stay; a rest without the private op is left alone.
func finish_guest() -> void:
	GAME.couch_finish_guest(_bed as Node3D)


## Release a pony from a couch's occupant list.
func release_pony(id: int) -> void:
	GAME.couch_release_pony(_bed as Node3D, id)


## Mean drawn bedding height (world y) under `points`, over the physics top the caller measured.
func surface_top(points: Array[Vector3], fallback: float) -> float:
	return GAME.visible_top(_bed, points, fallback)


## The clear floor to step off this seat, through the stock exit probe; `Vector3.INF` when none.
func exit_point(body: Node, fallback: Vector3, height: float, radius: float) -> Vector3:
	return GAME.couch_exit(body, _bed as Node3D, fallback, height, radius)


## The stock bed rest that owns this bed, installed on first use; null when it cannot answer.
func stock_rest() -> Node3D:
	return GAME.stock_bed_rest(_bed)
