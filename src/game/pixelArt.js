import { Filter, GlProgram } from 'pixi.js'

// The game is drawn with ordinary shapes, then this post-process turns the
// whole frame into grim medieval pixel art: it runs at a reduced resolution
// (see PIXEL_SIZE), snaps every colour to a limited palette with a touch of
// ordered dithering, and inks dark outlines along strong edges.

// Screen (CSS) pixels per art pixel.
export const PIXEL_SIZE = 2

// How far the camera zooms in on the world, so sprites get enough art
// pixels to read clearly.
export const WORLD_ZOOM = 1.3

// A muted, earthy palette with warm accents: soot and bone, moss, stone and
// steel, then blood, rust, fire and gold.
export const PALETTE = [
  // soot, earth and bone
  '#0e0b0a', '#1c1714', '#2b221c', '#3d2f25', '#4a3a2b', '#54402f', '#6e553c', '#7c6045', '#8a6c4b', '#98795a',
  '#a88a62', '#b89a70', '#c9ad80', '#d6bf94', '#e6d3a8',
  // moss and leaf
  '#121a12', '#1d2a1a', '#2a3b22', '#33452a', '#3a4f2b', '#46592f', '#4f6634', '#5d7339', '#6a7f42', '#7a8c4c',
  '#8a9a55', '#9fab66',
  // dry grass and straw
  '#3a3620', '#5c5530', '#706638', '#857a45', '#988b50', '#ab9c5c', '#c4b373',
  // stone, steel and snow
  '#16181e', '#262a33', '#2f343d', '#3c424d', '#4a515c', '#575f6b', '#69717c', '#7c848f', '#8f97a1', '#a7aeb6',
  '#c0c6cc', '#d9dee2', '#eef1f2',
  // dusk blues
  '#1d2836', '#33475a', '#4d6478',
  // blood, rust, fire and gold
  '#2a0e0e', '#4a1514', '#76201a', '#a3331f', '#cf5528', '#ee8a36', '#f6c25a', '#fdf0a6',
]

const INK = PALETTE[0]

const rgb = (hex) => [1, 3, 5].map((k) => parseInt(hex.slice(k, k + 2), 16) / 255)
const vec3 = (hex) => `vec3(${rgb(hex).map((v) => v.toFixed(4)).join(', ')})`

const vertex = `
in vec2 aPosition;
out vec2 vTextureCoord;

uniform vec4 uInputSize;
uniform vec4 uOutputFrame;
uniform vec4 uOutputTexture;

vec4 filterVertexPosition(void) {
  vec2 position = aPosition * uOutputFrame.zw + uOutputFrame.xy;
  position.x = position.x * (2.0 / uOutputTexture.x) - 1.0;
  position.y = position.y * (2.0 * uOutputTexture.z / uOutputTexture.y) - uOutputTexture.z;
  return vec4(position, 0.0, 1.0);
}

vec2 filterTextureCoord(void) {
  return aPosition * (uOutputFrame.zw * uInputSize.zw);
}

void main(void) {
  gl_Position = filterVertexPosition();
  vTextureCoord = filterTextureCoord();
}
`

const fragment = `
in vec2 vTextureCoord;
out vec4 finalColor;

uniform sampler2D uTexture;
uniform vec4 uInputPixel;
uniform vec4 uInputClamp;
uniform float uInk;
uniform float uDither;
uniform float uInkStrength;

const vec3 INK = ${vec3(INK)};

// 4×4 ordered (Bayer) dither threshold in 0..1, by formula so it works on
// every WebGL version.
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

// Which input pixel this fragment covers. Everything below reads from
// exact pixel centres, so the two triangles of the full-screen quad can't
// round differently and leave a seam along the diagonal.
vec2 pixelIndex() {
  // (+0.25: if the grid is ever half a pixel out, every lookup lands on a
  // boundary; this nudges it safely to one side either way.)
  return floor(vTextureCoord * uInputPixel.xy + 0.25);
}

vec3 texel(vec2 offset) {
  vec2 uv = (pixelIndex() + offset + 0.5) * uInputPixel.zw;
  return texture(uTexture, clamp(uv, uInputClamp.xy, uInputClamp.zw)).rgb;
}

// A gentle grim grade: slightly desaturated and warm.
vec3 grade(vec3 c) {
  float l = luma(c);
  c = mix(vec3(l), c, 0.9);
  c = pow(c, vec3(1.05));
  return c * vec3(1.0, 0.97, 0.93);
}

void consider(vec3 p, vec3 c, inout vec3 best, inout float bestDist) {
  vec3 d = c - p;
  float dist = dot(d * d, vec3(0.30, 0.59, 0.11));
  if (dist < bestDist) {
    bestDist = dist;
    best = p;
  }
}

vec3 nearest(vec3 c) {
  vec3 best = INK;
  float bestDist = 1e9;
${PALETTE.map((hex) => `  consider(${vec3(hex)}, c, best, bestDist);`).join('\n')}
  return best;
}

void main(void) {
  vec3 c = grade(texel(vec2(0.0)));
  float l = luma(c);

  // Ordered dithering, then snap to the palette.
  vec2 px = pixelIndex();
  c += (bayer4(px) - 0.5) * uDither;
  vec3 outColor = nearest(clamp(c, 0.0, 1.0));

  // Ink a one-pixel outline on the dark side of any strong edge.
  float brightest = max(
    max(luma(grade(texel(vec2(1.0, 0.0)))), luma(grade(texel(vec2(-1.0, 0.0))))),
    max(luma(grade(texel(vec2(0.0, 1.0)))), luma(grade(texel(vec2(0.0, -1.0)))))
  );
  if (brightest - l > uInk) outColor = mix(outColor, INK, uInkStrength);

  finalColor = vec4(outColor, 1.0);
}
`

export function createPixelArtFilter() {
  return new Filter({
    glProgram: GlProgram.from({ vertex, fragment, name: 'pixel-art' }),
    resources: {
      pixelArt: {
        uInk: { value: 0.16, type: 'f32' },
        uInkStrength: { value: 0.65, type: 'f32' },
        uDither: { value: 0.012, type: 'f32' },
      },
    },
  })
}
