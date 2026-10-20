shader_type canvas_item;
// The title screen painting (patch 0.125): the storm clouds drift and the
// puddle in front of the casino ripples. Everything is in the painting's own
// 1536x1024 pixels, so the numbers are the ones measured off the art.

uniform float time = 0.0;

void fragment() {
	vec2 size = vec2(1536.0, 1024.0);
	vec2 p = UV * size;
	vec2 uv = UV;

	// Clouds: rows shear sideways by a few pixels, less and less toward the horizon.
	if (p.y < 300.0) {
		float k = 1.0 - p.y / 300.0;
		float dx = (sin(time * 0.22 + p.y * 0.011) * 5.0 + sin(time * 0.1 + p.y * 0.03) * 3.0) * k;
		uv.x -= dx / size.x;
	}

	// The puddle: everything right of a diagonal edge, below the hedge.
	float edge = 1058.0 - (p.y - 738.0) * (368.0 / 286.0);
	if (p.y > 738.0 && p.x > edge) {
		float wob = sin(p.y * 0.09 + time * 1.6) * 2.2 + sin(p.y * 0.031 - time * 0.9) * 1.6;
		uv.x -= wob / size.x;
	}

	COLOR = texture(TEXTURE, uv);
}
