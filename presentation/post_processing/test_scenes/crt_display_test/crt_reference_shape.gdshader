shader_type canvas_item;
render_mode unshaded;

uniform int shape_type : hint_enum("Circle", "Square") = 0;
uniform int fill_type : hint_enum("Solid", "Linear Gradient", "Radial Gradient", "Hard Split", "Quadrants", "HDR Gradient") = 0;
uniform vec4 color_a : source_color = vec4(1.0);
uniform vec4 color_b : source_color = vec4(0.0);
uniform vec4 color_c : source_color = vec4(0.0);
uniform vec4 color_d : source_color = vec4(1.0);
uniform float hdr_multiplier : hint_range(1.0, 4.0, 0.1) = 1.0;


void fragment() {
	vec3 fill_color = color_a.rgb;
	if (fill_type == 1) {
		fill_color = mix(color_a.rgb, color_b.rgb, UV.x);
	} else if (fill_type == 2) {
		float radius = clamp(length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
		fill_color = mix(color_a.rgb, color_b.rgb, radius);
	} else if (fill_type == 3) {
		fill_color = UV.x < 1.0 / 3.0 ? color_a.rgb
			: UV.x < 2.0 / 3.0 ? color_b.rgb : color_c.rgb;
	} else if (fill_type == 4) {
		fill_color = UV.y < 0.5
			? (UV.x < 0.5 ? color_a.rgb : color_b.rgb)
			: (UV.x < 0.5 ? color_c.rgb : color_d.rgb);
	} else if (fill_type == 5) {
		fill_color = mix(color_a.rgb, color_b.rgb * hdr_multiplier, UV.y);
	}

	float coverage = 1.0;
	if (shape_type == 0) {
		float radius = length(UV * 2.0 - vec2(1.0));
		coverage = 1.0 - smoothstep(0.985, 1.0, radius);
	}
	COLOR = vec4(fill_color, coverage);
}
