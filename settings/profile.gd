extends RefCounted
## The four typed facets of one resolved per-mare profile.

const ROWS := preload("res://mods/unfplap/settings/rows.gd")


class Profile extends RefCounted:
	var consent: ROWS.Rows = null
	var preferences: ROWS.Rows = null
	var participation: ROWS.Rows = null
	var identity: ROWS.Rows = null


	static func of(consent: ROWS.Rows, preferences: ROWS.Rows,
			participation: ROWS.Rows, identity: ROWS.Rows) -> Profile:
		var out := Profile.new()
		out.consent = consent
		out.preferences = preferences
		out.participation = participation
		out.identity = identity
		return out
