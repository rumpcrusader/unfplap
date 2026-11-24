extends "res://mods/unfplap/shared/service.gd"
## Scope: world
## The act frame: the live runtime, the serial floor and the one pending body swap.
##
## A suite or a bare runtime may hold no owner instance and reads as no act, so nothing here needs a
## stand-in.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const OFFER := preload("res://mods/unfplap/offer/api.gd")
const STOCK_SMACK := preload("res://mods/unfplap/stock_smack/api.gd")


## The one suspended act: the runtime, the body it is leaving and the change that asked.
class Swap extends RefCounted:
	var runtime: Node = null
	var old_pony: Node = null
	var id := ""
	var change: BODY_CHANGE = null


## Handed over once by the composition root; a null peer is a no-op.
var _offer: OFFER = null
var _stock_smack: STOCK_SMACK = null
## The runtime of the live act, or null.
var _active: Node = null
## The last serial this process issued, kept as a floor under the stored one.
var _serial_issued := 0
## The one suspended act awaiting the body its source is building.
var _swap: Swap = null


## Takes the frame's two peers; the composition root is the only caller.
func wire(offer: OFFER, stock_smack: STOCK_SMACK) -> void:
	_offer = offer
	_stock_smack = stock_smack


## An act took the frame: the idle offer is cleared and the smack layer starts.
func set_active(runtime: Node) -> void:
	_active = runtime
	if is_instance_valid(_offer):
		_offer.clear_current()
	if is_instance_valid(_stock_smack):
		_stock_smack.act_start(runtime.get("pony"))


## The act ended, or a world close: the frame is free again.
func clear_active(runtime: Node) -> void:
	if _active == runtime:
		_active = null
		if is_instance_valid(_stock_smack):
			_stock_smack.act_end(runtime.get("pony"))


## The live act's runtime, or null.
func active() -> Node:
	return _active if is_instance_valid(_active) else null


## An act owns the frame; every starter gates on it.
func act_running() -> bool:
	return is_instance_valid(_active)


## The next serial for a new act, stored under the `unfplap.serial` key.
## The process's last value outranks a stale store, so no serial repeats.
func allocate_serial() -> int:
	var section := WORLD.mods().state("unfplap")
	_serial_issued = maxi(int(section.rows.get("serial", 0)), _serial_issued) + 1
	section.rows["serial"] = _serial_issued
	WORLD.mods().save()
	return _serial_issued


## Record the act's one pending body swap. The runtime keeps the act; this record only lets the new
## body's spawn find it before a second runtime is created.
func begin_body_swap(runtime: Node, old_pony: Node, id: String, change: BODY_CHANGE) -> void:
	if not is_instance_valid(runtime) or change == null:
		return
	var swap := Swap.new()
	swap.runtime = runtime
	swap.old_pony = old_pony
	swap.id = id
	swap.change = change
	_swap = swap


## The swap finished, failed or the act ended. Idempotent and scoped to the runtime.
func clear_body_swap(runtime: Node) -> void:
	if _swap != null and _swap.runtime == runtime:
		_swap = null


## True while a suspended act waits for its new body.
func body_swap_pending() -> bool:
	return _swap != null


## The suspended act's record for the roster, or null.
## While this names a body as the old one, the roster leaves that body out of its live list: its
## act is already moving to the new body, so the old one must not read as a live act anymore.
func pending_swap() -> Swap:
	return _swap


## A world started: the old world's pending swap is dropped.
func on_world(_host: Node) -> void:
	_swap = null


## The world closed: its swap goes with it. A live act is not force-stopped here; its runtime
## leaves with its body, so `active()` then answers null.
func on_world_closed() -> void:
	_swap = null


## The entry is leaving: drop the frame, the swap and the serial floor.
func shutdown() -> void:
	_active = null
	_swap = null
	_serial_issued = 0
	_offer = null
	_stock_smack = null
