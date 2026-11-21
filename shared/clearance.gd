extends RefCounted
## Pure Base clearance for act negotiation: the gates that run once per route, at offer formation
## and at hotkey attempt. The caller gathers the plain values; this file reads no service, scene,
## setting, clock or file. Contract: `docs/act_gate.md` (`## Base clearance`).

const REASON_ELIGIBLE := "eligibility"
const REASON_RELATIONSHIP := "relationship"
const REASON_AVAILABLE := "available"


## The typed answer. `reasons` names every failed row, in row order, and is empty when cleared.
class Result:
	var eligible := false
	var relationship_ok := false
	var available := false
	var reasons: PackedStringArray = []

	## True when every row passed.
	func ok() -> bool:
		return reasons.is_empty()

	## The first failed row, or an empty string.
	func reason() -> String:
		return "" if reasons.is_empty() else str(reasons[0])

	## The failed rows joined for a log line.
	func reasons_text() -> String:
		return "none" if reasons.is_empty() else ",".join(reasons)


## Combine the three rows. `eligible` is the eligibility service's `eligible?` answer consumed
## as a boolean; this module never inspects its rows.
static func evaluate(eligible: bool, relationship_ok: bool, available: bool) -> Result:
	var out := Result.new()
	out.eligible = eligible
	out.relationship_ok = relationship_ok
	out.available = available
	if not eligible:
		out.reasons.append(REASON_ELIGIBLE)
	if not relationship_ok:
		out.reasons.append(REASON_RELATIONSHIP)
	if not available:
		out.reasons.append(REASON_AVAILABLE)
	return out


## The relationship row of the clearance. The eligibility service owns the fact reads; this is the
## pure predicate both routes share.
static func relationship_ok(has_relationship: bool, romance_eligible: bool,
		love_level_meets_floor: bool) -> bool:
	if not has_relationship:
		return false
	return romance_eligible and love_level_meets_floor


## The availability row: not already in an act, not sleeping, present and valid, not Occupied.
static func available(in_act: bool, sleeping: bool, present: bool, occupied: bool) -> bool:
	return present and not in_act and not sleeping and not occupied
