shader_type canvas_item;
render_mode unshaded;

uniform int shape_type : hint_enum("Circle", "Square") = 0;
uniform int fill_type : hint_enum("Solid", "Linear Gradient", "Radial Gradient", "Hard Split", "Quadrants", "HDR Gradient", "Vertical Lines", "Horizontal Lines", "Diagonal Lines", "RGB Dots", "Concentric Rings") = 0;
uniform vec4 color_a : source_color = vec4(1.0);
uniform vec4 color_b : source_color = vec4(0.0);
uniform vec4 color_c : source_color = vec4(0.0);
uniform vec4 color_d : source_color = vec4(1.0);
uniform float hdr_multiplier : hint_range(1.0, 4.0, 0.1) = 1.0;

const float REFERENCE_SIZE = 210.0;


void fragment() {
	vec3 fill_color = color_a.rgb;
	vec2 local_pixel = floor(UV * REFERENCE_SIZE);
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
	} else if (fill_type == 6) {
		float line_width = UV.y < 1.0 / 3.0 ? 1.0 : UV.y < 2.0 / 3.0 ? 2.0 : 4.0;
		fill_color = mod(local_pixel.x, line_width * 4.0) < line_width
			? color_a.rgb : color_b.rgb;
	} else if (fill_type == 7) {
		float line_width = UV.x < 1.0 / 3.0 ? 1.0 : UV.x < 2.0 / 3.0 ? 2.0 : 4.0;
		fill_color = mod(local_pixel.y, line_width * 4.0) < line_width
			? color_a.rgb : color_b.rgb;
	} else if (fill_type == 8) {
		fill_color = mod(local_pixel.x + local_pixel.y, 12.0) < 2.0
			? color_a.rgb : color_b.rgb;
	} else if (fill_type == 9) {
		vec2 dot_position = mod(local_pixel, vec2(18.0));
		fill_color = color_d.rgb;
		if (dot_position.y >= 2.0 && dot_position.y < 7.0) {
			if (dot_position.x >= 1.0 && dot_position.x < 6.0) {
				fill_color = color_a.rgb;
			} else if (dot_position.x >= 7.0 && dot_position.x < 12.0) {
				fill_color = color_b.rgb;
			} else if (dot_position.x >= 13.0) {
				fill_color = color_c.rgb;
			}
		}
	} else if (fill_type == 10) {
		float radius_pixels = floor(length(UV - vec2(0.5)) * REFERENCE_SIZE);
		fill_color = mod(radius_pixels, 12.0) < 2.0 ? color_a.rgb : color_b.rgb;
	}

	float coverage = 1.0;
	if (shape_type == 0) {
		float radius = length(UV * 2.0 - vec2(1.0));
		coverage = 1.0 - smoothstep(0.985, 1.0, radius);
	}
	COLOR = vec4(fill_color, coverage);
}
