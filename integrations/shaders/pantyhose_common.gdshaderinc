// Shared patterns and the garment hull lift for Pantyhose & Panties compatibility.
//
// The pattern functions are adapted from Pantyhose & Panties 0.1.1 by mitty
// (`res://mods/pantyhose/shaders/hosiery_common.gdshaderinc`). The hull uniforms and
// `HOSIERY_HULL_VERTEX` are Unfplap's; see `docs/integrations.md` and `CREDITS.md`.
//
// Coordinates are the body's REST pose (CUSTOM0.xyz, about metres on a mare), so patterns stay
// on the body while she moves; the rest normal (CUSTOM1.xyz) picks the projection planes
// (tri-planar).

varying vec3 rest_pos;
varying vec3 rest_normal;
varying float edge_dist;

// Use as the body of vertex(): Godot only lets vertex() itself write varyings.
#define HOSIERY_VERTEX rest_pos = CUSTOM0.xyz; edge_dist = CUSTOM0.w; rest_normal = normalize(CUSTOM1.xyz + vec3(0.0, 0.0001, 0.0));

// The worn garment's depth field, built from the anatomy mesh by `anatomy/garment_hull.gd`.
// `hull_texture` is normalised over `hull_z_range`; a negative cell is invalid and skipped.
// `hull_basis` maps anatomy-local space (its +Z is toward the tail) into the garment model
// space. The local push is converted back by the basis' Z scale, so the margin stays in world
// millimetres on every body size. The margin ramps from `hull_min_margin` on the anatomy's
// vertical center line (the vulva midline, x = 0) to `hull_margin` toward the field's X sides.
uniform sampler2D hull_texture : filter_linear, repeat_disable;
uniform vec4 hull_domain = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 hull_z_range = vec2(0.0, 1.0);
instance uniform float hull_on = 0.0;
instance uniform vec3 hull_origin = vec3(0.0);
// Godot does not support matrix instance uniforms, so the basis and its inverse travel as
// their three column vectors. `hull_basis_z` is the anatomy's +Z (toward the tail).
instance uniform vec3 hull_basis_x = vec3(1.0, 0.0, 0.0);
instance uniform vec3 hull_basis_y = vec3(0.0, 1.0, 0.0);
instance uniform vec3 hull_basis_z = vec3(0.0, 0.0, 1.0);
instance uniform vec3 hull_basis_inv_x = vec3(1.0, 0.0, 0.0);
instance uniform vec3 hull_basis_inv_y = vec3(0.0, 1.0, 0.0);
instance uniform vec3 hull_basis_inv_z = vec3(0.0, 0.0, 1.0);
instance uniform float hull_margin = 0.0;
instance uniform float hull_min_margin = 0.0;

#define HOSIERY_HULL_VERTEX \
	if (hull_on > 0.5) { \
		mat3 hull_basis = mat3(hull_basis_x, hull_basis_y, hull_basis_z); \
		mat3 hull_basis_inv = mat3(hull_basis_inv_x, hull_basis_inv_y, hull_basis_inv_z); \
		vec3 hull_local = hull_basis_inv * (VERTEX - hull_origin); \
		vec2 hull_uv = (hull_local.xy - hull_domain.xy) / hull_domain.zw; \
		if (hull_uv.x > 0.0 && hull_uv.x < 1.0 && hull_uv.y > 0.0 && hull_uv.y < 1.0) { \
			float hull_raw = textureLod(hull_texture, hull_uv, 0.0).r; \
			if (hull_raw >= 0.0) { \
				float hull_surface = mix(hull_z_range.x, hull_z_range.y, hull_raw); \
				float hull_ramp = smoothstep(0.0, max(hull_domain.z * 0.5, 0.0001), abs(hull_local.x)); \
				float hull_margin_now = mix(hull_min_margin, hull_margin, hull_ramp); \
				float hull_push = hull_surface + hull_margin_now - hull_local.z; \
				if (hull_push > 0.0) { \
					float hull_edge = min(min(hull_uv.x, 1.0 - hull_uv.x), min(hull_uv.y, 1.0 - hull_uv.y)); \
					float hull_fade = smoothstep(0.0, 0.03, hull_edge); \
					float hull_scale = max(length(hull_basis_z), 0.0001); \
					vec3 hull_axis = hull_basis_z / hull_scale; \
					VERTEX += hull_axis * (hull_push * hull_scale * hull_fade); \
					NORMAL = normalize(mix(NORMAL, hull_axis, clamp(hull_push * 20.0, 0.0, 1.0) * 0.8)); \
				} \
			} \
		} \
	}

vec3 plane_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / max(w.x + w.y + w.z, 0.0001);
}

// Diamond net: 1 on a strand, 0 in a hole. `cell` in metres, `width` 0..0.5 of a cell.
float net2(vec2 p, float cell, float width) {
	vec2 q = vec2(p.x + p.y, p.x - p.y) / (cell * 1.41421);
	vec2 f = abs(fract(q) - 0.5);
	float d = 0.5 - max(f.x, f.y);  // distance to the nearest strand, in cells
	float aa = max(fwidth(q.x), 0.002) * 0.9;
	return 1.0 - smoothstep(width - aa, width + aa, d);
}

// Lace: rings of petals on a hex grid over a fine net. 1 = thread, 0 = hole.
float lace2(vec2 p) {
	float cell = 0.026;
	vec2 g = p / cell;
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(g, r) - h;
	vec2 b = mod(g - h, r) - h;
	vec2 c = dot(a, a) < dot(b, b) ? a : b;
	float d = length(c);
	float ang = atan(c.y, c.x);
	float petal = abs(d - (0.30 + 0.06 * cos(ang * 6.0)));
	float flower = 1.0 - smoothstep(0.035, 0.065, petal);
	float centre = 1.0 - smoothstep(0.07, 0.10, d);
	float fine = net2(p, 0.0042, 0.10);
	return max(max(flower, centre), fine * 0.95);
}

// Polka dots: 1 inside a dot.
float dots2(vec2 p) {
	vec2 g = p / 0.017;
	vec2 c = fract(g + vec2(0.5 * floor(mod(g.y, 2.0)), 0.0)) - 0.5;
	return 1.0 - smoothstep(0.20, 0.25, length(c));
}

// Ribs running up and down (cotton boyshorts): 0..1 stripes.
float ribs2(vec2 p) {
	return 0.5 + 0.5 * sin(p.x * 2.0 * 3.14159 / 0.0035);
}

// Tri-planar sample of one of the patterns above.
float tri(vec3 pos, vec3 nrm, int which, float cell, float width) {
	vec3 w = plane_weights(nrm);
	vec2 px = pos.zy; vec2 py = pos.xz; vec2 pz = pos.xy;
	if (which == 0) return net2(px, cell, width) * w.x + net2(py, cell, width) * w.y + net2(pz, cell, width) * w.z;
	if (which == 1) return lace2(px) * w.x + lace2(py) * w.y + lace2(pz) * w.z;
	if (which == 2) return dots2(px) * w.x + dots2(py) * w.y + dots2(pz) * w.z;
	return ribs2(px) * w.x + ribs2(vec2(py.y, py.x)) * w.y + ribs2(pz) * w.z;
}

// One of the patterns on a single flat sheet (the body's own UV layout, in metres): continuous
// over the legs and hips, no seams between projections (the tri-planar blend left odd holes in
// the net).
float pat(vec2 p, int which, float cell, float width) {
	if (which == 0) return net2(p, cell, width);
	if (which == 1) return lace2(p);
	if (which == 2) return dots2(p);
	return ribs2(vec2(p.y, p.x));
}
