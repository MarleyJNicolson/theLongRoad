import { Container, Graphics, Text } from 'pixi.js'
import { ROAD_WIDTH, SEGMENT } from '../road.js'
import { stageAt } from '../threat.js'
import { dirtPattern } from '../textures.js'
import { rand, randInt, roadFrame } from './helpers.js'
import { DEST_RADIUS, friendlyVillage, raidedVillage, banditStronghold, goblinWarcamp } from './destinations.js'

export const SIDE_WIDTH = 72
const ROUTE_ATTEMPTS = 20
const PX_PER_METRE = 20

const KINDS = [
  { make: friendlyVillage, weight: 34 },
  { make: raidedVillage, weight: 22 },
  { make: banditStronghold, weight: 22 },
  { make: goblinWarcamp, weight: 22 },
]

function pickKind() {
  let roll = Math.random() * KINDS.reduce((sum, k) => sum + k.weight, 0)
  return KINDS.find((k) => (roll -= k.weight) < 0) ?? KINDS[0]
}

// Wind a side road out from main-road point `i`. It bends back toward road
// that already exists: the main road only ever heads up the map, so nothing
// built down there can be run over later. Null if there's no room.
function planRoute(road, i, zones) {
  const { p, n } = roadFrame(road, i)
  const main = road.points.slice(Math.max(0, i - 160))
  const clear = (x, y, gap) => main.every((m) => Math.hypot(m.x - x, m.y - y) > gap)
  const firstSide = Math.random() < 0.5 ? 1 : -1
  // Try a handful of routes on each side: steeper or shallower, longer or
  // shorter, until one has room.
  for (let attempt = 0; attempt < ROUTE_ATTEMPTS; attempt++) {
    const side = attempt % 2 === 0 ? firstSide : -firstSide
    // Out to the side, often angled back down the map
    let heading = Math.atan2(n.y * side + rand(-0.2, 1.4), n.x * side)
    let curve = 0
    const points = [{ x: p.x, y: p.y }]
    const length = randInt(20, 32)
    for (let k = 0; k < length; k++) {
      curve = Math.max(-0.07, Math.min(0.07, curve + rand(-0.04, 0.04)))
      heading += curve
      const last = points[points.length - 1]
      points.push({ x: last.x + Math.cos(heading) * SEGMENT, y: last.y + Math.sin(heading) * SEGMENT })
    }
    const end = points[points.length - 1]
    // The destination sits just past the end of the road
    const cx = end.x + Math.cos(heading) * (DEST_RADIUS - 40)
    const cy = end.y + Math.sin(heading) * (DEST_RADIUS - 40)
    // Keep destinations level with or behind the junction, so the main road
    // (which only heads up the map) has plenty of room to steer round them.
    if (cy < p.y - 150) continue
    const apart = zones.every((z) => Math.hypot(z.x - cx, z.y - cy) > z.radius + DEST_RADIUS)
    const destClear = clear(cx, cy, DEST_RADIUS + ROAD_WIDTH / 2 + 40)
    const roadClear = points.slice(4).every((q) => clear(q.x, q.y, ROAD_WIDTH / 2 + SIDE_WIDTH / 2 + 30))
    if (apart && destClear && roadClear) {
      return { side, points, cx, cy, entrance: Math.atan2(end.y - cy, end.x - cx) }
    }
  }
  return null
}

function drawRoute(road, points, colours) {
  const path = (g, offset = 0) => {
    points.forEach((q, k) => {
      const a = points[Math.max(0, k - 1)]
      const b = points[Math.min(points.length - 1, k + 1)]
      const len = Math.hypot(b.x - a.x, b.y - a.y) || 1
      const x = q.x - ((b.y - a.y) / len) * offset
      const y = q.y + ((b.x - a.x) / len) * offset
      k === 0 ? g.moveTo(x, y) : g.lineTo(x, y)
    })
    return g
  }
  // Same textured earth as the main road, just narrower and less worn
  const style = (width, color, alpha = 1, textured = false) => {
    const fill = textured ? dirtPattern(color) : null
    return { width, color: fill ? 0xffffff : color, alpha, cap: 'round', join: 'round', fill }
  }
  const edge = path(new Graphics()).stroke(style(SIDE_WIDTH + 28, colours.edge, 0.3))
  path(edge).stroke(style(SIDE_WIDTH + 10, colours.edge, 0.9, true))
  const fill = path(new Graphics()).stroke(style(SIDE_WIDTH, colours.fill, 1, true))
  path(fill).stroke(style(18, colours.crown, 0.35, true))
  path(fill, -14).stroke(style(8, colours.rut, 0.65, true))
  path(fill, 14).stroke(style(8, colours.rut, 0.65, true))
  // Same layers as the main road, so the two blend at the junction
  road.edgeLayer.addChild(edge)
  road.fillLayer.addChild(fill)
  return [edge, fill]
}

// A fingerpost by the junction. The board stays level so it's easy to
// read, and points left or right toward the turning.
function signpost(stand, x, y, pointsLeft, title, metres, hostile) {
  const post = new Container()
  const g = new Graphics()
  g.circle(2, 2, 4).fill({ color: '#000', alpha: 0.25 })
  g.circle(0, 0, 3.5).fill('#5e3f22')
  const label = new Text({
    text: `${title} · ${metres} m`,
    style: { fontFamily: '"Pixelify Sans", monospace', fontWeight: '600', fontSize: 18, fill: hostile ? '#f3e3c0' : '#2a1f14' },
  })
  label.anchor.set(0.5)
  label.y = -20
  // Board drawn pointing right; mirrored to point left.
  const board = new Graphics()
  board.poly([-125, -36, 125, -36, 145, -20, 125, -4, -125, -4]).fill(hostile ? '#7a4a3a' : '#a8875c').stroke({ width: 3, color: '#3d2f25' })
  if (hostile) board.circle(125, -20, 5).fill('#e8e0c8')
  if (pointsLeft) board.scale.x = -1
  post.addChild(g, board, label)
  stand(post, x, y)
}

// A side road off main-road point `i` leading to a big destination, or null
// if it won't fit here.
export function sideRoad(ctx) {
  const { layer, road, i, zones } = ctx
  const route = planRoute(road, i, zones)
  if (!route) return null

  const metres = (i * SEGMENT) / PX_PER_METRE
  const { biome } = stageAt(metres)
  const roadViews = drawRoute(road, route.points, biome.road)
  // The main road, still to be generated beyond here, must steer round it all.
  road.keepOut.push(
    { x: route.cx, y: route.cy, radius: DEST_RADIUS },
    ...route.points.filter((_, k) => k > 3 && k % 2 === 0).map((q) => ({ x: q.x, y: q.y, radius: SIDE_WIDTH / 2 + 10 })),
  )

  const view = new Container()
  layer.addChild(view)
  const kind = pickKind()
  const faction = biome.name === 'The Darkwood' ? 'goblin' : biome.name === 'The Barrens' ? 'bandit' : Math.random() < 0.5 ? 'goblin' : 'bandit'
  const dest = kind.make({ ...ctx, view, cx: route.cx, cy: route.cy, entrance: route.entrance, metres, km: metres / 1000, faction })

  // Signpost on the verge just past the turning (the side road bends
  // back the other way, so it stays clear)
  const { p, n, d } = roadFrame(road, i)
  const sx = p.x + n.x * route.side * (ROAD_WIDTH / 2 + 70) + d.x * 80
  const sy = p.y + n.y * route.side * (ROAD_WIDTH / 2 + 70) + d.y * 80
  const length = Math.round((route.points.length * SEGMENT + DEST_RADIUS) / PX_PER_METRE)
  signpost(ctx.stand, sx, sy, route.points[6].x < p.x, dest.title, length, dest.hostile)

  return {
    ...dest,
    view,
    roadViews,
    sideRoad: { points: route.points, width: SIDE_WIDTH },
    // Keep trees off the road and out of the destination
    zone: { x: route.cx, y: route.cy, radius: DEST_RADIUS + 20 },
    zones: [
      { x: route.cx, y: route.cy, radius: DEST_RADIUS + 20 },
      ...route.points.map((q) => ({ x: q.x, y: q.y, radius: SIDE_WIDTH / 2 + 14 })),
    ],
    trigger: { x: route.cx, y: route.cy, radius: dest.trigger ?? 0 },
    animate: dest.animate ?? (() => {}),
  }
}

// Is (x, y) on this side road's surface?
export function onSideRoad(enc, x, y) {
  const { points, width } = enc.sideRoad
  for (let k = 0; k < points.length - 1; k++) {
    const a = points[k]
    const b = points[k + 1]
    const dx = b.x - a.x
    const dy = b.y - a.y
    const t = Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / (dx * dx + dy * dy)))
    if (Math.hypot(x - (a.x + dx * t), y - (a.y + dy * t)) < width / 2 + 4) return true
  }
  return false
}
