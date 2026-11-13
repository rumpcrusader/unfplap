extends RefCounted
## Pure proactive-request wording: the ask, both reminders, the clarification, the invitation, the
## give-up lines and the world-context situation texts. The facade supplies the face, relationship
## and history notes as strings, so this file has no Settings, scene or game access.
## See `docs/initiation.md`.

const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const FACTS := preload("res://mods/unfplap/initiation/facts.gd")
const POLICY := preload("res://mods/unfplap/initiation/policy.gd")


## The observed-situation prompt that opens the ask.
static func ask_context(request: FACTS.Request) -> String:
	var text := "[Observed situation, not player speech] "
	if request.cuddle:
		text += "You are cuddling with Anon and want more. You have decided to invite him to have sex in the bed. "
	elif request.pose == CATALOG.MISSIONARY:
		text += "You want Anon in bed with you. You have decided to invite him to come to bed and have sex. "
	else:
		text += "You want Anon to take you from behind. You have decided to ask him to come and have sex with you. "
	if not request.relation_note.is_empty():
		text += request.relation_note + " "
	if not _free(request):
		text += "Other ponies are around. Ask indirectly, with an in-character euphemism or hint; do not say it plainly. Phrase it as a question to him. "
	elif request.pose == CATALOG.STANDING:
		text += "You are alone together. Ask clearly enough that he can answer, in your own voice, and in the way that fits you and this relationship; do not sound like a script or a demand. Phrase it as a direct question ending with a question mark. "
	elif request.pose == CATALOG.MISSIONARY:
		text += "You are alone together. Ask him to come to bed with you, in your own voice, clearly enough that he can answer; do not sound like a script or a demand. Phrase it as a direct question ending with a question mark. "
	else:
		text += "You are alone together. You may ask directly or hint, whichever fits you and this relationship; make it clear enough that he can answer. Phrase it as a question to him. "
	text += "Say one or two short sentences in your own voice. Let it sound like you want him, not just the act. Do not describe your body or narrate actions, and do not use action tags."
	text += heat_line(request.heat)
	if not request.history_note.is_empty():
		text += " " + request.history_note
	return text


## The generated-intent purpose for the ask line.
static func ask_purpose(request: FACTS.Request) -> String:
	var text := "You have decided to ask Anon for sex."
	if request.cuddle:
		text = "You are cuddling with Anon and have decided to invite him to have sex in the bed."
	elif request.pose == CATALOG.MISSIONARY:
		text = "You want Anon in bed with you and have decided to invite him to come to bed for sex."
	elif request.pose == CATALOG.STANDING:
		text = "You want Anon to take you from behind and have decided to ask him for sex."
	if not request.relation_note.is_empty():
		text += " " + request.relation_note
	if not _free(request):
		text += " Other ponies are around, so hint indirectly and do not say it plainly; phrase it as a question."
	elif request.pose == CATALOG.STANDING:
		text += " You are alone together. Ask clearly enough that he can answer, in your own voice, in the way that fits you and this relationship; do not sound like a script or a demand. You are asking him a question."
	elif request.pose == CATALOG.MISSIONARY:
		text += " You are alone together. Ask him to come to bed with you, clearly enough that he can answer, in your own voice; do not sound like a script or a demand. You are asking him a question."
	else:
		text += " You may ask directly or hint, in your own voice, in the way that fits you and this relationship; make it clear enough that he can answer. Phrase it as a question."
	text += " Say one or two short sentences. Let it sound like you want him, not just the act. Begin with [calm], [happy] or [whispering]. Do not narrate actions. End with a question mark."
	text += heat_line(request.heat)
	if not request.history_note.is_empty():
		text += " " + request.history_note
	text += request.face_note
	return text


## The invitation after Anon accepted: the bed position or the presented back.
static func invite_purpose(request: FACTS.Request) -> String:
	var text := ""
	if request.pose == CATALOG.MISSIONARY:
		text = "You are lying beside Anon on the bed, ready for him. Comment on taking the bed position and invite him in your own voice, in a way that fits how you feel about him. One short sentence. Begin with [whispering] or [calm]. Do not narrate actions."
	else:
		text = "You have just turned your back to Anon and lifted your tail aside, ready for him. Comment on taking the position and invite him in your own voice, in a way that fits how you feel about him. One short sentence. Begin with [whispering] or [calm]. Do not narrate actions."
	text += request.face_note
	return text


static func clarify_purpose() -> String:
	return "Anon's answer was not clear. Ask him plainly, as a direct question, whether he wants this, in your own voice. One short sentence ending with a question mark. Do not narrate actions."


static func invite_give_up_purpose() -> String:
	return "Anon accepted but did not take you up on it. Say one short, in-character line letting it go for now, without anger. Do not narrate actions."


static func reminder_purpose(private: bool) -> String:
	if not private:
		return "Anon has not reacted to your hint. Ask once more, indirectly and in character, as a question in one short sentence. Other ponies are around. Do not repeat your first line."
	return "Anon has not answered your offer. Ask the question once more, short and in character; playful or plain is fine, but do not turn it into a demand. Do not repeat your first line."


static func give_up_purpose() -> String:
	return "Your offer is over for now. Say one short, in-character line letting it go without pressure or anger. Do not ask again and do not narrate actions."


## The heat sentence appended to both ask forms. Empty outside heat.
static func heat_line(heat: bool) -> String:
	if heat:
		return " You are in heat, and you want him; let the urgency show without turning it into a demand."
	return ""


## World-context text: she has decided to ask.
static func situation_ask(request: FACTS.Request) -> String:
	var text := "You are with Anon and have decided to ask him for sex."
	if request.cuddle:
		text = "You are cuddling with Anon and have decided to invite him to have sex in the bed."
	elif request.pose == CATALOG.MISSIONARY:
		text = "You want Anon in bed with you and have decided to invite him to come to bed for sex."
	elif request.pose == CATALOG.STANDING:
		text = "You want Anon to take you from behind and have decided to ask him for sex."
	if not request.private:
		text += " Other ponies are around, so you can only hint at it."
	return text


## World-context text: Anon answered the private offer.
static func situation_consent(accepted: bool) -> String:
	if accepted:
		return "Anon accepted your offer. You are alone together and taking the position he came for."
	return "Anon declined your offer. Accept it gracefully and do not pressure him."


## World-context text: the offer is over without an answer. It replaces the open ask situation so
## the director's next line does not keep the offer alive after the controller gave up.
static func situation_end() -> String:
	return "Your offer for sex is over for now. Anon did not take it up; let it go without pressure and stop asking."


## The single free/indirect decision. Every builder above branches on this once.
static func _free(request: FACTS.Request) -> bool:
	return POLICY.wording_mode(request.private) == POLICY.MODE_FREE
