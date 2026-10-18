import { Graphics } from 'pixi.js'

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
export function drawClearing(g, x, y, ex, ey, color = '#8f8a52') {
  for (let k = 0; k < 7; k++) {
    const a = (k / 7) * Math.PI * 2
    g.circle(x + Math.cos(a) * 55, y + Math.sin(a) * 45, rand(60, 80))
  }
  g.fill({ color, alpha: 0.55 })
  g.moveTo(x, y).lineTo(ex, ey).stroke({ width: 26, color, alpha: 0.5, cap: 'round' })
}

// Stone-ringed campfire. Adds its flame to `view`; call the returned
// function every frame to make it flicker.
export function campfire(g, view, x, y) {
  for (let k = 0; k < 8; k++) {
    const a = (k / 8) * Math.PI * 2
    g.circle(x + Math.cos(a) * 15, y + Math.sin(a) * 15, 4).fill('#7d7a72')
  }
  g.circle(x, y, 11).fill('#2a1f14')
  const fire = new Graphics()
  fire.circle(0, 0, 10).fill({ color: '#e8641e', alpha: 0.9 })
  fire.circle(0, 0, 6).fill('#ffb02e')
  fire.circle(0, 0, 3).fill('#fff1a8')
  fire.position.set(x, y)
  const glow = new Graphics().circle(0, 0, 70).fill({ color: '#ff9a3c', alpha: 0.12 })
  glow.position.set(x, y)
  view.addChild(glow, fire)
  return (time) => {
    fire.scale.set(1 + Math.sin(time * 17) * 0.12 + Math.sin(time * 7.3) * 0.08)
    fire.rotation = time * 2
    glow.alpha = 0.85 + Math.sin(time * 11) * 0.15
  }
}

export function drawLog(g, x1, y1, x2, y2, width = 16) {
  g.moveTo(x1, y1).lineTo(x2, y2).stroke({ width, color: '#5e3f22', cap: 'round' })
  g.moveTo(x1, y1).lineTo(x2, y2).stroke({ width: width / 4, color: '#7d5a36', alpha: 0.8, cap: 'round' })
  for (const [x, y] of [[x1, y1], [x2, y2]]) {
    g.circle(x, y, width * 0.38).fill('#a8875c').circle(x, y, width * 0.19).fill('#8a6a42')
  }
}
