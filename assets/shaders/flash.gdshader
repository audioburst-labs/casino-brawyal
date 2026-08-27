shader_type canvas_item;
// White impact flash: mixes the sprite toward pure white by `flash`.
// (modulate can only darken/tint, so hits need a shader to blow out white.)

uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(mix(tex.rgb, vec3(1.0), flash), tex.a) * COLOR;
}
