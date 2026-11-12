extends RefCounted
## The typed proactive-request facts: the plain values the pure rules and the wording read. The
## facade builds one per call from the live episode; it never carries a Node, a timer or a
## dictionary. See `docs/initiation.md`.

class Request extends RefCounted:
	## The pose she is offering, or the pose the invitation will use.
	var pose := ""
	var cuddle := false
	## True when the offer is private; the wording mode follows from it.
	var private := false
	var heat := false
	## Host-supplied prompt extras. Empty when the feature that owns them is off.
	var face_note := ""
	var relation_note := ""
	var history_note := ""
