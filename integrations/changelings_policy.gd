extends "res://mods/unfplap/shared/body_change_policy.gd"
## The changelings offer/reveal policy: prompt, decision and effect values. Its offer gate owns
## timing, so the generic milestone hook stays a no-op.

const POLICY := preload("res://mods/unfplap/shared/body_change_policy.gd")
const DEFAULTS_DATA := preload("res://mods/unfplap/shared/defaults_data.gd")
const PROMPT_TEXT := preload("res://mods/unfplap/shared/prompt_text.gd")

## The player-requested reveal's one exceptional beat: a readiness spike, a peak, a cue and the
## memory mark. The summary's own `form_reveal` input carries the comfort. A named shape is neutral.
const REVEAL_HEAT := 30.0
const REVEAL_PEAK := 150.0
const REVEAL_CUE := "She shows you the real her."
const REVEAL_MEMORY := "form_reveal"


## The offer waits until the act is active, after at least one pony climax, and only while she
## wears her own form. An outstanding offer or a used reveal is not offered again.
func should_offer(context: POLICY.BodyChangeActContext) -> bool:
	if context == null or context.form == null:
		return false
	return context.act_active and context.pony_climaxes >= 1 and context.form.is_own() \
		and not context.offer_pending and not context.reveal_used


## The one offer prompt, in her own voice. It names no mechanism and no shape.
func offer_prompt() -> String:
	var rows: Dictionary = DEFAULTS_DATA.prompts_block("body_change")
	return PROMPT_TEXT.render(rows.get("offer", ""), {})


## Naming a shape applies nothing.
func on_offer_accepted(_context: POLICY.BodyChangeActContext) -> POLICY.BodyChangeEffects:
	return POLICY.BodyChangeEffects.new()


## Only the own-form reveal is exceptional.
func on_reveal(_context: POLICY.BodyChangeActContext) -> POLICY.BodyChangeEffects:
	var effects := POLICY.BodyChangeEffects.new()
	effects.heat = REVEAL_HEAT
	effects.peak = REVEAL_PEAK
	effects.cue = REVEAL_CUE
	effects.memory_kind = REVEAL_MEMORY
	return effects
