shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Leaves. A canopy is a few hundred small cards, each painted with a spray
// of leaves, a conifer bough or a palm frond, wrapped around a dark solid
// core. Lighting follows the shape of the whole crown rather than each
// card, so a tree reads as one soft mass with a leafy edge.
//
// Vertex colour carries each card's tint; its alpha says whether the
// vertex belongs to a card (1) or to the solid core (0).

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 wind = vec2(1.0, 0.0);     // direction scaled by strength
uniform vec3 cell_mean[6];               // average leaf colour in each cell of the atlas (2 by 3)
uniform float gain = 0.46;             // leaves are darker than they look in a painting
uniform float autumn = 0.0;            // 0 summer .. 1 every broad-leaved tree has turned
uniform float spring = 0.0;            // 1 at the start of the year: fresh, pale new leaves

varying vec3 wpos;
varying float card;

void vertex() {
	card = COLOR.a;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// the whole crown leans and rocks; leaves flutter on top of that
	float strength = length(wind);
	float lean = VERTEX.y * VERTEX.y * 0.0016 * strength;
	float phase = dot(world.xz, vec2(0.05, 0.04)) + TIME * (0.9 + strength * 0.12);
	float rock = sin(phase) * 0.7 + sin(phase * 2.3 + 1.7) * 0.3;
	float flutter = sin(TIME * 4.6 + world.x * 2.3 + world.z * 1.7 + world.y * 2.9) * 0.014 * strength * min(VERTEX.y, 6.0) * card;
	vec2 dir = strength > 0.001 ? wind / strength : vec2(1.0, 0.0);
	vec3 push = vec3(dir.x, 0.0, dir.y) * (lean * (0.55 + 0.45 * rock) + flutter);
	push.y += flutter * 0.5;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(push, 0.0)).xyz;
	wpos = world;
}

void fragment() {
	vec3 base = COLOR.rgb;
	if (card > 0.5) {
		vec4 leaf = texture(atlas, UV);
		// As leaves shrink below a pixel their edges average away; thicken
		// them a little with distance so far trees stay full.
		float texels = max(length(fwidth(UV)) * 512.0, 1.0);
		float a = leaf.a * (1.0 + clamp(log2(texels), 0.0, 5.0) * 0.4);
		ALPHA = clamp(a, 0.0, 1.0);
		ALPHA_SCISSOR_THRESHOLD = 0.42;
		ALPHA_ANTIALIASING_EDGE = 0.3;
		ALPHA_TEXTURE_COORDINATE = UV * vec2(1024.0, 1536.0);
		int cell = (UV.x >= 0.5 ? 1 : 0) + int(floor(UV.y * 3.0)) * 2;
		if (cell == 0 && (autumn > 0.001 || spring > 0.001)) {
			// Broad leaves follow the season. Each tree turns at its own
			// moment, most to gold and some to red, and in spring the new
			// leaves are paler and fresher.
			float tree = fract(sin(dot(floor(wpos.xz / 5.0 + 0.5), vec2(12.9898, 78.233))) * 43758.5453);
			float turn = clamp((autumn - tree * 0.65) / 0.35, 0.0, 1.0);
			float lum = dot(base, vec3(0.3, 0.59, 0.11));
			vec3 gold = vec3(1.0, 0.55, 0.12) * lum * 2.6;
			vec3 red = vec3(0.9, 0.22, 0.08) * lum * 2.4;
			vec3 fall = mix(gold, red, step(0.72, fract(tree * 7.31)));
			base = mix(base, fall, turn);
			base = mix(base, base * vec3(0.86, 1.1, 0.7) + vec3(0.015, 0.04, 0.0), spring * 0.7);
		}
		ALBEDO = base * clamp(leaf.rgb / cell_mean[cell], 0.0, 2.5) * gain;
		BACKLIGHT = base * vec3(0.5, 0.6, 0.2);
	} else {
		ALBEDO = base;
	}
	// Light the crown as a whole: undo the flip that two-sided drawing
	// applies to faces seen from behind.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = 0.82;
	SPECULAR = 0.14;
	AO_LIGHT_AFFECT = 0.35;
}
