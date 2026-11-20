shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_nearest;

#include "pixelation.gdshaderinc"


void fragment() {
	COLOR = texture(screen_texture, get_pixelated_uv(FRAGCOORD.xy, SCREEN_PIXEL_SIZE));
}
