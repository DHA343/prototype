shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_nearest;

uniform float brightness : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform float contrast : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float saturation : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float hue : hint_range(-180.0, 180.0, 1.0) = 0.0;
uniform float gamma : hint_range(0.1, 3.0, 0.01) = 1.0;


vec3 rotate_hue(vec3 color, float degrees) {
	vec3 axis = vec3(0.5773502692);
	float angle = radians(degrees);
	float cosine = cos(angle);
	float sine = sin(angle);

	return color * cosine + cross(axis, color) * sine + axis * dot(axis, color) * (1.0 - cosine);
}


void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 color = screen_color.rgb + vec3(brightness);

	color = (color - vec3(0.5)) * contrast + vec3(0.5);

	float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luminance), color, saturation);
	color = rotate_hue(color, hue);
	color = pow(max(color, vec3(0.0)), vec3(1.0 / gamma));

	COLOR = vec4(max(color, vec3(0.0)), screen_color.a);
}
