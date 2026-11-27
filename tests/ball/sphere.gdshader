shader_type canvas_item;
render_mode unshaded;

uniform int pattern : hint_enum("Solid:0", "Single band:1", "FastNoise:4") = 0;
uniform vec4 body_color : source_color = vec4(0.8, 0.85, 0.9, 1.0);
uniform vec4 pattern_color : source_color = vec4(0.14, 0.23, 0.32, 1.0);
uniform float line_width : hint_range(0.06, 0.24) = 0.12;
uniform sampler3D noise_texture : source_color, filter_linear, repeat_disable;
uniform float gloss : hint_range(0.0, 1.0) = 0.35;
uniform float metal : hint_range(0.0, 1.0) = 0.0;
uniform mat3 surface_basis = mat3(1.0);

const int SINGLE_BAND = 1;
const int FAST_NOISE = 4;
const vec3 KEY = vec3(-0.43, 0.61, 0.665);
const vec3 FILL = vec3(0.62, -0.52, 0.59);
const vec3 SOFT_BLUE = vec3(0.27, 0.42, 0.64);

float band(float distance, float width, float feather) {
	return 1.0 - smoothstep(width - feather, width + feather, abs(distance));
}

float painted_band(float distance) {
	float feather = clamp(fwidth(distance) * 0.52, 0.008, 0.09);
	return band(distance, line_width, feather);
}

vec3 surface_paint(vec3 surface) {
	vec3 paint = body_color.rgb;
	if (pattern == FAST_NOISE) {
		paint = texture(noise_texture, surface * 0.46 + vec3(0.5)).rgb;
	} else if (pattern == SINGLE_BAND) {
		float across = dot(surface, normalize(vec3(0.43, 0.88, 0.18)));
		paint = mix(paint, pattern_color.rgb, painted_band(across));
	}
	return paint;
}

void fragment() {
	vec2 face = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float radius_squared = dot(face, face);
	float edge = max(fwidth(radius_squared) * 0.48, 0.004);
	float coverage = 1.0 - smoothstep(1.0 - edge, 1.0 + edge, radius_squared);
	vec3 normal = vec3(face, sqrt(max(0.0, 1.0 - radius_squared)));

	vec3 paint = surface_paint(surface_basis * normal);
	float lighting = max(0.0, dot(normal, KEY));
	float fill = max(0.0, dot(normal, FILL));
	float diffuse = 0.20 + 0.69 * lighting + 0.16 * fill * fill;
	float half_angle = max(0.0, dot(normal, normalize(KEY + vec3(0.0, 0.0, 1.0))));
	float highlight = pow(half_angle, mix(7.0, 72.0, gloss));
	vec3 shaded = paint * diffuse + vec3(highlight * mix(0.11, 0.65, gloss));

	vec3 reflected = reflect(vec3(0.0, 0.0, -1.0), normal);
	float softbox = band(reflected.y - 0.49, 0.10, 0.19)
		* band(reflected.x + 0.34, 0.39, 0.38) * smoothstep(-0.45, 0.35, reflected.z);
	float horizon = band(reflected.y + 0.43, 0.10, 0.19);
	vec3 reflections = paint * (0.13 + 0.40 * lighting)
		+ vec3(0.79, 0.86, 0.93) * softbox
		+ SOFT_BLUE * horizon * 0.55;
	shaded = mix(shaded, reflections + vec3(highlight * 0.52), metal);
	shaded += SOFT_BLUE * pow(max(0.0, 1.0 - normal.z), 3.0) * (0.10 + metal * 0.20);
	COLOR = vec4(shaded, coverage);
}
