shader_type canvas_item;
// Cloth for the foreground curtain overlay (patch 0.119). The texture is two
// stage curtains framing the left and right edges with the middle transparent;
// this swings each side as fabric hanging from the top: no movement at the
// rail, most at the hem, a slow main swing with a faster ripple over it, and
// a kick on `impulse` when Ace lands something heavy. The overlay sits in front
// of the painting and moves with more parallax, which is what sells the depth.

uniform float speed = 1.0;
uniform float sway = 0.010;                 // UV amplitude at the hem
uniform float ripple = 0.003;
uniform float impulse : hint_range(0.0, 1.0) = 0.0;
uniform vec2 parallax = vec2(0.0, 0.0);

void fragment() {
	float t = TIME * speed;
	vec2 uv = UV + parallax;
	// Left curtain swings on one clock, right on another, so they never mirror.
	float side = uv.x < 0.5 ? 0.0 : 1.0;
	float hang = smoothstep(0.05, 1.0, uv.y);            // rail to hem
	float main_swing = sin(t * 0.33 * 6.2832 + side * 2.4 + uv.y * 2.0) * sway;
	float fine = sin(t * 0.9 * 6.2832 + uv.y * 14.0 + side * 5.0) * ripple;
	float kick = sin(t * 2.6 * 6.2832 + uv.y * 7.0) * impulse * 0.012;
	uv.x += (main_swing + fine + kick) * hang;
	// A hem also lifts a little as it swings out.
	uv.y += abs(main_swing) * hang * 0.35;
	vec4 col = texture(TEXTURE, uv);
	// The folds catch light as they move: brighten with the swing.
	col.rgb *= 1.0 + (main_swing / max(sway, 0.0001)) * 0.05 * hang;
	COLOR = col * COLOR;
}
