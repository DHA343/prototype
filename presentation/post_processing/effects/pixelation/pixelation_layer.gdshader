shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// Transparent HDR Viewport textures contain premultiplied linear RGB.
uniform sampler2D layer_texture : repeat_disable, filter_nearest;
uniform bool pixelation_enabled = true;

#include "pixelation.gdshaderinc"


void fragment() {
	vec2 uv = pixelation_enabled
		? get_pixelated_uv(FRAGCOORD.xy, SCREEN_PIXEL_SIZE) : SCREEN_UV;
	COLOR = texture(layer_texture, uv);
}
