extends RefCounted
## The typed base for a provider's offer/reveal policy. The provider decides the timing and the
## contents; the base runtime executes the generic dialogue, readiness/peak/comfort, memory and
## form-request effects from `BodyChangeEffects`. No runtime hook is wired in this phase. No
## `class_name`: a provider extends this file by path.

const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")

## The generic act milestones a provider may act on.
enum ActEvent { ACTIVE, CLIMAX_END, AFTERGLOW, OFFER_ACCEPTED, REVEALED, FORM_SETTLED }


## The generic effects the runtime executes; `0`/`""` means none.
class BodyChangeEffects extends RefCounted:
	var heat: float = 0.0
	var peak: float = 0.0
	var comfort: int = 0
	var cue: String = ""
	var memory_kind: String = ""

	## True when this value asks for no effect.
	func is_empty() -> bool:
		return is_zero_approx(heat) and is_zero_approx(peak) and comfort == 0 \
			and cue.is_empty() and memory_kind.is_empty()


## The typed values a policy reads for the current event.
class BodyChangeActContext extends RefCounted:
	var pony_id: String = ""
	var form: BODY_FORM.BodyForm = null
	var change: BODY_CHANGE = null
	var origin: BODY_CHANGE.Origin = BODY_CHANGE.Origin.PROVIDER
	var state: BODY_CHANGE.State = BODY_CHANGE.State.REQUESTED
	var offer_pending: bool = false
	var reveal_used: bool = false
	var by_player: bool = false


## Every generic act milestone. The provider decides whether this event matters to it.
func on_act_event(_event: ActEvent, _context: BodyChangeActContext) -> void:
	pass


## True when the provider offers a form at this event.
func should_offer(_context: BodyChangeActContext) -> bool:
	return false


## The provider's offer prompt, or "" for none.
func offer_prompt() -> String:
	return ""


## The effects of an accepted offer. A fresh value means no effects.
func on_offer_accepted(_context: BodyChangeActContext) -> BodyChangeEffects:
	return BodyChangeEffects.new()


## The effects of a reveal. A fresh value means no effects.
func on_reveal(_context: BodyChangeActContext) -> BodyChangeEffects:
	return BodyChangeEffects.new()
