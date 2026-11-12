extends RefCounted
## Pure proactive-request rules: admission, cooldowns, privacy, the prompt schedule, pose choice
## and the closing-phase tables. No Node, tree, time, file, Settings or game access: the facade
## supplies plain values and keeps every timer. See `docs/initiation.md`.

const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

## Usual per-mare wait between offers.
const COOLDOWN_S := 600.0
## Heat shortens the offer cooldown to this share of the usual wait.
const HEAT_COOLDOWN := 0.25
const SCAN_INTERVAL_S := 0.5
const QUIET_CHAT_GAP_S := 45.0
const APPROACH_RADIUS_M := 24.0
const APPROACH_GOAL_M := 2.0
const ARRIVE_RANGE_M := 2.8
const ARRIVE_WAIT_S := 2.0
const APPROACH_TIMEOUT_S := 35.0
const PLAYER_MOVE_CANCEL_M := 5.0
const ASK_RANGE_CANCEL_M := 8.0
const PRIVACY_RADIUS_M := 30.0
const PROMPT_1_S := 12.0
const PROMPT_2_S := 24.0
## No reply at all: she lets it go after this long.
const GIVE_UP_S := 60.0
## After Anon answers, the answer, classifier and clarification need their own window.
const REPLY_GRACE_S := 45.0
const CLARIFY_GRACE_S := 30.0
## How long a private standing invitation may wait after the turn completes.
const INVITE_TIMEOUT_S := 60.0
## Safety cap while the presentation turns; the runtime's settled check normally wins earlier.
const PRESENT_TURN_TIMEOUT_S := 5.0
const RETRY_S := 30.0
## A bed invite only considers beds this close to Anon, so she can join without a long detour.
const BED_SEARCH_M := 10.0
## Walking to the bed front and waiting for Anon to lie down.
const BED_LEAD_TIMEOUT_S := 25.0
const BED_WAIT_TIMEOUT_S := 90.0
## Give her the ask line a moment before lying down on the offered bed counts as a yes.
const PHYSICAL_ACCEPT_GRACE_S := 2.5
## A pending classifier or a speaking reply extends the ask deadline by this much.
const DEADLINE_EXTEND_S := 5.0

## The request's own wording mode. Prompts branch on this once per builder.
const MODE_FREE := "free"
const MODE_INDIRECT := "indirect"

## Episode phases. The facade owns the enum; these are the pure spellings the tables use.
const PHASE_NONE := "none"
const PHASE_APPROACH := "approach"
const PHASE_ARRIVE := "arrive"
const PHASE_ASK := "ask"
const PHASE_PRESENT := "present"
const PHASE_INVITE := "invite"
const PHASE_BED_APPROACH := "bed_approach"
const PHASE_BED_LEAD := "bed_lead"
const PHASE_BED_WAIT := "bed_wait"

## Closing phases that set the full per-mare cooldown.
const COOLDOWN_PHASES := [PHASE_PRESENT, PHASE_INVITE, PHASE_ASK, PHASE_BED_LEAD, PHASE_BED_WAIT]
## Closing phases that only set the short retry, so a walk-over or unavailable ask does not retry
## every scan and does not eat the full cooldown either.
const RETRY_PHASES := [
	PHASE_APPROACH, PHASE_ARRIVE, PHASE_PRESENT, PHASE_INVITE, PHASE_ASK,
	PHASE_BED_APPROACH, PHASE_BED_LEAD, PHASE_BED_WAIT,
]
## Phases whose queued invitation line is still valid.
const INVITE_PHASES := [PHASE_PRESENT, PHASE_INVITE, PHASE_BED_WAIT]


static func cooldown_ready(now: float, last: float, seconds := COOLDOWN_S) -> bool:
	return now - last >= seconds


static func heat_cooldown(seconds: float) -> float:
	return seconds * HEAT_COOLDOWN


static func retry_ready(now: float, retry_at: float) -> bool:
	return now >= retry_at


## An indoor cuddle needs the house to herself; an outdoor one needs nobody within the radius.
static func cuddle_private(indoor: bool, house_alone: bool, others_near: bool) -> bool:
	return house_alone if indoor else not others_near


## A public offer overrides the privacy reserve for every kind of offer. Otherwise the same
## house-or-distance rule as a cuddle applies.
static func offer_private(public_offer: bool, house_alone: bool, others_near: bool) -> bool:
	if public_offer:
		return true
	return house_alone or not others_near


static func wording_mode(private: bool) -> String:
	return MODE_FREE if private else MODE_INDIRECT


static func next_prompt_time(prompts_sent: int) -> float:
	if prompts_sent <= 0:
		return PROMPT_1_S
	if prompts_sent == 1:
		return PROMPT_2_S
	return -1.0


## Per-mare pose choice for an automatic offer. Both feasible: a coin flip; one feasible: it.
static func pick_offer_pose(bed_ok: bool, standing_ok: bool, roll: float) -> String:
	if bed_ok and standing_ok:
		return CATALOG.MISSIONARY if roll < 0.5 else CATALOG.STANDING
	if bed_ok:
		return CATALOG.MISSIONARY
	if standing_ok:
		return CATALOG.STANDING
	return ""


## Weighted candidate choice over non-negative weights. Returns the index, or -1 when the total is
## zero.
static func weighted_pick(weights: Array, roll: float) -> int:
	var total := 0.0
	for item: Variant in weights:
		total += maxf(0.0, float(item))
	if total <= 0.0:
		return -1
	var target := clampf(roll, 0.0, 0.999999) * total
	var walked := 0.0
	for index in weights.size():
		walked += maxf(0.0, float(weights[index]))
		if target < walked:
			return index
	return weights.size() - 1


static func sets_cooldown(phase: String) -> bool:
	return phase in COOLDOWN_PHASES


static func sets_retry(phase: String) -> bool:
	return phase in RETRY_PHASES


static func invite_phase(phase: String) -> bool:
	return phase in INVITE_PHASES
