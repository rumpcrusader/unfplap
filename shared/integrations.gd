extends RefCounted
## The supported mod integrations: metadata, feature flags and the binding paths the integrations
## service resolves. Pure data with no scene access, shared by `integrations/service.gd` and the
## Integrations settings tab.
##
## A binding path starts at the act pony. Each step is `{"property": "..."}` for a property or
## `{"child": "..."}` for a direct child node; `"optional": true` on any step marks the whole binding
## optional. The service keeps optional bindings under watch so a node that appears mid-act is
## bound then.

const ORDER := ["kissing", "idle_life"]

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
	"idle_life": {
		"mod_id": "idle_life",
		"mod_name": "Idle Life",
		"author": "modChad",
		"verified_version": "1.4.2",
		"features": ["idle_life_stretch"],
		"bindings": {
			"pose": [
				{"property": "skeleton"},
				{"child": "UnfplapPose"},
			],
		},
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
