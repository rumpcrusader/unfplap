shader_type spatial;
// See-through black fabrics (sheer pantyhose, mesh, polka-dot sheer): a self-contained copy of
// Pantyhose & Panties 0.1.1's sheer shader by mitty
// (`res://mods/pantyhose/shaders/hosiery_sheer.gdshader`), plus Unfplap's garment hull lift and
// worn cloth jiggle.
// Like nylon, it looks darker where the fabric turns away from you (more layers in the line of
// sight). The look parameters and render modes are unchanged; see `docs/integrations.md`,
// `CREDITS.md`.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://mods/unfplap/integrations/shaders/pantyhose_common.gdshaderinc"
uniform vec4 colour : source_color = vec4(0.02, 0.02, 0.025, 1.0);
uniform float alpha = 0.40;        // facing you
uniform float edge_alpha = 0.90;   // at grazing angles
uniform float band = 0.010;        // a denser band along the cut edges (waist, cuffs)
uniform float dots = 0.0;
uniform float uv_metres = 0.0;
uniform float rough = 0.45;
uniform float spec = 0.45;

void vertex() {
	HOSIERY_VERTEX
	HOSIERY_HULL_VERTEX
	HOSIERY_JIGGLE_VERTEX
}

void fragment() {
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float a = mix(edge_alpha, alpha, pow(facing, 1.4));
	if (edge_dist < band) a = max(a, 0.93);
	if (dots > 0.5 && (uv_metres > 0.0 ? pat(UV * uv_metres, 2, 0.0, 0.0) : tri(rest_pos, rest_normal, 2, 0.0, 0.0)) > 0.5) a = 0.97;
	ALBEDO = colour.rgb;
	ALPHA = a;
	ROUGHNESS = rough;
	SPECULAR = spec;
	RIM = 0.25;
	RIM_TINT = 0.6;
}
