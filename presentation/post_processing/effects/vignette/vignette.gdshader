shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_nearest;

uniform float strength : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float radius : hint_range(0.0, 1.0, 0.01) = 0.58;
uniform float softness : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float falloff : hint_range(0.1, 4.0, 0.01) = 1.8;
uniform int shape_mode : hint_enum("Screen Ellipse", "Physical Circle") = 0;
uniform float center_x : hint_range(0.25, 0.75, 0.01) = 0.50;
uniform float center_y : hint_range(0.25, 0.75, 0.01) = 0.48;
uniform vec4 vignette_color : source_color = vec4(0.008, 0.004, 0.02, 1.0);


float get_vignette_amount(vec2 uv, float physical_aspect_ratio) {
	vec2 centered_uv = uv - vec2(center_x, center_y);
	float ratio = 1.0;
	if (shape_mode == 1) {
		ratio = physical_aspect_ratio;
	}

	float distance_from_center = length(vec2(centered_uv.x * ratio, centered_uv.y));
	float corner_distance = max(
		length(vec2((max(center_x, 1.0 - center_x)) * ratio, max(center_y, 1.0 - center_y))),
		0.001
	);
	float normalized_distance = clamp(
		distance_from_center / corner_distance,
		0.0,
		1.0
	);
	float radius_distance = max(1.0 - radius, 0.0001);
	float radial_amount = clamp(
		(normalized_distance - radius) / radius_distance,
		0.0,
		1.0
	);
	float smooth_amount = smoothstep(0.0, 1.0, radial_amount);
	float edge_amount = mix(radial_amount, smooth_amount, softness);
	edge_amount = pow(edge_amount, max(falloff, 0.0001));

	return clamp(edge_amount * strength * vignette_color.a, 0.0, 1.0);
}


void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	float physical_aspect_ratio = SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.0001);
	float vignette_amount = get_vignette_amount(SCREEN_UV, physical_aspect_ratio);
	vec3 color_filter = mix(
		vec3(1.0),
		clamp(vignette_color.rgb, vec3(0.0), vec3(1.0)),
		vignette_amount
	);
	COLOR = vec4(max(screen_color.rgb * color_filter, vec3(0.0)), screen_color.a);
}
