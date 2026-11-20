extends RefCounted
## One pony's stable identity facts. Fields are the record: no facts dictionary.
## `eligible_assertion()` is the only Variant, because absent and asserted-false differ.


class IdentityRecord extends RefCounted:
	var id := ""
	var era := 0
	var has_identity := false
	var is_player_pony := false
	var is_filly := false
	var is_stallion := false
	var has_eligible_assertion := false
	var eligible := false
	## Read-only participation block; the one nested document.
	var participation: Dictionary = {}

	func eligible_assertion() -> Variant:
		return eligible if has_eligible_assertion else null
