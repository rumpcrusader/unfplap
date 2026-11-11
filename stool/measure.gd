extends RefCounted
## Pure reach-gap arithmetic for the footstool rule. See docs/stool.md.

## The vertical gap between her opening and his part, with each body measured from its own floor.
## On level ground this is simply her bits above her hooves minus his bits above his feet.
static func gap(her_opening_y: float, her_hoof_y: float, his_root_y: float,
		his_foot_y: float) -> float:
	for value: float in [her_opening_y, her_hoof_y, his_root_y, his_foot_y]:
		if not is_finite(value):
			return NAN
	return (her_opening_y - her_hoof_y) - (his_root_y - his_foot_y) \
		+ (her_hoof_y - his_foot_y)


static func required(gap_m: float, threshold_m: float) -> bool:
	return is_finite(gap_m) and is_finite(threshold_m) and gap_m > threshold_m
