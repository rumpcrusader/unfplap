extends RefCounted
## The stable id and display name of one presented body, read by the act.

const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")

## The stable act identity of one presented body: the relationship id when it is ready, the
## pony-identity fallback otherwise.
class Identity extends RefCounted:
	var id := ""
	var body: Node = null


## Read one body's stable act identity. The relationship meta is preferred whenever it appears;
## a mod may assign it after the pony enters the tree.
static func identity_of(body: Node) -> Identity:
	var out := Identity.new()
	out.body = body
	if not is_instance_valid(body):
		return out
	var meta_id := str(body.get_meta("relationship_id", "")) if body.has_meta("relationship_id") else ""
	out.id = meta_id if not meta_id.is_empty() else PONY_ID.from("", body.get("identity"))
	return out


## The presented body's name for the act caption and dialogue.
## A borrowed shape still belongs to the same relationship, preferences and history.
static func display_name(form: BODY_FORM.BodyForm, body: Node, id: String) -> String:
	var presented := str(form.form_name).strip_edges() if form != null else ""
	if presented.is_empty() and is_instance_valid(body):
		var identity: Variant = body.get("identity")
		var display: Variant = identity.get("display_name") if identity != null else null
		presented = str(display).strip_edges() if display != null else ""
	return presented if not presented.is_empty() else id
