import { Graphics } from 'pixi.js'

export const SEGMENT = 30
export const ROAD_WIDTH = 96
const CHUNK = 40
const LOOK_AHEAD = 120
const MAX_DRIFT = 1.1 // max angle (rad) the road may wander from heading "up"
const UP = -Math.PI / 2

// An endless winding dirt road, generated ahead of the player as a polyline
// and drawn in chunks so old pieces can be thrown away.
export class Road {
  constructor(edgeLayer, fillLayer) {
    this.edgeLayer = edgeLayer
    this.fillLayer = fillLayer
    this.points = [{ x: 0, y: 300, along: 0 }]
    this.heading = UP
    this.curve = 0
    this.targetCurve = 0
    this.untilNewCurve = 15
    this.chunks = []
    this.drawnUpTo = 0
  }

  generate(count) {
    for (let n = 0; n < count; n++) {
      const last = this.points[this.points.length - 1]

      if (--this.untilNewCurve <= 0) {
        this.targetCurve = (Math.random() * 2 - 1) * 0.09
        this.untilNewCurve = 8 + Math.floor(Math.random() * 14)
      }
      const drift = this.heading - UP
      if (Math.abs(drift) > MAX_DRIFT) this.targetCurve = -Math.sign(drift) * 0.06

      this.curve += (this.targetCurve - this.curve) * 0.12
      this.heading += this.curve
      this.points.push({
        x: last.x + Math.cos(this.heading) * SEGMENT,
        y: last.y + Math.sin(this.heading) * SEGMENT,
        along: last.along + SEGMENT,
      })
    }
  }

  // Make sure road exists well beyond the given point index.
  ensureAhead(index) {
    while (this.points.length < index + LOOK_AHEAD) {
      this.generate(CHUNK)
      this.drawChunk(Math.max(0, this.drawnUpTo - 1), this.points.length - 1)
      this.drawnUpTo = this.points.length
    }
  }

  drawChunk(start, end) {
    const pts = this.points.slice(start, end + 1)
    const path = (g, offset = 0) => {
      pts.forEach((p, i) => {
        const n = this.normal(start + i)
        const x = p.x + n.x * offset
        const y = p.y + n.y * offset
        i === 0 ? g.moveTo(x, y) : g.lineTo(x, y)
      })
      return g
    }
    const style = (width, color, alpha = 1) => ({ width, color, alpha, cap: 'round', join: 'round' })

    const edge = path(new Graphics()).stroke(style(ROAD_WIDTH + 16, '#6f5130'))
    const fill = path(new Graphics()).stroke(style(ROAD_WIDTH, '#b9925e'))
    path(fill, -20).stroke(style(6, '#9c7646', 0.7))
    path(fill, 20).stroke(style(6, '#9c7646', 0.7))
    path(fill, 0).stroke(style(14, '#c4a06c', 0.5))

    this.edgeLayer.addChild(edge)
    this.fillLayer.addChild(fill)
    this.chunks.push({ end, edge, fill })
  }

  normal(i) {
    const a = this.points[Math.min(i, this.points.length - 2)]
    const b = this.points[Math.min(i, this.points.length - 2) + 1]
    const len = Math.hypot(b.x - a.x, b.y - a.y) || 1
    return { x: -(b.y - a.y) / len, y: (b.x - a.x) / len }
  }

  // Nearest point on the road, searching around a hint index for speed.
  nearest(x, y, hint) {
    let best = { dist: Infinity, index: hint, along: 0 }
    const from = Math.max(0, hint - 25)
    const to = Math.min(this.points.length - 2, hint + 40)
    for (let i = from; i <= to; i++) {
      const a = this.points[i]
      const b = this.points[i + 1]
      const dx = b.x - a.x
      const dy = b.y - a.y
      const t = Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / (dx * dx + dy * dy)))
      const dist = Math.hypot(x - (a.x + dx * t), y - (a.y + dy * t))
      if (dist < best.dist) best = { dist, index: i, along: a.along + t * SEGMENT }
    }
    return best
  }

  cull(index) {
    this.chunks = this.chunks.filter((c) => {
      if (c.end >= index - 60) return true
      c.edge.destroy()
      c.fill.destroy()
      return false
    })
  }
}
