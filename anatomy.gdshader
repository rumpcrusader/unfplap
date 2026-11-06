shader_type spatial;

// integration: ported from PonyPussyParadise winking.gdshader. Same lighting as
// near_pony.gdshader. Vertex colour: R is the inner pink mask, G is closeness to an opening,
// which places the lip band and contour.
#include "res://addons/cel-shader/includes/base-cel-shader.gdshaderinc"

#include "res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc"

uniform vec4 skin_color: source_color;
uniform vec4 skin_shadow: source_color;
uniform vec4 inner_color: source_color;
uniform vec4 inner_shadow: source_color;
uniform vec4 fresnel: source_color = vec4(0.1, 0.1, 0.1, 0.1);

varying vec3 lit_fill;
varying vec3 gloss_color;
varying float gloss_strength;

// integration: how far the pink interior draws in front of its true depth, in metres.
uniform float cut_depth = 0.0;
// integration: a small depth bias for the outer anatomy, so the jiggling coat cannot cover it.
uniform float cover_depth = 0.0;

// integration: the vulva widens locally around its own opening, so the anal bulb above it never
// scales with the insertion.
uniform vec3 vulva_centre = vec3(0.0, -0.012, 0.02);
uniform float vulva_open = 0.0;
uniform float vulva_radius = 0.055;
// integration: 1 widens the whole rim, lower leaves the back of a ring quieter than its front.
uniform float vulva_taper = 1.0;

// integration: the teats mesh fades to her coat at the rim and gets its sway uniforms.
uniform vec4 coat_color: source_color;
uniform vec4 coat_shadow: source_color;
uniform vec3 sway_left = vec3(0.0);
uniform vec3 sway_right = vec3(0.0);
// integration: the skin strip is trimmed by UV.x along her midline.
uniform float span_from = -1.0;
uniform float span_to = 2.0;
uniform float span_fade = 0.01;
uniform float gap_from = 2.0;
uniform float gap_to = 2.0;
uniform float contour_amount = 1.0;

void vertex() {
	VERTEX += flank_jiggle(VERTEX);
	VERTEX += (VERTEX.x < 0.0 ? sway_left : sway_right) * (1.0 - COLOR.b);
	if (vulva_open > 0.0001) {
		vec3 spread = VERTEX - vulva_centre;
		vec3 flat_offset = vec3(spread.x, spread.y, 0.0);
		float near_hole = 1.0 - smoothstep(vulva_radius * 0.25, vulva_radius, length(flat_offset));
		float facing = smoothstep(-0.02, 0.02, spread.z);
		float amount = mix(vulva_taper, 1.0, facing);
		float widen = 1.0 + vulva_open * near_hole * amount;
		spread.x *= widen;
		spread.y *= widen;
		VERTEX = vulva_centre + spread;
	}
}

void fragment() {
	float inside = smoothstep(0.42, 0.58, COLOR.r);
	float skin = smoothstep(0.58, 0.63, COLOR.g);
	float lip = smoothstep(0.84, 0.88, COLOR.g);
	if (UV.x < span_from || UV.x > span_to || (UV.x > gap_from && UV.x < gap_to)) {
		discard;
	}
	float ends = 1.0 - smoothstep(0.0, span_fade, UV.x - span_from) * smoothstep(0.0, span_fade, span_to - UV.x);
	float to_coat = max(COLOR.b, ends);
	float contour = step(dot(NORMAL, VIEW), 0.4) * max(inside, skin) * (1.0 - to_coat) * contour_amount;

	// integration: only from behind her, so the pink never shows through from the side.
	vec3 rear = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	float rear_face = smoothstep(0.3, 0.65, dot(rear, VIEW));
	vec3 pulled = VERTEX + VIEW * (cut_depth * inside + cover_depth) * rear_face;
	vec4 clip = PROJECTION_MATRIX * vec4(pulled, 1.0);
	DEPTH = clip.z / clip.w;

	vec3 fill = mix(skin_color.rgb, skin_shadow.rgb, lip);
	vec3 shade = mix(skin_shadow.rgb, skin_shadow.rgb * 0.82, lip);
	fill = mix(fill, inner_color.rgb, inside);
	shade = mix(shade, inner_shadow.rgb, inside);
	fill = mix(fill, coat_color.rgb, to_coat);
	shade = mix(shade, coat_shadow.rgb, to_coat);

	vec3 line = mix(skin_shadow.rgb * 0.7, inner_shadow.rgb, inside);
	lit_fill = mix(fill, line, contour);
	ALBEDO = mix(shade, line * 0.8, contour);
	gloss_color = mix(vec3(0.1), vec3(0.75), inside);
	gloss_strength = mix(0.1, 0.45, inside);
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	DIFFUSE_LIGHT += diffuse_light(lit_fill, LIGHT_COLOR, LIGHT, NORMAL, ATTENUATION);
	SPECULAR_LIGHT += specular_light(LIGHT_COLOR, gloss_color, gloss_strength, NORMAL, VIEW, LIGHT, ATTENUATION);
	SPECULAR_LIGHT += fresnel_light(LIGHT_COLOR, fresnel.rgb, fresnel.a, NORMAL, VIEW, LIGHT, ATTENUATION);
}
