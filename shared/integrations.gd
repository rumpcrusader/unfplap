extends RefCounted
## The supported mod integrations: metadata, feature flags and the binding paths the integrations
## service resolves. Pure data with no scene access, shared by the service and the settings tab.
##
## A binding step is `{"property": "..."}`, `{"child": "..."}` or `{"optional": true}`. The service
## keeps optional bindings under watch so a node that appears mid-act is bound then.

const ORDER := ["kissing", "pantyhose"]

const PROVIDERS := {
	"kissing": {
		"mod_id": "kissing",
		"mod_name": "Kissing",
		"author": "modChad",
		"verified_version": "1.2.9",
		"features": ["kissing_reactions"],
		"bindings": {
			"feelings": [{"child": "KissingFeelings"}],
			"excitement": [{"property": "excitement"}],
			"beat": [{"property": "excitement"}, {"child": "Beat"}],
			"skeleton": [{"property": "skeleton"}],
			"fidgets": [{"property": "skeleton"}, {"child": "KissingFidgets", "optional": true}],
		},
	},
	## The Pantyhose & Panties adapter is a world integration: no per-act provider, no bindings, its
	## own every-frame pass. See `docs/integrations.md` (`## Pantyhose & Panties`).
	"pantyhose": {
		"mod_id": "pantyhose",
		"mod_name": "Pantyhose & Panties",
		"author": "mitty",
		"verified_version": "0.1.1",
		"features": ["pantyhose_undress", "pantyhose_bulge", "pantyhose_jiggle"],
		"bindings": {},
	},
}


## Provider ids in panel order.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in ORDER:
		out.append(id)
	return out


## Every provider entry in panel order.
static func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in ORDER:
		out.append(PROVIDERS[id])
	return out


## One provider entry, or an empty dictionary for an unknown id.
static func provider(id: String) -> Dictionary:
	var found: Variant = PROVIDERS.get(id, {})
	if found is Dictionary:
		return found
	return {}
