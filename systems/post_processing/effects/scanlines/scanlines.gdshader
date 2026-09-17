shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture
	: hint_screen_texture, repeat_disable, filter_nearest;

uniform float line_count : hint_range(1.0, 1080.0, 1.0) = 240.0;
uniform float line_thickness : hint_range(0.01, 1.0, 0.01) = 0.5;
uniform float edge_softness : hint_range(0.0, 0.5, 0.01) = 0.05;
uniform float strength : hint_range(0.0, 1.0, 0.01) = 0.3;


float get_scanline_brightness(float screen_y) {
	float safe_line_count = max(line_count, 1.0);
	float safe_line_thickness = clamp(line_thickness, 0.01, 1.0);
	float safe_edge_softness = clamp(edge_softness, 0.0, 0.5);
	float safe_strength = clamp(strength, 0.0, 1.0);
	float phase = fract(screen_y * safe_line_count);
	float distance_to_line_center = abs(phase - 0.5);
	float line_half_width = safe_line_thickness * 0.5;
	float edge_end = min(line_half_width + safe_edge_softness, 0.5);
	edge_end = max(edge_end, line_half_width + 0.0001);
	float line_mask = 1.0 - smoothstep(
		line_half_width,
		edge_end,
		distance_to_line_center
	);

	return clamp(1.0 - line_mask * safe_strength, 0.0, 1.0);
}


void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	float brightness = get_scanline_brightness(SCREEN_UV.y);
	COLOR = vec4(screen_color.rgb * brightness, screen_color.a);
}
