shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_nearest;

uniform int pixel_size : hint_range(1, 32, 1) = 4;
uniform vec2 reference_resolution;


void fragment() {
	vec2 viewport_size = 1.0 / SCREEN_PIXEL_SIZE;

	float resolution_scale = min(
		viewport_size.x / reference_resolution.x,
		viewport_size.y / reference_resolution.y
	);

	float scaled_pixel_size = max(1.0, floor(float(pixel_size) * resolution_scale + 0.5));

	vec2 block_origin = floor(FRAGCOORD.xy / scaled_pixel_size) * scaled_pixel_size;

	vec2 pixelated_uv = (block_origin + vec2(scaled_pixel_size * 0.5)) * SCREEN_PIXEL_SIZE;

	COLOR = texture(screen_texture, pixelated_uv);
}
