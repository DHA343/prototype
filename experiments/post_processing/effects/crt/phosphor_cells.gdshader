shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear;
uniform float mask_pitch : hint_range(2.0, 6.0, 1.0) = 3.0;
uniform int row_height : hint_range(1, 8, 1) = 3;
uniform int mask_pattern : hint_enum("Staggered RGB:0", "RGB Stripes:1", "Green / Magenta Stripes:2") = 0;
uniform float mask_strength : hint_range(0.0, 1.0, 0.01) = 0.5;

#include "mask_geometry.gdshaderinc"


vec3 cell_emission(vec2 fragment_position, vec2 screen_uv, vec2 pixel_size) {
	float row_offset = mask_row_offset(
		fragment_position.y, mask_pitch, float(row_height), mask_pattern);
	float pixel_left = fragment_position.x - 0.5;
	// Preserve RGB's center alignment. G/M uses pixel boundaries so a 2px pair stays visible.
	float alignment = mask_pattern == 2 ? 0.0 : 0.5;
	vec3 emission = vec3(0.0);
	for (int sample_x = 0; sample_x < 4; sample_x++) {
		float sample_offset = (float(sample_x) + 0.5) * 0.25 - 0.5;
		vec3 screen_rgb = textureLod(screen_texture,
			screen_uv + vec2(sample_offset, 0.0) * pixel_size, 0.0).rgb;
		vec3 coverage = mask_aperture_integral(
			pixel_left + float(sample_x) * 0.25, 0.25, row_offset,
			mask_pitch, mask_pattern, alignment);
		emission += screen_rgb * coverage;
	}
	// Coverage includes sample area; compensate each channel's emitting occupancy.
	return emission * (mask_pattern == 2 ? 2.0 : 3.0);
}


void fragment() {
	vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec3 output_rgb = screen_color.rgb;
	if (mask_strength > 0.0) {
		vec3 emission = cell_emission(FRAGCOORD.xy, SCREEN_UV, SCREEN_PIXEL_SIZE);
		output_rgb = mix(screen_color.rgb, emission, mask_strength);
	}
	COLOR = vec4(output_rgb, screen_color.a);
}
