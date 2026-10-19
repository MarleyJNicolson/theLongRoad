import { Container, Graphics } from 'pixi.js'
import { ROAD_WIDTH } from '../road.js'
import { bush } from '../scenery.js'
import { stageAt } from '../threat.js'
import { addProp, maybeAddChest } from '../loot.js'
import { rand, randInt, roadFrame, sideThatFits, drawClearing, campfire, drawLog } from './helpers.js'

export function drawLeanTo(g, x, y, facing) {
  const c = Math.cos(facing)
  const s = Math.sin(facing)
  const pt = (fx, fy) => [x + fx * c - fy * s, y + fx * s + fy * c]
  g.poly([...pt(-14, -24), ...pt(18, -24), ...pt(18, 24), ...pt(-14, 24)].map((v) => v + 5)).fill({ color: '#000', alpha: 0.2 })
  g.poly([...pt(-14, -24), ...pt(18, -24), ...pt(18, 24), ...pt(-14, 24)]).fill('#c8b994')
  g.poly([...pt(-14, -24), ...pt(2, -24), ...pt(2, 24), ...pt(-14, 24)]).fill('#b3a37c')
  g.moveTo(...pt(-14, -24)).lineTo(...pt(-14, 24)).stroke({ width: 3, color: '#5e3f22' })
  g.moveTo(...pt(2, -24)).lineTo(...pt(2, 24)).stroke({ width: 1.5, color: '#8f8160' })
  g.circle(...pt(-6, 8), 5).fill('#7d4a3a')
}

export function drawWatchtower(g, x, y) {
  g.rect(x - 13, y - 9, 34, 34).fill({ color: '#000', alpha: 0.25 })
  g.rect(x - 17, y - 17, 34, 34).fill('#6e4a28')
  for (let k = -12; k <= 12; k += 8) g.moveTo(x - 17, y + k).lineTo(x + 17, y + k)
  g.stroke({ width: 1, color: '#4a3220' })
  g.rect(x - 17, y - 17, 34, 34).stroke({ width: 3, color: '#4a3220' })
  for (const [px, py] of [[-17, -17], [17, -17], [-17, 17], [17, 17]]) g.circle(x + px, y + py, 3.5).fill('#3a2a1a')
}

// Bandit camp: canvas lean-tos round a fire, stolen loot piled up, and a
// watchtower by the road whose lookout raises the alarm from far off.
export function banditCamp({ layer, road, i, difficulty, extra, enemies }) {
  const offset = ROAD_WIDTH / 2 + 150
  const side = sideThatFits(road, i, offset)
  if (!side) return null
  const { at } = roadFrame(road, i)
  const [cx, cy] = at(0, side * offset)

  const view = new Container()
  const g = new Graphics()
  view.addChild(g)
  drawClearing(g, cx, cy, ...at(0, side * (ROAD_WIDTH / 2)), '#8a7f55')

  const solids = [{ x: cx, y: cy, radius: 16 }]
  const start = rand(0, Math.PI * 2)
  const tents = randInt(2, 3)
  for (let k = 0; k < tents; k++) {
    const a = start + (k / tents) * Math.PI * 2
    const tx = cx + Math.cos(a) * 95
    const ty = cy + Math.sin(a) * 82
    drawLeanTo(g, tx, ty, a)
    solids.push({ x: tx, y: ty, radius: 22 })
  }
  // Log benches round the fire
  for (let k = 0; k < 3; k++) {
    const a = start + Math.PI / tents + (k / 3) * Math.PI * 2
    const bx = cx + Math.cos(a) * 42
    const by = cy + Math.sin(a) * 42
    const t = a + Math.PI / 2
    drawLog(g, bx - Math.cos(t) * 14, by - Math.sin(t) * 14, bx + Math.cos(t) * 14, by + Math.sin(t) * 14, 9)
  }
  // Stolen goods
  const [chx, chy] = at(rand(-60, -30), side * (offset + 60))
  const loot = []
  maybeAddChest(loot, view, chx, chy)
  addProp(view, 'crate', chx + 22, chy + 6, 15)
  addProp(view, 'barrel', chx - 20, chy + 10, 8)
  solids.push({ x: chx, y: chy, radius: 12 })
  const flicker = campfire(g, view, cx, cy)

  const [twx, twy] = at(40, side * (ROAD_WIDTH / 2 + 55))
  drawWatchtower(g, twx, twy)
  solids.push({ x: twx, y: twy, radius: 20 })
  layer.addChild(view)

  const members = [enemies.add('archer', twx, twy, { x: twx, y: twy, facing: Math.atan2(cy - twy, cx - twx) + Math.PI })]
  const sitting = Math.min(5 + extra, 2 + Math.floor(difficulty))
  for (let k = 0; k < sitting; k++) {
    const a = rand(0, Math.PI * 2)
    const x = cx + Math.cos(a) * 32
    const y = cy + Math.sin(a) * 32
    members.push(enemies.add('bandit', x, y, { x, y, facing: a + Math.PI }))
  }
  if (difficulty >= 1 || Math.random() < 0.35) {
    const [x, y] = at(-20, side * (offset + 20))
    members.push(enemies.add('captain', x, y, { x, y, facing: Math.atan2(cy - y, cx - x) }))
  }

  return {
    view,
    members,
    solids,
    loot,
    zone: { x: cx, y: cy, radius: 200 },
    trigger: { x: twx, y: twy, radius: 470 },
    animate: flicker,
  }
}

// Bandit roadblock: a spiked log barricade right across the road. Getting
// round it means leaving the road for the mud while the bandits pile in.
export function banditRoadblock({ layer, road, i, difficulty, extra, enemies }) {
  const { at, d } = roadFrame(road, i)
  const half = ROAD_WIDTH / 2 + 36

  const view = new Container()
  const g = new Graphics()
  view.addChild(g)
  g.moveTo(...at(4, -half)).lineTo(...at(4, half)).stroke({ width: 22, color: '#000', alpha: 0.2, cap: 'round' })
  // Sharpened stakes pointing at oncoming traffic
  for (let l = -half + 6; l <= half - 6; l += 13) {
    g.moveTo(...at(-2, l)).lineTo(...at(-22, l + rand(-3, 3)))
  }
  g.stroke({ width: 4, color: '#7a5a34', cap: 'round' })
  for (let l = -half + 6; l <= half - 6; l += 13) g.circle(...at(-22, l), 1.6)
  g.fill('#c9b28a')
  drawLog(g, ...at(0, -half), ...at(0, 14))
  drawLog(g, ...at(0, -14), ...at(0, half))
  const side = Math.random() < 0.5 ? -1 : 1
  const [bx, by] = at(36, side * (half + 10))
  const [rx, ry] = at(58, side * (half + 18))
  const loot = []
  addProp(view, 'crate', bx, by)
  addProp(view, 'barrel', rx, ry)
  maybeAddChest(loot, view, ...at(46, side * (half + 30))) // the tolls they've taken
  layer.addChild(view)

  const solids = []
  for (let l = -half; l <= half; l += 12) {
    const [x, y] = at(0, l)
    solids.push({ x, y, radius: 10 })
  }
  solids.push({ x: bx, y: by, radius: 11 }, { x: rx, y: ry, radius: 9 })

  // Bandits wait behind the logs and on the verges, watching the road.
  const facing = Math.atan2(-d.y, -d.x)
  const posts = [
    [rand(24, 40), rand(-30, 30)],
    [rand(-50, -30), -(half + rand(20, 40))],
    [rand(-50, -30), half + rand(20, 40)],
    [rand(30, 60), rand(-40, 40)],
    [rand(50, 80), -(half + rand(10, 30))],
  ]
  const count = Math.min(5 + extra, 2 + Math.floor(difficulty))
  // Any more than that wait further back up the road
  while (posts.length < count) posts.push([rand(60, 120), rand(-half - 30, half + 30)])
  const members = posts.slice(0, count).map(([along, lateral]) => {
    const [x, y] = at(along, lateral)
    return enemies.add('bandit', x, y, { x, y, facing })
  })

  const [mx, my] = at(0, 0)
  return {
    view,
    members,
    solids,
    loot,
    zone: { x: mx, y: my, radius: half + 130 },
    trigger: { x: mx, y: my, radius: 430 },
    animate() {},
  }
}

// Bandit ambush: bandits crouched in thick roadside bushes. Watch for the
// tells: hoods peeking out, a glint of steel, trampled grass and rustling.
// A stone into a bush will flush them out early.
export function banditAmbush({ layer, road, i, difficulty, extra, enemies }) {
  const { at, n } = roadFrame(road, i)
  const view = new Container()
  const ground = new Graphics()
  view.addChild(ground)
  const spots = []
  const members = []
  const count = Math.min(5 + extra, 2 + Math.floor(difficulty))
  const sides = Math.random() < 0.5 ? [1, -1] : [Math.random() < 0.5 ? -1 : 1]
  for (let k = 0; k < count; k++) {
    const side = sides[k % sides.length]
    const along = (k / count) * Math.max(110, count * 24) + rand(-10, 10)
    const r = rand(22, 27)
    const [x, y] = at(along, side * (ROAD_WIDTH / 2 + rand(36, 60)))
    // Trampled, darker grass and boot prints leading out of the bush
    ground.ellipse(x, y, r + 14, r + 10).fill({ color: '#4a6b30', alpha: 0.35 })
    for (let s = 0; s < 4; s++) {
      const [fx, fy] = at(along + (s % 2 ? 5 : -5), side * (ROAD_WIDTH / 2 + 6 + s * 9))
      ground.ellipse(fx, fy, 3, 2).fill({ color: '#3a2a1a', alpha: 0.45 })
    }

    const b = bush(r, stageAt(road.points[i].along / 20).biome) // blends in with the local scrub
    b.position.set(x, y)
    b.rotation = b.baseRotation = rand(0, Math.PI * 2)
    // A hood poking out on the road side, and a blade that catches the light
    const toRoad = { x: -n.x * side, y: -n.y * side }
    const peek = new Graphics().circle(0, 0, 6.5).fill('#2d2a26').circle(2, 0, 2.5).fill('#8c2f22')
    peek.position.set(x + toRoad.x * (r - 6), y + toRoad.y * (r - 6))
    const glint = new Graphics()
      .moveTo(-5, 0).lineTo(5, 0).moveTo(0, -5).lineTo(0, 5)
      .stroke({ width: 2, color: '#ffffff', cap: 'round' })
      .circle(0, 0, 2).fill('#ffffff')
    glint.position.set(peek.x + toRoad.y * 10, peek.y - toRoad.x * 10)
    glint.alpha = 0
    view.addChild(b, peek, glint)
    spots.push({ bush: b, peek, glint, nextGlint: rand(0.5, 2.5) })

    const facing = Math.atan2(toRoad.y, toRoad.x)
    members.push(enemies.add('bandit', x, y, { x, y, facing, hidden: true }))
  }
  // Their stash, stowed further back from the road
  const loot = []
  maybeAddChest(loot, view, ...at(55, sides[0] * (ROAD_WIDTH / 2 + 95)))
  layer.addChild(view)

  const [mx, my] = at(55, 0)
  let rustle = rand(0.5, 1.5)
  let shaking = null
  return {
    view,
    members,
    solids: [],
    loot,
    zone: { x: mx, y: my, radius: ROAD_WIDTH / 2 + 110 },
    trigger: { x: mx, y: my, radius: 210 },
    animate(time, dt) {
      rustle -= dt
      if (rustle <= 0) {
        shaking = { spot: spots[Math.floor(Math.random() * spots.length)], until: time + 0.6 }
        rustle = rand(1, 2.5)
      }
      spots.forEach((spot, k) => {
        const lurking = members[k].hidden
        spot.peek.visible = lurking
        spot.bush.rotation = spot.bush.baseRotation
        if (shaking?.spot === spot && time < shaking.until && lurking) {
          spot.bush.rotation += Math.sin(time * 40) * 0.14
        }
        spot.nextGlint -= dt
        if (spot.nextGlint <= 0 && lurking) {
          spot.glintStart = time
          spot.nextGlint = rand(1.5, 3.5)
        }
        const g = time - (spot.glintStart ?? -9)
        spot.glint.alpha = lurking && g < 0.35 ? Math.sin((g / 0.35) * Math.PI) : 0
        spot.glint.rotation = g * 3
      })
    },
  }
}
