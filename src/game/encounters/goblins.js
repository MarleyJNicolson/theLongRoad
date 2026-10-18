import { Container, Graphics } from 'pixi.js'
import { ROAD_WIDTH } from '../road.js'
import { addProp, maybeAddChest } from '../loot.js'
import { rand, randInt, roadFrame, sideThatFits, drawClearing, campfire } from './helpers.js'

export function drawHideTent(g, x, y, facing) {
  const c = Math.cos(facing)
  const s = Math.sin(facing)
  const pt = (fx, fy) => [x + fx * c - fy * s, y + fx * s + fy * c]
  g.ellipse(x + 6, y + 6, 28, 24).fill({ color: '#000', alpha: 0.2 })
  g.poly([...pt(26, 0), ...pt(0, -22), ...pt(-24, 0), ...pt(0, 22)]).fill('#8b7355')
  g.poly([...pt(26, 0), ...pt(0, -22), ...pt(0, 22)]).fill('#9c8462')
  g.moveTo(...pt(-24, 0)).lineTo(...pt(26, 0)).stroke({ width: 2, color: '#5e4a33' })
  g.poly([...pt(26, 0), ...pt(14, -7), ...pt(14, 7)]).fill('#2a1f14')
  for (const [fx, fy] of [[-18, -10], [8, -16], [-6, 14]]) g.circle(...pt(fx, fy), 3).fill('#6e5a40')
}

export function drawSkullTotem(g, x, y) {
  g.circle(x + 3, y + 3, 7).fill({ color: '#000', alpha: 0.2 })
  g.circle(x, y, 3).fill('#5a3a1a')
  g.circle(x, y - 2, 6).fill('#e8e0c8')
  g.circle(x - 2, y - 3, 1.6).fill('#1a1008')
  g.circle(x + 2, y - 3, 1.6).fill('#1a1008')
}

export function scatterBones(g, x, y, spreadX, spreadY, count) {
  for (let k = 0; k < count; k++) {
    const bx = x + rand(-spreadX, spreadX)
    const by = y + rand(-spreadY, spreadY)
    const a = rand(0, Math.PI)
    g.moveTo(bx - Math.cos(a) * 5, by - Math.sin(a) * 5).lineTo(bx + Math.cos(a) * 5, by + Math.sin(a) * 5)
  }
  g.stroke({ width: 2, color: '#e8e0c8', cap: 'round' })
}

// Goblin camp: hide tents round a campfire in a clearing just off the road.
// The goblins mill about until the cart comes into view, then swarm it.
export function goblinCamp({ layer, road, i, difficulty, extra, enemies }) {
  const offset = ROAD_WIDTH / 2 + 125
  const side = sideThatFits(road, i, offset)
  if (!side) return null
  const { at } = roadFrame(road, i)
  const [cx, cy] = at(0, side * offset)

  const view = new Container()
  const g = new Graphics()
  view.addChild(g)
  drawClearing(g, cx, cy, ...at(0, side * (ROAD_WIDTH / 2)))

  const solids = [{ x: cx, y: cy, radius: 16 }]
  const tents = randInt(2, 3)
  const start = rand(0, Math.PI * 2)
  for (let k = 0; k < tents; k++) {
    const a = start + (k / tents) * Math.PI * 2 + rand(-0.3, 0.3)
    const tx = cx + Math.cos(a) * 92
    const ty = cy + Math.sin(a) * 80
    drawHideTent(g, tx, ty, a + Math.PI)
    solids.push({ x: tx, y: ty, radius: 22 })
  }
  scatterBones(g, cx, cy, 70, 60, 5)
  drawSkullTotem(g, ...at(-20, side * (ROAD_WIDTH / 2 + 22)))
  const flicker = campfire(g, view, cx, cy)
  // Stolen goods stacked beside a tent
  const loot = []
  const la = start + Math.PI / tents
  const [lx, ly] = [cx + Math.cos(la) * 100, cy + Math.sin(la) * 86]
  addProp(view, 'crate', lx, ly, 16)
  maybeAddChest(loot, view, lx - 6, ly + 22)
  if (Math.random() < 0.6) addProp(view, 'barrel', lx + 20, ly + 8, 8)
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
    trigger: { x: cx, y: cy, radius: 430 },
    animate: flicker,
  }
}

// Goblin burrows: dirt mounds right beside the road. Goblins pop out of the
// holes one after another as the cart rolls past.
export function goblinBurrows({ layer, road, i, difficulty, extra, enemies }) {
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
  maybeAddChest(loot, view, ...at(70, sides[0] * (ROAD_WIDTH / 2 + 105))) // their hoard
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
export function goblinLooters({ layer, road, i, difficulty, extra, enemies }) {
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
  g.poly([...pt(-32, -20), ...pt(32, -20), ...pt(32, 20), ...pt(-32, 20)]).fill('#3a2a1a')
  g.poly([...pt(-30, -18), ...pt(30, -18), ...pt(30, 18), ...pt(-30, 18)]).fill('#5e3f22')
  for (const fx of [-18, 18]) g.moveTo(...pt(fx, -20)).lineTo(...pt(fx, 20))
  g.stroke({ width: 4, color: '#2a1f14' })
  g.moveTo(...pt(-30, 0)).lineTo(...pt(30, 0)).stroke({ width: 2, color: '#4a3220' })
  g.poly([...pt(-24, -26), ...pt(-12, -26), ...pt(-12, -21), ...pt(-24, -21)]).fill('#2a1f14')
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
  addProp(view, 'crate', ...at(28, lateral + side * 30), 16)
  addProp(view, 'crate', ...at(-36, lateral - side * 14), 14)
  addProp(view, 'barrel', ...at(40, lateral - side * 6), 8)
  maybeAddChest(loot, view, ...at(-10, lateral - side * 40)) // the merchant's strongbox
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
