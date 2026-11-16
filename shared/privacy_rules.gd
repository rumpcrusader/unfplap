extends RefCounted
## Pure privacy rules for an act offer or a cuddle. The caller gathers the world facts (the
## house, the other mares and the radius); this file only applies the rule. There is no public
## override: visibility is derived from the surroundings, never chosen by reasoning, dialogue or
## a setting. Contract: `docs/initiation.md` (`## Privacy`).


## The offer rule: the house is empty of other mares, or nobody is near Anon.
static func offer_private(house_alone: bool, others_near: bool) -> bool:
	return house_alone or not others_near


## The cuddle rule: indoors the house must be empty of other mares; outdoors nobody may be near.
static func cuddle_private(indoors: bool, house_alone: bool, others_near: bool) -> bool:
	return house_alone if indoors else not others_near
