extends RefCounted
## Pure Context for act reasoning: the soft inputs both Mare reasoning stages and the Anon
## classifier receive. A Context never gates an offer or a start; it only informs the decision.
## The caller builds one snapshot from plain facts. No service, scene, setting, clock or file.

const ANSWER_ACCEPT := "accept"
const ANSWER_REFUSE := "refuse"
const ANSWER_COUNTER_OFFER := "counter_offer"


## The typed context snapshot. `prompt_facts()` is the stable payload a reasoning prompt carries.
class Context:
	var willingness := false
	var history_tier := "steady"
	var history_hurt := 0
	var history_comfort := 0
	var history_blocks_start := false
	var history_blocks_offers := false
	var history_offer_weight := 0.0
	var cycle_phase := "normal"
	var heat := false
	var diestrus := false
	var aftercare := false
	var private := false
	var public_preference := false
	var mood := ""
	var relation_note := ""
	var history_note := ""

	## The reasoning payload. Plain JSON-safe values only; no node, no live state.
	func prompt_facts() -> Dictionary:
		return {
			"willing": willingness,
			"history": {
				"tier": history_tier,
				"hurt": history_hurt,
				"comfort": history_comfort,
				"blocks_start": history_blocks_start,
				"blocks_offers": history_blocks_offers,
				"offer_weight": history_offer_weight,
			},
			"cycle": cycle_phase,
			"heat": heat,
			"diestrus": diestrus,
			"aftercare": aftercare,
			"private": private,
			"public_preference": public_preference,
			"mood": mood,
			"relation_note": relation_note,
			"history_note": history_note,
		}


## Build a Context from a plain facts dictionary. Missing keys keep the neutral defaults.
static func build(facts: Dictionary) -> Context:
	var out := Context.new()
	out.willingness = bool(facts.get("willingness", false))
	var history: Variant = facts.get("history", {})
	if history is Dictionary:
		var row := history as Dictionary
		out.history_tier = str(row.get("tier", "steady"))
		out.history_hurt = int(row.get("hurt", 0))
		out.history_comfort = int(row.get("comfort", 0))
		out.history_blocks_start = bool(row.get("blocks_start", false))
		out.history_blocks_offers = bool(row.get("blocks_offers", false))
		out.history_offer_weight = float(row.get("offer_weight", 0.0))
	out.cycle_phase = str(facts.get("cycle_phase", "normal"))
	out.heat = bool(facts.get("heat", false))
	out.diestrus = bool(facts.get("diestrus", false)) or out.cycle_phase == "diestrus"
	out.aftercare = bool(facts.get("aftercare", false))
	out.private = bool(facts.get("private", false))
	out.public_preference = bool(facts.get("public_preference", false))
	out.mood = str(facts.get("mood", ""))
	out.relation_note = str(facts.get("relation_note", ""))
	out.history_note = str(facts.get("history_note", ""))
	return out


## Normalize a reasoning answer. Unknown text maps to `refuse`; the caller applies the failure
## rule for its own stage.
static func answer(value: Variant) -> String:
	var text := str(value).strip_edges().to_lower()
	if text in [ANSWER_ACCEPT, "yes", "accepted"]:
		return ANSWER_ACCEPT
	if text in [ANSWER_COUNTER_OFFER, "counter", "not_here", "not here"]:
		return ANSWER_COUNTER_OFFER
	return ANSWER_REFUSE
