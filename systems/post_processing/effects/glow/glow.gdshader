shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear_mipmap;

uniform float threshold : hint_range(0.0, 8.0, 0.1) = 1.0;
uniform float softness : hint_range(0.01, 4.0, 0.1) = 1.0;
uniform float strength : hint_range(0.0, 10.0, 0.1) = 0.5;
uniform float radius : hint_range(0.0, 8.0, 0.1) = 4.0;


vec3 get_highlight_color(vec2 uv, float mip_level) {
	vec3 color = textureLod(screen_texture, uv, mip_level).rgb;
	float brightness = max(color.r, max(color.g, color.b));
	float highlight = smoothstep(threshold, threshold + softness, brightness);

	return color * highlight;
}


void fragment() {
	vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	float mip_level = log(max(radius, 1.0)) / log(2.0);
	vec3 glow_color = get_highlight_color(SCREEN_UV, mip_level) * 0.5;

	glow_color += get_highlight_color(SCREEN_UV, mip_level + 1.0) * 0.3;
	glow_color += get_highlight_color(SCREEN_UV, mip_level + 2.0) * 0.2;

	COLOR = vec4(screen_color.rgb + glow_color * strength, screen_color.a);
}
