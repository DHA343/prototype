shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear;
uniform float spread_strength : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float spread_width : hint_range(0.0, 1.0, 0.05) = 0.75;


void fragment() {
	vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec3 output_rgb = screen_color.rgb;
	if (spread_strength > 0.0 && spread_width > 0.0) {
		vec2 offset_uv = SCREEN_PIXEL_SIZE * spread_width * 0.5;
		vec2 lower_uv = SCREEN_PIXEL_SIZE * 0.5;
		vec2 upper_uv = vec2(1.0) - lower_uv;
		// Four bilinear reads spread light to the adjacent pixels without adding energy.
		// Limit the footprint to one pixel so the mask's finest pattern does not reverse.
		vec3 spread_rgb = textureLod(screen_texture,
			clamp(SCREEN_UV + vec2(-offset_uv.x, -offset_uv.y), lower_uv, upper_uv), 0.0).rgb;
		spread_rgb += textureLod(screen_texture,
			clamp(SCREEN_UV + vec2(offset_uv.x, -offset_uv.y), lower_uv, upper_uv), 0.0).rgb;
		spread_rgb += textureLod(screen_texture,
			clamp(SCREEN_UV + vec2(-offset_uv.x, offset_uv.y), lower_uv, upper_uv), 0.0).rgb;
		spread_rgb += textureLod(screen_texture,
			clamp(SCREEN_UV + offset_uv, lower_uv, upper_uv), 0.0).rgb;
		output_rgb = mix(screen_color.rgb, spread_rgb * 0.25, spread_strength);
	}
	COLOR = vec4(output_rgb, screen_color.a);
}
