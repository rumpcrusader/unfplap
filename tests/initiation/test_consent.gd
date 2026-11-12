extends SceneTree
## The private-answer state machine: transcript handling, the model step, the one clarification,
## the same-text guard, pending replacement and the ask deadline.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/initiation/test_consent.gd

const CONSENT := preload("res://mods/unfplap/initiation/consent.gd")

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
	var reply := CONSENT.Reply.new()

	var ignored := CONSENT.on_text(reply, "   ", "unclear")
	check(not ignored.accepted and ignored.action == CONSENT.Action.NONE,
		"an empty answer is ignored")
	check(not reply.seen, "an empty answer leaves the reply untouched")

	var yes := CONSENT.on_text(reply, " Yes, please. ", "accept")
	check(yes.accepted and yes.action == CONSENT.Action.ACCEPT, "a clear yes accepts")
	check(reply.seen and reply.intent == "accept" and reply.source == "local",
		"a clear yes records the local intent")
	check(reply.text == "Yes, please." and reply.response == "Yes, please.",
		"the answer text is trimmed")

	var second := CONSENT.on_text(reply, "not now", "decline")
	check(not second.accepted, "a second answer is ignored before any clarification")

	var uncertain := CONSENT.Reply.new()
	var unclear := CONSENT.on_text(uncertain, "maybe", "unclear")
	check(unclear.accepted and unclear.action == CONSENT.Action.NONE,
		"an unclear answer is taken but resolves nothing")
	check(uncertain.pending and not uncertain.started, "an unclear answer waits for the model")

	var busy := CONSENT.poll(uncertain, false, false)
	check(busy.action == CONSENT.Action.NONE, "a busy director defers the model")
	var speaking := CONSENT.poll(uncertain, true, true)
	check(speaking.action == CONSENT.Action.NONE, "her own speech defers the model")
	var ready := CONSENT.poll(uncertain, true, false)
	check(ready.action == CONSENT.Action.CLASSIFY, "an idle director starts the model")

	var model_yes := CONSENT.on_model(uncertain, "accept", "")
	check(model_yes.action == CONSENT.Action.ACCEPT, "a model yes accepts")
	check(not uncertain.pending and not uncertain.started, "the model result clears the wait")
	check(uncertain.source == "llm", "a clean model reply records the source")

	var detail := CONSENT.Reply.new()
	CONSENT.on_text(detail, "hmm", "unclear")
	var model_detail := CONSENT.on_model(detail, "decline", "timeout")
	check(model_detail.action == CONSENT.Action.DECLINE, "a model no declines")
	check(detail.source == "llm:timeout", "a provider note is kept in the source")

	var unclear_model := CONSENT.Reply.new()
	CONSENT.on_text(unclear_model, "maybe later", "unclear")
	var model_unclear := CONSENT.on_model(unclear_model, "unclear", "unavailable")
	check(model_unclear.action == CONSENT.Action.CLARIFY, "an unclear model answer clarifies")
	var clarify := CONSENT.poll(unclear_model, true, false)
	check(clarify.action == CONSENT.Action.CLARIFY,
		"an unresolved answer asks for the one clarification")
	unclear_model.clarified = true
	var no_second := CONSENT.poll(unclear_model, true, false)
	check(no_second.action == CONSENT.Action.NONE, "the clarification happens once")

	# After the clarification, the same text is the fallback re-read and is ignored; a different
	# answer can still resolve it.
	var clarified := CONSENT.Reply.new()
	CONSENT.on_text(clarified, "maybe", "unclear")
	CONSENT.on_model(clarified, "unclear", "")
	clarified.clarified = true
	var same := CONSENT.on_text(clarified, "maybe", "unclear")
	check(not same.accepted, "the same text after the clarification is ignored")
	var different := CONSENT.on_text(clarified, "yes", "accept")
	check(different.accepted and different.action == CONSENT.Action.ACCEPT,
		"a different answer after the clarification resolves")

	# A new answer replaces one still waiting for the model.
	var replaced := CONSENT.Reply.new()
	CONSENT.on_text(replaced, "hmm", "unclear")
	replaced.started = true
	replaced.key = "offer:rarity:1"
	var replace := CONSENT.on_text(replaced, "yes", "accept")
	check(replace.cancel_pending, "a replacement cancels the running model request")
	check(replace.accepted and replace.action == CONSENT.Action.ACCEPT,
		"a replacement answer resolves")
	var replaced_late := CONSENT.Reply.new()
	CONSENT.on_text(replaced_late, "hmm", "unclear")
	var replace_late := CONSENT.on_text(replaced_late, "yes", "accept")
	check(not replace_late.cancel_pending, "a replacement with no request has nothing to cancel")

	check(CONSENT.deadline(false, true) == CONSENT.WAIT, "an unexpired deadline waits")
	check(CONSENT.deadline(true, true) == CONSENT.EXTEND, "an in-flight answer extends the deadline")
	check(CONSENT.deadline(true, false) == CONSENT.ABANDON, "a quiet expired ask gives up")

	print("INITIATION_CONSENT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INITIATION_CONSENT_PASS")
	quit(0 if failures == 0 else 1)
