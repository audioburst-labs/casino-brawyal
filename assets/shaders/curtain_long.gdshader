shader_type canvas_item;
// One LONG curtain for the screen-change transition (patch 0.125, third pass).
//
// The idle curtain is the front end of a curtain that is much longer than the
// screen: the artwork (swag, tassel, hem) hangs at the edge exactly as it
// always did, and its cloth continues off-screen behind it. Sliding the whole
// thing inward brings that cloth into view, so the curtain closes without being
// copied or stretched.
//
// The artwork ends at the screen edge with its tie-back tassel cut in half, so
// the first stretch of the extension is the artwork mirrored about that edge
// (it completes the tassel) and then fades into plain velvet in the artwork's
// own palette. The sway is copied from curtain_cloth.gdshader, so at rest this
// is the idle curtain, and the cloth is sheared by `tip_px`, the lag of the hem
// behind the rail it hangs from.

uniform sampler2D art : filter_linear;
uniform float dir = 1.0;                  // +1 left curtain, -1 right curtain
uniform vec2 rect_px = vec2(2000.0, 1080.0);
uniform vec4 art_rect = vec4(0.0, 0.0, 1920.0, 1280.0);   // where the FULL picture sits in this rect, px
uniform float tip_px = 0.0;
uniform float billow = 0.0;               // 0 hanging still, 1 being dragged
uniform float mirror_px = 125.0;
uniform float speed = 1.0;
uniform float sway = 0.010;
uniform float ripple = 0.003;
uniform vec4 deep : source_color = vec4(0.05, 0.004, 0.014, 1.0);
uniform vec4 lit : source_color = vec4(0.40, 0.055, 0.085, 1.0);

vec3 velvet(float d, float y_px) {
	// Folds that are not a pattern: three waves of unrelated lengths, each leaning
	// and curving by its own amount down the cloth, plus slow patches of light and
	// dark. `dir` and the distance keep the two curtains from matching. Reds only;
	// the gold stays on the artwork's edges and ropes.
	float s = dir * 7.3;
	float w1 = sin(d * 0.0520 + s + 1.3 + 1.7 * sin(y_px * 0.0031 + d * 0.0042 + s));
	float w2 = sin(d * 0.0971 + s * 1.9 + 4.1 + 1.1 * sin(y_px * 0.0047 + 2.0 + d * 0.0016));
	float w3 = sin(d * 0.0237 + s * 0.6 + 0.7 * sin(y_px * 0.0021 + 5.0));
	float w4 = sin(d * 0.1630 + y_px * 0.0011 + s * 2.3);
	float fold = 0.5 + 0.5 * clamp((0.40 * w1 + 0.20 * w2 + 0.46 * w3 + 0.10 * w4) / 0.95, -1.0, 1.0);
	// Some folds are deep and some shallow.
	float depth = 0.65 + 0.35 * sin(d * 0.0063 + y_px * 0.0009 + s * 3.1);
	vec3 col = mix(deep.rgb, lit.rgb, smoothstep(0.10, 0.90, fold) * depth + (1.0 - depth) * 0.3);
	// Creases at the bottom of a fold are a little darker.
	col *= mix(0.72, 1.0, smoothstep(0.04, 0.32, fold));
	// Slow drifts of light across the cloth.
	col *= 0.9 + 0.2 * sin(d * 0.0031 + y_px * 0.0017 + s) * sin(y_px * 0.0023 + d * 0.0011);
	return col * mix(0.55, 1.0, smoothstep(0.0, 270.0, y_px));
}

void fragment() {
	vec2 p = UV * rect_px;
	float yf = clamp(p.y / rect_px.y, 0.0, 1.0);
	// The hem lags behind the rail; the lower the cloth, the more.
	p.x -= tip_px * pow(yf, 1.6);

	// The picture's own coordinates, with the idle sway (copied) on top.
	vec2 uv = (p - art_rect.xy) / art_rect.zw;
	// The idle curtain's own shader ends `COLOR = col * COLOR`, and COLOR already
	// holds the picture's pixel at that spot, so the idle curtain is drawn with its
	// pixel squared: darker and richer than the raw artwork. Matching it means
	// doing the same, with the same unswayed pixel (this is why the first version
	// was visibly brighter than the idle curtain).
	vec2 uv0 = uv;
	float t = TIME * speed;
	float side = dir > 0.0 ? 0.0 : 1.0;
	float hang = smoothstep(0.05, 1.0, uv.y);
	float amp = 1.0 + billow * 2.5;
	float main_swing = sin(t * 0.33 * 6.2832 + side * 2.4 + uv.y * 2.0) * sway * amp;
	float fine = sin(t * 0.9 * 6.2832 + uv.y * 14.0 + side * 5.0) * ripple * amp;
	uv.x += (main_swing + fine) * hang;
	uv.y += abs(main_swing) * hang * 0.35;

	// Distance past the screen edge's end of the picture, in px (negative inside).
	float d = dir > 0.0 ? -uv.x * art_rect.z : (uv.x - 1.0) * art_rect.z;
	vec4 col;
	if (d <= 0.0) {
		col = texture(art, uv);
		col *= texture(art, uv0);
		// Only this side's half of the picture.
		col.a *= dir > 0.0 ? step(uv.x, 0.5) : step(0.5, uv.x);
	} else {
		// The first stretch mirrors the picture about its edge (completing the
		// cut tassel), then it fades into velvet.
		float mx = dir > 0.0 ? d / art_rect.z : 1.0 - d / art_rect.z;
		vec4 mir = texture(art, vec2(mx, uv.y));
		float d0 = dir > 0.0 ? -uv0.x * art_rect.z : (uv0.x - 1.0) * art_rect.z;
		vec2 uv0m = vec2(dir > 0.0 ? d0 / art_rect.z : 1.0 - d0 / art_rect.z, uv0.y);
		mir *= texture(art, uv0m);
		vec3 vel = velvet(d, p.y);
		// Carry the artwork's own light and dark down the cloth: take how bright the
		// picture is at this height just inside its edge and let the velvet inherit
		// it near the seam, fading to its own folds further out. That is what makes
		// the two read as one piece of cloth.
		float sx = dir > 0.0 ? 110.0 / art_rect.z : 1.0 - 110.0 / art_rect.z;
		// Averaged down the cloth, or the pleat highlights print as stripes.
		float lum = 0.0;
		for (int i = -4; i <= 4; i++) {
			vec2 at = vec2(sx, clamp(uv0.y + float(i) * 0.07, 0.0, 1.0));
			vec4 s = texture(art, at) * texture(art, at);
			lum += dot(s.rgb, vec3(0.3, 0.5, 0.2)) / 9.0;
		}
		float shade = mix(1.0, clamp(lum / 0.07, 0.75, 1.3), 0.45);
		vel *= mix(shade, 1.0, smoothstep(80.0, 300.0, d));
		float m = smoothstep(mirror_px - 75.0, mirror_px, d);
		// Opaque throughout: the gaps in the mirrored ropes are filled with velvet,
		// so nothing behind the curtain shows through the part that is in view
		// only while it is drawn across.
		col = vec4(mix(vel, mir.rgb, mir.a * (1.0 - m)), 1.0);
	}
	if (uv.y < 0.0 || uv.y > 1.0) {
		col.a = 0.0;
	}
	col.rgb *= 1.0 + (main_swing / max(sway, 0.0001)) * 0.05 * hang;
	COLOR = col * COLOR;
}
