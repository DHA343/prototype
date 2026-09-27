shader_type canvas_item;
render_mode unshaded;

uniform vec4 dark_color : source_color = vec4(0.05, 0.055, 0.07, 1.0);
uniform vec4 light_color : source_color = vec4(0.075, 0.08, 0.1, 1.0);
uniform float cell_size : hint_range(1.0, 512.0, 1.0) = 96.0;

varying vec2 world_position;


void vertex() {
	world_position = (
		MODEL_MATRIX
		* vec4(VERTEX, 0.0, 1.0)
	).xy;
}


void fragment() {
	vec2 cell_position = floor(world_position / cell_size);
	float checker = mod(cell_position.x + cell_position.y, 2.0);
	COLOR = mix(dark_color, light_color, checker);
}
