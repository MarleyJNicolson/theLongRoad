// The pixel-art pass (port of pixelArt.js). It runs on a rect exactly the size
// of the world viewport, at art resolution: one fragment per art pixel. It
// grades the colour, dithers, snaps to the palette and inks dark outlines.
shader_type canvas_item;
render_mode unshaded;

uniform vec3 palette[60];
uniform float ink_threshold = 0.16;
uniform float ink_strength = 0.65;
uniform float dither = 0.012;

const vec3 INK = vec3(14.0, 11.0, 10.0) / 255.0;

// 4×4 ordered (Bayer) dither threshold in 0..1, by formula.
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x / 2.0 + a.y * a.y * 0.75);
}
float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Everything reads from exact pixel centres, so the two triangles of the quad
// can't round differently and leave a seam along the diagonal.
vec3 texel(sampler2D tex, vec2 index, vec2 offset, vec2 pixel) {
	vec2 uv = (index + offset + 0.5) * pixel;
	return texture(tex, clamp(uv, pixel * 0.5, 1.0 - pixel * 0.5)).rgb;
}

// A gentle grim grade: slightly desaturated and warm.
vec3 grade(vec3 c) {
	float l = luma(c);
	c = mix(vec3(l), c, 0.9);
	c = pow(c, vec3(1.05));
	return c * vec3(1.0, 0.97, 0.93);
}

vec3 nearest(vec3 c) {
	vec3 best = INK;
	float best_dist = 1e9;
	for (int i = 0; i < 60; i++) {
		vec3 d = c - palette[i];
		float dist = dot(d * d, vec3(0.30, 0.59, 0.11));
		if (dist < best_dist) {
			best_dist = dist;
			best = palette[i];
		}
	}
	return best;
}

void fragment() {
	// Which input pixel this fragment covers. (+0.25: if the grid is ever half
	// a pixel out, every lookup lands on a boundary; this nudges it safely to
	// one side either way.)
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE + 0.25);

	vec3 c = grade(texel(TEXTURE, px, vec2(0.0), TEXTURE_PIXEL_SIZE));
	float l = luma(c);

	// Ordered dithering, then snap to the palette.
	c += (bayer4(px) - 0.5) * dither;
	vec3 out_color = nearest(clamp(c, 0.0, 1.0));

	// Ink a one-pixel outline on the dark side of any strong edge.
	float brightest = max(
		max(luma(grade(texel(TEXTURE, px, vec2(1.0, 0.0), TEXTURE_PIXEL_SIZE))),
			luma(grade(texel(TEXTURE, px, vec2(-1.0, 0.0), TEXTURE_PIXEL_SIZE)))),
		max(luma(grade(texel(TEXTURE, px, vec2(0.0, 1.0), TEXTURE_PIXEL_SIZE))),
			luma(grade(texel(TEXTURE, px, vec2(0.0, -1.0), TEXTURE_PIXEL_SIZE)))));
	if (brightest - l > ink_threshold) out_color = mix(out_color, INK, ink_strength);

	COLOR = vec4(out_color, 1.0);
}
