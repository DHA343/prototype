shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_nearest;

uniform float scanline_strength : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float scanline_size : hint_range(2.0, 8.0, 0.1) = 3.0;
uniform float luminance_influence : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform int mask_style : hint_enum("Stretched VGA", "VGA") = 0;
uniform float mask_strength : hint_range(0.0, 1.0, 0.01) = 0.67;
uniform float brightness_compensation : hint_range(0.5, 2.0, 0.01) = 1.0;


float get_vga_phase(vec2 position) {
	if (mask_style == 1) {
		position = floor(position * vec2(1.0, 0.5));
	}

	return fract((position.x + position.y * 3.0) / 6.0);
}


vec3 get_vga_mask(float phase) {
	float dark = 1.0 - 0.5 * mask_strength;
	float light = 1.0 + mask_strength;
	vec3 mask = vec3(dark);

	if (phase < 0.3333) {
		mask.r = light;
	} else if (phase < 0.6666) {
		mask.g = light;
	} else {
		mask.b = light;
	}

	return mask;
}


void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);

	float luminance = clamp(dot(screen_color.rgb, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
	float effective_strength = scanline_strength * (1.0 - luminance_influence * luminance);
	// Keep both display patterns aligned to output pixels at every resolution.
	float scanline_phase = fract(FRAGCOORD.y / scanline_size);
	float gap_profile = 0.5 + 0.5 * cos(6.28318530718 * scanline_phase);
	// Balance the beam peak and gap so fine scanlines do not darken the whole image.
	float scanline_brightness = (1.0 - effective_strength * gap_profile)
		/ (1.0 - 0.5 * effective_strength);

	vec2 mask_position = floor(1.000001 * FRAGCOORD.xy + vec2(0.5));
	vec3 shadow_mask = get_vga_mask(get_vga_phase(mask_position));
	vec3 output_rgb = screen_color.rgb * scanline_brightness * shadow_mask;
	COLOR = vec4(output_rgb * brightness_compensation, screen_color.a);
}
