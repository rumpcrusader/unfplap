extends "res://mods/unfplap/shared/body_change_policy.gd"
## The changelings provider's offer/reveal policy. The base runtime executes the generic effects;
## this file owns the pack's offer prompt, its after-the-first-climax/own-form decision and the
## reveal's heat, peak, cue, memory and comfort values. No `class_name`.

const POLICY := preload("res://mods/unfplap/shared/body_change_policy.gd")

## The one offer prompt, in her own voice. It names no mechanism and no shape.
const OFFER_PROMPT := "Offer him a gift: for the rest of this, you will wear any adult mare's shape he names. Say it in one short line, at most 24 words, in your own voice, as a proud indulgence rather than a plea. Do not explain how it works and do not list names."
## The player-requested reveal's one exceptional beat: a readiness spike, a peak and the comfort
## mark the act history reads. A named shape is neutral.
const REVEAL_HEAT := 30.0
const REVEAL_PEAK := 150.0
const REVEAL_CUE := "She shows you the real her."
const REVEAL_MEMORY := "form_reveal"
const REVEAL_COMFORT := 1


## The offer waits until the act is active, after at least one pony climax, and only while she
## wears her own form. An outstanding offer or a used reveal is not offered again.
func should_offer(context: POLICY.BodyChangeActContext) -> bool:
	if context == null or context.form == null:
		return false
	return context.act_active and context.pony_climaxes >= 1 and context.form.is_own() \
		and not context.offer_pending and not context.reveal_used


func offer_prompt() -> String:
	return OFFER_PROMPT


## A named shape is a neutral continuation: no heat, peak or comfort.
func on_offer_accepted(_context: POLICY.BodyChangeActContext) -> POLICY.BodyChangeEffects:
	return POLICY.BodyChangeEffects.new()


## The player-requested return to her own form is the act's one exceptional reveal.
func on_reveal(_context: POLICY.BodyChangeActContext) -> POLICY.BodyChangeEffects:
	var effects := POLICY.BodyChangeEffects.new()
	effects.heat = REVEAL_HEAT
	effects.peak = REVEAL_PEAK
	effects.cue = REVEAL_CUE
	effects.memory_kind = REVEAL_MEMORY
	effects.comfort = REVEAL_COMFORT
	return effects
