shader_type spatial;

// Near pony (hybrid_near_mesh.gd, 2026-09-25): several cel-shaded rig surfaces of one skeleton
// merged into one, at full detail. Each source surface keeps its own material values through a
// palette entry (CUSTOM1.x = entry index): the uniforms of addons/cel-shader/cel-shader-base
// .gdshader moved into arrays, the fragment and light code unchanged, so the look is the rig's.
// Entries share one base texture (or none: the default white, as the rig surfaces sample it).
// Colours arrive linear (the rig's source_color uniforms are converted the same way on upload).
// Lighting is eldskald's cel base (addons/cel-shader, MIT) unchanged.

#include "res://addons/cel-shader/includes/base-cel-shader.gdshaderinc"

const int ENTRIES = 32;
uniform vec4 pal_color[ENTRIES];
uniform vec4 pal_specular[ENTRIES];
uniform vec4 pal_fresnel[ENTRIES];
uniform vec4 pal_shadow[ENTRIES];
uniform sampler2D base_texture: source_color;
uniform sampler2D specular_texture: hint_default_white;
uniform sampler2D fresnel_texture: hint_default_white;

varying vec3 SPECULAR_COLOR;
varying float SPECULAR_STRENGTH;
varying vec3 FRESNEL_COLOR;
varying float FRESNEL_STRENGTH;

varying vec2 base_uv;
varying flat int pal;

// Slap wobble, as on the rig coat (pony_flank_touch.gd drives it).
#include "res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc"

// 1 for the palette entries that are her coat (pony_flank_touch.gd): folded wings, the dock and
// other merged parts near the flank stay still.
uniform float jiggle_entry[ENTRIES];

// integration: mod-owned mirror of the anal mound shape key. The centre is the Blender
// body.glb anus centre mapped to the Godot body-local (0, 0.572, 0.299).
uniform vec3 anal_centre = vec3(0.0, 0.572, 0.299);
uniform float anal_scale = 1.0;
uniform float anal_reach = 0.09;

// integration: the body coat around the vulva. anatomy.gd sets these in body-local (NearBody)
// space from the anatomy's rest frame, so the coat spreads with the solved lip opening and the
// area under the genitals can be held still against the rump wobble.
uniform vec3 vulva_centre = vec3(0.0, 0.548, 0.292);
uniform vec3 vulva_out = vec3(0.0, 0.0, 1.0);
uniform float vulva_scale = 1.0;
uniform float vulva_reach = 0.04;
uniform float vulva_depth = 0.0;
uniform vec3 jiggle_still_centre = vec3(0.0);
uniform float jiggle_still_radius = 0.0;

void vertex() {
	pal = int(CUSTOM1.x + 0.5);
	vec3 rest = VERTEX;
	if (abs(anal_scale - 1.0) > 0.000001) {
		vec3 spread = VERTEX - anal_centre;
		float weight = 1.0 - smoothstep(0.0, anal_reach, length(spread));
		spread *= 1.0 + (anal_scale - 1.0) * weight;
		VERTEX = anal_centre + spread;
	}
	float still = 1.0;
	if (jiggle_still_radius > 0.0) {
		still = smoothstep(jiggle_still_radius * 0.8, jiggle_still_radius,
			distance(rest, jiggle_still_centre));
	}
	VERTEX += flank_jiggle(rest) * jiggle_entry[pal] * still;
	if (abs(vulva_scale - 1.0) > 0.000001 || abs(vulva_depth) > 0.000001) {
		vec3 spread = VERTEX - vulva_centre;
		float weight = 1.0 - smoothstep(0.0, vulva_reach, length(spread));
		vec3 out_axis = normalize(vulva_out);
		vec3 tangent = spread - out_axis * dot(spread, out_axis);
		VERTEX += tangent * ((vulva_scale - 1.0) * weight)
			- out_axis * (vulva_depth * weight);
	}
	base_uv = UV;
}

void fragment() {
	vec4 color = pal_color[pal];
	vec4 specular = pal_specular[pal];
	vec4 fresnel = pal_fresnel[pal];
	vec4 shadow_color = pal_shadow[pal];
	SPECULAR_COLOR = specular.rgb * texture(specular_texture, base_uv).rgb;
	SPECULAR_STRENGTH = specular.a * texture(specular_texture, base_uv).a;
	FRESNEL_COLOR = fresnel.rgb * texture(fresnel_texture, base_uv).rgb;
	FRESNEL_STRENGTH = fresnel.a * texture(fresnel_texture, base_uv).a;

	vec3 fill = color.rgb * texture(base_texture, base_uv).rgb;
	vec3 shade = shadow_color.rgb * texture(base_texture, base_uv).rgb;
	ALBEDO = mix(fill, shade, shadow_color.a);
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	vec4 color = pal_color[pal];
	vec4 shadow_color = pal_shadow[pal];
	vec3 lit_fill = mix(ALBEDO, color.rgb * texture(base_texture, base_uv).rgb, shadow_color.a);
	DIFFUSE_LIGHT += diffuse_light(
			lit_fill,
			LIGHT_COLOR,
			LIGHT,
			NORMAL,
			ATTENUATION
	);
	SPECULAR_LIGHT += specular_light(
			LIGHT_COLOR,
			SPECULAR_COLOR,
			SPECULAR_STRENGTH,
			NORMAL,
			VIEW,
			LIGHT,
			ATTENUATION
	);
	SPECULAR_LIGHT += fresnel_light(
			LIGHT_COLOR,
			FRESNEL_COLOR,
			FRESNEL_STRENGTH,
			NORMAL,
			VIEW,
			LIGHT,
			ATTENUATION
	);
}
