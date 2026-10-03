shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Afterimage:0,Frame Blend:1,LCD Response:2,Phosphor Persistence:3,Feedback:4,Frame Hold:5,Temporal AA:6") = 0;
uniform sampler2D history_texture : repeat_disable, filter_linear;
uniform sampler2D velocity_texture : repeat_disable, filter_nearest;
uniform bool history_valid = false;
uniform float frame_delta = 0.016;
uniform float persistence : hint_range(0.01, 2.0, 0.01) = 0.2;
uniform float blend_amount : hint_range(0.0, 0.99, 0.01) = 0.65;
uniform float zoom : hint_range(0.9, 1.1, 0.001) = 1.005;
uniform float rotation : hint_range(-10.0, 10.0, 0.1) = 0.5;
uniform float capture_fps : hint_range(1.0, 60.0, 1.0) = 8.0;

vec3 effect_color(vec2 uv, vec3 c) {
	if (!history_valid) { return c; }
	vec3 previous = texture(history_texture, uv).rgb;
	float decay = exp(-frame_delta / persistence);
	if (mode == 0) { return mix(c, max(c, previous * decay), blend_amount); }
	if (mode == 1) { return mix(c, previous, blend_amount); }
	if (mode == 2) {
		vec3 response = vec3(decay, pow(decay, 0.8), pow(decay, 1.2));
		return mix(c, previous, response);
	}
	if (mode == 3) { return max(c, previous * vec3(pow(decay, 1.3), decay, pow(decay, 1.8))); }
	if (mode == 4) {
		vec2 p = lab_rotate(radians(rotation)) * ((uv - 0.5) / zoom) + 0.5;
		vec3 feedback = texture(history_texture, clamp(p, vec2(0.0), vec2(1.0))).rgb;
		return mix(c, feedback, blend_amount);
	}
	if (mode == 6) {
		vec3 velocity = texture(velocity_texture, uv).rgb;
		vec2 offset = (velocity.rg - 0.5) / 8.0 * velocity.b;
		vec3 history = texture(history_texture, clamp(uv - offset, vec2(0.0), vec2(1.0))).rgb;
		vec3 lo = c;
		vec3 hi = c;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 sample_color = lab_sample(uv + vec2(float(x), float(y)) * lab_pixel_size());
				lo = min(lo, sample_color);
				hi = max(hi, sample_color);
			}
		}
		return mix(c, clamp(history, lo, hi), blend_amount);
	}
	return previous;
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

