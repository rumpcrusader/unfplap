extends Node
## Shared impressions fake: records each committed memory event for the act-flow suites.

var calls: Array = []

func commit(id: String, data: Dictionary, event_id: String) -> void:
	calls.append({"id": id, "data": data.duplicate(true), "event_id": event_id})
