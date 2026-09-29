shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform int wave_count = 0;
uniform vec4 geometry[16];
uniform vec4 behavior[16];
uniform vec2 heading[16];
uniform vec2 viewport_size = vec2(1920.0, 1080.0);
uniform vec4 ring_color : source_color = vec4(0.8, 0.95, 1.0, 0.48);
uniform float displacement : hint_range(0.0, 6.0) = 2.5;

void fragment() {
	vec2 pixel_position = SCREEN_UV * viewport_size;
	vec2 offset_sum = vec2(0.0);
	float glow = 0.0;
	for (int i = 0; i < wave_count; i++) {
		vec2 axis = heading[i];
		vec2 side = vec2(-axis.y, axis.x);
		vec2 relative = pixel_position - geometry[i].xy;
		vec2 radii = max(geometry[i].zw, vec2(1.0));
		vec2 local_position = vec2(dot(relative, axis), dot(relative, side));
		float ellipse_distance = length(local_position / radii);
		float band_distance = (ellipse_distance - 1.0) * min(radii.x, radii.y);
		float band = exp(-pow(band_distance / 4.0, 2.0));
		vec2 gradient = local_position / (radii * radii);
		vec2 normal_direction = gradient / max(length(gradient), 0.00001);
		vec2 outward = axis * normal_direction.x + side * normal_direction.y;
		offset_sum += outward * band * behavior[i].x * behavior[i].z * displacement;
		glow += band * behavior[i].x * behavior[i].y;
	}
	float offset_length = length(offset_sum);
	offset_sum *= min(1.0, displacement / max(offset_length, 0.0001));
	vec2 sample_uv = clamp(SCREEN_UV - offset_sum / viewport_size, vec2(0.0), vec2(1.0));
	vec4 screen_color = texture(screen_texture, sample_uv);
	COLOR = vec4(mix(screen_color.rgb, ring_color.rgb, min(glow, 1.0) * ring_color.a), 1.0);
}
