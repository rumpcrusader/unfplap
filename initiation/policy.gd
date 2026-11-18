extends RefCounted
## Pure proactive-request pacing and wording rules: the scan, the cooldown, the retry, the
## approach, the ask range and the free/indirect wording mode. No Node, tree, time, file, Settings
## or game access: the facade supplies plain values and keeps every timer.
## See `docs/initiation.md`.

## Heat shortens the offer cooldown to this share of the usual wait.
const HEAT_COOLDOWN := 0.25
const SCAN_INTERVAL_S := 0.5
const QUIET_CHAT_GAP_S := 45.0
## The standing offer's reach: Anon must be within this distance. It is not the walk distance.
const STANDING_RANGE_M := 24.0
const APPROACH_GOAL_M := 2.0
const ARRIVE_RANGE_M := 2.8
const ARRIVE_WAIT_S := 2.0
const APPROACH_TIMEOUT_S := 35.0
const PLAYER_MOVE_CANCEL_M := 5.0
const RETRY_S := 30.0
## A bed invite only considers beds this close to Anon, so she can join without a long detour.
const BED_SEARCH_M := 7.0
## Walking to the bed front.
const BED_LEAD_TIMEOUT_S := 25.0

## The request's own wording mode. Prompts branch on this once per builder.
const MODE_FREE := "free"
const MODE_INDIRECT := "indirect"

## Episode phases. The facade owns the enum; these are the pure spellings the tables use.
const PHASE_NONE := "none"
const PHASE_APPROACH := "approach"
const PHASE_ARRIVE := "arrive"
const PHASE_ASK := "ask"
const PHASE_BED_APPROACH := "bed_approach"


static func cooldown_ready(now: float, last: float, seconds: float) -> bool:
	return now - last >= seconds


static func heat_cooldown(seconds: float) -> float:
	return seconds * HEAT_COOLDOWN


static func retry_ready(now: float, retry_at: float) -> bool:
	return now >= retry_at


## A private offer words freely; a public one hints.
static func wording_mode(private: bool) -> String:
	return MODE_FREE if private else MODE_INDIRECT
