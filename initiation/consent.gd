extends RefCounted
## The private-answer state machine for a proactive offer. Pure: the facade supplies the local
## intent, the director state and the classifier result, then performs the returned action.
## See `docs/initiation.md` (`## Consent`).

## The one clarification, then give up.
const UNCLEAR := "unclear"
## The ask deadline outcomes.
const WAIT := "wait"
const EXTEND := "extend"
const ABANDON := "give_up"


## What the facade should do next.
enum Action { NONE, CLASSIFY, ACCEPT, DECLINE, CLARIFY }


## One answer episode. The facade owns one per request.
class Reply extends RefCounted:
	## A transcript has been taken as the answer.
	var seen := false
	## The one clarification line was queued.
	var clarified := false
	## An unclear answer is waiting for the model.
	var pending := false
	## The model request is already in flight.
	var started := false
	## The resolved intent, the source it came from and the answer text.
	var intent := ""
	var source := ""
	var text := ""
	## The answer text that was taken, for the clarified same-text guard.
	var response := ""
	## The classifier key while a request is in flight.
	var key := ""


## The decision the facade applies. `cancel_pending` is a new answer replacing one still waiting
## for the model; `accepted` is false when the text was ignored.
class Decision extends RefCounted:
	var action: int = Action.NONE
	var accepted := false
	var cancel_pending := false


## Take a transcript. `intent` is the local classification of the same text.
static func on_text(reply: Reply, text: String, intent: String) -> Decision:
	var out := Decision.new()
	text = text.strip_edges()
	if text.is_empty():
		return out
	if reply.pending:
		# A new answer replaces the one still waiting for the model.
		out.cancel_pending = reply.started
		reply.pending = false
		reply.started = false
		reply.seen = false
	if reply.seen:
		# One clear answer ends the wait. After the one clarification, a different answer may
		# still resolve it; the same text is the tick's fallback re-reading it.
		if not reply.clarified:
			return out
		if text == reply.response:
			return out
	out.accepted = true
	reply.seen = true
	reply.text = text
	reply.response = text
	if intent != UNCLEAR:
		reply.intent = intent
		reply.source = "local"
		out.action = _action_for(intent)
		return out
	# The tick starts the model once the director is idle again.
	reply.pending = true
	reply.started = false
	return out


## Take the model result. A provider error or a missing classifier is `unclear`.
static func on_model(reply: Reply, intent: String, detail: String) -> Decision:
	reply.pending = false
	reply.started = false
	reply.intent = intent
	reply.source = "llm" if detail.is_empty() else "llm:%s" % detail
	var out := Decision.new()
	out.accepted = true
	out.action = _action_for(intent)
	return out


## The pending answer decides whether the model may start; a resolved unclear answer asks for the
## one clarification.
static func poll(reply: Reply, director_idle: bool, pony_speaking: bool) -> Decision:
	var out := Decision.new()
	if not reply.seen:
		return out
	if reply.pending:
		if not reply.started and director_idle and not pony_speaking:
			out.action = Action.CLASSIFY
		return out
	if reply.intent == UNCLEAR and not reply.clarified:
		out.action = Action.CLARIFY
	return out


## The ask deadline. It extends while an answer, a line or her own speech is in flight.
static func deadline(expired: bool, in_flight: bool) -> String:
	if not expired:
		return WAIT
	return EXTEND if in_flight else ABANDON


static func _action_for(intent: String) -> int:
	match intent:
		"accept":
			return Action.ACCEPT
		"decline":
			return Action.DECLINE
		_:
			return Action.CLARIFY
