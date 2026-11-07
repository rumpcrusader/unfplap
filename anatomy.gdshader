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
// integration: local position, so the pink interior can be clipped to the solved hole radius.
varying vec3 hole_pos;
varying vec3 gloss_color;
varying float gloss_strength;

// integration: how far the pink interior draws in front of its true depth, in metres.
uniform float cut_depth = 0.0;
// integration: a small depth bias for the outer anatomy, so the jiggling coat cannot cover it.
uniform float cover_depth = 0.0;

// integration: the opening's rim and the radius where the mound must stay put. The band between
// them is remapped radially, so the hole grows to the shaft while the outer silhouette keeps its
// size and the lips thin out.
uniform vec3 vulva_centre = vec3(0.0, -0.012, 0.02);
uniform float lip_radius = 0.03;
uniform float lip_outer = 0.066;
// integration: mesh-local radius the opening must reach (Anon's shaft at the contact plane).
uniform float hole_target = 0.0;
// integration: how much of the widening also scales depth. 1 is a uniform mesh scale (a mound);
// 0 keeps the rest relief (the vulva). The anal ring uses a tunable fraction.
uniform float hole_depth_scale = 0.0;
// integration: cheat for the anal act only. Scale the whole vulva model about the anal opening so
// the ponut swells with the shaft. The vulva lips move with it, which is fine because they are out
// of frame; the anal overlay has its own material and is not scaled.
uniform float anal_swell = 0.0;
uniform vec3 anal_swell_centre = vec3(0.0);
// integration: Anon's shaft as a swept circle in world space. Any vulva vertex that ends up
// inside it is projected onto its surface, so the lips cannot intersect the cock.
uniform vec3 shaft_pivot = vec3(0.0);
uniform vec3 shaft_axis = vec3(0.0);
uniform float shaft_length = 0.0;
uniform float shaft_radii[8];

// integration: how much of the opening happens vertically. The lips part sideways around the
// shaft; the top and bottom of the opening barely move, which keeps them tight on the shaft.
uniform float lip_vertical = 0.5;

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
	if (hole_target > lip_radius) {
		vec3 spread = VERTEX - vulva_centre;
		float radius = length(spread.xy);
		// Scale the band multiplicatively, like the build that wrapped well, but solved so the rim
		// lands exactly on the shaft radius and the falloff extends past the shaft so there is
		// still lip material around it. Scaling (rather than translating) is what gives the mound
		// enough area to surround a large shaft.
		float reach = max(lip_outer, hole_target * 1.15);
		float weight = 1.0 - smoothstep(lip_radius, reach, radius);
		float amount = (hole_target / lip_radius - 1.0) * weight;
		if (radius > 0.0001 && weight > 0.0) {
			// Anisotropic: the lips part sideways (full), the top and bottom only partly, so the
			// opening becomes a wide oval whose ends stay wrapped on the shaft.
			spread.x *= 1.0 + amount;
			spread.y *= 1.0 + amount * lip_vertical;
			spread.z *= 1.0 + amount * hole_depth_scale;
			VERTEX = vulva_centre + spread;
		}
	}
	if (anal_swell > 0.0001) {
		VERTEX = anal_swell_centre + (VERTEX - anal_swell_centre) * (1.0 + anal_swell);
	}
	// Only the outside surface is projected onto the shaft. The inner wall sits behind the rim and
	// stays there: pushing both layers onto the same cylinder made the pink poke through the lips.
	if (shaft_length > 0.0001 && vulva_centre.z - VERTEX.z < 0.004) {
		vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float t = clamp(dot(world - shaft_pivot, shaft_axis), 0.0, shaft_length);
		vec3 centre = shaft_pivot + shaft_axis * t;
		vec3 offset = world - centre;
		float dist = length(offset);
		float sample = t / shaft_length * 7.0;
		int low = int(floor(sample));
		float radius = mix(shaft_radii[low], shaft_radii[min(low + 1, 7)], fract(sample));
		if (dist < radius) {
			vec3 dir = dist > 0.00001 ? offset / dist : vec3(0.0, 1.0, 0.0);
			world = centre + dir * (radius + 0.0005);
			VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
		}
	}
	hole_pos = VERTEX;
}

void fragment() {
	float inside = smoothstep(0.42, 0.58, COLOR.r);
	// The pink interior must fill the opening exactly: everything within the solved hole radius is
	// interior, so the shaft is covered right up to the lips instead of showing through.
	if (hole_target > 0.0) {
		// The interior is only interior inside the opening. Painting (and depth-pulling) the inner
		// wall beyond the lip ring is what showed as pink folds around the shaft.
		// Keep the pulled pink well inside the lip ring: it must never reach the rim, or it shows
		// past the lips as a fold.
		float hole_r = length((hole_pos - vulva_centre).xy);
		inside *= 1.0 - smoothstep(hole_target * 0.55, hole_target * 0.8, hole_r);
	}
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
