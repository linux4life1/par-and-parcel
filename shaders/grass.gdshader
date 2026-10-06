shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled, world_vertex_coords;
// Standing grass in the rough. The same patch of tufts is laid over the
// ground around the camera; each tuft looks up the land beneath it, so it
// sits on the terrain, grows only where rough grows, and takes the colour of
// the ground it stands on. Painting or reshaping the course moves the grass
// with no rebuilding.

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D tile_tex : filter_nearest, repeat_disable;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(128.0);
uniform float tile_size = 5.0;
uniform vec3 pal_rough = vec3(0.1, 0.2, 0.05);
uniform vec3 pal_deep = vec3(0.07, 0.15, 0.04);
uniform vec3 growth = vec3(0.4, 1.0, 1.0);     // height in rough, in deep rough, and how thick
uniform vec2 wind = vec2(1.0, 0.0);
uniform vec2 fade = vec2(62.0, 94.0);          // tufts shrink away between these distances
uniform vec2 cloud_offset = vec2(0.0);
uniform float cloud_cover = 0.2;
uniform vec3 season_grass = vec3(1.0);   // the season's tint, the same as the ground's
uniform vec3 blade_mean = vec3(0.3, 0.35, 0.15);   // average colour of the grass picture
uniform float gain = 1.0;

// must match the terrain shader, so grass ends where the turf does
const float PRIORITY[10] = float[10](1.0, 1.12, 1.38, 1.5, 1.62, 1.32, 0.94, 1.58, 1.25, 1.05);

varying vec3 tint;
varying float tip;
varying vec3 ground_n;

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

float land(vec2 wp) {
	return textureLod(height_tex, (wp / tile_size + 0.5) / (map_size + 1.0), 0.0).r;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 wp = origin.xz;
	tip = 1.0 - UV2.y;
	float grow = 0.0;
	tint = pal_rough;
	ground_n = vec3(0.0, 1.0, 0.0);
	vec2 tc = wp / tile_size;
	float seed = hash21(wp * 1.37);
	float dist = distance(origin.xz, CAMERA_POSITION_WORLD.xz);
	if (tc.x > 0.5 && tc.y > 0.5 && tc.x < map_size.x - 0.5 && tc.y < map_size.y - 0.5 && seed <= growth.z && dist < fade.y) {
		// how much rough and deep rough lies here, measured as the terrain does
		vec2 tp = tc
			+ (vnoise2(wp * 0.055 + 23.0) - 0.5) * 0.8
			+ (vnoise2(wp * 0.19 + 11.0) - 0.5) * 0.55
			+ (vnoise2(wp * 0.8 + 3.0) - 0.5) * 0.14;
		vec2 base = floor(tp);
		vec2 f = tp - base - 0.5;
		vec3 wx = vec3(0.5 * (0.5 - f.x) * (0.5 - f.x), 0.75 - f.x * f.x, 0.5 * (0.5 + f.x) * (0.5 + f.x));
		vec3 wy = vec3(0.5 * (0.5 - f.y) * (0.5 - f.y), 0.75 - f.y * f.y, 0.5 * (0.5 + f.y) * (0.5 + f.y));
		float cov[10];
		for (int k = 0; k < 10; k++) {
			cov[k] = 0.0;
		}
		float lock = 0.0;
		float bare = 0.0;
		vec3 data = vec3(0.0);
		for (int j = 0; j < 3; j++) {
			for (int i = 0; i < 3; i++) {
				ivec2 c = ivec2(clamp(base + vec2(float(i - 1), float(j - 1)), vec2(0.0), map_size - 1.0));
				vec4 d = texelFetch(tile_tex, c, 0);
				float w = wx[i] * wy[j];
				int raw = int(d.r * 255.0 + 0.5);
				cov[min(raw & 63, 9)] += w;
				lock += raw >= 128 ? w : 0.0;
				bare += (raw & 64) != 0 ? w : 0.0;
				data += d.gba * w;
			}
		}
		float total = 0.0;
		float w_rough = 0.0;
		float w_deep = 0.0;
		for (int k = 0; k < 10; k++) {
			float v = pow(cov[k] * PRIORITY[k], 12.0);
			total += v;
			if (k == 0) {
				w_rough = v;
			} else if (k == 6) {
				w_deep = v;
			}
		}
		w_rough /= total;
		w_deep /= total;
		float turf = w_rough + w_deep;
		float health = data.y;
		grow = (growth.x * w_rough + growth.y * w_deep) * smoothstep(0.35, 0.8, turf) * (1.0 - smoothstep(0.15, 0.5, bare));
		grow *= mix(0.6, 1.0, smoothstep(0.2, 0.8, health));
		grow *= 1.0 - smoothstep(fade.x, fade.y, dist);

		// Everything below only matters where a tuft actually stands.
		if (grow >= 0.02) {
			// sit on the land, and share its shading
			float h0 = land(wp);
			float hx = land(wp + vec2(tile_size, 0.0)) - land(wp - vec2(tile_size, 0.0));
			float hz = land(wp + vec2(0.0, tile_size)) - land(wp - vec2(0.0, tile_size));
			ground_n = normalize(vec3(-hx, 2.0 * tile_size, -hz));
			// no grass on rock faces
			grow *= 1.0 - smoothstep(0.10, 0.26, 1.0 - ground_n.y);

			// the colour of the ground underneath, patchy in the same places
			float n = fbm(wp * 0.11) * 0.45 + vnoise(wp * 0.021) * 0.3 + vnoise(wp * 0.006 + 31.0) * 0.25;
			vec3 dry = mix(vec3(1.0), vec3(1.12, 1.04, 0.78), smoothstep(0.45, 0.8, vnoise(wp * 0.013 + 5.0)));
			vec3 c_rough = pal_rough * dry * (0.66 + 0.6 * n);
			vec3 c_deep = pal_deep * (0.72 + 0.42 * n);
			tint = (c_rough * w_rough + c_deep * w_deep) / max(turf, 0.001);
			vec3 tired = mix(pow(vec3(0.52, 0.42, 0.22), vec3(2.2)), pow(vec3(0.70, 0.66, 0.30), vec3(2.2)), smoothstep(0.2, 0.7, health));
			tint = mix(tint, tired, (1.0 - smoothstep(0.25, 0.95, health)) * 0.85);
			tint *= 1.0 - 0.3 * data.x;
			// each tuft a touch lighter or darker than its neighbours
			tint *= 0.86 + 0.3 * hash21(wp * 0.71 + 3.0);
			float ring = land(wp + vec2(3.0, 0.0) * tile_size) + land(wp - vec2(3.0, 0.0) * tile_size)
				+ land(wp + vec2(0.0, 3.0) * tile_size) + land(wp - vec2(0.0, 3.0) * tile_size);
			float relief = clamp(0.5 + (h0 - ring * 0.25) * 0.22, 0.0, 1.0);
			tint *= mix(0.6, 1.3, relief);
			float cl = fbm((wp + cloud_offset) * 0.0042);
			float edge = 0.78 - cloud_cover * 0.62;
			tint *= 1.0 - 0.36 * smoothstep(edge - 0.07, edge + 0.07, cl);
			if (lock > 0.001) {
				vec3 dull = vec3(dot(tint, vec3(0.33))) * 0.52;
				tint = mix(tint, dull, smoothstep(0.3, 0.7, lock) * 0.8);
			}

			vec3 rel = VERTEX - origin;
			rel.y *= grow;
			rel.xz *= mix(0.6, 1.0, min(grow * 1.5, 1.0));
			// lean and shiver in the wind, from the tips
			float strength = length(wind);
			float phase = TIME * (1.6 + strength * 0.25) + wp.x * 0.35 + wp.y * 0.27;
			float sway = (0.35 + 0.65 * sin(phase)) * 0.05 * strength + sin(TIME * 5.3 + wp.x * 3.1 + wp.y * 2.3) * 0.012 * strength;
			vec2 dir = strength > 0.001 ? wind / strength : vec2(1.0, 0.0);
			rel.xz += dir * sway * tip * tip * (0.4 + grow);
			VERTEX = vec3(wp.x, h0 - 0.02, wp.y) + rel;
		}
	}
	if (grow < 0.02) {
		// nothing grows here: fold the tuft away to nothing
		VERTEX = vec3(wp.x, -1000.0, wp.y);
	}
}

void fragment() {
	vec4 blade = texture(atlas, UV);
	float texels = max(length(fwidth(UV)) * 512.0, 1.0);
	float a = blade.a * (1.0 + clamp(log2(texels), 0.0, 5.0) * 0.45);
	ALPHA = clamp(a, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * 1024.0;
	ALBEDO = tint * season_grass * clamp(blade.rgb / blade_mean, 0.0, 2.2) * gain * mix(0.9, 1.12, tip);
	NORMAL = normalize((VIEW_MATRIX * vec4(ground_n, 0.0)).xyz);
	ROUGHNESS = 0.95;
	AO_LIGHT_AFFECT = 0.0;
}
