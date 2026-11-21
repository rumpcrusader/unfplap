@abstract
extends "res://mods/unfplap/body_change/values_port.gd"
## The typed host for the body-change handover: the read contract plus the one swap-seam handle.
## The runtime implements it once per pony; `body_change/act.gd` reads it.

const SWAP_PORT := preload("res://mods/unfplap/body_change/swap_port.gd")


@abstract func swap() -> SWAP_PORT
