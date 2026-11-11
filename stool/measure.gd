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


## How many steps are needed so the remaining gap is below `threshold_m`. The first step is
## required once the gap passes the threshold; each later step covers one `step_m` of it.
static func count(gap_m: float, threshold_m: float, step_m: float) -> int:
	if not is_finite(gap_m) or not is_finite(threshold_m) or not is_finite(step_m):
		return 0
	if step_m <= 0.001 or gap_m <= threshold_m:
		return 0
	return maxi(1, floori((gap_m - threshold_m) / step_m + 0.000001) + 1)
