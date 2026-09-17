shader_type canvas_item;
render_mode unshaded;

// Based on the Stretched VGA and VGA shadow mask modes in Libretro dotmask.glsl.
uniform sampler2D screen_texture
	: hint_screen_texture, repeat_disable, filter_nearest;

uniform int mask_style : hint_enum("Stretched VGA", "VGA") = 0;
uniform bool bgr_subpixels = false;
uniform float mask_dark : hint_range(0.0, 2.0, 0.1) = 0.5;
uniform float mask_light : hint_range(0.0, 2.0, 0.1) = 1.5;


float get_vga_phase(vec2 position) {
	if (mask_style == 1) {
		position = floor(position * vec2(1.0, 0.5));
	}

	return fract((position.x + position.y * 3.0) / 6.0);
}


vec3 get_vga_mask(float phase) {
	vec3 mask = vec3(mask_dark);

	if (phase < 0.3333) {
		return bgr_subpixels
			? vec3(mask.r, mask.g, mask_light)
			: vec3(mask_light, mask.g, mask.b);
	}
	if (phase < 0.6666) {
		mask.g = mask_light;
		return mask;
	}
	return bgr_subpixels
		? vec3(mask_light, mask.g, mask.b)
		: vec3(mask.r, mask.g, mask_light);
}


void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec2 mask_position = floor(1.000001 * FRAGCOORD.xy + vec2(0.5));
	float phase = get_vga_phase(mask_position);
	vec3 mask = get_vga_mask(phase);
	vec3 gamma_color = pow(max(screen_color.rgb, vec3(0.0)), vec3(2.2));
	vec3 multiplied_color = pow(
		max(gamma_color * mask, vec3(0.0)),
		vec3(1.0 / 2.2)
	);
	COLOR = vec4(multiplied_color, screen_color.a);
}
