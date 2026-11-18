instance uniform float garment_jiggle_amount = 0.0;
instance uniform float garment_jiggle_time = 0.0;
instance uniform vec3 garment_jiggle_center = vec3(0.0, 0.0, 0.0);
instance uniform vec3 garment_jiggle_normal = vec3(0.0, 0.0, 1.0);
instance uniform float garment_jiggle_radius = 0.12;

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
