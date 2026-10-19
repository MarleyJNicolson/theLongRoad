import { Container, Graphics } from 'pixi.js'
import { ROAD_WIDTH } from '../road.js'
import { bush } from '../scenery.js'
import { stageAt } from '../threat.js'
import { addProp, maybeAddChest } from '../loot.js'
import { rand, randInt, roadFrame, setBack, footpath, drawClearing, campfire, DEEP_CHEST_CHANCE } from './helpers.js'
import { leanTo, watchtower, log } from '../structures.js'
import { project, turn } from '../iso.js'

// Bandit camp: canvas lean-tos round a fire, stolen loot piled up, and a
// watchtower by the road whose lookout raises the alarm from far off.
// Out in the wilds, the camp is found by its smoke or the path to it, and
// the lookout watches the path instead of the road.
export function banditCamp(ctx) {
  const { layer, stand, road, i, difficulty, extra, enemies } = ctx
  const offset = ROAD_WIDTH / 2 + 150
  const spot = setBack(ctx, offset, 200)
  if (!spot) return null
  const { side } = spot
  const { at, d, n } = roadFrame(road, i)
  const [cx, cy] = [spot.x, spot.y]
  // Positions around the camp: `along` the road's direction, `out` away from it
  const atCamp = (along, out) => [cx + d.x * along + n.x * side * out, cy + d.y * along + n.y * side * out]
  const edge = at(0, side * (ROAD_WIDTH / 2))

  const view = new Container()
  const g = new Graphics()
  view.addChild(g)
  drawClearing(g, cx, cy, ...(spot.deep ? [] : edge), '#8a7f55')
  const path = spot.deep ? footpath(g, edge, [cx, cy]) : []

  const solids = [{ x: cx, y: cy, radius: 16 }]
  const start = rand(0, Math.PI * 2)
  const tents = randInt(2, 3)
  for (let k = 0; k < tents; k++) {
    const a = start + (k / tents) * Math.PI * 2
    const tx = cx + Math.cos(a) * 95
    const ty = cy + Math.sin(a) * 82
    stand(leanTo(a + Math.PI), tx, ty, { fade: { r: 28, height: 36 } })
    solids.push({ x: tx, y: ty, radius: 22 })
  }
  // Log benches round the fire
  for (let k = 0; k < 3; k++) {
    const a = start + Math.PI / tents + (k / 3) * Math.PI * 2
    const bx = cx + Math.cos(a) * 42
    const by = cy + Math.sin(a) * 42
    const t = a + Math.PI / 2
    stand(log(28, 4.5, t), bx, by)
  }
  // Stolen goods
  const [chx, chy] = atCamp(rand(-60, -30), 60)
  const loot = []
  maybeAddChest(loot, stand, chx, chy, spot.deep ? DEEP_CHEST_CHANCE : undefined)
  addProp(stand, 'crate', chx + 22, chy + 6, 15)
  addProp(stand, 'barrel', chx - 20, chy + 10, 8)
  solids.push({ x: chx, y: chy, radius: 12 })
  const flicker = campfire(g, view, stand, cx, cy)

  const [twx, twy] = atCamp(40, spot.deep ? -125 : -(offset - ROAD_WIDTH / 2 - 55))
  const toCamp = Math.atan2(cy - twy, cx - twx)
  stand(watchtower(toCamp).g, twx, twy, { fade: { r: 20, height: 56 } })
  solids.push({ x: twx, y: twy, radius: 20 })
  layer.addChild(view)

  // The lookout keeps watch at the foot of the ladder
  const [ax, ay] = [twx + Math.cos(toCamp) * 26, twy + Math.sin(toCamp) * 26]
  const members = [enemies.add('archer', ax, ay, { x: ax, y: ay, facing: toCamp + Math.PI })]
  const sitting = Math.min(5 + extra, 2 + Math.floor(difficulty))
  for (let k = 0; k < sitting; k++) {
    const a = rand(0, Math.PI * 2)
    const x = cx + Math.cos(a) * 32
    const y = cy + Math.sin(a) * 32
    members.push(enemies.add('bandit', x, y, { x, y, facing: a + Math.PI }))
  }
  if (difficulty >= 1 || Math.random() < 0.35) {
    const [x, y] = atCamp(-20, 20)
    members.push(enemies.add('captain', x, y, { x, y, facing: Math.atan2(cy - y, cx - x) }))
  }

  return {
    view,
    members,
    solids,
    loot,
    zone: { x: cx, y: cy, radius: 200 },
    zones: [{ x: cx, y: cy, radius: 200 }, ...path],
    trigger: { x: twx, y: twy, radius: spot.deep ? 360 : 470 },
    animate: flicker,
  }
}

// Bandit roadblock: a spiked log barricade right across the road. Getting
// round it means leaving the road for the mud while the bandits pile in.
export function banditRoadblock({ layer, stand, road, i, difficulty, extra, enemies }) {
  const { at, d, n } = roadFrame(road, i)
  const half = ROAD_WIDTH / 2 + 36

  const view = new Container()
  const g = new Graphics()
  view.addChild(g)
  g.moveTo(...at(4, -half)).lineTo(...at(4, half)).stroke({ width: 22, color: '#000', alpha: 0.2, cap: 'round' })
  // Two logs across the road, overlapping in the middle
  const across = Math.atan2(n.y, n.x)
  stand(log(half + 14, 8, across), ...at(0, (-half + 14) / 2))
  stand(log(half + 14, 8, across), ...at(-3, (half - 14) / 2))
  // Sharpened stakes jutting out at oncoming traffic, each stood at its foot
  const T = turn(Math.atan2(d.y, d.x))
  for (let l = -half + 6; l <= half - 6; l += 13) {
    const stake = new Graphics()
    const [tx, ty] = project([...T([-20, rand(-3, 3), 0]).slice(0, 2), 13])
    stake.moveTo(0, -3).lineTo(tx, ty).stroke({ width: 3.5, color: '#7a5a34', cap: 'round' })
    stake.circle(tx, ty, 1.6).fill('#c9b28a')
    stand(stake, ...at(-6, l))
  }
  const side = Math.random() < 0.5 ? -1 : 1
  const [bx, by] = at(36, side * (half + 10))
  const [rx, ry] = at(58, side * (half + 18))
  const loot = []
  addProp(stand, 'crate', bx, by)
  addProp(stand, 'barrel', rx, ry)
  maybeAddChest(loot, stand, ...at(46, side * (half + 30))) // the tolls they've taken
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
export function banditAmbush({ layer, stand, road, i, difficulty, extra, enemies }) {
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
    stand(b, x, y)
    b.baseRotation = 0
    // A hood peeking over the top on the road side, and a blade that
    // catches the light
    const toRoad = { x: -n.x * side, y: -n.y * side }
    const peek = new Graphics().circle(0, 0, 6.5).fill('#2d2a26').circle(toRoad.x * 2.5, 1, 2.5).fill('#8c2f22')
    stand(peek, x + toRoad.x * r * 0.45, y - r * 1.1, { depth: y + 0.4 })
    const glint = new Graphics()
      .moveTo(-5, 0).lineTo(5, 0).moveTo(0, -5).lineTo(0, 5)
      .stroke({ width: 2, color: '#ffffff', cap: 'round' })
      .circle(0, 0, 2).fill('#ffffff')
    stand(glint, x + toRoad.x * r * 0.9, y - r * 0.6, { depth: y + 0.5 })
    glint.alpha = 0
    spots.push({ bush: b, peek, glint, nextGlint: rand(0.5, 2.5) })

    const facing = Math.atan2(toRoad.y, toRoad.x)
    members.push(enemies.add('bandit', x, y, { x, y, facing, hidden: true }))
  }
  // Their stash, stowed further back from the road
  const loot = []
  maybeAddChest(loot, stand, ...at(55, sides[0] * (ROAD_WIDTH / 2 + 95)))
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
