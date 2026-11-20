uniform int pixel_size : hint_range(1, 32, 1) = 4;
uniform vec2 reference_resolution;


vec2 get_pixelated_uv(vec2 fragment_position, vec2 screen_pixel_size) {
	vec2 viewport_size = 1.0 / screen_pixel_size;
	float resolution_scale = min(
		viewport_size.x / reference_resolution.x,
		viewport_size.y / reference_resolution.y
	);
	float scaled_pixel_size = max(1.0, floor(float(pixel_size) * resolution_scale + 0.5));
	vec2 block_origin = floor(fragment_position / scaled_pixel_size) * scaled_pixel_size;
	return (block_origin + vec2(scaled_pixel_size * 0.5)) * screen_pixel_size;
}
