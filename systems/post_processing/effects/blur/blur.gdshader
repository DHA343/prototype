shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear_mipmap;

uniform float radius : hint_range(0.0, 16.0, 0.5) = 4.0;
uniform float strength : hint_range(0.0, 1.0, 0.01) = 1.0;


void fragment() {
	vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	float mip_level = log(max(radius, 1.0)) / log(2.0);
	vec4 blurred_color = textureLod(screen_texture, SCREEN_UV, mip_level);

	COLOR = mix(screen_color, blurred_color, strength);
}
