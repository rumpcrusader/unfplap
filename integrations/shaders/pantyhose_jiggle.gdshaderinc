// The worn cloth jiggle for Pantyhose & Panties compatibility: a copy of the game's
// `res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc` spring, driven by
// `integrations/garment_jiggle.gd` so a worn piece wobbles with the rump underneath it. The
// adapter writes the five instance uniforms per node, so two mares never share a wobble. The two
// copied shaders call `HOSIERY_JIGGLE_VERTEX` after `HOSIERY_HULL_VERTEX`, so the lift and the
// pattern coordinates stay on the rest position. With the amount at 0 every vertex pays one
// uniform branch. See `docs/integrations.md`.
instance uniform float garment_jiggle_amount = 0.0;  // metres of the first push; 0 = off
instance uniform float garment_jiggle_time = 0.0;    // seconds since the smack
instance uniform vec3 garment_jiggle_center = vec3(0.0, 0.0, 0.0);  // hit spot, garment-local
instance uniform vec3 garment_jiggle_normal = vec3(0.0, 0.0, 1.0);  // outward coat normal, local
instance uniform float garment_jiggle_radius = 0.12;  // metres; borrowed from the live coat

// Gaussian falloff around the hit, an inward-first wave along the outward normal and the rump's
// vertical bob a beat behind it; the ripple reaches the edge of the falloff a little later.
#define HOSIERY_JIGGLE_VERTEX \
	if (garment_jiggle_amount > 0.0) { \
		float jiggle_d = distance(VERTEX, garment_jiggle_center); \
		float jiggle_r = max(garment_jiggle_radius, 0.0001); \
		if (jiggle_d <= jiggle_r * 1.6) { \
			float jiggle_n = jiggle_d / jiggle_r; \
			float jiggle_falloff = exp(-2.5 * jiggle_n * jiggle_n); \
			float jiggle_t = max(garment_jiggle_time - jiggle_d * 0.6, 0.0); \
			float jiggle_wave = -exp(-4.2 * jiggle_t) * sin(28.0 * jiggle_t); \
			float jiggle_bob = exp(-3.6 * jiggle_t) * sin(24.0 * max(jiggle_t - 0.035, 0.0)); \
			vec3 jiggle_axis = garment_jiggle_normal; \
			float jiggle_len = length(jiggle_axis); \
			jiggle_axis = jiggle_len > 0.00001 ? jiggle_axis / jiggle_len : vec3(0.0, 0.0, 1.0); \
			vec3 jiggle_offset = jiggle_axis * jiggle_wave * 0.8 + vec3(0.0, 1.0, 0.0) * jiggle_bob; \
			VERTEX += jiggle_offset * (garment_jiggle_amount * jiggle_falloff); \
		} \
	}
