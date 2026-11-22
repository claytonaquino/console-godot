shader_type canvas_item;

// Fundo animado do launcher. "accent" acompanha a cor do jogo selecionado.
uniform vec3 base_dark : source_color = vec3(0.025, 0.035, 0.07);
uniform vec3 base_mid : source_color = vec3(0.07, 0.11, 0.22);
uniform vec3 accent : source_color = vec3(0.16, 0.45, 0.65);

void fragment() {
	vec2 uv = UV;
	float t = TIME * 0.06;
	float w1 = 0.5 + 0.5 * sin(uv.x * 3.1 + t * 5.0 + sin(uv.y * 2.3 + t * 3.0));
	float w2 = 0.5 + 0.5 * sin(uv.y * 2.4 - t * 4.0 + cos(uv.x * 1.7 + t * 2.0));
	vec3 col = mix(base_dark, base_mid, w1 * (1.0 - uv.y) * 0.9);
	col = mix(col, accent, w2 * 0.28 * (1.0 - uv.y * 0.6));
	float vignette = smoothstep(1.25, 0.25, distance(uv, vec2(0.5, 0.45)));
	COLOR = vec4(col * (0.55 + 0.45 * vignette), 1.0);
}
