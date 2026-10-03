shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

// These effects operate on a 2D height field, with near=0 and far=1.
uniform int mode : hint_enum("Depth of Field:0,Bokeh:1,Depth Fog:2,SSAO (pseudo):3,SSR (pseudo):4,Contact Shadows:5,Light Shafts:6,Normal Lighting:7,Depth Outline:8,SSIL (pseudo):9,Volumetric Fog (pseudo):10") = 0;
uniform int depth_source : hint_enum("Luminance:0,Vertical Plane:1,Radial Dome:2,Custom Depth Map:3") = 0;
uniform sampler2D custom_depth : repeat_disable, filter_linear;
uniform sampler2D custom_normal : repeat_disable, filter_linear;
uniform bool use_custom_normal = false;
uniform bool invert_depth = false;
uniform float depth_scale : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float normal_scale : hint_range(0.0, 30.0, 0.1) = 8.0;
uniform float amount : hint_range(0.0, 3.0, 0.01) = 0.8;
uniform float radius : hint_range(0.0, 64.0, 0.5) = 12.0;
uniform float focus_depth : hint_range(0.0, 1.0, 0.01) = 0.4;
uniform float focus_width : hint_range(0.01, 1.0, 0.01) = 0.12;
uniform float depth_bias : hint_range(0.001, 0.3, 0.001) = 0.015;
uniform float depth_range : hint_range(0.01, 1.0, 0.01) = 0.25;
uniform vec2 light_position = vec2(0.7, 0.2);
uniform vec4 tint : source_color = vec4(0.65, 0.8, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.2;

float depth_at(vec2 uv) {
	vec2 p = clamp(uv, vec2(0.0), vec2(1.0));
	float d = 1.0 - clamp(lab_luma(lab_sample(p)), 0.0, 1.0);
	if (depth_source == 1) { d = 1.0 - p.y; }
	else if (depth_source == 2) { d = clamp(length(p - 0.5) * 1.5, 0.0, 1.0); }
	else if (depth_source == 3) { d = texture(custom_depth, p).r; }
	d = clamp(d * depth_scale, 0.0, 1.0);
	return invert_depth ? 1.0 - d : d;
}
vec3 normal_at(vec2 uv) {
	if (use_custom_normal) { return normalize(texture(custom_normal, uv).rgb * 2.0 - 1.0 + vec3(0.0, 0.0, 0.00001)); }
	vec2 px = lab_pixel_size() * 2.0;
	vec2 gradient = vec2(depth_at(uv + vec2(px.x, 0.0)) - depth_at(uv - vec2(px.x, 0.0)),
		depth_at(uv + vec2(0.0, px.y)) - depth_at(uv - vec2(0.0, px.y)));
	return normalize(vec3(gradient * normal_scale, 1.0));
}
vec3 effect_color(vec2 uv, vec3 c) {
	float d = depth_at(uv);
	vec2 px = lab_pixel_size();
	if (mode <= 1) {
		float coc = smoothstep(focus_width, focus_width + 0.3, abs(d - focus_depth));
		vec3 total = c;
		float weight = 1.0;
		for (int i = 0; i < 32; i++) {
			float f = (float(i) + 0.5) / 32.0;
			float a = float(i) * 2.399963;
			vec2 p = uv + vec2(cos(a), sin(a)) * sqrt(f) * radius * coc * px;
			vec3 tap = lab_sample(p);
			// Foreground samples remain visible; farther samples cannot leak through sharp near pixels.
			float w = 1.0 - smoothstep(0.03, 0.18, depth_at(p) - d);
			if (mode == 1) { w *= 1.0 + max(lab_luma(tap) - 0.7, 0.0) * amount * 4.0; }
			total += tap * w;
			weight += w;
		}
		return mix(c, total / max(weight, 0.001), min(amount, 1.0));
	}
	if (mode == 2) { return mix(c, tint.rgb, 1.0 - exp(-d * amount * 2.0)); }
	if (mode == 3) {
		float occlusion = 0.0;
		vec3 n = normal_at(uv);
		for (int i = 0; i < 16; i++) {
			float a = float(i) * 2.399963;
			vec2 offset = vec2(cos(a), sin(a)) * radius * px * sqrt((float(i) + 1.0) / 16.0);
			float sample_depth = depth_at(uv + offset);
			float expected = d + dot(n.xy, offset / max(px, vec2(0.00001))) * 0.001;
			float delta = expected - sample_depth;
			occlusion += smoothstep(depth_bias, depth_bias + 0.03, delta)
				* (1.0 - smoothstep(depth_range * 0.5, depth_range, abs(delta)));
		}
		return c * max(0.0, 1.0 - occlusion * amount / 16.0);
	}
	if (mode == 4) {
		vec3 n = normal_at(uv);
		vec3 ray = reflect(vec3(0.0, 0.0, -1.0), n);
		vec3 reflection = c;
		float hit = 0.0;
		for (int i = 1; i <= 32; i++) {
			float t = float(i) / 32.0;
			vec2 p = uv + ray.xy * t * radius * px * 8.0;
			float ray_depth = d + ray.z * t * depth_range;
			if (p.x < 0.0 || p.y < 0.0 || p.x > 1.0 || p.y > 1.0) { break; }
			float crossing = depth_at(p) - ray_depth;
			if (abs(crossing) < depth_bias + 0.02 && i > 2) {
				reflection = lab_blur(p, roughness * radius);
				hit = (1.0 - t) * smoothstep(0.0, 0.1, min(min(p.x, p.y), min(1.0 - p.x, 1.0 - p.y)));
				break;
			}
		}
		float fresnel = 0.15 + 0.85 * pow(1.0 - abs(n.z), 3.0);
		return mix(c, reflection * tint.rgb, clamp(hit * fresnel * amount, 0.0, 1.0));
	}
	if (mode == 5) {
		vec2 direction = normalize(light_position - uv + vec2(0.00001));
		float blocked = 0.0;
		for (int i = 1; i <= 24; i++) {
			float t = float(i) / 24.0;
			float obstacle = d - depth_at(uv + direction * t * radius * px * 3.0);
			blocked = max(blocked, smoothstep(depth_bias, depth_bias + 0.05, obstacle) * (1.0 - t));
		}
		return c * max(0.0, 1.0 - blocked * amount);
	}
	if (mode == 6) {
		vec3 shafts = vec3(0.0);
		float transmission = 1.0;
		for (int i = 0; i < 32; i++) {
			float t = float(i) / 32.0;
			vec2 p = mix(uv, light_position, t * 0.95);
			transmission *= mix(0.94, 1.0, depth_at(p));
			vec3 tap = lab_sample(p);
			shafts += max(tap - vec3(0.5), vec3(0.0)) * transmission;
		}
		return c + shafts * tint.rgb * amount / 16.0;
	}
	if (mode == 7) {
		vec3 n = normal_at(uv);
		vec3 light = normalize(vec3((light_position - uv) * 2.0, 0.4));
		float diffuse = max(dot(n, light), 0.0);
		float specular = pow(max(dot(n, normalize(light + vec3(0.0, 0.0, 1.0))), 0.0), mix(80.0, 4.0, roughness));
		return mix(c, c * (0.2 + diffuse * tint.rgb) + tint.rgb * specular * 0.25, min(amount, 1.0));
	}
	if (mode == 9) {
		vec3 bounce = vec3(0.0);
		for (int i = 0; i < 16; i++) {
			float a = float(i) * 2.399963;
			vec2 p = uv + vec2(cos(a), sin(a)) * radius * px * sqrt((float(i) + 1.0) / 16.0);
			float delta = abs(depth_at(p) - d);
			float visibility = 1.0 - smoothstep(depth_bias, depth_range, delta);
			bounce += lab_sample(p) * visibility;
		}
		return c + bounce * (0.25 + c * 0.75) * amount / 32.0;
	}
	if (mode == 10) {
		float density = 0.0;
		for (int i = 0; i < 24; i++) {
			float t = (float(i) + 0.5) / 24.0;
			vec2 p = mix(vec2(uv.x, 1.0), uv, t);
			float cloud = lab_hash(floor(p * 24.0 + vec2(TIME * 0.2, t * 4.0)));
			density += mix(0.4, 1.0, cloud) * step(t, d);
		}
		float transmission = exp(-density * amount / 12.0);
		float forward_light = exp(-length(uv - light_position) * 3.0);
		return c * transmission + tint.rgb * (0.3 + forward_light) * (1.0 - transmission);
	}
	vec2 gradient = vec2(depth_at(uv + vec2(px.x, 0.0)) - depth_at(uv - vec2(px.x, 0.0)),
		depth_at(uv + vec2(0.0, px.y)) - depth_at(uv - vec2(0.0, px.y)));
	return mix(c, tint.rgb, clamp(length(gradient) * amount * 3.0, 0.0, 1.0));
}
void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}
