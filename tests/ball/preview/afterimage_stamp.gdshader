shader_type canvas_item;
render_mode unshaded;

uniform bool gradient_enabled = true;
uniform float root_color_hold = 0.28;
uniform float edge_color_strength = 1.0;
uniform float base_opacity = 0.88;

varying float freshness;

void vertex() {
	freshness = COLOR.a;
}

void fragment() {
	float radial_distance = length(UV * 2.0 - 1.0);
	float palette_position = 0.0;
	float coverage = step(radial_distance, 1.0);
	if (gradient_enabled) {
		float age = 1.0 - freshness;
		float age_position = smoothstep(root_color_hold, 1.0, age);
		float rim_onset = smoothstep(root_color_hold, mix(root_color_hold, 1.0, 0.53), age);
		float rim_position = smoothstep(0.48, 1.0, radial_distance);
		palette_position = mix(age_position, 1.0, rim_position * rim_onset * edge_color_strength);
		coverage = 1.0 - smoothstep(0.4, 1.0, radial_distance);
	}
	vec4 tint = texture(TEXTURE, vec2(palette_position, 0.5));
	float opacity = base_opacity * smoothstep(0.0, 0.65, freshness);
	COLOR = vec4(tint.rgb, tint.a * coverage * opacity);
}
