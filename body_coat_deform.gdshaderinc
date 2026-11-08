// Mod-owned rig-coat deformation. `body_coat_patch.gd` keeps the game shader's flank_jiggle
// include, adds this file after it, and swaps the `VERTEX += flank_jiggle(VERTEX);` call for
// `VERTEX += body_coat_deform(VERTEX);`. The game include and the cel material stay untouched.
// No nested #include here: Godot resolves the main shader's includes, and this file uses the
// flank_jiggle function the game include already defined above it.

// The ponut shape key lives on the pony body, not the genitals overlay. Body-local centre,
// matching the Blender body.glb anus point mapped to Godot (0, 0.572, 0.299).
uniform vec3 body_coat_anal_centre = vec3(0.0, 0.572, 0.299);
uniform float body_coat_anal_scale = 1.0;
uniform float body_coat_anal_reach = 0.09;

// The vulva's body-local frame and the no-jiggle zone under it. anatomy.gd converts them from
// the anatomy's bone-local transform with the pony_hips bind pose, so poses do not move them.
uniform vec3 body_coat_vulva_centre = vec3(0.0, 0.548, 0.292);
uniform vec3 body_coat_vulva_out = vec3(0.0, 0.0, 1.0);
uniform float body_coat_vulva_scale = 1.0;
uniform float body_coat_vulva_reach = 0.04;
uniform float body_coat_vulva_depth = 0.0;
uniform vec3 body_coat_still_centre = vec3(0.0);
uniform float body_coat_still_radius = 0.0;
// The visible anal cup is a separate overlay from the body ponut; its own still zone keeps the
// rump wave from pushing the coat through the cup while the vulva is stretched.
uniform vec3 body_coat_anal_still_centre = vec3(0.0);
uniform float body_coat_anal_still_radius = 0.0;
// Both still zones are ellipsoids in the anatomy's body-local frame. `oval` is the vertical
// half-axis as a share of the lateral one; `fade` is the fraction of the radius used to blend
// the mask back to full jiggle at the rim.
uniform vec3 body_coat_still_right = vec3(1.0, 0.0, 0.0);
uniform vec3 body_coat_still_up = vec3(0.0, 1.0, 0.0);
uniform float body_coat_still_oval = 0.7;
uniform float body_coat_still_fade = 0.25;

float body_coat_still_mask(vec3 vertex, vec3 centre, float radius) {
	if (radius <= 0.0) {
		return 1.0;
	}
	vec3 d = vertex - centre;
	vec3 q = vec3(
		dot(d, normalize(body_coat_still_right)) / radius,
		dot(d, normalize(body_coat_still_up)) / (radius * max(body_coat_still_oval, 0.05)),
		dot(d, normalize(body_coat_vulva_out)) / radius);
	float fade = clamp(body_coat_still_fade, 0.02, 0.95);
	return smoothstep(1.0 - fade, 1.0, length(q));
}

vec3 body_coat_deform(vec3 vertex) {
	vec3 rest = vertex;
	vec3 offset = vec3(0.0);
	if (abs(body_coat_anal_scale - 1.0) > 0.000001) {
		vec3 spread = vertex - body_coat_anal_centre;
		float weight = 1.0 - smoothstep(0.0, body_coat_anal_reach, length(spread));
		offset += spread * ((body_coat_anal_scale - 1.0) * weight);
	}
	float still_vulva = body_coat_still_mask(rest, body_coat_still_centre,
		body_coat_still_radius);
	float still_anal = body_coat_still_mask(rest, body_coat_anal_still_centre,
		body_coat_anal_still_radius);
	offset += flank_jiggle(rest) * min(still_vulva, still_anal);
	if (abs(body_coat_vulva_scale - 1.0) > 0.000001
			|| abs(body_coat_vulva_depth) > 0.000001) {
		vec3 spread = vertex - body_coat_vulva_centre;
		float weight = 1.0 - smoothstep(0.0, body_coat_vulva_reach, length(spread));
		vec3 out_axis = normalize(body_coat_vulva_out);
		vec3 tangent = spread - out_axis * dot(spread, out_axis);
		offset += tangent * ((body_coat_vulva_scale - 1.0) * weight)
			- out_axis * (body_coat_vulva_depth * weight);
	}
	return offset;
}
