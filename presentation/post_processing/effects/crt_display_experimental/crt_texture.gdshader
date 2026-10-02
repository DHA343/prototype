shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear;
uniform float texture_strength : hint_range(0.0, 0.5, 0.01) = 0.2;
uniform float texture_size : hint_range(1.0, 4.0, 0.1) = 1.5;


float variation_hash(ivec2 lattice_cell) {
	uint bits = uint(lattice_cell.x) * 374761393u + uint(lattice_cell.y) * 668265263u;
	bits = (bits ^ (bits >> 16u)) * 2246822519u;
	bits = (bits ^ (bits >> 13u)) * 3266489917u;
	bits = bits ^ (bits >> 16u);
	return float(bits) * (2.0 / 4294967296.0) - 1.0;
}


float lattice_variation(ivec2 cell) {
	// Remove local low frequencies; this is high-pass random, not a blue-noise texture.
	float neighbors = variation_hash(cell + ivec2(-1, 0))
		+ variation_hash(cell + ivec2(1, 0))
		+ variation_hash(cell + ivec2(0, -1))
		+ variation_hash(cell + ivec2(0, 1));
	// Match the unbounded variance to the original before limiting the tails.
	return clamp((variation_hash(cell) - 0.25 * neighbors) * 0.894427191, -1.0, 1.0);
}


float sample_variation(vec2 fragment_position) {
	vec2 pattern_position = fragment_position / texture_size - 0.5;
	ivec2 lattice_cell = ivec2(floor(pattern_position));
	vec2 weights = smoothstep(vec2(0.0), vec2(1.0), fract(pattern_position));
	float upper_variation = mix(lattice_variation(lattice_cell),
		lattice_variation(lattice_cell + ivec2(1, 0)), weights.x);
	float lower_variation = mix(lattice_variation(lattice_cell + ivec2(0, 1)),
		lattice_variation(lattice_cell + ivec2(1, 1)), weights.x);
	return mix(upper_variation, lower_variation, weights.y);
}


void fragment() {
	vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	float multiplier = 1.0;
	if (texture_strength > 0.0) {
		multiplier += texture_strength * sample_variation(FRAGCOORD.xy);
	}
	COLOR = vec4(screen_color.rgb * multiplier, screen_color.a);
}
