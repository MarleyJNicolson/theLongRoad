import { Container, Graphics } from 'pixi.js'
import { ROAD_WIDTH } from '../road.js'
import { addProp, maybeAddChest } from '../loot.js'
import { rand, randInt, roadFrame, setBack, footpath, drawClearing, campfire, DEEP_CHEST_CHANCE } from './helpers.js'
import { hideTent, skullTotem, overturnedWagon } from '../structures.js'

export function scatterBones(g, x, y, spreadX, spreadY, count) {
  for (let k = 0; k < count; k++) {
    const bx = x + rand(-spreadX, spreadX)
    const by = y + rand(-spreadY, spreadY)
    const a = rand(0, Math.PI)
    g.moveTo(bx - Math.cos(a) * 5, by - Math.sin(a) * 5).lineTo(bx + Math.cos(a) * 5, by + Math.sin(a) * 5)
  }
  g.stroke({ width: 2, color: '#e8e0c8', cap: 'round' })
}

// Goblin camp: hide tents round a campfire in a clearing, either just off
// the road or out in the wilds down a trodden path (a skull on a pole
// marks where it leaves the road). The goblins mill about until you come
// into view, then swarm.
export function goblinCamp(ctx) {
  const { layer, stand, road, i, difficulty, extra, enemies } = ctx
  const spot = setBack(ctx, ROAD_WIDTH / 2 + 125, 190)
  if (!spot) return null
  const { side } = spot
  const { at } = roadFrame(road, i)
  const [cx, cy] = [spot.x, spot.y]
  const edge = at(0, side * (ROAD_WIDTH / 2))

  const view = new Container()
  const g = new Graphics()
  view.addChild(g)
  drawClearing(g, cx, cy, ...(spot.deep ? [] : edge))
  const path = spot.deep ? footpath(g, edge, [cx, cy], '#8f8a52') : []

  const solids = [{ x: cx, y: cy, radius: 16 }]
  const tents = randInt(2, 3)
  const start = rand(0, Math.PI * 2)
  for (let k = 0; k < tents; k++) {
    const a = start + (k / tents) * Math.PI * 2 + rand(-0.3, 0.3)
    const tx = cx + Math.cos(a) * 92
    const ty = cy + Math.sin(a) * 80
    stand(hideTent(a + Math.PI), tx, ty, { fade: { r: 24, height: 48 } })
    solids.push({ x: tx, y: ty, radius: 22 })
  }
  scatterBones(g, cx, cy, 70, 60, 5)
  stand(skullTotem(), ...at(-20, side * (ROAD_WIDTH / 2 + 22)))
  const flicker = campfire(g, view, stand, cx, cy)
  // Stolen goods stacked beside a tent
  const loot = []
  const la = start + Math.PI / tents
  const [lx, ly] = [cx + Math.cos(la) * 100, cy + Math.sin(la) * 86]
  addProp(stand, 'crate', lx, ly, 16)
  maybeAddChest(loot, stand, lx - 6, ly + 22, spot.deep ? DEEP_CHEST_CHANCE : undefined)
  if (Math.random() < 0.6) addProp(stand, 'barrel', lx + 20, ly + 8, 8)
  solids.push({ x: lx, y: ly, radius: 10 })
  layer.addChild(view)

  const wander = { x: cx, y: cy, min: 32, max: 70 }
  const members = []
  for (let k = 0; k < Math.min(7 + extra, 3 + Math.floor(difficulty * 1.5)); k++) {
    const a = rand(0, Math.PI * 2)
    const r = rand(32, 65)
    members.push(enemies.add('goblin', cx + Math.cos(a) * r, cy + Math.sin(a) * r, { x: cx, y: cy, wander }))
  }

  return {
    view,
    members,
    solids,
    loot,
    zone: { x: cx, y: cy, radius: 190 },
    zones: [{ x: cx, y: cy, radius: 190 }, ...path],
    trigger: { x: cx, y: cy, radius: spot.deep ? 330 : 430 },
    animate: flicker,
  }
}

// Goblin burrows: dirt mounds right beside the road. Goblins pop out of the
// holes one after another as the cart rolls past.
export function goblinBurrows({ layer, stand, road, i, difficulty, extra, enemies }) {
  const { at, n } = roadFrame(road, i)
  const view = new Container()
  const g = new Graphics()
  view.addChild(g)

  const sides = Math.random() < 0.4 ? [1, -1] : [Math.random() < 0.5 ? -1 : 1]
  const holes = randInt(3, 4)
  const members = []
  for (let k = 0; k < holes; k++) {
    const side = sides[k % sides.length]
    const [x, y] = at((k / holes) * 140 + rand(-10, 10), side * (ROAD_WIDTH / 2 + rand(30, 70)))
    g.ellipse(x + 3, y + 3, 19, 16).fill({ color: '#000', alpha: 0.15 })
    g.ellipse(x, y, 18, 15).fill('#7a5c3a')
    g.ellipse(x - 3, y - 3, 10, 8).fill('#8c6b45')
    g.ellipse(x, y, 8, 7).fill('#1a1008')
    for (let s = 0; s < 6; s++) g.circle(x + rand(-28, 28), y + rand(-24, 24), rand(1.5, 3.5))
    g.fill('#7a5c3a')
    const facing = Math.atan2(-n.y * side, -n.x * side)
    const count = (k < Math.min(4, 1 + difficulty) ? 2 : 1) + Math.min(2, Math.floor(extra / 2))
    for (let c = 0; c < count; c++) {
      members.push(enemies.add('goblin', x, y, { x, y, facing, hidden: true }))
    }
  }
  scatterBones(g, ...at(70, 0), 40, ROAD_WIDTH / 2 + 60, 3)
  const loot = []
  maybeAddChest(loot, stand, ...at(70, sides[0] * (ROAD_WIDTH / 2 + 105))) // their hoard
  layer.addChild(view)

  const [mx, my] = at(70, 0)
  let started = false
  let nextPop = 0
  return {
    view,
    members,
    solids: [],
    loot,
    zone: { x: mx, y: my, radius: ROAD_WIDTH / 2 + 120 },
    trigger: { x: mx, y: my, radius: 280 },
    engage() {
      started = true
      members.filter((m) => !m.hidden).forEach((m) => m.engage())
    },
    animate(time) {
      if (!started || time < nextPop) return
      const next = members.find((m) => m.hidden && m.alive)
      if (next) next.engage()
      nextPop = time + 0.3
    },
  }
}

// Goblin looters: a merchant's wagon overturned at the roadside, goods strewn
// everywhere. The goblins are busy picking it over and slow to notice you.
export function goblinLooters({ layer, stand, road, i, difficulty, extra, enemies }) {
  const { at, d } = roadFrame(road, i)
  const side = Math.random() < 0.5 ? -1 : 1
  const lateral = side * (ROAD_WIDTH / 2 - 4)
  const [wx, wy] = at(0, lateral)
  const angle = Math.atan2(d.y, d.x) + rand(-0.35, 0.35)
  const c = Math.cos(angle)
  const s = Math.sin(angle)
  const pt = (fx, fy) => [wx + fx * c - fy * s, wy + fx * s + fy * c]

  const view = new Container()
  const g = new Graphics()
  view.addChild(g)
  // Upturned wagon: we see its dark underside, axles and one wheel left on.
  stand(overturnedWagon(angle), wx, wy, { fade: { r: 34, height: 26 } })
  // A loose wheel, the broken shaft and the spilled load
  const [lx, ly] = at(-50, lateral + side * 40)
  g.circle(lx, ly, 13).stroke({ width: 3, color: '#3a2a1a' })
  for (let k = 0; k < 4; k++) {
    const a = (k / 4) * Math.PI
    g.moveTo(lx - Math.cos(a) * 12, ly - Math.sin(a) * 12).lineTo(lx + Math.cos(a) * 12, ly + Math.sin(a) * 12)
  }
  g.stroke({ width: 2, color: '#3a2a1a' })
  g.moveTo(...pt(32, 6)).lineTo(...pt(62, 14)).stroke({ width: 4, color: '#6e4a28', cap: 'round' })
  for (let k = 0; k < 10; k++) g.circle(...at(rand(-60, 60), lateral + rand(-50, 30) * side), 3)
  g.fill('#c0392b')
  for (let k = 0; k < 6; k++) g.ellipse(...at(rand(-50, 50), lateral + rand(-40, 30) * side), 5, 4)
  g.fill('#c9b28a')
  const loot = []
  addProp(stand, 'crate', ...at(28, lateral + side * 30), 16)
  addProp(stand, 'crate', ...at(-36, lateral - side * 14), 14)
  addProp(stand, 'barrel', ...at(40, lateral - side * 6), 8)
  maybeAddChest(loot, stand, ...at(-10, lateral - side * 40)) // the merchant's strongbox
  layer.addChild(view)

  const solids = [-22, 0, 22].map((fx) => {
    const [x, y] = pt(fx, 0)
    return { x, y, radius: 19 }
  })

  const wander = { x: wx, y: wy, min: 34, max: 58 }
  const members = []
  for (let k = 0; k < Math.min(6 + extra, 3 + Math.floor(difficulty)); k++) {
    const a = rand(0, Math.PI * 2)
    members.push(enemies.add('goblin', wx + Math.cos(a) * 45, wy + Math.sin(a) * 40, { x: wx, y: wy, wander }))
  }

  return {
    view,
    members,
    solids,
    loot,
    zone: { x: wx, y: wy, radius: 140 },
    trigger: { x: wx, y: wy, radius: 230 },
    animate() {},
  }
}
