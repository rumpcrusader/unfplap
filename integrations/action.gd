extends RefCounted
## One write a pure provider asks the facade to make. The facade owns the target node, the
## save/restore of the original value and the optional-binding watch; the provider only names the
## binding, the property and the value.

const SET := "set"
const BIND := "bind"
const RESTORE := "restore"

class Value:
	var kind := SET
	var binding := ""
	var property := ""
	var value: Variant = null
	var optional := false


## Save and set `property` on a required binding.
static func set_value(binding: String, property: String, value: Variant) -> Value:
	var action := Value.new()
	action.kind = SET
	action.binding = binding
	action.property = property
	action.value = value
	return action


## Set `property` on a binding that may appear later; the facade keeps it pending until it does.
static func bind_value(binding: String, property: String, value: Variant,
		optional := false) -> Value:
	var action := Value.new()
	action.kind = BIND
	action.binding = binding
	action.property = property
	action.value = value
	action.optional = optional
	return action


## Put `property` back to the value the facade saved before this provider first wrote it. The
## save record stays, so a later write still restores the act-start value at the final reset.
static func restore_value(binding: String, property: String) -> Value:
	var action := Value.new()
	action.kind = RESTORE
	action.binding = binding
	action.property = property
	return action
