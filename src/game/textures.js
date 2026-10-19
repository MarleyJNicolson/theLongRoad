import { FillPattern, Texture } from 'pixi.js'

// Textures painted in code when the game starts: tileable noise-based dirt
// and grass, so the road and ground aren't flat colour. Everything here is
// near-white and gets tinted to each region's colours where it's used.
// (No canvas, e.g. in tests: everything falls back to plain colour.)

const SIZE = 256
const cache = new Map()

// Seeded random, so the textures are the same every run.
function seeded(seed) {
  let s = seed
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0
    return s / 4294967296
  }
}

// Tileable value noise: a lattice of random values that wraps at the edges,
// blended smoothly between points.
function noiseLayer(random, cells) {
  const lattice = Array.from({ length: cells * cells }, random)
  const at = (x, y) => lattice[((y + cells) % cells) * cells + ((x + cells) % cells)]
  const smooth = (t) => t * t * (3 - 2 * t)
  return (px, py) => {
    const fx = (px / SIZE) * cells
    const fy = (py / SIZE) * cells
    const x0 = Math.floor(fx)
    const y0 = Math.floor(fy)
    const tx = smooth(fx - x0)
    const ty = smooth(fy - y0)
    const top = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * tx
    const bottom = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * tx
    return top + (bottom - top) * ty
  }
}

// Several octaves of noise added together: broad patches plus fine grain.
function fractal(random, octaves) {
  const layers = octaves.map(([cells, weight]) => [noiseLayer(random, cells), weight])
  const total = octaves.reduce((sum, [, w]) => sum + w, 0)
  return (x, y) => layers.reduce((sum, [layer, w]) => sum + layer(x, y) * w, 0) / total
}

function paint(name, draw) {
  if (cache.has(name)) return cache.get(name)
  if (typeof document === 'undefined') return null
  const canvas = document.createElement('canvas')
  canvas.width = canvas.height = SIZE
  const ctx = canvas.getContext('2d')
  draw(ctx)
  const texture = Texture.from(canvas)
  // Smooth sampling: with nearest, a screen pixel landing exactly between
  // two texture pixels can round differently on each of the two triangles
  // a shape is drawn with, leaving a visible diagonal seam. (The pixel-art
  // pass makes everything blocky afterwards anyway.)
  texture.source.scaleMode = 'linear'
  cache.set(name, texture)
  return texture
}

// Fill every pixel from a brightness function (0..1 → grey).
function shade(ctx, brightness) {
  const img = ctx.createImageData(SIZE, SIZE)
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      const v = Math.max(0, Math.min(255, brightness(x, y) * 255))
      const k = (y * SIZE + x) * 4
      img.data[k] = img.data[k + 1] = img.data[k + 2] = v
      img.data[k + 3] = 255
    }
  }
  ctx.putImageData(img, 0, 0)
}

// Wrap-around dabs so speckles cross the tile edges seamlessly.
function dab(ctx, x, y, r, style) {
  ctx.fillStyle = style
  for (const dx of [-SIZE, 0, SIZE]) {
    for (const dy of [-SIZE, 0, SIZE]) {
      ctx.beginPath()
      ctx.ellipse(x + dx, y + dy, r, r * 0.8, 0, 0, Math.PI * 2)
      ctx.fill()
    }
  }
}

// Packed earth: mottled, gritty, with pebbles and the odd crack.
export function dirtTexture() {
  return paint('dirt', (ctx) => {
    const random = seeded(7)
    const noise = fractal(random, [[4, 3], [12, 2], [40, 1.2], [128, 0.8]])
    shade(ctx, (x, y) => 0.72 + noise(x, y) * 0.32)
    for (let k = 0; k < 260; k++) {
      const r = 0.6 + random() * 1.8
      const tone = Math.floor(120 + random() * 110)
      dab(ctx, random() * SIZE, random() * SIZE, r, `rgba(${tone},${tone},${tone},0.85)`)
    }
    // Hairline cracks
    ctx.strokeStyle = 'rgba(70,70,70,0.35)'
    ctx.lineWidth = 1
    for (let k = 0; k < 14; k++) {
      let x = random() * SIZE
      let y = random() * SIZE
      ctx.beginPath()
      ctx.moveTo(x, y)
      for (let s = 0; s < 4; s++) {
        x += (random() - 0.5) * 18
        y += (random() - 0.5) * 18
        ctx.lineTo(x, y)
      }
      ctx.stroke()
    }
  })
}

// Meadow grass: patchy light and shade with a scatter of blade marks.
export function grassTexture() {
  return paint('grass', (ctx) => {
    const random = seeded(19)
    const noise = fractal(random, [[3, 3], [9, 2], [32, 1], [96, 0.7]])
    shade(ctx, (x, y) => 0.8 + noise(x, y) * 0.24)
    for (let k = 0; k < 900; k++) {
      const x = random() * SIZE
      const y = random() * SIZE
      const light = random() < 0.5
      ctx.strokeStyle = light ? 'rgba(255,255,255,0.22)' : 'rgba(0,0,0,0.16)'
      ctx.lineWidth = 1
      for (const dx of [-SIZE, 0, SIZE]) {
        for (const dy of [-SIZE, 0, SIZE]) {
          ctx.beginPath()
          ctx.moveTo(x + dx, y + dy)
          ctx.lineTo(x + dx + (random() - 0.5) * 3, y + dy - 2 - random() * 4)
          ctx.stroke()
        }
      }
    }
  })
}

// A copy of a texture with a colour multiplied in (pattern fills ignore a
// stroke's own colour, so road textures are baked per colour).
function tinted(name, base, colour) {
  const key = `${name}:${colour}`
  if (cache.has(key) || !base) return cache.get(key) ?? null
  const canvas = document.createElement('canvas')
  canvas.width = canvas.height = SIZE
  const ctx = canvas.getContext('2d')
  ctx.drawImage(base.source.resource, 0, 0)
  ctx.globalCompositeOperation = 'multiply'
  ctx.fillStyle = colour
  ctx.fillRect(0, 0, SIZE, SIZE)
  const texture = Texture.from(canvas)
  // Smooth sampling: with nearest, a screen pixel landing exactly between
  // two texture pixels can round differently on each of the two triangles
  // a shape is drawn with, leaving a visible diagonal seam. (The pixel-art
  // pass makes everything blocky afterwards anyway.)
  texture.source.scaleMode = 'linear'
  cache.set(key, texture)
  return texture
}

// A repeating, world-anchored pattern of dirt in the given colour, or null
// (plain colour) when textures aren't available.
export function dirtPattern(colour) {
  const texture = tinted('dirt', dirtTexture(), colour)
  return texture ? new FillPattern(texture, 'repeat') : null
}
