import { Container, Graphics } from 'pixi.js'
import { ROAD_WIDTH, SEGMENT } from './road.js'
import { BIOMES, stageAt } from './threat.js'

const rand = (min, max) => min + Math.random() * (max - min)
const pick = (arr) => arr[Math.floor(Math.random() * arr.length)]
const shadow = (g, r, alpha = 0.2) => g.ellipse(r * 0.3, r * 0.35, r, r * 0.82).fill({ color: '#000', alpha })

const SPREAD = 950 // how far from the road the land is dressed
const ATTEMPTS = 5 // tries per side for each stretch of road

// --- Trees -----------------------------------------------------------------

// Broad, lumpy oak canopy.
function oak(r, biome) {
  const g = shadow(new Graphics(), r)
  g.circle(0, 0, r).fill(pick(biome.trees))
  for (let k = 0; k < 5; k++) {
    const a = (k / 5) * Math.PI * 2 + rand(-0.3, 0.3)
    g.circle(Math.cos(a) * r * 0.55, Math.sin(a) * r * 0.55, r * rand(0.38, 0.5)).fill({ color: pick(biome.trees), alpha: 0.9 })
  }
  g.circle(-r * 0.3, -r * 0.3, r * 0.5).fill({ color: biome.leaf, alpha: 0.75 })
  g.circle(-r * 0.4, -r * 0.42, r * 0.22).fill({ color: biome.leaf, alpha: 0.6 })
  return g
}

// Small, pale and airy, with a glimpse of white bark.
function birch(r, biome) {
  const g = shadow(new Graphics(), r, 0.15)
  g.rect(r * 0.5, -2, 4, 7).fill('#e8e0c8').rect(r * 0.5, 1, 4, 1.5).fill('#2b221c')
  const pale = biome.name === 'The Frostmarch' ? ['#c0c6cc', '#a7aeb6'] : ['#7a8c4c', '#8a9a55', '#9fab66']
  for (let k = 0; k < 6; k++) {
    g.circle(rand(-r, r) * 0.45, rand(-r, r) * 0.45, r * rand(0.35, 0.55)).fill({ color: pick(pale), alpha: 0.9 })
  }
  return g
}

// Conifer seen from above: stacked star-shaped tiers of needles.
function pine(r, biome) {
  const g = shadow(new Graphics(), r)
  const snowy = biome.name === 'The Frostmarch'
  const tiers = [
    [1, pick(biome.trees)],
    [0.7, pick(biome.trees)],
    [0.42, snowy ? '#d9dee2' : biome.leaf],
  ]
  const spin = rand(0, Math.PI)
  for (const [scale, colour] of tiers) {
    const pts = []
    for (let k = 0; k < 18; k++) {
      const a = spin + (k / 18) * Math.PI * 2
      const d = r * scale * (k % 2 ? 0.68 : 1)
      pts.push(Math.cos(a) * d, Math.sin(a) * d)
    }
    g.poly(pts).fill(colour)
  }
  if (snowy) g.circle(-r * 0.2, -r * 0.2, r * 0.18).fill('#eef1f2')
  return g
}

// Bare, twisted branches; only the trunk is solid.
function deadTree(r) {
  const g = new Graphics()
  g.circle(3, 4, r * 0.25).fill({ color: '#000', alpha: 0.2 })
  const branch = (x, y, a, len, w) => {
    const ex = x + Math.cos(a) * len
    const ey = y + Math.sin(a) * len
    g.moveTo(x, y).lineTo(ex, ey).stroke({ width: w, color: '#5c4a38', cap: 'round' })
    if (len > 8) {
      branch(ex, ey, a + rand(0.3, 0.7), len * 0.6, w * 0.65)
      branch(ex, ey, a - rand(0.3, 0.7), len * 0.55, w * 0.65)
    }
  }
  const limbs = Math.floor(rand(4, 6))
  for (let k = 0; k < limbs; k++) branch(0, 0, (k / limbs) * Math.PI * 2 + rand(-0.3, 0.3), r * rand(0.45, 0.6), 4)
  g.circle(0, 0, r * 0.2).fill('#4a3a2b').circle(0, 0, r * 0.1).fill('#3d2f25')
  return g
}

// --- Rocks and stones -------------------------------------------------------

function rock(r) {
  const g = shadow(new Graphics(), r)
  g.ellipse(0, 0, r, r * 0.75).fill('#8d8a80')
  g.ellipse(-r * 0.25, -r * 0.2, r * 0.45, r * 0.3).fill('#a8a59a')
  return g
}

// A big faceted boulder, sometimes lichened or snow-capped.
function boulder(r, biome) {
  const g = new Graphics()
  const pts = []
  const sides = Math.floor(rand(7, 10))
  for (let k = 0; k < sides; k++) {
    const a = (k / sides) * Math.PI * 2
    const d = r * rand(0.78, 1.05)
    pts.push(Math.cos(a) * d, Math.sin(a) * d)
  }
  g.poly(pts.map((v, k) => v + (k % 2 ? r * 0.3 : r * 0.25))).fill({ color: '#000', alpha: 0.25 })
  g.poly(pts).fill('#6f6b63')
  g.poly(pts.map((v) => v * 0.7 - r * 0.12)).fill('#8d8a80')
  g.poly(pts.map((v) => v * 0.35 - r * 0.25)).fill('#a8a59a')
  g.moveTo(-r * 0.1, -r * 0.5).lineTo(r * 0.15, 0).lineTo(r * 0.05, r * 0.4).stroke({ width: 1.5, color: '#4a463f' })
  if (biome.name === 'The Frostmarch') g.poly(pts.map((v) => v * 0.45 - r * 0.3)).fill({ color: '#eef1f2', alpha: 0.9 })
  else if (Math.random() < 0.4) g.circle(r * 0.3, r * 0.2, r * 0.25).fill({ color: '#5d7339', alpha: 0.7 })
  return g
}

// An ancient ring of standing stones.
function standingStones(r) {
  const g = new Graphics()
  g.circle(0, 0, r + 10).fill({ color: '#000', alpha: 0.08 })
  g.roundRect(-9, -6, 18, 12, 2).fill('#7c848f') // the altar
  const solids = []
  const count = 7
  for (let k = 0; k < count; k++) {
    const a = (k / count) * Math.PI * 2
    const x = Math.cos(a) * r
    const y = Math.sin(a) * r
    g.ellipse(x + 3, y + 4, 8, 6).fill({ color: '#000', alpha: 0.25 })
    g.roundRect(x - 6, y - 8, 12, 15, 3).fill('#69717c').stroke({ width: 1.5, color: '#3c424d' })
    g.rect(x - 4, y - 6, 4, 9).fill('#8f97a1')
    solids.push({ x, y, radius: 9 })
  }
  return { g, solids }
}

// --- Ground clutter ---------------------------------------------------------

function stump(r) {
  const g = shadow(new Graphics(), r)
  g.circle(0, 0, r).fill('#6e553c')
  g.circle(0, 0, r * 0.75).fill('#b89a70').circle(0, 0, r * 0.45).stroke({ width: 1, color: '#8a6c4b' })
  g.circle(0, 0, r * 0.15).fill('#8a6c4b')
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

export function bush(r, biome = BIOMES[0]) {
  const [a, b, c] = biome.bush
  const g = shadow(new Graphics(), r, 0.15)
  g.circle(-r * 0.4, 0, r * 0.7).fill(a)
  g.circle(r * 0.4, -r * 0.1, r * 0.75).fill(b)
  g.circle(0, r * 0.3, r * 0.6).fill(c)
  if (Math.random() < 0.4) g.circle(r * 0.2, -r * 0.2, 2.5).fill('#c0392b')
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

// Tumbledown stone walls with gaps, fallen roof beams and rubble.
function ruin() {
  const g = new Graphics()
  const w = rand(60, 76)
  const h = rand(46, 58)
  const solids = []
  g.rect(-w / 2 + 4, -h / 2 + 5, w, h).fill({ color: '#000', alpha: 0.18 })
  g.rect(-w / 2, -h / 2, w, h).fill({ color: '#3d2f25', alpha: 0.75 }) // the old floor
  const corners = [[-w / 2, -h / 2], [w / 2, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]]
  for (let side = 0; side < 4; side++) {
    const [x1, y1] = corners[side]
    const [x2, y2] = corners[(side + 1) % 4]
    // Each wall survives in a few stretches
    const steps = 6
    for (let k = 0; k < steps; k++) {
      if (Math.random() < 0.35) continue
      const t1 = k / steps
      const t2 = (k + 1) / steps
      const ax = x1 + (x2 - x1) * t1
      const ay = y1 + (y2 - y1) * t1
      const bx = x1 + (x2 - x1) * t2
      const by = y1 + (y2 - y1) * t2
      g.moveTo(ax, ay).lineTo(bx, by).stroke({ width: 9, color: '#4a463f', cap: 'square' })
      g.moveTo(ax, ay).lineTo(bx, by).stroke({ width: 6, color: '#8a857a', cap: 'square' })
      solids.push({ x: (ax + bx) / 2, y: (ay + by) / 2, radius: 7 })
    }
  }
  // Collapsed roof timbers
  for (let k = 0; k < 3; k++) {
    const y = rand(-h / 3, h / 3)
    g.moveTo(-w / 2 + rand(0, 15), y).lineTo(w / 2 - rand(0, 15), y + rand(-12, 12)).stroke({ width: 3, color: '#2b221c' })
  }
  // Chimney stack still standing in one corner
  const [cx, cy] = pick(corners)
  g.rect(cx - 7, cy - 7, 14, 14).fill('#69717c').stroke({ width: 2, color: '#3c424d' })
  solids.push({ x: cx, y: cy, radius: 9 })
  // Rubble
  for (let k = 0; k < 10; k++) g.circle(rand(-w / 2 - 8, w / 2 + 8), rand(-h / 2 - 8, h / 2 + 8), rand(1.5, 3.5))
  g.fill('#7c766c')
  if (Math.random() < 0.6) g.circle(rand(-w / 4, w / 4), rand(-h / 4, h / 4), 8).fill('#4f6634')
  return { g, solids }
}

// --- What grows where ------------------------------------------------------------

// Relative chances of each feature in each region. `size` is a radius
// range, `top` puts it above the travellers (tree canopies), `solid` is the
// fraction of its radius you can't pass through.
const FEATURES = {
  oak: { draw: oak, size: [26, 44], top: true, solid: 0.6, grove: 0.35 },
  birch: { draw: birch, size: [16, 24], top: true, solid: 0.45, grove: 0.5 },
  pine: { draw: pine, size: [20, 36], top: true, solid: 0.45, grove: 0.6 },
  deadTree: { draw: deadTree, size: [22, 34], top: true, solid: 0.22 },
  // `stones` is how many stones can be gathered from it
  boulder: { draw: boulder, size: [16, 32], solid: 0.85, stones: [10, 16] },
  rock: { draw: rock, size: [5, 12], stones: [3, 6] },
  stump: { draw: stump, size: [6, 10] },
  log: { draw: fallenLog, size: [16, 26] },
  bush: { draw: bush, size: [10, 17] },
  tufts: { draw: tufts, size: [10, 10] },
  flowers: { draw: flowers, size: [10, 16] },
  mushrooms: { draw: mushrooms, size: [8, 12] },
  bones: { draw: bones, size: [8, 12] },
  patch: { draw: patch, size: [70, 140], flat: true },
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
  constructor(groundLayer, canopyLayer, road, getZones = () => []) {
    this.patches = new Container() // ground colour patches lie under everything
    groundLayer.addChild(this.patches)
    this.ground = groundLayer
    this.canopy = canopyLayer
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
      item.obj.destroy()
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
      item.obj.destroy()
      return false
    })
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
    const obj = f.parts ? drawn.g : drawn
    obj.position.set(x, y)
    if (!f.parts) obj.rotation = rand(0, Math.PI * 2)
    else obj.rotation = rand(-0.4, 0.4)
    ;(f.flat ? this.patches : f.top ? this.canopy : this.ground).addChild(obj)

    let solids = []
    if (f.parts) {
      // Solid parts were laid out unrotated around the origin
      const c = Math.cos(obj.rotation)
      const s = Math.sin(obj.rotation)
      solids = drawn.solids.map((q) => ({ x: x + q.x * c - q.y * s, y: y + q.x * s + q.y * c, radius: q.radius }))
    } else if (f.solid) {
      solids = [{ x, y, radius: r * f.solid }]
    }
    const gather = f.stones ? Math.floor(rand(f.stones[0], f.stones[1] + 1)) : 0
    this.items.push({ obj, index: i, x, y, r, big: !!big, solids, gather, kind: name })
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
      item.obj.destroy()
      this.items.splice(this.items.indexOf(item), 1)
    } else {
      item.obj.tint = 0xc8c2b8
      for (let k = 0; k < 6; k++) item.obj.circle(rand(-item.r, item.r) * 0.8, rand(-item.r, item.r) * 0.8, rand(1, 2.5))
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
