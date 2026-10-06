shader_type sky;
// A sky with a real horizon, a sun, and clouds that drift with the wind and
// thicken with the weather. The same cloud field shades the ground.

uniform vec3 top_color : source_color = vec3(0.16, 0.38, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.76, 0.90);
uniform vec3 ground_color : source_color = vec3(0.2, 0.25, 0.2);
uniform vec3 cloud_lit : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_dark : source_color = vec3(0.55, 0.6, 0.68);
uniform float cloud_cover = 0.2;
uniform vec2 cloud_offset = vec2(0.0);
uniform float night = 0.0;          // 0 by day, 1 in the dead of night

// the same noise picture the ground uses, so cloud shadows match the clouds
uniform sampler2D noise_tex : filter_linear, repeat_enable;

float fbm(vec2 p) {
	return texture(noise_tex, p * 0.03125).b;
}

float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.5));
	if (h < 0.0) {
		col = mix(horizon_color, ground_color, smoothstep(0.0, -0.25, h));
	}
	// the sun and its glow
	float sd = max(dot(dir, LIGHT0_DIRECTION), 0.0);
	vec3 sun = LIGHT0_COLOR * LIGHT0_ENERGY;
	col += sun * (pow(sd, 900.0) * 6.0 + pow(sd, 24.0) * 0.12 + pow(sd, 4.0) * 0.04);
	// stars come out as the light goes
	if (night > 0.02 && h > 0.0) {
		vec3 g = dir * 150.0;
		vec3 cell = floor(g);
		float pick = hash31(cell);
		if (pick > 0.9962) {
			float pt = 1.0 - smoothstep(0.06, 0.42, length(fract(g) - 0.5));
			float twinkle = 0.75 + 0.25 * sin(TIME * 2.0 + pick * 900.0);
			col += vec3(0.85, 0.92, 1.0) * pt * twinkle * night * (0.5 + hash31(cell + 7.0)) * 1.3 * smoothstep(0.02, 0.25, h);
		}
	}
	// clouds on a flat layer high above
	if (h > 0.015) {
		vec2 uv = dir.xz / (h + 0.18) * 1.6 + cloud_offset * 0.0042 * 60.0;
		float c = fbm(uv * 0.55);
		float edge = 0.78 - cloud_cover * 0.62;
		float m = smoothstep(edge - 0.1, edge + 0.16, c);
		float dense = smoothstep(edge, edge + 0.4, c);
		vec3 cc = mix(cloud_lit, cloud_dark, dense * (0.45 + 0.5 * cloud_cover));
		cc += sun * pow(sd, 6.0) * 0.08 * (1.0 - dense);
		col = mix(col, cc, m * smoothstep(0.015, 0.14, h) * 0.95);
	}
	COLOR = col;
}
