extends RefCounted
## Typed boundary data for the memory service. Pure: plain values only, no scene, tree, time,
## file or settings access. Inner classes cannot see the script enums, so a stored enum value is
## an int and `0` is the first member of each enum.

## What the director currently holds for one mod-owned key.
enum LineState { ABSENT, QUEUED, GENERATING, SPEAKING, DELIVERED, UNKNOWN }
## The three ways the mod queues one of its own lines.
enum LineKind { REACTION, UTTERANCE, BYSTANDER }
## A settings-driven act reaction. The names are the `act_prompts.event_*` keys.
enum Reaction { CLIMAX, END_EARLY, HISTORY_REFUSAL, HISTORY_REMINDER, HISTORY_COMPLAINT,
		TOLERANCE_WARNING, TOLERANCE_STOP }
## A world-context event with fixed wording.
enum NoteKind { CANCELLED, CLIMAXED, STOPPED, APOLOGY }
## Why an act stopped. Only reachable reasons are listed.
enum StopReason { NONE, UNWILLING, PICKED_UP, INTERRUPTED, FORM_CHANGE, WITHDREW }
## The impression slot, which owns the idempotent event-id suffix.
enum ImpressionSlot { ACT, ACT_EARLY, REFUSAL, STAY_CLOSE }
## How an observer perceived the act.
enum Sense { SIGHT, SOUND }


## One impression write plus its optional relationship event. `event_text` empty means the
## moment records no world event.
class Impression extends RefCounted:
	var id := ""
	var event_id := ""
	## An `ImpressionSlot` value.
	var slot := 0
	var mood := "relaxed"
	var romance := 0
	var thought := ""
	var event_text := ""


## The strongest clean act kept per mare.
class Peak extends RefCounted:
	var id := ""
	var event_id := ""
	var text := ""
	var score := 0.0


## One observer's recorded memory of the act.
class Witness extends RefCounted:
	var id := ""
	var young := false
	## A `Sense` value.
	var sense := 0
	var indoors := false
	var distance := 0.0
	var place := ""
	var text := ""

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"young": young,
			"sense": sense,
			"indoors": indoors,
			"distance": distance,
			"place": place,
			"text": text,
		}


## One live observer, used to pick a bystander speaker. Nothing is committed.
class Observer extends RefCounted:
	var id := ""
	var node: Node3D
	## A `Sense` value.
	var sense := 0
	var indoors := false


## The private relationship facts for a cue prompt. No raw scores or counts leave this type.
class CueFacts extends RefCounted:
	var friendship := ""
	var friendship_level := -1
	var love := ""
	var love_level := -1
	var stage := ""
	var anger := 0.0
	var mood := ""
	var first_time := false
	var careful := false

	func to_dict() -> Dictionary:
		return {
			"friendship": friendship,
			"friendship_level": friendship_level,
			"love": love,
			"love_level": love_level,
			"stage": stage,
			"anger": anger,
			"mood": mood,
			"first_time": first_time,
			"careful": careful,
		}


## One unused shared memory for the cue prompt. `found()` is false when there is none.
class MemoryHit extends RefCounted:
	var id := ""
	var text := ""

	func found() -> bool:
		return not text.strip_edges().is_empty()


## The director key a queued line owns, and whether it was accepted.
class Line extends RefCounted:
	var key := ""
	var queued := false


## One line the mod wants the director to say.
class LineRequest extends RefCounted:
	## A `LineKind` value.
	var kind := 0
	var id := ""
	var event_id := ""
	var suffix := ""
	## The ready prompt for `UTTERANCE`/`BYSTANDER`; the fallback text for a `REACTION`.
	var purpose := ""
	## A `Reaction` value, read only by `REACTION`.
	var reaction := 0
	## The act/event guard handed to the director.
	var valid := Callable()
	## The completion callback, used by `UTTERANCE`.
	var finished := Callable()
