shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform int input_kind = 0;
uniform float input_level = 0.2;


void fragment() {
	vec2 pixel = floor(FRAGCOORD.xy);
	vec3 input_rgb = vec3(input_level);
	if (input_kind == 1) {
		input_rgb *= pixel.x < 16.0 ? 0.05 : 1.0;
	} else if (input_kind == 2) {
		input_rgb *= pixel.y == 12.0 ? 1.0 : 0.05;
	} else if (input_kind == 3) {
		input_rgb *= pixel.x == 16.0 ? 1.0 : 0.05;
	} else if (input_kind == 4) {
		int channel = int(floor(pixel.x / 4.0)) % 3;
		input_rgb = vec3(0.0);
		input_rgb[channel] = input_level;
	} else if (input_kind == 5) {
		input_rgb *= pixel.x / 31.0;
	}
	COLOR = vec4(input_rgb, 1.0);
}
