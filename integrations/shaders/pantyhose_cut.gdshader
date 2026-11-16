shader_type spatial;
// Opaque black fabrics with real holes (fishnet, lace, cotton, satin, ribbed): a self-contained
// copy of Pantyhose & Panties 0.1.1's cut shader by mitty
// (`res://mods/pantyhose/shaders/hosiery_cut.gdshader`), plus Unfplap's garment hull lift.
// The look parameters and render modes are unchanged; see `docs/integrations.md`, `CREDITS.md`.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://mods/unfplap/integrations/shaders/pantyhose_common.gdshaderinc"
uniform vec4 colour : source_color = vec4(0.025, 0.025, 0.03, 1.0);
uniform float rough = 0.85;
uniform float spec = 0.25;
uniform float rim = 0.1;
uniform float net = 0.0;           // 1 = fishnet holes everywhere but the band
uniform float net_cell = 0.0105;
uniform float net_width = 0.13;
uniform float lace = 0.0;          // 1 = lace all over
uniform float trim = 0.0;          // width of a lace trim along the edges (0 = none)
uniform float ribs = 0.0;
uniform float band = 0.005;        // a solid elastic band along the edges (fishnet/lace keep it)
uniform float uv_metres = 0.0;    // > 0: patterns follow the body's UV layout (metres per UV unit)

void vertex() {
	HOSIERY_VERTEX
	HOSIERY_HULL_VERTEX
}

void fragment() {
	float solid = 1.0;
	bool in_band = edge_dist < band;
	if (net > 0.5 && !in_band) solid = (uv_metres > 0.0 ? pat(UV * uv_metres, 0, net_cell, net_width) : tri(rest_pos, rest_normal, 0, net_cell, net_width));
	if (lace > 0.5 && !in_band) solid = (uv_metres > 0.0 ? pat(UV * uv_metres, 1, 0.0, 0.0) : tri(rest_pos, rest_normal, 1, 0.0, 0.0));
	if (trim > 0.0 && edge_dist < trim) {
		// Scalloped lace edge: open lace inside the trim, a wavy outer border.
		float wave = 0.0025 * (0.5 + 0.5 * sin((rest_pos.x + rest_pos.y + rest_pos.z) * 900.0));
		if (edge_dist < wave) discard;
		// A thin solid line where the trim meets the solid fabric, open lace below it.
		solid = edge_dist > trim - 0.0015 ? 1.0 : (uv_metres > 0.0 ? pat(UV * uv_metres, 1, 0.0, 0.0) : tri(rest_pos, rest_normal, 1, 0.0, 0.0));
	}
	if (solid < 0.5) discard;
	float shade = 1.0;
	if (ribs > 0.5) shade = 0.75 + 0.5 * (uv_metres > 0.0 ? pat(UV * uv_metres, 3, 0.0, 0.0) : tri(rest_pos, rest_normal, 3, 0.0, 0.0));
	if (in_band) shade *= 1.35;
	ALBEDO = colour.rgb * shade;
	ROUGHNESS = rough;
	SPECULAR = spec;
	RIM = rim;
	RIM_TINT = 0.5;
}
