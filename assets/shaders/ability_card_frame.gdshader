shader_type canvas_item;
// The ability card's body (patch 0.125): a rounded metal frame (copper, silver
// or gold by upgrade tier) around a teal green panel. One rect, no textures:
// the art, title and sockets are laid over it by AbilityCard.

uniform vec2 size_px = vec2(190.0, 300.0);
uniform vec4 m_hi : source_color = vec4(0.94, 0.72, 0.55, 1.0);
uniform vec4 m_mid : source_color = vec4(0.75, 0.42, 0.25, 1.0);
uniform vec4 m_lo : source_color = vec4(0.42, 0.19, 0.09, 1.0);
uniform float radius = 12.0;
uniform float frame = 6.0;
uniform float glint = 0.0;       // 0 for copper, more for silver and gold
uniform float time = 0.0;

float rbox(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = UV * size_px;
	vec2 c = p - size_px * 0.5;
	float d = rbox(c, size_px * 0.5, radius);
	float alpha = 1.0 - smoothstep(-0.7, 0.4, d);
	float di = rbox(c, size_px * 0.5 - vec2(frame), radius - frame * 0.4);
	float inside = 1.0 - smoothstep(-0.7, 0.4, di);

	// the metal: a diagonal sheen, bright, body, shadow, body, bright
	float t = clamp(UV.x * 0.45 + UV.y * 0.55, 0.0, 1.0);
	vec3 metal;
	if (t < 0.24) metal = mix(m_hi.rgb, m_mid.rgb, t / 0.24);
	else if (t < 0.46) metal = mix(m_mid.rgb, m_lo.rgb, (t - 0.24) / 0.22);
	else if (t < 0.70) metal = mix(m_lo.rgb, m_mid.rgb, (t - 0.46) / 0.24);
	else metal = mix(m_mid.rgb, m_hi.rgb, (t - 0.70) / 0.30);
	// a bright lip along the top outer edge, a dark one along the bottom
	float edge = -d;
	metal += vec3(1.0) * 0.38 * (1.0 - smoothstep(0.0, 2.0, edge)) * step(c.y, 0.0);
	metal *= 1.0 - 0.38 * (1.0 - smoothstep(0.0, 2.4, edge)) * step(0.0, c.y);
	// the slow glint across silver and gold
	float sweep = fract(time * 0.16) * 2.6 - 0.8;
	float band = 1.0 - smoothstep(0.0, 0.07, abs(UV.x * 0.8 + UV.y * 0.6 - sweep));
	metal += vec3(1.0, 0.97, 0.85) * band * glint;

	// the panel: teal green, lighter in the middle, darker at the rim, no texture
	float ry = p.y / size_px.y;
	vec3 teal = mix(vec3(0.047, 0.271, 0.278), vec3(0.031, 0.184, 0.200), ry);
	teal += vec3(0.02, 0.1, 0.09) * (1.0 - smoothstep(0.0, 0.55, length((UV - vec2(0.5, 0.62)) * vec2(1.0, 1.4))));
	float rim = 1.0 - smoothstep(0.0, 9.0, -di);
	teal *= 1.0 - 0.4 * rim;
	// a thin dark line where the panel meets the metal
	float seam = 1.0 - smoothstep(0.0, 2.0, -di);
	teal = mix(teal, m_lo.rgb * 0.7, seam * 0.9);

	COLOR = vec4(mix(metal, teal, inside), alpha);
}
