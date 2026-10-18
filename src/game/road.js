import { Container, Graphics, Text } from 'pixi.js'
import { STAGE_LENGTH, stageAt } from './threat.js'

export const SEGMENT = 30
export const ROAD_WIDTH = 96
const CHUNK = 40
const LOOK_AHEAD = 120
const MAX_DRIFT = 1.1 // max angle (rad) the road may wander from heading "up"
const UP = -Math.PI / 2
const MAX_HEADING = 1.4 // hard limit (rad) from "up": the road never turns back on itself
const AVOID_LOOKAHEAD = 12 // segments ahead the road checks for places to steer round
const PX_PER_METRE = 20
const MILESTONE_EVERY = 250 // metres

const LABEL = { fontFamily: 'Georgia, serif', fill: '#2a1f14', fontWeight: 'bold' }

// A stone by the roadside with the distance carved on it; where a new
// region begins, a wooden sign naming it as well.
function milestone(metres) {
  const view = new Container()
  const stone = new Graphics()
  stone.ellipse(3, 4, 15, 9).fill({ color: '#000', alpha: 0.2 })
  stone.roundRect(-15, -9, 30, 17, 6).fill('#b9b5aa').stroke({ width: 1.5, color: '#7d7a72' })
  const label = new Text({ text: `${metres} m`, style: { ...LABEL, fontSize: 10 } })
  label.anchor.set(0.5)
  view.addChild(stone, label)

  if (metres % STAGE_LENGTH === 0) {
    const { name } = stageAt(metres)
    const sign = new Graphics()
    sign.moveTo(0, -9).lineTo(0, -22).stroke({ width: 3, color: '#5e3f22' })
    sign.roundRect(-58, -40, 116, 20, 3).fill('#a8875c').stroke({ width: 2, color: '#5e3f22' })
    const title = new Text({ text: name, style: { ...LABEL, fontSize: 12 } })
    title.anchor.set(0.5)
    title.y = -30
    view.addChild(sign, title)
  }
  return view
}

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
    this.keepOut = [] // { x, y, radius } places the road must steer round (side-road destinations)
    this.chunks = []
    this.drawnUpTo = 0
  }

  generate(count) {
    for (let n = 0; n < count; n++) {
      const last = this.points[this.points.length - 1]
      // Forget keep-out zones the road has long since left behind.
      if (n === 0) this.keepOut = this.keepOut.filter((z) => z.y - last.y < 2500)

      if (--this.untilNewCurve <= 0) {
        this.targetCurve = (Math.random() * 2 - 1) * 0.09
        this.untilNewCurve = 8 + Math.floor(Math.random() * 14)
      }
      const drift = this.heading - UP
      if (Math.abs(drift) > MAX_DRIFT) this.targetCurve = -Math.sign(drift) * 0.06

      // Steer hard away from anything built off a side road.
      const away = this.avoid(last)
      if (away) {
        this.targetCurve = away * 0.12
        this.curve = away * Math.max(Math.abs(this.curve), 0.07)
      }

      this.curve += (this.targetCurve - this.curve) * 0.12
      this.heading = UP + Math.max(-MAX_HEADING, Math.min(MAX_HEADING, this.heading + this.curve - UP))
      this.points.push({
        x: last.x + Math.cos(this.heading) * SEGMENT,
        y: last.y + Math.sin(this.heading) * SEGMENT,
        along: last.along + SEGMENT,
      })
    }
  }

  // Which way to turn (-1 left, 1 right, 0 no need) to keep the road ahead
  // clear of the keep-out zones.
  avoid(from) {
    const cos = Math.cos(this.heading)
    const sin = Math.sin(this.heading)
    for (const zone of this.keepOut) {
      const reach = zone.radius + ROAD_WIDTH / 2 + 60
      if (Math.hypot(zone.x - from.x, zone.y - from.y) > reach + AVOID_LOOKAHEAD * SEGMENT) continue
      for (let k = 1; k <= AVOID_LOOKAHEAD; k++) {
        const x = from.x + cos * SEGMENT * k
        const y = from.y + sin * SEGMENT * k
        if (Math.hypot(zone.x - x, zone.y - y) < reach) {
          // Turn away from the side the zone is on.
          const side = cos * (zone.y - from.y) - sin * (zone.x - from.x)
          return side > 0 ? -1 : 1
        }
      }
    }
    return 0
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

    // The road surface changes with the region it runs through.
    const colours = stageAt(this.points[start].along / 20).biome.road
    const edge = path(new Graphics()).stroke(style(ROAD_WIDTH + 16, colours.edge))
    const fill = path(new Graphics()).stroke(style(ROAD_WIDTH, colours.fill))
    path(fill, -20).stroke(style(6, colours.rut, 0.7))
    path(fill, 20).stroke(style(6, colours.rut, 0.7))
    path(fill, 0).stroke(style(14, colours.crown, 0.5))

    // Milestones on the right-hand verge
    const markers = []
    for (let i = start + 1; i <= end; i++) {
      const prev = Math.floor(this.points[i - 1].along / PX_PER_METRE / MILESTONE_EVERY)
      const here = Math.floor(this.points[i].along / PX_PER_METRE / MILESTONE_EVERY)
      if (here === prev || here === 0) continue
      const p = this.points[i]
      const n = this.normal(i)
      const marker = milestone(here * MILESTONE_EVERY)
      marker.position.set(p.x + n.x * (ROAD_WIDTH / 2 + 26), p.y + n.y * (ROAD_WIDTH / 2 + 26))
      markers.push(marker)
    }

    this.edgeLayer.addChild(edge)
    this.fillLayer.addChild(fill, ...markers)
    this.chunks.push({ end, edge, fill, markers })
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
      c.markers.forEach((m) => m.destroy({ children: true }))
      return false
    })
  }
}
