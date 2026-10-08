shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// The whole course is drawn by this one shader. Each tile's type, wetness,
// turf health and weeds arrive in a small data texture, so painting terrain
// or a passing rain shower never rebuilds any geometry.
//
// Tiles are never drawn as squares. For every pixel the shader measures how
// much of each surface lies nearby (a smooth 3x3 kernel), lets small
// features such as bunkers and paths punch above their weight, and blends
// across a narrow band. The result is rounded, organic outlines.

uniform sampler2D tile_tex : filter_nearest, repeat_disable;   // r type (+128 not owned, +64 bare), g wet, b health, a weeds
uniform vec2 map_size = vec2(128.0, 128.0);
uniform float tile_size = 5.0;
uniform float grid_alpha = 0.0;
uniform float contour_alpha = 0.0;
uniform int overlay = 0;            // 0 off, 1 moisture, 2 turf health, 3 height, 4 mood, 5 lot value, 6 lights, 7 slope (4, 5 and 6 store that in alpha, not weeds)
uniform sampler2D slope_tex : filter_linear, repeat_disable;   // grade in percent, from the same reading as the arrows
uniform float slope_green_full = 4.0;   // percent that reads as the steepest colour on a green
uniform float slope_course_full = 20.0; // and on the rest of the course
uniform vec3 slope_c0 = vec3(0.82, 0.80, 0.68);
uniform vec3 slope_c1 = vec3(0.55, 0.66, 0.36);
uniform vec3 slope_c2 = vec3(0.72, 0.52, 0.24);
uniform vec3 slope_c3 = vec3(0.45, 0.22, 0.16);
uniform vec3 brush = vec3(0.0, 0.0, -1.0);   // x, z, radius; negative radius hides it
uniform vec3 brush_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec4 land_rect = vec4(0.0);          // x0, z0, x1, z1 of a highlighted land parcel
uniform vec3 pal[15];               // linear colour per terrain type, then the hazard's second colour
uniform float lava = 0.0;           // 1 when the hazard is lava
uniform float heat = 0.0;           // extra glow during an eruption
uniform vec2 cloud_offset = vec2(0.0);
uniform float cloud_cover = 0.2;
uniform vec3 season_grass = vec3(1.0);   // the season's tint on everything grassy
// photographic ground: one layer per kind of surface
uniform sampler2DArray ground_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray ground_nor : filter_linear_mipmap, repeat_enable;
uniform vec3 ground_mean[10];       // average colour of each layer
uniform float layer_of[14];         // which layer each terrain type uses
uniform float layer_size[14];       // metres one repeat of the texture covers
uniform float layer_bump[14];       // how strongly its bumps catch the light

// How strongly each surface claims the ground near its edge. Small features
// get a boost so a one-tile bunker survives the smoothing as a round pit.
const float PRIORITY[14] = float[14](1.0, 1.12, 1.38, 1.5, 1.62, 1.32, 0.94, 1.58, 1.25, 1.05, 1.16, 1.42, 1.48, 1.88);

varying vec3 wpos;
varying float relief;

// Smooth noise is read from a small picture (tools/make_noise.py) rather
// than computed: the same patterns for a fraction of the cost.
uniform sampler2D noise_tex : filter_linear, repeat_enable;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	return textureLod(noise_tex, p * 0.015625, 0.0).r;
}

// two unrelated noises at once
vec2 vnoise2(vec2 p) {
	return textureLod(noise_tex, p * 0.015625, 0.0).rg;
}

// four octaves layered together
float fbm(vec2 p) {
	return textureLod(noise_tex, p * 0.03125, 0.0).b;
}

// Where the weeds are, as patches rather than an even sprinkle: the same
// field in the grass shader decides where a dandelion stands, so the
// standing weeds grow out of the ground patches. 0..1 coverage.
float weed_patch(vec2 wp, float weeds) {
	float wn = fbm(wp * 0.45) * 0.55 + vnoise(wp * 1.7 + 17.0) * 0.45;
	float t = mix(0.80, 0.36, weeds);
	return smoothstep(t, t + 0.10, wn) * step(0.02, weeds);
}

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

// Height of the water surface, for ripples.
float wave(vec2 p) {
	return vnoise(p * 0.55 + vec2(TIME * 0.35, TIME * 0.22)) * 0.6
		+ vnoise(p * 1.7 - vec2(TIME * 0.5, TIME * 0.1)) * 0.3
		+ vnoise(p * 4.3 + vec2(0.0, TIME * 0.9)) * 0.1;
}

// The photograph for a surface, sampled at two scales so it holds up both
// close to and from far away and never visibly repeats. Returned as a
// multiplier around 1, so the biome's palette still sets the colour.
vec3 photo(int t, vec2 wp, out vec2 bump) {
	float layer = layer_of[t];
	float size = layer_size[t];
	vec2 uv1 = wp / size;
	vec2 uv2 = vec2(wp.x * 0.829 - wp.y * 0.559, wp.x * 0.559 + wp.y * 0.829) / (size * 6.3) + vec2(0.37, 0.11);
	vec3 mean = ground_mean[int(layer)];
	vec3 a1 = texture(ground_tex, vec3(uv1, layer)).rgb / mean;
	vec3 a2 = texture(ground_tex, vec3(uv2, layer)).rgb / mean;
	vec3 n1 = texture(ground_nor, vec3(uv1, layer)).rgb * 2.0 - 1.0;
	vec3 n2 = texture(ground_nor, vec3(uv2, layer)).rgb * 2.0 - 1.0;
	bump = (n1.xy + n2.xy * 0.6) * layer_bump[t];
	return clamp(a1 * mix(vec3(1.0), a2, 0.75), 0.25, 2.6);
}

// Colour of one surface at a world position.
//   n      broad noise, 0..1
//   fine   photographic detail for this surface, about 1 on average
//   grain  how much the view looks "down the nap" of mown grass, -1..1
vec3 terrain_color(int t, vec2 wp, float n, vec3 fine, float grain, out float rough, out float grass, out float emit) {
	rough = 0.92;
	grass = 1.0;
	emit = 0.0;
	if (t == 1) {           // fairway: broad mowing stripes whose shade depends on the view
		float s = step(0.5, fract((wp.x + wp.y) / 17.0)) * 2.0 - 1.0;
		return pal[1] * (1.0 + 0.085 * s * (0.45 + 0.55 * grain)) * (0.9 + 0.2 * n) * mix(vec3(1.0), fine, 0.8);
	}
	if (t == 2) {           // green: a tight criss-cross cut
		float a = step(0.5, fract(wp.x / 3.2)) * 2.0 - 1.0;
		float b = step(0.5, fract(wp.y / 3.2)) * 2.0 - 1.0;
		rough = 0.8;
		return pal[2] * (1.0 + 0.035 * a * grain + 0.035 * b) * (0.95 + 0.1 * n) * mix(vec3(1.0), fine, 0.5);
	}
	if (t == 3) {           // tee box
		float a = step(0.5, fract(wp.x / 2.4)) * 2.0 - 1.0;
		return pal[3] * (1.0 + 0.04 * a) * (0.94 + 0.12 * n) * mix(vec3(1.0), fine, 0.6);
	}
	if (t == 4) {           // bunker: raked sand
		grass = 0.0;
		rough = 1.0;
		float rake = sin((wp.x * 0.8 + wp.y * 0.5) * 4.0 + vnoise(wp * 0.7) * 5.0) * 0.5 + 0.5;
		return pal[4] * (0.9 + 0.08 * vnoise(wp * 2.5) + 0.05 * rake) * fine;
	}
	if (t == 5) {           // the hazard: water, or lava
		grass = 0.0;
		if (lava > 0.5) {
			rough = 0.75;
			float flow = vnoise(wp * 0.2 + vec2(TIME * 0.05, TIME * 0.035));
			float crust = vnoise(wp * 0.5 - vec2(TIME * 0.03, 0.0)) * 0.6 + vnoise(wp * 1.2 + flow * 2.5) * 0.4;
			float hot = smoothstep(0.38, 0.72, crust + 0.2 * sin(TIME * 0.7 + flow * 6.0) + heat * 0.25);
			emit = hot;
			return mix(pal[5] * 0.35, pal[14], hot);
		}
		rough = 0.04;
		return mix(pal[5], pal[14], wave(wp) * 0.6);
	}
	if (t == 6) {           // deep rough: tussocky and uneven
		grass = 0.35;
		float tuft = vnoise(wp * 1.1) * 0.6 + vnoise(wp * 3.1) * 0.4;
		return pal[6] * (0.72 + 0.42 * n) * (0.85 + 0.3 * tuft) * fine;
	}
	if (t == 7) {           // cart path: fine gravel
		grass = 0.0;
		rough = 0.85;
		return pal[7] * (0.94 + 0.1 * vnoise(wp * 3.0)) * fine;
	}
	if (t == 8) {           // bare rock, cracked
		grass = 0.0;
		rough = 0.8;
		float crack = smoothstep(0.0, 0.05, abs(vnoise(wp * 0.7) - 0.5)) * smoothstep(0.0, 0.035, abs(vnoise(wp * 1.9 + 4.0) - 0.5));
		return pal[8] * (0.75 + 0.4 * vnoise(wp * 0.25)) * (0.7 + 0.3 * crack) * fine;
	}
	if (t == 9) {           // scorched ground and ash
		grass = 0.0;
		return pal[9] * (0.78 + 0.32 * n) * fine;
	}
	if (t == 10) {          // firm fairway: tighter stripes, a little paler
		float s = step(0.5, fract((wp.x + wp.y) / 11.0)) * 2.0 - 1.0;
		rough = 0.88;
		return pal[10] * (1.0 + 0.06 * s * (0.45 + 0.55 * grain)) * (0.94 + 0.12 * n) * mix(vec3(1.0), fine, 0.85);
	}
	if (t == 11) {          // fast green: a finer cut
		float a = step(0.5, fract(wp.x / 2.2)) * 2.0 - 1.0;
		float b = step(0.5, fract(wp.y / 2.2)) * 2.0 - 1.0;
		rough = 0.72;
		return pal[11] * (1.0 + 0.028 * a * grain + 0.028 * b) * (0.97 + 0.08 * n) * mix(vec3(1.0), fine, 0.45);
	}
	if (t == 12) {          // waste: sandy scrub, never raked
		grass = 0.18;
		rough = 0.96;
		float scrub = vnoise(wp * 0.85) * 0.6 + vnoise(wp * 2.4 + 9.0) * 0.4;
		float tuft = smoothstep(0.42, 0.72, scrub);
		vec3 sand = pal[12] * (0.9 + 0.1 * vnoise(wp * 2.2));
		vec3 bush = pal[12] * vec3(0.62, 0.78, 0.48);
		return mix(sand, bush, tuft * 0.65) * fine;
	}
	if (t == 13) {          // a stream is water in every biome, including a volcano
		grass = 0.0;
		rough = 0.05;
		return mix(pal[13], pal[14], wave(wp) * 0.55);
	}
	grass = 0.7;            // rough: longer, patchier grass
	float clump = vnoise(wp * 0.8) * 0.55 + vnoise(wp * 2.6) * 0.45;
	vec3 dry = mix(vec3(1.0), vec3(1.12, 1.04, 0.78), smoothstep(0.45, 0.8, vnoise(wp * 0.013 + 5.0)));
	return pal[0] * dry * (0.66 + 0.6 * n) * (0.9 + 0.2 * clump) * fine;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	relief = COLOR.r;
}

void fragment() {
	vec2 wp = wpos.xz;
		// patchiness at two scales: tufts a few metres across, and whole areas
	// of lusher or drier ground a hundred metres across
	float n = fbm(wp * 0.11) * 0.45 + vnoise(wp * 0.021) * 0.3 + vnoise(wp * 0.006 + 31.0) * 0.25;
	vec3 view_w = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
	float grain = dot(normalize(view_w.xz + vec2(0.0001)), normalize(vec2(1.0, 1.0)));

	// --- how much of each surface is near this point ---
	vec2 tp = wp / tile_size
		+ (vnoise2(wp * 0.055 + 23.0) - 0.5) * 0.8
		+ (vnoise2(wp * 0.19 + 11.0) - 0.5) * 0.55
		+ (vnoise2(wp * 0.8 + 3.0) - 0.5) * 0.14;
	vec2 base = floor(tp);
	vec2 f = tp - base - 0.5;
	vec3 wx = vec3(0.5 * (0.5 - f.x) * (0.5 - f.x), 0.75 - f.x * f.x, 0.5 * (0.5 + f.x) * (0.5 + f.x));
	vec3 wy = vec3(0.5 * (0.5 - f.y) * (0.5 - f.y), 0.75 - f.y * f.y, 0.5 * (0.5 + f.y) * (0.5 + f.y));
	float cov[14];
	for (int k = 0; k < 14; k++) {
		cov[k] = 0.0;
	}
	vec3 data = vec3(0.0);
	float lock = 0.0;
	for (int j = 0; j < 3; j++) {
		for (int i = 0; i < 3; i++) {
			ivec2 c = ivec2(clamp(base + vec2(float(i - 1), float(j - 1)), vec2(0.0), map_size - 1.0));
			vec4 d = texelFetch(tile_tex, c, 0);
			float w = wx[i] * wy[j];
			int raw = int(d.r * 255.0 + 0.5);
			int t = min(raw & 63, 13);
			cov[t] += w;
			lock += raw >= 128 ? w : 0.0;
			data += d.gba * w;
		}
	}
	float wt[14];
	float total = 0.0;
	for (int k = 0; k < 14; k++) {
		float v = pow(cov[k] * PRIORITY[k], 12.0);
		wt[k] = v;
		total += v;
	}
	vec3 col = vec3(0.0);
	float rough = 0.0;
	float grass = 0.0;
	float emit = 0.0;
	vec2 bump = vec2(0.0);
	for (int k = 0; k < 14; k++) {
		float w = wt[k] / total;
		if (w > 0.004) {
			float r_;
			float g_;
			float e_;
			vec2 b_;
			vec3 fine = photo(k, wp, b_);
			col += terrain_color(k, wp, n, fine, grain, r_, g_, e_) * w;
			rough += r_ * w;
			grass += g_ * w;
			emit += e_ * w;
			bump += b_ * w;
		}
	}
	float w_green = (wt[2] + wt[11]) / total;
	float w_bunker = wt[4] / total;
	float w_water = (wt[5] + wt[13]) / total;
	float w_hazard = wt[5] / total;
	float w_brook = wt[13] / total;
	float wet = data.x;
	float health = data.y;
	float weeds = data.z;
	bool is_lava = lava > 0.5;
	// A stream stays water on a volcano. Only the hazard tile is lava.
	float wet_liquid = (is_lava ? 0.0 : cov[5]) + cov[13];
	float wet_w = (is_lava ? 0.0 : w_hazard) + w_brook;

	// --- edges that give the ground some depth ---
	// a collar of slightly longer grass round every green
	float collar = smoothstep(0.10, 0.30, cov[2] + cov[11]) * (1.0 - w_green) * (1.0 - w_bunker) * (1.0 - w_water);
	col = mix(col, col * vec3(0.80, 0.86, 0.78), collar * 0.75);
	// bunkers sit below the turf: shade the inside of the lip, brighten the rim
	float lip_in = w_bunker * (1.0 - smoothstep(0.42, 0.68, cov[4]));
	float lip_out = (1.0 - w_bunker) * smoothstep(0.18, 0.38, cov[4]);
	col *= 1.0 - 0.30 * lip_in;
	col = mix(col, col * 1.12 + vec3(0.01), lip_out * 0.6);
	// water: shallow at the shore, deep in the middle, with a line of foam.
	// On a volcano this is the stream. The lava lake is handled below.
	if (wet_liquid > 0.01) {
		float depth = smoothstep(0.42, 0.95, wet_liquid);
		col = mix(col, col * mix(vec3(1.25, 1.3, 1.15), vec3(0.62, 0.7, 0.85), depth), wet_w);
		float shore = wet_w * (1.0 - smoothstep(0.40, 0.50, wet_liquid));
		float foam = shore * smoothstep(0.35, 0.75, vnoise(wp * 2.2 + vec2(TIME * 0.4, 0.0)) + 0.25 * sin(TIME * 1.3 + wp.x * 0.7));
		col = mix(col, vec3(0.85, 0.9, 0.92), foam * 0.7);
		rough = mix(rough, 0.5, foam);
		float bank = (1.0 - wet_w) * smoothstep(0.16, 0.36, wet_liquid);
		col = mix(col, col * vec3(0.62, 0.58, 0.5), bank * 0.6);
	}
	if (is_lava && cov[5] > 0.01) {
		float bank = (1.0 - w_hazard) * smoothstep(0.12, 0.36, cov[5]);
		col = mix(col, vec3(0.05, 0.03, 0.03), bank * 0.75);
		emit += bank * 0.25;
	}

	// steep ground shows rock and bare earth through the grass
	vec3 n_w = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float cliff = smoothstep(0.10, 0.26, 1.0 - n_w.y) * (1.0 - w_water) * (1.0 - w_green);
	if (cliff > 0.001) {
		float strata = vnoise(vec2(wpos.y * 1.6, (wp.x + wp.y) * 0.08)) * 0.5 + vnoise(wp * 0.5) * 0.5;
		vec3 rock = pal[8] * (0.6 + 0.7 * strata);
		col = mix(col, rock, cliff * 0.85);
		grass *= 1.0 - cliff;
		rough = mix(rough, 0.85, cliff);
	}

	// tired turf goes yellow, then brown
	vec3 tired = mix(lin(vec3(0.52, 0.42, 0.22)), lin(vec3(0.70, 0.66, 0.30)), smoothstep(0.2, 0.7, health));
	col = mix(col, tired, grass * (1.0 - smoothstep(0.25, 0.95, health)) * 0.85);

	// weeds: ragged patches of coarse, paler broadleaf growth over the
	// turf, mottled, with the odd flower head close up (the standing
	// dandelions and plantains are the grass shader's)
	float patch = weed_patch(wp, weeds) * min(grass * 1.4, 1.0) * (1.0 - w_water) * (1.0 - w_bunker);
	if (patch > 0.001) {
		float px = fwidth(wp.x);
		float close = 1.0 - smoothstep(0.03, 0.09, px);
		// coarse, dark broadleaf growth, yellowing where it is thickest,
		// mottled close up and rough-surfaced
		float mottle = (vnoise(wp * 6.0 + 41.0) * 0.6 + vnoise(wp * 2.3 + 8.0) * 0.4) * close + 0.5 * (1.0 - close);
		vec3 wl = mix(lin(vec3(0.30, 0.40, 0.14)), lin(vec3(0.50, 0.52, 0.20)), smoothstep(0.3, 1.0, weeds) * 0.7) * (0.6 + 0.8 * mottle);
		// rosettes: darker hearts where the leaves meet
		vec2 rc = floor(wp * 2.2);
		vec2 rin = fract(wp * 2.2) - 0.5 + (vec2(hash21(rc + 3.0), hash21(rc + 5.0)) - 0.5) * 0.5;
		float heart = (1.0 - smoothstep(0.08, 0.24, length(rin))) * step(0.3, hash21(rc)) * close;
		wl *= 1.0 - 0.3 * heart;
		col = mix(col, wl, patch * 0.85);
		rough = mix(rough, 0.95, patch * 0.5);
	}

	// wet ground darkens, then puddles
	float soak = step(0.01, grass + (1.0 - rough)) * (1.0 - step(0.01, emit)) * (1.0 - w_water);
	// Water stands in the hollows, in patches; everywhere else the ground
	// just goes dark and glossy.
	float puddle = 0.0;
	if (wet > 0.5 && relief < 0.54) {
		vec2 pn = vnoise2(wp * 0.07 + 3.0);
		float pool = (1.0 - smoothstep(0.40, 0.54, relief)) * smoothstep(0.35, 0.62, pn.x);
		puddle = smoothstep(0.7, 0.95, wet + (vnoise(wp * 0.6) - 0.5) * 0.3) * soak * pool;
	}
	col *= 1.0 - 0.3 * wet * step(0.01, grass) * (1.0 - w_water);
	col = mix(col, lin(vec3(0.38, 0.46, 0.52)), puddle * 0.5 * step(0.01, grass));
	rough = mix(rough, 0.5, smoothstep(0.3, 0.9, wet) * 0.6 * soak);
	rough = mix(rough, 0.08, puddle);

	// hollows a touch darker, crests a touch lighter
	col *= mix(0.6, 1.3, relief) * (1.0 - w_water) + w_water;

	// clouds drift across the course
	float cl = fbm((wp + cloud_offset) * 0.0042);
	float edge = 0.78 - cloud_cover * 0.62;
	float shade = smoothstep(edge - 0.07, edge + 0.07, cl);
	col *= 1.0 - 0.36 * shade * (1.0 - emit);

	float luma = dot(col, vec3(0.3, 0.6, 0.1));
	if (overlay == 1) {
		vec3 wcol = mix(lin(vec3(0.85, 0.75, 0.45)), lin(vec3(0.10, 0.35, 0.85)), smoothstep(0.0, 0.9, wet));
		col = wcol * (0.55 + 1.6 * luma);
	} else if (overlay == 2) {
		vec3 hcol = mix(lin(vec3(0.80, 0.20, 0.15)), lin(vec3(0.20, 0.75, 0.25)), health);
		hcol = mix(hcol, lin(vec3(0.85, 0.75, 0.10)), smoothstep(0.1, 0.6, weeds));
		col = mix(vec3(luma) * 0.5, hcol * (0.55 + 1.6 * luma), step(0.2, grass));
	} else if (overlay == 3) {
		float hgt = clamp((wpos.y + 8.0) / 20.0, 0.0, 1.0);
		vec3 ecol = mix(lin(vec3(0.15, 0.30, 0.55)), mix(lin(vec3(0.30, 0.65, 0.30)), lin(vec3(0.90, 0.85, 0.70)), smoothstep(0.5, 1.0, hgt)), smoothstep(0.0, 0.5, hgt));
		col = ecol * (0.55 + 1.6 * luma);
	} else if (overlay == 4) {
		// Alpha is the mood, 0.5 calm, towards 0 annoyed, towards 1 pleased.
		float m = clamp(weeds, 0.0, 1.0);
		vec3 moodc = mix(lin(vec3(0.72, 0.16, 0.12)), lin(vec3(0.18, 0.62, 0.28)), m);
		float felt = smoothstep(0.02, 0.14, abs(m - 0.5));
		col = mix(vec3(luma) * 0.5, moodc * (0.55 + 1.6 * luma), felt);
	} else if (overlay == 5) {
		// Alpha is the lot value, 0 the cheapest ground, 1 the dearest.
		float v = clamp(weeds, 0.0, 1.0);
		vec3 vcol = mix(lin(vec3(0.22, 0.30, 0.40)), lin(vec3(0.93, 0.74, 0.16)), v);
		col = vcol * (0.55 + 1.6 * luma);
	} else if (overlay == 6) {
		// Alpha is how well the spot is lit after dark.
		float lit = clamp(weeds, 0.0, 1.0);
		vec3 lcol = mix(lin(vec3(0.05, 0.07, 0.14)), lin(vec3(1.0, 0.93, 0.62)), lit);
		col = lcol * (0.45 + 1.4 * luma);
	} else if (overlay == 7) {
		// Grade in percent. Greens use a finer scale so 1 to 4% still reads.
		vec2 suv = clamp(wp / (map_size * tile_size), vec2(0.001), vec2(0.999));
		float pct = texture(slope_tex, suv).r;
		float fine = smoothstep(0.35, 0.7, w_green);
		float span = max(mix(slope_course_full, slope_green_full, fine), 0.001);
		float t = clamp(pct / span, 0.0, 1.0);
		vec3 scol = slope_c0;
		if (t < 0.333) {
			scol = mix(slope_c0, slope_c1, t / 0.333);
		} else if (t < 0.666) {
			scol = mix(slope_c1, slope_c2, (t - 0.333) / 0.333);
		} else {
			scol = mix(slope_c2, slope_c3, (t - 0.666) / 0.334);
		}
		col = lin(scol) * (0.55 + 1.6 * luma);
	}

	// land you do not own yet is washed out and hatched
	if (lock > 0.001) {
		float hatch = step(0.5, fract((wp.x - wp.y) / 7.0));
		vec3 dull = vec3(dot(col, vec3(0.33))) * (0.5 + 0.08 * hatch);
		col = mix(col, dull, smoothstep(0.3, 0.7, lock) * 0.8);
	}

	// height contours: essential for reading a green
	if (contour_alpha > 0.0) {
		float ch = wpos.y / 0.25;
		float line = 1.0 - smoothstep(0.0, fwidth(ch) * 1.4, abs(fract(ch - 0.5) - 0.5));
		float ch5 = wpos.y / 1.0;
		float major = 1.0 - smoothstep(0.0, fwidth(ch5) * 2.0, abs(fract(ch5 - 0.5) - 0.5));
		col = mix(col, col * 0.45, clamp(line * 0.5 + major * 0.8, 0.0, 1.0) * contour_alpha);
	}
	if (grid_alpha > 0.0) {
		vec2 g = abs(fract(wp / tile_size) - 0.5);
		float fw = fwidth(wp.x / tile_size) * 1.5;
		float line = smoothstep(0.5 - fw, 0.5, max(g.x, g.y));
		col = mix(col, vec3(1.0), line * grid_alpha * 0.16);
	}
	if (brush.z > 0.0) {
		float bd = distance(wp, brush.xy);
		float fw = fwidth(bd) * 1.5 + 0.15;
		float ring = 1.0 - smoothstep(0.0, fw, abs(bd - brush.z));
		float fill = 1.0 - smoothstep(brush.z - fw, brush.z, bd);
		col = mix(col, brush_color, clamp(ring * 0.9 + fill * 0.16, 0.0, 1.0));
	}
	if (land_rect.z > land_rect.x) {
		vec2 lo = wp - land_rect.xy;
		vec2 hi = land_rect.zw - wp;
		float inside = step(0.0, min(min(lo.x, lo.y), min(hi.x, hi.y)));
		float edge_d = min(min(lo.x, lo.y), min(hi.x, hi.y));
		float border = inside * (1.0 - smoothstep(0.0, 1.2 + fwidth(wp.x) * 2.0, edge_d));
		col = mix(col, brush_color, clamp(border + inside * 0.18, 0.0, 1.0));
	}

	// the grain of the ground catches the light
	vec3 lumpy = normalize(n_w + vec3(bump.x, 0.0, -bump.y) * (1.0 - w_water));
	NORMAL = normalize((VIEW_MATRIX * vec4(lumpy, 0.0)).xyz);
	// ripples catch the light on open water
	if (wet_w > 0.5) {
		float e = 0.35;
		float hx = wave(wp + vec2(e, 0.0)) - wave(wp - vec2(e, 0.0));
		float hz = wave(wp + vec2(0.0, e)) - wave(wp - vec2(0.0, e));
		vec3 ripple = normalize(vec3(-hx * 0.9, 1.0, -hz * 0.9));
		NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(ripple, 0.0)).xyz, wet_w));
	}
	col *= mix(vec3(1.0), season_grass, clamp(grass, 0.0, 1.0) * (1.0 - w_water));
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = mix(0.3, 0.6, wet_w);
	EMISSION = pal[14] * emit * (2.2 + heat * 2.0) * (overlay == 0 ? 1.0 : 0.0);
}
