import { Graphics } from 'pixi.js'
import { ROAD_WIDTH } from './road.js'

const rand = (min, max) => min + Math.random() * (max - min)
const pick = (arr) => arr[Math.floor(Math.random() * arr.length)]

function tree(r) {
  const g = new Graphics()
  g.ellipse(r * 0.35, r * 0.4, r, r * 0.85).fill({ color: '#000', alpha: 0.18 })
  g.circle(0, 0, r).fill(pick(['#2f6b2a', '#386f2e', '#2b5e30']))
  g.circle(-r * 0.3, -r * 0.3, r * 0.55).fill({ color: '#4c8a3a', alpha: 0.8 })
  g.circle(r * 0.35, r * 0.1, r * 0.4).fill({ color: '#3f7d34', alpha: 0.8 })
  return g
}

export function bush(r) {
  const g = new Graphics()
  g.ellipse(r * 0.3, r * 0.35, r, r * 0.8).fill({ color: '#000', alpha: 0.15 })
  g.circle(-r * 0.4, 0, r * 0.7).fill('#467a32')
  g.circle(r * 0.4, -r * 0.1, r * 0.75).fill('#4f8a38')
  g.circle(0, r * 0.3, r * 0.6).fill('#3f7030')
  if (Math.random() < 0.4) g.circle(r * 0.2, -r * 0.2, 2.5).fill('#c0392b')
  return g
}

function rock(r) {
  const g = new Graphics()
  g.ellipse(r * 0.3, r * 0.3, r, r * 0.7).fill({ color: '#000', alpha: 0.2 })
  g.ellipse(0, 0, r, r * 0.75).fill('#8d8a80')
  g.ellipse(-r * 0.25, -r * 0.2, r * 0.45, r * 0.3).fill('#a8a59a')
  return g
}

function tufts() {
  const g = new Graphics()
  for (let i = 0; i < 4; i++) {
    const x = rand(-10, 10)
    const y = rand(-6, 6)
    g.moveTo(x, y).lineTo(x + rand(-3, 3), y - rand(5, 9))
  }
  return g.stroke({ width: 2, color: '#4e8a36', cap: 'round' })
}

// Trees, bushes and rocks scattered beside the road, kept clear of it.
export class Scenery {
  constructor(groundLayer, canopyLayer, road, getZones = () => []) {
    this.ground = groundLayer
    this.canopy = canopyLayer
    this.road = road
    this.getZones = getZones // areas (camps, roadblocks) to keep clear
    this.items = []
    this.placedUpTo = 0
  }

  get obstacles() {
    return this.items.filter((item) => item.solid)
  }

  update(index) {
    // Lag behind generation so we can check clearance against upcoming road.
    while (this.placedUpTo < this.road.points.length - 40) {
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
    for (const side of [-1, 1]) {
      for (let k = 0; k < 3; k++) {
        if (Math.random() > 0.45) continue
        const roll = Math.random()
        const kind = roll < 0.3 ? 'tree' : roll < 0.5 ? 'bush' : roll < 0.62 ? 'rock' : 'tufts'
        const r = kind === 'tree' ? rand(26, 44) : kind === 'bush' ? rand(10, 17) : kind === 'rock' ? rand(5, 12) : 10
        const offset = ROAD_WIDTH / 2 + 20 + r + rand(0, 520) * Math.random()
        const x = p.x + n.x * offset * side + rand(-15, 15)
        const y = p.y + n.y * offset * side + rand(-15, 15)
        if (!this.isClear(x, y, i, r + 12)) continue

        const obj = { tree, bush, rock, tufts }[kind](r)
        obj.position.set(x, y)
        obj.rotation = rand(0, Math.PI * 2)
        ;(kind === 'tree' ? this.canopy : this.ground).addChild(obj)
        // Trees are solid: collide with the trunk and inner canopy.
        this.items.push({ obj, index: i, x, y, solid: kind === 'tree', radius: r * 0.7 })
      }
    }
  }

  isClear(x, y, i, margin) {
    if (this.getZones().some((z) => Math.hypot(z.x - x, z.y - y) < z.radius + margin)) return false
    const pts = this.road.points
    for (let j = Math.max(0, i - 40); j < Math.min(pts.length, i + 40); j++) {
      if (Math.hypot(pts[j].x - x, pts[j].y - y) < ROAD_WIDTH / 2 + margin) return false
    }
    return true
  }
}
