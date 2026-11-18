// The worn cloth jiggle for Pantyhose & Panties compatibility: a copy of the game's
// `res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc` spring, driven by
// `integrations/garment_jiggle.gd` from the live values on her coat material, mapped into this
// garment's model space. The adapter writes the six instance uniforms per node, so two mares never
// share a wobble, and they plus the ten hull ones are exactly Godot's sixteen. The two copied
// shaders evaluate it at the rest cloth position, then run the hull lift and add the offset, so the
// lift keeps sampling its rest UVs. With the amount at 0 every vertex pays one uniform branch. See
// `docs/integrations.md`.
instance uniform float garment_jiggle_amount = 0.0;  // metres of the first push; 0 = off
instance uniform float garment_jiggle_time = 0.0;    // seconds since the smack
instance uniform vec3 garment_jiggle_center = vec3(0.0, 0.0, 0.0);  // hit spot, garment-local
instance uniform vec3 garment_jiggle_normal = vec3(0.0, 0.0, 1.0);  // outward coat normal, local
instance uniform float garment_jiggle_radius = 0.12;  // metres; borrowed from the live coat
instance uniform vec3 garment_jiggle_up = vec3(0.0, 1.0, 0.0);  // the body's up, garment-local

// Gaussian falloff around the hit, an inward-first wave along the outward normal and the rump's
// vertical bob a beat behind it; the ripple reaches the edge of the falloff a little later.
vec3 hosiery_jiggle(vec3 vertex) {
	if (garment_jiggle_amount <= 0.0) {
		return vec3(0.0);
	}
	float radius = max(garment_jiggle_radius, 0.0001);
	float d = distance(vertex, garment_jiggle_center);
	if (d > radius * 1.6) {
		return vec3(0.0);
	}
	float n = d / radius;
	float falloff = exp(-2.5 * n * n);
	float t = max(garment_jiggle_time - d * 0.6, 0.0);
	float wave = -exp(-4.2 * t) * sin(28.0 * t);
	float bob = exp(-3.6 * t) * sin(24.0 * max(t - 0.035, 0.0));
	vec3 jiggle_axis = garment_jiggle_normal;
	float axis_len = length(jiggle_axis);
	jiggle_axis = axis_len > 0.00001 ? jiggle_axis / axis_len : vec3(0.0, 0.0, 1.0);
	vec3 jiggle_up = garment_jiggle_up;
	float up_len = length(jiggle_up);
	jiggle_up = up_len > 0.00001 ? jiggle_up / up_len : vec3(0.0, 1.0, 0.0);
	return (jiggle_axis * wave * 0.8 + jiggle_up * bob) * (garment_jiggle_amount * falloff);
}
