shader_type spatial;

// integration: the player part shader. Same lighting as
// near_pony.gdshader. The texture supplies detail and a warm tip mask; the baked AO steps into cel
// shadow bands.
#include "res://addons/cel-shader/includes/base-cel-shader.gdshaderinc"

uniform vec4 color: source_color;
uniform vec4 shadow_color: source_color;
uniform vec4 tip_color: source_color;
uniform vec4 tip_shadow: source_color;
uniform sampler2D base_texture: source_color, hint_default_white;
uniform sampler2D ao_texture: hint_default_white;
uniform sampler2D normal_texture: hint_normal;
uniform vec4 specular: source_color = vec4(0.35, 0.35, 0.35, 0.3);
uniform vec4 fresnel: source_color = vec4(0.1, 0.1, 0.1, 0.1);

// integration: bends the shaft along a circular arc from its root, keeping its length.
uniform vec3 shaft_root = vec3(0.0);
uniform vec3 shaft_axis = vec3(0.0, 0.0, 1.0);
uniform float shaft_length = 1.0;
uniform vec3 bend_turn = vec3(0.0);
uniform float squish_at = 0.0;
uniform float squish = 0.0;
uniform float compress = 0.0;
// integration: thickness multipliers, ramped from the base to the middle of the shaft.
uniform float girth_base = 1.0;
uniform float girth_mid = 1.0;
// integration: the glans thickness band, the axial length stretch and the heartbeat pulse.
uniform float girth_head = 1.0;
uniform float length_scale = 1.0;
uniform float head_start = 0.72;
uniform float head_full = 0.86;
uniform float throb = 0.0;
// integration: the heartbeat also lifts the shaft, most at the tip and none at the base. `throb_up`
// is world up in mesh-local space; the rise reads as the cock bobbing while it is out of her.
uniform float throb_lift = 0.0;
uniform vec3 throb_up = vec3(0.0, 1.0, 0.0);

varying vec3 lit_fill;

vec3 spin(vec3 v, vec3 k, float angle) {
	return v * cos(angle) + cross(k, v) * sin(angle) + k * dot(k, v) * (1.0 - cos(angle));
}

void vertex() {
	float raw = dot(VERTEX - shaft_root, shaft_axis);
	float along = raw * length_scale;
	if (raw > 0.0) {
		vec3 ring = VERTEX - shaft_root - shaft_axis * raw;
		float span = shaft_length * 0.11;
		float near_pinch = (along - squish_at) / span;
		float near_bulge = (along - squish_at + span * 1.8) / (span * 1.2);
		float pinch = exp(-near_pinch * near_pinch);
		float bulge = exp(-near_bulge * near_bulge);
		ring *= 1.0 + squish * (0.07 * bulge - 0.11 * pinch) + compress * 0.8;
		float length_t = clamp(along / max(shaft_length, 0.001), 0.0, 1.0);
		ring *= mix(girth_base, girth_mid, smoothstep(0.0, 0.35, length_t));
		ring *= mix(1.0, girth_head, smoothstep(head_start, head_full, length_t));
		ring *= 1.0 + throb;
		// Stretching along the axis changes the normal's axial share.
		float axial = dot(NORMAL, shaft_axis);
		NORMAL = normalize(NORMAL - shaft_axis * axial
			+ shaft_axis * axial / max(length_scale, 0.001));
		float stem = along * (1.0 - compress);
		vec3 centre = shaft_root + shaft_axis * stem;
		float angle = length(bend_turn);
		if (angle > 0.001) {
			vec3 k = bend_turn / angle;
			vec3 side = cross(k, shaft_axis);
			float radius = shaft_length / angle;
			float turn = angle * stem / shaft_length;
			centre = shaft_root + shaft_axis * radius * sin(turn) + side * radius * (1.0 - cos(turn));
			ring = spin(ring, k, turn);
			NORMAL = spin(NORMAL, k, turn);
		}
		VERTEX = centre + ring;
		if (throb_lift > 0.0) {
			// Up perpendicular to the shaft, so the lift is a bow and never a length pulse.
			vec3 up = throb_up - shaft_axis * dot(shaft_axis, throb_up);
			float up_len = length(up);
			if (up_len > 0.001) {
				float lift_t = clamp(along / max(shaft_length, 0.001), 0.0, 1.0);
				VERTEX += up * (throb_lift * lift_t * lift_t / up_len);
			}
		}
	}
}

void fragment() {
	vec3 tex = texture(base_texture, UV).rgb;
	float ao = texture(ao_texture, UV).r;
	float warm = smoothstep(2.2, 2.45, tex.r / max(tex.g, 0.01));
	float value = clamp(dot(tex, vec3(0.333)) / 0.2, 0.7, 1.25);
	float crease = smoothstep(0.66, 0.74, ao);
	float deep = smoothstep(0.46, 0.54, ao);
	float contour = step(dot(NORMAL, VIEW), 0.3);

	vec3 fill = mix(color.rgb, tip_color.rgb, warm) * value;
	vec3 shade = mix(shadow_color.rgb, tip_shadow.rgb, warm) * value;
	fill = mix(shade, fill, crease);
	shade *= mix(0.72, 1.0, deep);
	lit_fill = mix(fill, shade * 0.8, contour);
	ALBEDO = shade * mix(0.8, 1.0, 1.0 - contour);
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = 0.8;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	DIFFUSE_LIGHT += diffuse_light(lit_fill, LIGHT_COLOR, LIGHT, NORMAL, ATTENUATION);
	SPECULAR_LIGHT += specular_light(LIGHT_COLOR, specular.rgb, specular.a, NORMAL, VIEW, LIGHT, ATTENUATION);
	SPECULAR_LIGHT += fresnel_light(LIGHT_COLOR, fresnel.rgb, fresnel.a, NORMAL, VIEW, LIGHT, ATTENUATION);
}
