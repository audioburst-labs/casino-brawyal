shader_type canvas_item;
// The menu panel on the title screen (patch 0.125): the scene behind it, blurred
// and pulled toward a deep navy, darkest at the left edge and a little clearer
// toward the right, where it meets the street.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.027, 0.035, 0.11);
uniform float blur_lod = 2.8;

void fragment() {
	vec3 behind = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb;
	float a = mix(0.84, 0.46, smoothstep(0.0, 1.0, UV.x));
	COLOR = vec4(mix(behind * 0.65, tint, a), 1.0);
}
