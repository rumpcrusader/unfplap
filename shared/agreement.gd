extends RefCounted
## The Act Negotiation's Agreement package and the opaque handle the Act service receives. The
## Negotiation service is the only writer: it builds the package once, freezes it and closes it
## through its one close path. The Act service reads the handle id, the frozen values it needs and
## calls `cancel`; it never mutates the package. Pure data: no scene reads, no service, no clock.

const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const CLEARANCE := preload("res://mods/unfplap/shared/clearance.gd")
const CONTEXT := preload("res://mods/unfplap/shared/context.gd")

## The route that formed the Agreement.
enum Trigger { MARE_OFFER, ANON_OFFER, HOTKEY_MATCH }

## How an Agreement ended. The Negotiation service maps these to the terminal outcome.
enum End { NONE, STARTED, START_FAILED, EXPIRED, INTERRUPTED, CANCELLED }

## The two TTLs.
const OFFER_TTL_S := 120.0
const AGREEMENT_TTL_S := 120.0

## Interruption reasons a handle cancel or a stage close may carry.
const REASON_PRIVACY := "privacy"
const REASON_POSE := "pose"
const REASON_HOTKEY := "hotkey"
const REASON_TARGET_LEFT := "target_left"
const REASON_CANCELLED := "cancelled"
const REASON_COUNTER_OFFER := "counter_offer"
const REASON_LOCKED := "locked"
const REASON_REASONING_FAILED := "reasoning_failed"
const REASON_CLASSIFIER_UNAVAILABLE := "classifier_unavailable"
const REASON_NO_CONTEXT_POSE := "no_context_pose"
const REASON_OCCUPIED := "occupied"


## The complete frozen package. Every field is set at formation; the service never rewrites one.
class Package:
	var id := 0
	var generation := 0
	var runtime: Node = null
	var pony: Node3D = null
	var pony_id := ""
	var option: POSE_OPTIONS.Option = null
	var private := false
	var clearance: CLEARANCE.Result = null
	var context: CONTEXT.Context = null
	var answer := ""
	var pose_profile_ok := true
	var pose_source_ok := true
	var accepted_at := 0.0
	var ttl_s := AGREEMENT_TTL_S
	var hold_token := ""
	var hold_old_wander := true
	var trigger := Trigger.MARE_OFFER
	var classifier_scope := ""
	var offer_line := ""

	func expires_at() -> float:
		return accepted_at + ttl_s

	func expired(now: float) -> bool:
		return now >= expires_at()

	func option_key() -> String:
		return option.key() if option != null else ""

	## The hotkey match: the same mare and the exact pose option `(pose, source, bed, cuddle)`.
	func matches(target: Node, option_in: POSE_OPTIONS.Option) -> bool:
		if not is_instance_valid(pony) or pony != target or option == null or option_in == null:
			return false
		return option.matches(option_in.pose, option_in.source, option_in.bed, option_in.cuddle)


## The opaque handle. The cancel callback is bound to the id and generation, so a late handle
## cannot touch a newer Agreement; clearance, Context and the scope stay inside the service.
class Handle:
	var id := 0
	var generation := 0
	var pony: Node3D = null
	var pony_id := ""
	var option: POSE_OPTIONS.Option = null
	var private := false
	var pose_profile_ok := true
	var pose_source_ok := true
	var hold_token := ""
	var hold_old_wander := true
	var trigger := Trigger.MARE_OFFER
	var cancel: Callable

	func valid() -> bool:
		return id > 0 and generation > 0 and cancel.is_valid()
