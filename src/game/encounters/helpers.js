import { Container, Graphics } from 'pixi.js'
import { flames } from '../structures.js'

export const rand = (min, max) => min + Math.random() * (max - min)
export const randInt = (min, max) => Math.floor(rand(min, max + 1))

// Local frame at a road point: `at(along, lateral)` converts road-relative
// offsets (along the direction of travel, sideways from the centre line)
// into world coordinates.
export function roadFrame(road, i) {
  const p = road.points[i]
  const q = road.points[i + 1]
  const n = road.normal(i)
  const len = Math.hypot(q.x - p.x, q.y - p.y) || 1
  const d = { x: (q.x - p.x) / len, y: (q.y - p.y) / len }
  const at = (along, lateral) => [p.x + d.x * along + n.x * lateral, p.y + d.y * along + n.y * lateral]
  return { p, n, d, at }
}

// Which side of the road (-1 or 1) has room for something `offset` away from
// the centre line without spilling onto a nearby bend. 0 if neither.
export function sideThatFits(road, i, offset) {
  const { p, n } = roadFrame(road, i)
  const pts = road.points.slice(Math.max(0, i - 40), i + 40)
  const fits = (s) => {
    const x = p.x + n.x * s * offset
    const y = p.y + n.y * s * offset
    return pts.every((rp) => Math.hypot(rp.x - x, rp.y - y) > offset - 10)
  }
  const first = Math.random() < 0.5 ? -1 : 1
  return fits(first) ? first : fits(-first) ? -first : 0
}

// A trampled clearing with a path out to the road edge at (ex, ey).
// (No path if it's off in the wilds: see `footpath`.)
export function drawClearing(g, x, y, ex, ey, color = '#8f8a52') {
  for (let k = 0; k < 7; k++) {
    const a = (k / 7) * Math.PI * 2
    g.circle(x + Math.cos(a) * 55, y + Math.sin(a) * 45, rand(60, 80))
  }
  g.fill({ color, alpha: 0.55 })
  if (ex === undefined) return
  g.moveTo(x, y).lineTo(ex, ey).stroke({ width: 26, color, alpha: 0.5, cap: 'round' })
}

// How often a camp or homestead is set back off in the wilds rather than
// beside the road, and how much likelier a chest is out there.
export const DEEP_CHANCE = 0.45
export const DEEP_CHEST_CHANCE = 0.9

// Where to put something `radius` across that would sit `near` the road
// edge. Often it's further off, out of sight in the wilds (`deep`), found
// by a footpath, a column of smoke or a marker by the road. Null if
// nothing fits.
export function setBack({ road, i, zones = [] }, near, radius, { deepOnly = false, far = 380 } = {}) {
  const goDeep = deepOnly || Math.random() < DEEP_CHANCE
  const tries = goDeep ? [rand(near + 160, near + far), rand(near + 100, near + 220)] : []
  if (!deepOnly) tries.push(near)
  const { at } = roadFrame(road, i)
  for (const offset of tries) {
    const side = sideThatFits(road, i, offset)
    if (!side) continue
    const [x, y] = at(0, side * offset)
    if (!zones.every((z) => Math.hypot(z.x - x, z.y - y) > z.radius + radius)) continue
    const deep = offset > near + 60
    // The road still to come must steer round it
    if (deep) road.keepOut.push({ x, y, radius: radius + 30 })
    return { side, offset, deep, x, y }
  }
  return null
}

// A winding footpath trodden from the road edge out to (tx, ty). Returns
// zones along it to keep trees off.
export function footpath(g, [fx, fy], [tx, ty], color = '#8a7f55') {
  const len = Math.hypot(tx - fx, ty - fy)
  const steps = Math.max(2, Math.round(len / 28))
  const nx = -(ty - fy) / len
  const ny = (tx - fx) / len
  const sway = rand(18, 40) * (Math.random() < 0.5 ? -1 : 1)
  const wobble = rand(1.5, 3)
  const pts = []
  for (let k = 0; k <= steps; k++) {
    const t = k / steps
    const off = Math.sin(t * Math.PI) * sway + Math.sin(t * Math.PI * wobble) * 8 * Math.sin(t * Math.PI)
    pts.push([fx + (tx - fx) * t + nx * off, fy + (ty - fy) * t + ny * off])
  }
  const trace = (width, alpha) => {
    pts.forEach(([x, y], k) => (k ? g.lineTo(x, y) : g.moveTo(x, y)))
    g.stroke({ width, color, alpha, cap: 'round', join: 'round' })
  }
  trace(24, 0.35)
  trace(13, 0.55)
  return pts.map(([x, y]) => ({ x, y, radius: 18 }))
}

// Smoke curling up from (x, y) at height `z`, high enough to be seen over
// the trees from the road. Call the returned function every frame.
export function smokePlume(stand, x, y, z = 10, { every = 0.2, colour = '#b4aea4' } = {}) {
  const smoke = stand(new Container(), x, y, { depth: y + 2 })
  const puffs = []
  let next = 0
  return (time, dt) => {
    if (time > next && smoke.parent) {
      const puff = new Graphics().circle(0, 0, 8).fill({ color: colour, alpha: 0.55 })
      puff.position.set(rand(-4, 4), -z)
      puff.seed = rand(0, 6)
      puff.life = 0
      smoke.addChild(puff)
      puffs.push(puff)
      next = time + every
    }
    for (let k = puffs.length - 1; k >= 0; k--) {
      const p = puffs[k]
      p.life += dt
      p.x += dt * (5 + p.life * 4 + Math.sin(p.life * 1.7 + p.seed) * 9)
      p.y -= dt * 42
      p.scale.set(1 + p.life * 0.8)
      p.alpha = Math.max(0, 1 - p.life / 7)
      if (p.life > 7) {
        p.destroy()
        puffs.splice(k, 1)
      }
    }
  }
}

// Stone-ringed campfire: stones and glow on the ground (`g`, `view`), the
// flames stood up with `stand`. Call the returned function every frame to
// make it flicker.
export function campfire(g, view, stand, x, y) {
  for (let k = 0; k < 8; k++) {
    const a = (k / 8) * Math.PI * 2
    g.ellipse(x + Math.cos(a) * 15, y + Math.sin(a) * 12, 4.5, 3.5).fill('#7d7a72')
  }
  g.ellipse(x, y, 11, 8).fill('#2a1f14')
  for (const a of [0.4, 2.2]) {
    g.moveTo(x - Math.cos(a) * 10, y - Math.sin(a) * 7).lineTo(x + Math.cos(a) * 10, y + Math.sin(a) * 7).stroke({ width: 3.5, color: '#4a3220', cap: 'round' })
  }
  const fire = stand(flames(), x, y + 1)
  const glow = new Graphics().circle(0, 0, 70).fill({ color: '#ff9a3c', alpha: 0.12 })
  glow.position.set(x, y)
  view.addChild(glow)
  const smoke = smokePlume(stand, x, y, 16)
  return (time, dt = 1 / 60) => {
    smoke(time, dt)
    fire.scale.set(1 + Math.sin(time * 7.3) * 0.08, 1 + Math.sin(time * 17) * 0.14 + Math.sin(time * 5.1) * 0.08)
    fire.skew.x = Math.sin(time * 4.3) * 0.12
    glow.alpha = 0.85 + Math.sin(time * 11) * 0.15
  }
}
