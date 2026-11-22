shader_type canvas_item;

// Cantos arredondados para a capa dos jogos.
uniform vec2 rect_size = vec2(340.0, 460.0);
uniform float radius = 26.0;

void fragment() {
	vec2 p = UV * rect_size;
	vec2 q = abs(p - rect_size * 0.5) - (rect_size * 0.5 - vec2(radius));
	float d = length(max(q, vec2(0.0))) - radius;
	vec4 c = texture(TEXTURE, UV);
	c.a *= clamp(0.5 - d, 0.0, 1.0);
	COLOR = c;
}
