extends SceneTree
## The prompt graph contract over the shipped prompts document: structure, rendering and each
## structural failure the renderer must refuse. The only suite that reads `prompts.json`.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_prompts.gd

const DEFAULTS := preload("res://mods/unfplap/shared/defaults_data.gd")
const PROMPT_TEXT := preload("res://mods/unfplap/shared/prompt_text.gd")

## Every id the phase's consumers name; a typo here must fail against the document.
const CONSUMER_IDS := [
	"act.cue", "act.utterance", "act.climax", "act.end_early", "act.bystander",
	"act.bystander_setting", "act.note", "act.note.body", "act.note.caress",
	"act.state_line", "act.seed", "act.angles", "act.speech_feel",
	"act.speech_feel_frequency",
	"ask.context", "ask.purpose", "ask.situation", "ask.openings", "ask.modes",
	"ask.heat", "ask.crowd",
	"ask.openings.context_cuddle", "ask.openings.context_bed",
	"ask.openings.context_standing", "ask.openings.purpose_default",
	"ask.openings.purpose_cuddle", "ask.openings.purpose_bed",
	"ask.openings.purpose_standing", "ask.openings.situation_default",
	"ask.openings.situation_cuddle", "ask.openings.situation_bed",
	"ask.openings.situation_standing",
	"ask.modes.context_public", "ask.modes.context_free", "ask.modes.context_free_bed",
	"ask.modes.context_free_standing", "ask.modes.purpose_public", "ask.modes.purpose_free",
	"ask.modes.purpose_free_bed", "ask.modes.purpose_free_standing",
	"history.tiers", "history.tiers.stop", "history.tiers.withdrawn", "history.tiers.hurt",
	"history.tiers.hint", "history.lines", "history.lines.reminder", "history.lines.complaint",
	"history.lines.ask", "history.lines.refusal_stop", "history.lines.refusal",
	"relationship.stages", "relationship.tones", "relationship.memory",
	"cycle.heat", "cycle.diestrus",
	"beats",
	"body_change.offer",
]

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var document: Dictionary = DEFAULTS.prompts()
	check(not document.is_empty(), "the shipped prompts document exists")
	check(DEFAULTS.prompts_valid(), "the shipped prompts document parses")
	var problems: Array[String] = PROMPT_TEXT.validate(document)
	check(problems.is_empty(), "the shipped prompts document is a valid graph: %s"
		% str(problems))
	check(_missing(document, CONSUMER_IDS).is_empty(),
		"every id the code names is in the file: %s" % str(_missing(document, CONSUMER_IDS)))
	_check_render(document)
	_check_failures(document)
	print("PROMPTS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("PROMPTS_PASS")
	quit(0 if failures == 0 else 1)


func _check_render(document: Dictionary) -> void:
	var values_by_id := {}
	for id: String in CONSUMER_IDS:
		var node: Variant = _at(document, id)
		if not node is Dictionary or not (node as Dictionary).get("template") is String:
			continue
		var values := {}
		for slot: Variant in (node as Dictionary).get("slots", []):
			values[str(slot)] = "1"
		values_by_id[id] = values
	var rendered := PROMPT_TEXT.render_document(document, values_by_id)
	for id: String in values_by_id:
		check(not str(rendered.get(id, "")).is_empty(), "the composite renders: " + id)

	var cue: Dictionary = _at(document, "act.cue")
	var marks := {
		"seed": "SEEDMARK", "state": "STATEMARK", "relationship": "RELATIONMARK",
		"tone": "TONEMARK", "memory": "MEMORYMARK", "face_note": "FACEMARK",
		"preferences": "PREFERENCEMARK", "recent": "RECENTMARK",
	}
	var full := PROMPT_TEXT.render(cue, marks)
	for slot: String in marks:
		check(full.contains(str(marks[slot])), "a declared slot renders: " + slot)
	check(not full.contains("{"), "a rendered prompt keeps no placeholder")
	var empty_seed := marks.duplicate()
	empty_seed["seed"] = ""
	var short := PROMPT_TEXT.render(cue, empty_seed)
	check(not short.contains("SEEDMARK") and short.length() < full.length(),
		"a part with an empty slot is dropped")
	check(short.contains("STATEMARK"), "a direct slot keeps the rest of the template")
	check(PROMPT_TEXT.render("a   b", {}) == "a b", "a run of spaces collapses")
	check(PROMPT_TEXT.render("  a  \n  b  ", {}) == "a\nb", "newlines survive and edges trim")

	var deep := {"slots": [], "template": "{p0}"}
	for index in range(40):
		deep["p%d" % index] = "{p%d}" % (index + 1)
	deep["p40"] = "end"
	check(PROMPT_TEXT.render(deep, {}) == "", "the depth guard refuses a runaway chain")


func _check_failures(document: Dictionary) -> void:
	var planted: Dictionary = document.duplicate(true)
	var cue: Dictionary = _at(planted, "act.cue")
	cue["template"] = str(cue["template"]) + " {nope}"
	check(_has_failure(planted, "unknown reference"), "an unknown reference fails")

	planted = document.duplicate(true)
	cue = _at(planted, "act.cue")
	cue["loop"] = "{loop}"
	cue["template"] = str(cue["template"]) + " {loop}"
	check(_has_failure(planted, "cycle"), "a cycle fails")

	planted = document.duplicate(true)
	cue = _at(planted, "act.cue")
	cue["memory"] = "plain text"
	check(_has_failure(planted, "both a part and a slot"), "a part and a slot name fails")

	planted = document.duplicate(true)
	cue = _at(planted, "act.cue")
	cue["orphan"] = "plain text"
	check(_has_failure(planted, "unreachable"), "an unreachable part fails")

	planted = document.duplicate(true)
	cue = _at(planted, "act.cue")
	(cue["slots"] as Array).append("orphan")
	check(_has_failure(planted, "unused slot"), "an unused slot fails")

	planted = document.duplicate(true)
	cue = _at(planted, "act.cue")
	cue.erase("template")
	check(_has_failure(planted, "missing template"), "a composite without a template fails")

	planted = document.duplicate(true)
	cue = _at(planted, "act.cue")
	cue.erase("slots")
	check(_has_failure(planted, "missing slots"), "a composite without slots fails")

	planted = document.duplicate(true)
	var seeds: Dictionary = _at(planted, "act.seed")
	seeds["quiet"] = "a plain leaf with {state}"
	check(_has_failure(planted, "plain string"), "a placeholder in a plain string fails")

	var typo: Array = CONSUMER_IDS.duplicate()
	typo.append("act.nope")
	check(_missing(document, typo) == ["act.nope"], "a typo in a consumer id fails")


func _has_failure(document: Dictionary, needle: String) -> bool:
	for text: String in PROMPT_TEXT.validate(document):
		if text.contains(needle):
			return true
	return false


func _missing(document: Dictionary, ids: Array) -> Array:
	var out: Array = []
	for id: String in ids:
		if _at(document, id) == null:
			out.append(id)
	return out


func _at(document: Dictionary, id: String) -> Variant:
	var node: Variant = document
	for part: String in id.split(".", false):
		if not node is Dictionary or not (node as Dictionary).has(part):
			return null
		node = (node as Dictionary)[part]
	return node
