shader_type canvas_item;
// The living painting (patch 0.119). One shader over a still background that
// makes the scene behave like a place rather than a poster: the whole frame
// drifts very slowly (a Ken Burns breath plus a few pixels of mouse
// parallax), the painted curtains at the edges sway, lights pulse and
// flicker inside soft ellipses, the background slot machines' reel windows
// scroll, warm haze wobbles the lower half, and for the night exterior it
// rains, the wet ground shimmers, searchlights sweep the clouds and
// lightning can flash. Every region is a plain ellipse or rectangle in the
// TEXTURE's own UV space, so nothing needs a hand-painted mask and the same
// preset fits every screen size (the TextureRect covers, so UV = painting).
//
// All motion is "subtle, always alive" (the designer's call): you notice it
// when it stops. Amplitudes are UV fractions, so 0.005 is about 8 px on the
// 1536-wide paintings.

uniform float speed = 1.0;
uniform vec2 parallax = vec2(0.0, 0.0);   // UV offset, driven by the script from the mouse
uniform float drift_zoom : hint_range(0.0, 0.05) = 0.012;
uniform float drift_speed = 0.05;
uniform float impulse : hint_range(0.0, 1.0) = 0.0;   // a heavy hit; decays in the script

// Curtains: the outer `curtain_width` of the frame on each side sways.
uniform float curtain_width : hint_range(0.0, 0.5) = 0.13;
uniform float curtain_sway = 0.005;
uniform float curtain_speed = 0.35;

// Lights: up to 6 ellipses (centre x, centre y, radius x, radius y).
uniform int light_count = 0;
uniform vec4 lights[6];
uniform float light_pulse : hint_range(0.0, 0.6) = 0.14;

// Reel windows: up to 8 rectangles (x, y, w, h) where a strip of suit-coloured
// blobs scrolls downward, blended faintly over the painted machine face.
uniform int reel_count = 0;
uniform vec4 reels[8];
uniform float reel_speed = 0.35;
uniform float reel_alpha : hint_range(0.0, 1.0) = 0.32;

// Warm haze wobble below `haze_top`.
uniform float haze_top = 0.55;
uniform float haze_amp = 0.0012;

// Night exterior.
uniform float rain : hint_range(0.0, 1.0) = 0.0;
uniform float ground_y = 0.62;             // wet ground shimmers below this
uniform float shimmer = 0.0;
uniform int beam_count = 0;
uniform vec4 beams[3];                     // origin x, origin y, base angle, sweep amplitude
uniform float lightning : hint_range(0.0, 1.0) = 0.0;

uniform float vignette : hint_range(0.0, 0.6) = 0.16;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float t = TIME * speed;
	vec2 uv = UV;

	// --- the slow breath of the whole frame, plus the mouse's few pixels
	float z = 1.0 + drift_zoom * (0.5 + 0.5 * sin(t * drift_speed * 6.2832));
	vec2 centre = vec2(0.5, 0.5)
		+ vec2(sin(t * drift_speed * 4.1), cos(t * drift_speed * 3.3)) * drift_zoom * 0.35
		+ parallax;
	uv = (uv - centre) / z + centre;

	// --- curtains: fabric hanging from the top, so the swing grows downward
	float edge_l = 1.0 - smoothstep(0.0, curtain_width, uv.x);
	float edge_r = 1.0 - smoothstep(0.0, curtain_width, 1.0 - uv.x);
	float hang = max(edge_l, edge_r) * (0.35 + 0.65 * uv.y);
	float sway = sin(t * curtain_speed * 6.2832 + uv.y * 5.0) * curtain_sway
		+ sin(t * curtain_speed * 2.3 * 6.2832 + uv.y * 11.0) * curtain_sway * 0.35;
	sway *= 1.0 + impulse * 5.0;
	uv.x += sway * hang;

	// --- warm haze near the floor
	if (uv.y > haze_top && haze_amp > 0.0) {
		float hw = smoothstep(haze_top, 1.0, uv.y);
		uv += (vec2(vnoise(uv * 9.0 + vec2(t * 0.17, 0.0)),
			vnoise(uv * 9.0 + vec2(0.0, t * 0.13))) - 0.5) * haze_amp * hw;
	}

	// --- wet ground: horizontal ripple of the reflections
	if (shimmer > 0.0 && uv.y > ground_y) {
		float depth = (uv.y - ground_y) / max(1.0 - ground_y, 0.001);
		uv.x += (vnoise(vec2(uv.x * 40.0, uv.y * 120.0 + t * 1.8)) - 0.5) * shimmer * depth;
	}

	vec4 col = texture(TEXTURE, uv);

	// --- lights that pulse and flicker, each on its own clock
	for (int i = 0; i < light_count; i++) {
		vec2 d = (uv - lights[i].xy) / max(lights[i].zw, vec2(0.0001));
		float m = 1.0 - smoothstep(0.55, 1.0, length(d));
		float fi = float(i);
		float pulse = 0.5 + 0.5 * sin(t * (0.9 + 0.31 * fi) * 6.2832 + fi * 1.7);
		float flicker = vnoise(vec2(t * 4.0 + fi * 13.0, fi * 7.0));
		float gain = light_pulse * ((pulse * 0.65 + flicker * 0.35) - 0.5);
		col.rgb *= 1.0 + gain * m;
	}

	// --- reel windows: a strip of blobs rolling down each little window
	for (int i = 0; i < reel_count; i++) {
		vec4 r = reels[i];
		vec2 local = (uv - r.xy) / max(r.zw, vec2(0.0001));
		if (local.x >= 0.0 && local.x <= 1.0 && local.y >= 0.0 && local.y <= 1.0) {
			float fi = float(i);
			float roll = local.y * 3.0 - t * reel_speed * (0.75 + 0.2 * hash21(vec2(fi, 3.0)));
			float cell = floor(roll);
			float f = fract(roll);
			float blob = smoothstep(0.18, 0.42, f) * smoothstep(0.82, 0.58, f);
			// Three columns, like three reels behind the glass.
			float colw = fract(local.x * 3.0);
			blob *= smoothstep(0.1, 0.35, colw) * smoothstep(0.9, 0.65, colw);
			float pick = hash21(vec2(cell, fi * 5.0 + floor(local.x * 3.0)));
			vec3 suit = pick < 0.25 ? vec3(0.9, 0.2, 0.2)
				: pick < 0.5 ? vec3(0.25, 0.75, 0.35)
				: pick < 0.75 ? vec3(0.35, 0.5, 1.0)
				: vec3(1.0, 0.85, 0.35);
			// Fade at the window's edges so the rectangle never shows.
			float fade = smoothstep(0.0, 0.2, local.x) * smoothstep(1.0, 0.8, local.x)
				* smoothstep(0.0, 0.2, local.y) * smoothstep(1.0, 0.8, local.y);
			col.rgb = mix(col.rgb, suit, reel_alpha * blob * fade);
		}
	}

	// --- rain: thin fast streaks in three depth layers
	if (rain > 0.0) {
		float streaks = 0.0;
		for (int layer = 0; layer < 3; layer++) {
			float fl = float(layer);
			float dens = 26.0 + fl * 22.0;
			vec2 p = vec2(UV.x * dens + UV.y * 3.0, UV.y * (2.2 + fl) + t * (1.6 + fl * 0.5));
			float lane = hash21(vec2(floor(p.x), fl));
			float drop = fract(p.y + lane * 7.0);
			float line = smoothstep(0.0, 0.03, fract(p.x) ) * smoothstep(0.09, 0.03, fract(p.x));
			float head = smoothstep(0.0, 0.45, drop) * smoothstep(0.55, 0.45, drop);
			streaks += line * head * (lane > 0.72 ? 1.0 : 0.0) * (0.55 - fl * 0.12);
		}
		col.rgb += vec3(0.75, 0.8, 0.95) * streaks * 0.35 * rain;
	}

	// --- searchlights sweeping the sky
	for (int i = 0; i < beam_count; i++) {
		vec4 b = beams[i];
		float ang = b.z + sin(t * 0.22 + float(i) * 2.1) * b.w;
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 rel = uv - b.xy;
		float along = dot(rel, dir);
		if (along > 0.0) {
			float across = abs(rel.x * dir.y - rel.y * dir.x);
			float width = 0.006 + along * 0.06;
			float cone = smoothstep(width, 0.0, across) * smoothstep(0.75, 0.05, along);
			col.rgb += vec3(0.95, 0.85, 0.6) * cone * 0.22;
		}
	}

	// --- lightning: a flat wash the script spikes and lets fall
	col.rgb += vec3(0.7, 0.72, 0.9) * lightning * 0.28;

	// --- a vignette that breathes with the frame
	float v = length(UV - vec2(0.5)) ;
	col.rgb *= 1.0 - vignette * v * v * 1.6 * (0.9 + 0.1 * sin(t * 0.4));

	COLOR = col * COLOR;
}
