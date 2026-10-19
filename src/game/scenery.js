import { Container, Graphics } from 'pixi.js'
import { ROAD_WIDTH, SEGMENT } from './road.js'
import { BIOMES, stageAt } from './threat.js'
import { box, drawSolid } from './iso.js'

const rand = (min, max) => min + Math.random() * (max - min)
const pick = (arr) => arr[Math.floor(Math.random() * arr.length)]
// A shadow on the ground, cast down and to the right (the light is from the
// top left), under something standing at the origin.
const shadow = (g, w, h, alpha = 0.22) => g.ellipse(w * 0.3, h * 0.15, w, h).fill({ color: '#000', alpha })

const SPREAD = 950 // how far from the road the land is dressed
const ATTEMPTS = 5 // tries per side for each stretch of road

// Everything standing up is drawn in three-quarter view like the people:
// its base sits at the origin (where it meets the ground) and it rises up
// the screen. Draw functions return the Graphics plus how tall it is.

// --- Trees -----------------------------------------------------------------

const BARK = '#5c4632'
const BARK_SHADE = '#46352a'

// A trunk rising from the ground, flared at the roots, shaded on the right.
function trunk(g, width, height, colour = BARK, shade = BARK_SHADE) {
  g.poly([-width, 0, -width * 0.65, -height, width * 0.65, -height, width, 0]).fill(colour)
  g.poly([width * 0.15, 0, width * 0.2, -height, width * 0.65, -height, width, 0]).fill(shade)
  for (const s of [-1, 1]) g.poly([s * width * 0.6, 0, s * width * 1.7, 1.5, s * width * 0.9, -width * 0.8]).fill(colour)
}

// Broad oak: a stout trunk under a big lumpy crown, lit from the top left.
function oak(r, biome) {
  const g = new Graphics()
  const [dark, mid, light] = [...biome.trees].sort()
  const stem = r * 0.8
  const cy = -(stem + r * 0.55) // middle of the crown
  shadow(g, r * 1.05, r * 0.42)
  trunk(g, r * 0.16 + 2, stem + r * 0.2)
  g.circle(0, cy + r * 0.1, r).fill(dark)
  for (let k = 0; k < 7; k++) {
    const a = (k / 7) * Math.PI * 2 + rand(-0.25, 0.25)
    const lit = Math.sin(a) < 0 // upper clumps catch the light
    g.circle(Math.cos(a) * r * 0.55, cy + Math.sin(a) * r * 0.5, r * rand(0.38, 0.52)).fill(lit ? mid : dark)
  }
  g.circle(-r * 0.25, cy - r * 0.3, r * 0.5).fill({ color: light, alpha: 0.85 })
  g.circle(-r * 0.4, cy - r * 0.5, r * 0.22).fill({ color: biome.leaf, alpha: 0.8 })
  // The crown's shadowed underside
  g.ellipse(0, cy + r * 0.62, r * 0.8, r * 0.25).fill({ color: '#000', alpha: 0.18 })
  return { g, height: stem + r * 1.55 }
}

// Birch: a slender white trunk with dark marks and a small, airy crown.
function birch(r, biome) {
  const g = new Graphics()
  const stem = r * 1.4
  shadow(g, r * 0.8, r * 0.3, 0.18)
  trunk(g, 2.6, stem, '#e8e0c8', '#c9bfa6')
  for (let k = 0; k < 5; k++) {
    const y = -stem * rand(0.1, 0.9)
    g.rect(rand(-2, 0.5), y, rand(1.5, 3), 1.2).fill('#2b221c')
  }
  const pale = biome.name === 'The Frostmarch' ? ['#a7aeb6', '#c0c6cc', '#d9dee2'] : ['#6a7f42', '#7a8c4c', '#8a9a55', '#9fab66']
  const cy = -stem - r * 0.3
  for (let k = 0; k < 9; k++) {
    const x = rand(-r, r) * 0.55
    const y = cy + rand(-r, r) * 0.6
    g.circle(x, y, r * rand(0.28, 0.42)).fill(y < cy ? pale[pale.length - 1] : pick(pale))
  }
  return { g, height: stem + r * 0.9 }
}

// Pine: stacked tiers of needles narrowing to a point; snow on the tiers in
// the Frostmarch.
function pine(r, biome) {
  const g = new Graphics()
  const snowy = biome.name === 'The Frostmarch'
  const [dark, mid] = [...biome.trees].sort()
  const stem = r * 0.35
  const tiers = 4
  const tierH = r * 0.62
  shadow(g, r * 0.9, r * 0.35)
  trunk(g, r * 0.1 + 2, stem + 4)
  for (let k = 0; k < tiers; k++) {
    const w = r * (1 - k * 0.2)
    const base = -stem - k * tierH * 0.8
    const top = base - tierH * 1.25
    g.poly([-w, base, 0, top, w, base]).fill(k % 2 ? mid : dark)
    g.poly([0, top, w, base, w * 0.35, base]).fill({ color: '#000', alpha: 0.15 }) // shaded side
    if (snowy) g.poly([-w * 0.55, base - tierH * 0.55, 0, top, w * 0.25, base - tierH * 0.6]).fill('#eef1f2')
    else if (k === tiers - 1) g.poly([-w * 0.35, base - tierH * 0.6, 0, top, 0, base - tierH * 0.4]).fill({ color: biome.leaf, alpha: 0.6 })
  }
  return { g, height: stem + tierH * (tiers * 0.8 + 0.45) }
}

// Dead tree: a bare, twisted trunk with branches clawing upward.
function deadTree(r) {
  const g = new Graphics()
  const stem = r * 0.9
  shadow(g, r * 0.5, r * 0.2, 0.18)
  trunk(g, 3, stem, '#5c4a38', '#463828')
  const branch = (x, y, a, len, w) => {
    const ex = x + Math.cos(a) * len
    const ey = y + Math.sin(a) * len
    g.moveTo(x, y).lineTo(ex, ey).stroke({ width: w, color: '#5c4a38', cap: 'round' })
    if (len > 7) {
      branch(ex, ey, a + rand(0.25, 0.6), len * 0.62, w * 0.65)
      branch(ex, ey, a - rand(0.25, 0.6), len * 0.55, w * 0.65)
    }
  }
  const limbs = Math.floor(rand(3, 5))
  for (let k = 0; k < limbs; k++) {
    const a = -Math.PI / 2 + (k / (limbs - 1) - 0.5) * 2.2 + rand(-0.2, 0.2)
    branch(0, -stem * rand(0.7, 1), a, r * rand(0.45, 0.6), 3.2)
  }
  return { g, height: stem + r * 0.6 }
}

// --- Rocks and stones -------------------------------------------------------

// A small rock: a low mound, lit on top.
function rock(r) {
  const g = new Graphics()
  shadow(g, r * 1.1, r * 0.45, 0.25)
  g.ellipse(0, -r * 0.3, r, r * 0.6).fill('#77736a')
  g.ellipse(-r * 0.2, -r * 0.45, r * 0.65, r * 0.38).fill('#9a968c')
  return g
}

// A big boulder: lit top, shaded face, a crack; lichen or snow on top.
function boulder(r, biome) {
  const g = new Graphics()
  shadow(g, r * 1.2, r * 0.45, 0.28)
  const pts = []
  const sides = Math.floor(rand(8, 11))
  for (let k = 0; k < sides; k++) {
    const a = (k / sides) * Math.PI * 2
    const d = rand(0.82, 1.05)
    // Flat underneath, where it sits on the ground
    pts.push(Math.cos(a) * r * d, Math.min(0, -r * 0.6 + Math.sin(a) * r * 0.75 * d))
  }
  g.poly(pts).fill('#5f5b54')
  g.poly(pts.map((v, k) => (k % 2 ? v * 0.75 - r * 0.2 : v * 0.85 - r * 0.08))).fill('#7c786f')
  g.poly(pts.map((v, k) => (k % 2 ? v * 0.42 - r * 0.42 : v * 0.5 - r * 0.15))).fill('#9a968c')
  g.moveTo(r * 0.1, -r * 0.9).lineTo(r * 0.25, -r * 0.5).lineTo(r * 0.12, -r * 0.1).stroke({ width: 1.5, color: '#3c3a35' })
  if (biome.name === 'The Frostmarch') g.ellipse(-r * 0.1, -r * 1.05, r * 0.65, r * 0.25).fill('#eef1f2')
  else if (Math.random() < 0.4) g.ellipse(r * 0.35, -r * 0.35, r * 0.25, r * 0.18).fill({ color: '#5d7339', alpha: 0.8 })
  return { g, height: r * 1.4 }
}

// One standing stone: a weathered upright slab.
function slab() {
  const g = new Graphics()
  const w = rand(5, 7)
  const h = rand(16, 24)
  shadow(g, w * 1.6, 4, 0.28)
  g.roundRect(-w, -h, w * 2, h, 2).fill('#69717c')
  g.rect(w * 0.2, -h + 2, w * 0.8, h - 2).fill('#575f6b') // shaded side
  g.roundRect(-w, -h, w * 2, 4, 2).fill('#8f97a1') // weathered top
  g.moveTo(-w * 0.4, -h * 0.6).lineTo(-w * 0.1, -h * 0.35).stroke({ width: 1, color: '#3c424d' })
  return g
}

// An ancient ring of standing stones round a flat altar stone.
function standingStones(r) {
  const g = new Graphics()
  g.ellipse(0, 0, r + 10, (r + 10) * 0.9).fill({ color: '#000', alpha: 0.06 })
  g.roundRect(-10, -5, 20, 10, 2).fill('#7c848f').stroke({ width: 1, color: '#575f6b' })
  const solids = []
  const uprights = []
  const count = 7
  for (let k = 0; k < count; k++) {
    const a = (k / count) * Math.PI * 2
    const x = Math.cos(a) * r
    const y = Math.sin(a) * r * 0.9
    uprights.push({ g: slab(), x, y })
    solids.push({ x, y, radius: 8 })
  }
  return { g, solids, uprights }
}

// --- Ground clutter ---------------------------------------------------------

// A tree stump: a short cylinder with rings on its cut top.
function stump(r) {
  const g = new Graphics()
  shadow(g, r * 1.2, r * 0.45, 0.25)
  const h = r * 0.9
  g.rect(-r, -h, r * 2, h).fill('#5c4632')
  g.rect(r * 0.2, -h, r * 0.8, h).fill('#46352a')
  g.ellipse(0, 0, r, r * 0.45).fill('#5c4632')
  g.ellipse(0, -h, r, r * 0.45).fill('#b89a70')
  g.ellipse(0, -h, r * 0.55, r * 0.25).stroke({ width: 1, color: '#8a6c4b' })
  return g
}

function fallenLog(r) {
  const g = new Graphics()
  g.moveTo(-r + 3, 4).lineTo(r + 3, 4).stroke({ width: 10, color: '#000', alpha: 0.2, cap: 'round' })
  g.moveTo(-r, 0).lineTo(r, 0).stroke({ width: 10, color: '#5e3f22', cap: 'round' })
  g.moveTo(-r + 4, -2).lineTo(r - 6, -2).stroke({ width: 2, color: '#7d5a36' })
  g.circle(r, 0, 4.5).fill('#a8875c').circle(r, 0, 2).fill('#8a6a42')
  g.moveTo(-r * 0.2, -4).lineTo(-r * 0.35, -11).stroke({ width: 2, color: '#5e3f22', cap: 'round' })
  return g
}

// A bush: a rounded mound of leaves, lit on top.
export function bush(r, biome = BIOMES[0]) {
  const [a, b, c] = biome.bush
  const g = new Graphics()
  shadow(g, r * 1.1, r * 0.4, 0.18)
  g.circle(-r * 0.45, -r * 0.45, r * 0.6).fill(c)
  g.circle(r * 0.45, -r * 0.45, r * 0.62).fill(a)
  g.circle(0, -r * 0.75, r * 0.7).fill(b)
  g.circle(-r * 0.2, -r * 0.95, r * 0.35).fill({ color: '#ffffff', alpha: 0.12 })
  if (Math.random() < 0.4) g.circle(r * 0.25, -r * 0.7, 2.5).fill('#c0392b')
  return g
}

function tufts(r, biome) {
  const g = new Graphics()
  for (let i = 0; i < 5; i++) {
    const x = rand(-10, 10)
    const y = rand(-6, 6)
    g.moveTo(x, y).lineTo(x + rand(-3, 3), y - rand(5, 9))
  }
  return g.stroke({ width: 2, color: biome.grass, cap: 'round' })
}

function flowers(r) {
  const g = new Graphics()
  const colour = pick(['#e6d3a8', '#f6c25a', '#a3331f', '#8f6fb0', '#d9dee2'])
  for (let k = 0; k < 12; k++) {
    const x = rand(-r, r)
    const y = rand(-r, r) * 0.7
    g.moveTo(x, y).lineTo(x, y + 4).stroke({ width: 1, color: '#4f6634' })
    g.circle(x, y, 1.8).fill(colour)
  }
  return g
}

function mushrooms(r) {
  const g = new Graphics()
  for (let k = 0; k < 4; k++) {
    const x = rand(-r, r)
    const y = rand(-r, r) * 0.6
    const s = rand(2.5, 4)
    g.circle(x + 1, y + 1, s).fill({ color: '#000', alpha: 0.2 })
    g.circle(x, y, s).fill('#a3331f')
    g.circle(x - s * 0.3, y - s * 0.3, s * 0.3).fill('#e6d3a8')
  }
  return g
}

function bones(r) {
  const g = new Graphics()
  for (let k = 0; k < 4; k++) {
    const x = rand(-r, r)
    const y = rand(-r, r) * 0.6
    const a = rand(0, Math.PI)
    g.moveTo(x - Math.cos(a) * 6, y - Math.sin(a) * 6).lineTo(x + Math.cos(a) * 6, y + Math.sin(a) * 6)
  }
  g.stroke({ width: 2, color: '#e6d3a8', cap: 'round' })
  g.circle(rand(-4, 4), rand(-4, 4), 4).fill('#e6d3a8')
  return g
}

// A faint patch of the region's own grass tones, so the land isn't one flat colour.
function patch(r, biome) {
  const g = new Graphics()
  const colour = pick([biome.grass, biome.leaf])
  for (let k = 0; k < 4; k++) g.ellipse(rand(-r, r) * 0.4, rand(-r, r) * 0.3, r * rand(0.5, 0.8), r * rand(0.35, 0.55))
  g.fill({ color: colour, alpha: 0.1 })
  return g
}

// --- Abandoned cottage ----------------------------------------------------------

// Tumbledown stone walls with gaps, a chimney stack still standing, fallen
// roof beams and rubble. The floor and rubble lie on the ground; each
// surviving stretch of wall stands up on its own, sorted by its base.
function ruin() {
  const g = new Graphics()
  const w = rand(64, 80)
  const h = rand(48, 60)
  const solids = []
  const uprights = []
  g.rect(-w / 2 - 2, -h / 2 - 2, w + 4, h + 4).fill({ color: '#000', alpha: 0.12 })
  g.rect(-w / 2, -h / 2, w, h).fill({ color: '#3d2f25', alpha: 0.75 }) // the old floor
  // Collapsed roof timbers and rubble across the floor
  for (let k = 0; k < 3; k++) {
    const y = rand(-h / 3, h / 3)
    g.moveTo(-w / 2 + rand(4, 15), y).lineTo(w / 2 - rand(4, 15), y + rand(-12, 12)).stroke({ width: 3.5, color: '#2b221c' })
  }
  for (let k = 0; k < 14; k++) g.ellipse(rand(-w / 2 - 10, w / 2 + 10), rand(-h / 2 - 8, h / 2 + 10), rand(2, 4), rand(1.5, 3))
  g.fill('#7c766c')
  if (Math.random() < 0.6) g.circle(rand(-w / 4, w / 4), rand(-h / 4, h / 4), 9).fill({ color: '#4f6634', alpha: 0.8 })

  const corners = [[-w / 2, -h / 2], [w / 2, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]]
  for (let side = 0; side < 4; side++) {
    const [x1, y1] = corners[side]
    const [x2, y2] = corners[(side + 1) % 4]
    const angle = Math.atan2(y2 - y1, x2 - x1)
    const len = Math.hypot(x2 - x1, y2 - y1)
    // Each wall survives in a few stretches, highest towards the corners
    const steps = 5
    for (let k = 0; k < steps; k++) {
      if (Math.random() < 0.35) continue
      const t = (k + 0.5) / steps
      const edge = 1 - Math.abs(t - 0.5) * 2 // 0 at the corners
      const high = rand(6, 14) + (1 - edge) * rand(6, 16)
      const x = x1 + (x2 - x1) * t
      const y = y1 + (y2 - y1) * t
      const wall = new Graphics()
      drawSolid(wall, box(len / steps + 0.5, 7, high, angle, pick(['#8a857a', '#827d72', '#918c80']), { top: '#a39e92' }), { outline: '#4a463f' })
      // A stone or two left balanced on top
      if (Math.random() < 0.5) wall.rect(rand(-5, 2), -high - 3, rand(4, 7), 3).fill('#7c776d')
      uprights.push({ g: wall, x, y })
      solids.push({ x, y, radius: 7 })
    }
  }
  // Chimney stack still standing in one corner
  const [cx, cy] = pick(corners)
  const chimney = new Graphics()
  drawSolid(chimney, box(14, 14, rand(38, 52), 0, '#69717c', { top: '#3c424d' }), { outline: '#3c424d' })
  uprights.push({ g: chimney, x: cx, y: cy })
  solids.push({ x: cx, y: cy, radius: 9 })
  return { g, solids, uprights }
}

// --- What grows where ------------------------------------------------------------

// Relative chances of each feature in each region. `size` is a radius
// range; `upright` things stand up and are depth-sorted with the people (a
// trunk or boulder hides whoever is behind it); `solid` is how much of the
// base you can't pass through (for trees, just the trunk); `spin` things
// lie flat on the ground and can be turned any way.
const FEATURES = {
  oak: { draw: oak, size: [26, 44], upright: true, solid: (r) => r * 0.16 + 4, grove: 0.35, tree: true },
  birch: { draw: birch, size: [16, 24], upright: true, solid: () => 4, grove: 0.5, tree: true },
  pine: { draw: pine, size: [20, 36], upright: true, solid: (r) => r * 0.1 + 4, grove: 0.6, tree: true },
  deadTree: { draw: deadTree, size: [22, 34], upright: true, solid: () => 5, tree: true },
  // `stones` is how many stones can be gathered from it
  boulder: { draw: boulder, size: [16, 32], upright: true, solid: (r) => r * 0.85, stones: [10, 16] },
  rock: { draw: rock, size: [5, 12], stones: [3, 6] },
  stump: { draw: stump, size: [6, 10] },
  log: { draw: fallenLog, size: [16, 26], spin: true },
  bush: { draw: bush, size: [10, 17] },
  tufts: { draw: tufts, size: [10, 10] },
  flowers: { draw: flowers, size: [10, 16], spin: true },
  mushrooms: { draw: mushrooms, size: [8, 12] },
  bones: { draw: bones, size: [8, 12], spin: true },
  patch: { draw: patch, size: [70, 140], flat: true, spin: true },
  ruin: { draw: ruin, size: [48, 48], parts: true },
  stones: { draw: standingStones, size: [40, 46], parts: true },
}

const MIXES = {
  'The Meadows': { oak: 10, birch: 6, pine: 2, deadTree: 1, bush: 9, boulder: 2, rock: 6, stump: 2, log: 1.5, flowers: 8, tufts: 14, patch: 2, ruin: 0.4, stones: 0.15 },
  'The Darkwood': { pine: 16, oak: 6, deadTree: 4, bush: 8, mushrooms: 6, log: 4, stump: 4, boulder: 2, rock: 3, tufts: 8, patch: 2, bones: 1, ruin: 0.35, stones: 0.1 },
  'The Barrens': { deadTree: 5, oak: 1, bush: 7, boulder: 6, rock: 10, bones: 4, tufts: 12, patch: 3, ruin: 0.5, stones: 0.3 },
  'The Frostmarch': { pine: 12, deadTree: 3, birch: 3, boulder: 5, rock: 6, tufts: 6, log: 2, patch: 2, ruin: 0.35, stones: 0.3 },
}

function choose(mix) {
  let roll = Math.random() * Object.values(mix).reduce((a, b) => a + b, 0)
  for (const [name, weight] of Object.entries(mix)) if ((roll -= weight) < 0) return name
  return 'tufts'
}

// Dresses the land on both sides of the road, out past the edge of the
// screen, and keeps it clear of the road, side roads and encounters.
export class Scenery {
  // `uprightLayer` is the depth-sorted layer shared with the people.
  constructor(groundLayer, uprightLayer, road, getZones = () => []) {
    this.patches = new Container() // ground colour patches lie under everything
    groundLayer.addChild(this.patches)
    this.ground = groundLayer
    this.upright = uprightLayer
    this.road = road
    this.getZones = getZones // areas (camps, roadblocks) to keep clear
    this.items = []
    this.placedUpTo = 0
  }

  get obstacles() {
    return this.items.flatMap((item) => item.solids)
  }

  // Remove anything already standing inside these zones (a side road laid
  // through ground that has been planted).
  clear(zones) {
    this.items = this.items.filter((item) => {
      if (!zones.some((z) => Math.hypot(z.x - item.x, z.y - item.y) < z.radius + item.r * 0.5)) return true
      this.remove(item)
      return false
    })
  }

  // `budget` caps how many stretches of road get dressed this frame, so a
  // freshly generated chunk of road is spread over several frames.
  update(index, budget = Infinity) {
    // Lag behind generation so we can check clearance against upcoming road.
    while (budget-- > 0 && this.placedUpTo < this.road.points.length - 40) {
      this.placeAround(this.placedUpTo++)
    }
    this.items = this.items.filter((item) => {
      if (item.index >= index - 80) return true
      this.remove(item)
      return false
    })
  }

  remove(item) {
    item.obj.destroy()
    item.extras?.forEach((o) => o.destroy())
  }

  // Trees you're standing behind fade, so you never lose sight of yourself.
  fadeAround(x, y) {
    for (const item of this.items) {
      if (!item.height) continue
      const hidden = y < item.y && y > item.y - item.height && Math.abs(x - item.x) < item.r + 6
      const target = hidden ? 0.4 : 1
      item.obj.alpha += (target - item.obj.alpha) * 0.2
    }
  }

  placeAround(i) {
    const p = this.road.points[i]
    const n = this.road.normal(i)
    const { biome } = stageAt((i * SEGMENT) / 20)
    const mix = MIXES[biome.name] ?? MIXES['The Meadows']
    for (const side of [-1, 1]) {
      for (let k = 0; k < ATTEMPTS; k++) {
        const name = choose(mix)
        // Spread evenly across the whole width, not bunched by the road
        const offset = ROAD_WIDTH / 2 + 30 + rand(0, SPREAD)
        const x = p.x + n.x * offset * side + rand(-15, 15)
        const y = p.y + n.y * offset * side + rand(-15, 15)
        if (this.place(name, x, y, i, biome) && FEATURES[name].grove && Math.random() < FEATURES[name].grove) {
          // Trees like company
          for (let g = 0; g < Math.floor(rand(2, 5)); g++) {
            const a = rand(0, Math.PI * 2)
            const d = rand(40, 90)
            this.place(name, x + Math.cos(a) * d, y + Math.sin(a) * d, i, biome)
          }
        }
      }
    }
  }

  place(name, x, y, i, biome) {
    const f = FEATURES[name]
    const r = rand(...f.size)
    const big = f.solid || f.parts
    if (!this.isClear(x, y, i, f.flat ? 0 : r + 12, big ? r : 0)) return false

    const drawn = f.draw(r, biome)
    const obj = drawn.g ?? drawn
    obj.position.set(x, y)
    if (f.spin) obj.rotation = rand(0, Math.PI * 2)
    if (f.upright) {
      obj.zIndex = y // depth-sorted by where it meets the ground
      this.upright.addChild(obj)
    } else {
      ;(f.flat ? this.patches : this.ground).addChild(obj)
    }

    let solids = []
    const extras = []
    if (f.parts) {
      solids = drawn.solids.map((q) => ({ x: x + q.x, y: y + q.y, radius: q.radius }))
      // Separate standing pieces (stones in a ring), each sorted by its own base
      for (const u of drawn.uprights ?? []) {
        u.g.position.set(x + u.x, y + u.y)
        u.g.zIndex = y + u.y
        this.upright.addChild(u.g)
        extras.push(u.g)
      }
    } else if (f.solid) {
      solids = [{ x, y, radius: f.solid(r) }]
    }
    const gather = f.stones ? Math.floor(rand(f.stones[0], f.stones[1] + 1)) : 0
    const height = f.tree ? drawn.height : 0 // only trees fade (see fadeAround)
    this.items.push({ obj, extras, index: i, x, y, r, big: !!big, solids, gather, kind: name, height })
    return true
  }

  // The nearest rock or boulder with stones left, within `reach` of its edge.
  gatherableNear(x, y, reach) {
    let best = null
    let bestDist = Infinity
    for (const item of this.items) {
      if (!item.gather) continue
      const d = Math.hypot(item.x - x, item.y - y) - item.r
      if (d < reach && d < bestDist) {
        best = item
        bestDist = d
      }
    }
    return best
  }

  // Take stones from a rock: small rocks are carried off whole once empty;
  // boulders stay, chipped and pale.
  quarry(item, taken) {
    item.gather = Math.max(0, item.gather - taken)
    if (item.gather) return
    if (item.kind === 'rock') {
      this.remove(item)
      this.items.splice(this.items.indexOf(item), 1)
    } else {
      item.obj.tint = 0xc8c2b8
      for (let k = 0; k < 6; k++) item.obj.circle(rand(-item.r, item.r) * 0.8, -item.r * rand(0.1, 1.1), rand(1, 2.5))
      item.obj.fill('#a8a59a')
    }
  }

  // Clear of the road, encounters, and (for big things) other big things.
  isClear(x, y, i, margin, room) {
    if (this.getZones().some((z) => Math.hypot(z.x - x, z.y - y) < z.radius + margin)) return false
    const pts = this.road.points
    for (let j = Math.max(0, i - 70); j < Math.min(pts.length, i + 70); j++) {
      if (Math.hypot(pts[j].x - x, pts[j].y - y) < ROAD_WIDTH / 2 + margin) return false
    }
    if (room) {
      for (let k = this.items.length - 1; k >= 0 && k > this.items.length - 400; k--) {
        const o = this.items[k]
        if (o.big && Math.hypot(o.x - x, o.y - y) < (o.r + room) * 0.8) return false
      }
    }
    return true
  }
}
