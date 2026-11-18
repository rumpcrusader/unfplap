extends RefCounted
## The world-side shape-change source contract and its manager.
##
## A source is any object, normally a Node, that implements this duck-typed surface:
##
##   is_active() -> bool                     the source is installed in this launch
##   handles_pony(pony: Node) -> bool        this pony may change shape through it
##   is_changing() -> bool                   a body change is under way
##   old_actor() -> Node                     the body being left, while it still exists
##   new_actor() -> Node                     the body the change produced, when it exists
##   target() -> String                      the requested shape id, "" for her own form
##   current_shape() -> String               the shape worn now, "" for her own form
##   claims_body(pony: Node) -> bool         a newly spawned body belongs to this change
##   request_true_form() -> bool             start a change back to her own form
##   request_shape(shape_id: String) -> bool start a change to a named shape
##   set_player_request(by_player: bool)     (optional) mark the change just started
##   request_appear() -> bool                (optional) bring the actor out while idle
##   poll() -> void                          advance the source's own read of the world; it may
##                                           start a change the source's own AI began, with no
##                                           request call, and the runtime will see it
##   source_name() -> String                 a short name for the act log
##   prepare_pony(pony: Node) -> void        (optional) fit metadata on a body
##   has_tail_placement(pony: Node) -> bool  (optional) a source-owned tail placement exists
##   apply_tail_placement(pony: Node) -> void (optional) re-apply the current tail placement
##   tail_placement_report() -> String       (optional) one line per live source-owned tail
##   installed_character_ids() -> Array[String] (optional) mares listed while away
##   requested_by_player() -> bool           the change carries a player's ask
##   asks_form_change(text: String) -> bool  the text asks for a reveal
##   named_form(text: String) -> String      the shape named in the text, or ""
##   named_form_note(text: String) -> String (optional) a short status when the named
##                                           shape is known but cannot be worn
##
## Nothing here preloads a source and no source may name unfplap's runtime or main. The manager
## returns the first active source that handles a pony; the handover core knows only this contract.
## A source that starts a change on its own (an AI action, not a `request_*` call) sets its own
## changing state in `poll()`; the runtime polls before it reads `is_changing()` and `old_actor()`.

var _sources: Array = []


## Add one source. Registering the same source twice is a no-op.
func register(source: Variant) -> void:
	if source == null or not is_instance_valid(source) or _sources.has(source):
		return
	_sources.append(source)


func unregister(source: Variant) -> void:
	_sources.erase(source)


## Re-read every source's installation state. The sources own their own gates.
func refresh() -> void:
	for source: Variant in _sources:
		if is_instance_valid(source) and source.has_method("refresh"):
			source.call("refresh")


## The source that handles this pony, or null. The first registered matching source wins.
func source_for(pony: Node) -> Variant:
	if not is_instance_valid(pony):
		return null
	for source: Variant in _sources:
		if not is_instance_valid(source) or not source.has_method("handles_pony"):
			continue
		if source.has_method("is_active") and not bool(source.call("is_active")):
			continue
		if bool(source.call("handles_pony", pony)):
			return source
	return null


## Any active source at all, for the debug actions and the act watcher.
func active() -> bool:
	for source: Variant in _sources:
		if is_instance_valid(source) and source.has_method("is_active") \
				and bool(source.call("is_active")):
			return true
	return false


## Every active source. Used by the rare listing and spawn paths, never by an act tick.
func active_sources() -> Array:
	var out: Array = []
	for source: Variant in _sources:
		if is_instance_valid(source) and source.has_method("is_active") \
				and bool(source.call("is_active")):
			out.append(source)
	return out


## Let every active source fit a body it brings. A missing hook is a no-op.
func prepare_pony(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	for source: Variant in active_sources():
		if source.has_method("prepare_pony"):
			source.call("prepare_pony", pony)


func has_tail_placement(pony: Node) -> bool:
	if not is_instance_valid(pony):
		return false
	var source: Variant = source_for(pony)
	return source != null and source.has_method("has_tail_placement") \
		and bool(source.call("has_tail_placement", pony))


func apply_tail_placement(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	var source: Variant = source_for(pony)
	if source != null and source.has_method("apply_tail_placement"):
		source.call("apply_tail_placement", pony)


func tail_placement_report() -> String:
	var lines := PackedStringArray()
	for source: Variant in active_sources():
		if not source.has_method("tail_placement_report"):
			continue
		var text := str(source.call("tail_placement_report")).strip_edges()
		if not text.is_empty():
			lines.append(text)
	return "\n".join(lines)


## Every installed mare id, deduplicated, in source order.
func installed_character_ids() -> Array[String]:
	var out: Array[String] = []
	for source: Variant in active_sources():
		if not source.has_method("installed_character_ids"):
			continue
		var ids: Variant = source.call("installed_character_ids")
		if not ids is Array:
			continue
		for raw: Variant in ids:
			var id := str(raw).strip_edges()
			if not id.is_empty() and not out.has(id):
				out.append(id)
	return out
