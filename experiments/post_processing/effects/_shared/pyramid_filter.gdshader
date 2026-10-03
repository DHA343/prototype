shader_type canvas_item;
render_mode unshaded;

uniform sampler2D input_texture : repeat_disable, filter_linear;
uniform sampler2D detail_texture : repeat_disable, filter_linear;
uniform int stage = 0;
uniform float radius = 1.0;
uniform float threshold = 0.8;
uniform bool bloom = false;

void fragment() {
	vec2 p = (vec2(0.5) + radius) / vec2(textureSize(input_texture, 0));
	vec3 result = texture(input_texture, UV).rgb;
	if (stage == 2) {
		float l = dot(result, vec3(0.2126, 0.7152, 0.0722));
		result *= max(l - threshold, 0.0) / max(l, 0.0001);
	} else if (stage == 0) {
		result = result * 4.0;
		result += texture(input_texture, UV + p).rgb;
		result += texture(input_texture, UV - p).rgb;
		result += texture(input_texture, UV + vec2(p.x, -p.y)).rgb;
		result += texture(input_texture, UV + vec2(-p.x, p.y)).rgb;
		result /= 8.0;
	} else {
		result = vec3(0.0);
		result += texture(input_texture, UV + vec2(-2.0 * p.x, 0.0)).rgb;
		result += texture(input_texture, UV + vec2(-p.x, p.y)).rgb * 2.0;
		result += texture(input_texture, UV + vec2(0.0, 2.0 * p.y)).rgb;
		result += texture(input_texture, UV + p).rgb * 2.0;
		result += texture(input_texture, UV + vec2(2.0 * p.x, 0.0)).rgb;
		result += texture(input_texture, UV + vec2(p.x, -p.y)).rgb * 2.0;
		result += texture(input_texture, UV + vec2(0.0, -2.0 * p.y)).rgb;
		result += texture(input_texture, UV - p).rgb * 2.0;
		result /= 12.0;
		if (bloom) { result = mix(result, texture(detail_texture, UV).rgb, 0.5); }
	}
	COLOR = vec4(result, 1.0);
}
