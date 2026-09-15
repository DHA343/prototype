shader_type canvas_item;

instance uniform float softness = 0.35;
instance uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.35);


void fragment() {
	vec2 point = UV * 2.0 - vec2(1.0);
	float distance_from_center = length(point);
	float edge_start = 1.0 - clamp(softness, 0.001, 1.0);
	float alpha = 1.0 - smoothstep(edge_start, 1.0, distance_from_center);
	COLOR = vec4(shadow_color.rgb, shadow_color.a * alpha);
}
