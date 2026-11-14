extends RefCounted
## Pure memory wording and ids. No Node, tree, time, file or settings access.
## The event texts must read correctly after the profile rewrites a leading "You and Anon " to
## "You and <name>", so no event line uses second-person pronouns for the pony. The private
## thoughts stay first-person. An adult witness event is only what she perceived; the game's
## per-pony story summary forms the personal memory.

const FACTS := preload("res://mods/unfplap/memory/facts.gd")

## Perception plus uncertainty, never a conclusion. Each act picks a different one so repeated
## memories and retold gossip do not read the same.
const WITNESS_TAILS := [
	" They were moving about together and making happy sounds, and she could not tell what they were doing.",
	" They seemed to be playing some game, and she was not sure what the game was.",
	" They were busy together and giggling, and she could not tell what it was about.",
]


## One mod-owned director key. Every key is prefixed so the act owns its lines.
static func key(event_id: String, kind: String, suffix: String) -> String:
	return "unfplap:%s:%s:%s" % [event_id, kind, suffix]


static func key_prefix(event_id: String) -> String:
	return "unfplap:%s:" % event_id


## Keep only a line that has actually started speaking. A line that is merely queued or still
## being generated must not outlive the act.
static func keep_active(state: int, key_value: String, active: String,
		keep_speaking: bool) -> bool:
	return keep_speaking and state == FACTS.LineState.SPEAKING \
		and not key_value.is_empty() and key_value == active


## The idempotent suffix for one impression slot.
static func impression_suffix(slot: int) -> String:
	match slot:
		FACTS.ImpressionSlot.ACT_EARLY:
			return ":summary"
		FACTS.ImpressionSlot.REFUSAL:
			return ":mood"
		FACTS.ImpressionSlot.STAY_CLOSE:
			return ":stay_close_gain"
		_:
			return ":gain"


## The world-context event kind for one impression slot. A refusal is a refusal, not a
## relationship summary; the act summary is a relationship event.
static func event_kind(slot: int) -> String:
	return "intimacy" if slot == FACTS.ImpressionSlot.REFUSAL else "relationship"


## The idempotent event-id suffix for one impression slot. A refusal keeps its bare id; the act
## summary keeps its own `:summary` id so a later prompt can recall the act.
static func event_suffix(slot: int) -> String:
	return "" if slot == FACTS.ImpressionSlot.REFUSAL else ":summary"


## The private stay-close thought. A positive act reads as cared for; a bad act reads as a
## repair beat, not a romance.
static func stay_close_thought(caressed: bool, positive: bool) -> String:
	if not positive:
		return "He stayed close after, even though I was hurt; it helped a little."
	if caressed:
		return "He stayed close and caressed me after; I felt cared for."
	return "He stayed close after; I felt cared for."


## The `act_prompts.event_*` setting key for one reaction.
static func reaction_name(reaction: int) -> String:
	match reaction:
		FACTS.Reaction.END_EARLY:
			return "end_early"
		FACTS.Reaction.HISTORY_REFUSAL:
			return "history_refusal"
		FACTS.Reaction.HISTORY_REMINDER:
			return "history_reminder"
		FACTS.Reaction.HISTORY_COMPLAINT:
			return "history_complaint"
		FACTS.Reaction.TOLERANCE_WARNING:
			return "tolerance_warning"
		FACTS.Reaction.TOLERANCE_STOP:
			return "tolerance_stop"
		_:
			return "climax"


## The event-id fragment for one stop reason.
static func stop_name(reason: int) -> String:
	match reason:
		FACTS.StopReason.UNWILLING:
			return "unwilling"
		FACTS.StopReason.PICKED_UP:
			return "picked up"
		FACTS.StopReason.INTERRUPTED:
			return "interrupted"
		FACTS.StopReason.FORM_CHANGE:
			return "form change"
		FACTS.StopReason.WITHDREW:
			return "withdrew"
		_:
			return ""


static func cancel_text() -> String:
	return "Anon stopped before she climaxed."


static func climax_text() -> String:
	return "You and Anon made love, and she climaxed."


static func stop_text(reason: int) -> String:
	match reason:
		FACTS.StopReason.UNWILLING:
			return "She did not want to keep going, so it stopped."
		FACTS.StopReason.PICKED_UP:
			return "Anon picked her up, and the act ended."
		FACTS.StopReason.INTERRUPTED:
			return "Something interrupted them, and the act ended."
		FACTS.StopReason.FORM_CHANGE:
			return "Anon changed form, and the act ended."
		FACTS.StopReason.WITHDREW:
			return "Anon kept doing something she did not like, so she stopped it."
		_:
			return "The act ended."


static func apology_text() -> String:
	return "Anon apologized for last time."


static func refusal_text(bucked: bool) -> String:
	if bucked:
		return "She refused him, and bucked when he would not stop."
	return "She refused him when he wanted more."


static func refusal_thought(bucked: bool) -> String:
	if bucked:
		return "He kept pushing after I said no, so I bucked him off. I need space."
	return "He wanted more than I did. I said no and turned him away."


static func witness_kind(young: bool) -> String:
	return "witnessed_scene" if young else "witnessed_intimacy"


static func witness_scene_prefix(partner_name: String, indoors: bool) -> String:
	if indoors:
		return "She walked in on Anon and %s." % partner_name
	return "She saw Anon and %s out in the open." % partner_name


static func witness_text(partner_name: String, young: bool, indoors: bool, serial: int,
		sense := FACTS.Sense.SIGHT) -> String:
	if not young:
		if sense == FACTS.Sense.SOUND:
			return "She heard Anon and %s together." % partner_name
		return "She saw Anon and %s together, close and unguarded." % partner_name
	var index := posmod(serial, WITNESS_TAILS.size())
	return witness_scene_prefix(partner_name, indoors) + str(WITNESS_TAILS[index])


static func witness_thought(partner_name: String, young: bool, _indoors: bool,
		sense := FACTS.Sense.SIGHT) -> String:
	if young:
		return ""
	if sense == FACTS.Sense.SOUND:
		return "I heard Anon and %s together." % partner_name
	return "I saw Anon and %s together." % partner_name


static func witness_impression(partner_name: String, young: bool, indoors: bool,
		sense := FACTS.Sense.SIGHT) -> Dictionary:
	var out: Dictionary = {"mood": "amused"} if young else {"mood": "surprised"}
	var thought := witness_thought(partner_name, young, indoors, sense)
	if not thought.is_empty():
		out["thought"] = thought
	return out
