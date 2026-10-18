import { Container, Graphics } from 'pixi.js'
import { ROAD_WIDTH } from '../road.js'
import { addProp, maybeAddChest } from '../loot.js'
import { rand, randInt, roadFrame, sideThatFits } from './helpers.js'

const REWARD = 5 // gold the grateful farmer gives for driving the raiders off

// A thatched farmhouse in its fenced yard, set back from the road. `pt` maps
// house-local coordinates (+x towards the road) to world coordinates.
function drawFarmstead(g, pt, { brokenFence, charred }) {
  const rect = (x1, y1, x2, y2) => [...pt(x1, y1), ...pt(x2, y1), ...pt(x2, y2), ...pt(x1, y2)]
  // Vegetable rows behind the house
  for (let row = 0; row < 4; row++) {
    for (let k = -3; k <= 3; k++) g.circle(...pt(-50 - row * 9, k * 9), 3)
  }
  g.fill('#4f8a38')
  // Fence round the plot, with a gap for the gate facing the road
  for (let fy = -62; fy <= 62; fy += 12) {
    for (const fx of [-88, 50]) {
      if (fx === 50 && Math.abs(fy) < 16) continue
      if (brokenFence && Math.random() < 0.3) continue
      g.circle(...pt(fx, fy), 2.5)
    }
  }
  for (let fx = -88; fx <= 50; fx += 12) {
    for (const fy of [-62, 62]) {
      if (brokenFence && Math.random() < 0.3) continue
      g.circle(...pt(fx, fy), 2.5)
    }
  }
  g.fill('#5e3f22')
  // Path from the door to the gate
  g.poly(rect(28, -7, 50, 7)).fill({ color: '#b9925e', alpha: 0.8 })
  // House: shadow, walls, then a two-sided thatched roof
  g.poly(rect(-24, -34, 34, 44)).fill({ color: '#000', alpha: 0.22 })
  g.poly(rect(-30, -40, 30, 40)).fill('#cbb98c')
  g.poly(rect(-28, -38, 0, 38)).fill('#c9a24a')
  g.poly(rect(0, -38, 28, 38)).fill('#b8913e')
  for (const fx of [-21, -14, -7, 7, 14, 21]) g.moveTo(...pt(fx, -36)).lineTo(...pt(fx, 36))
  g.stroke({ width: 1, color: '#9a7a32', alpha: 0.6 })
  g.moveTo(...pt(0, -40)).lineTo(...pt(0, 40)).stroke({ width: 3, color: '#8a6a2a' })
  g.poly(rect(-14, 18, -4, 28)).fill('#7d7a72')
  g.poly(rect(-12, 20, -6, 26)).fill('#2a1f14')
  if (charred) {
    for (let k = 0; k < 6; k++) g.circle(...pt(rand(-22, 22), rand(-32, 32)), rand(5, 11))
    g.fill({ color: '#2a1f14', alpha: 0.75 })
  }
}

// The farmer, who comes out to thank you once the raiders are gone.
function drawFarmer() {
  const farmer = new Container()
  const arm = new Graphics().roundRect(0, -2, 11, 4, 2).fill('#7a5a3a')
  arm.position.set(0, -6)
  const body = new Graphics()
  body.ellipse(2, 2, 9, 11).fill({ color: '#000', alpha: 0.2 })
  body.ellipse(0, 0, 7, 9).fill('#7a5a3a')
  body.circle(0, 0, 6).fill('#d4b25e')
  body.circle(0, 0, 3.5).fill('#c29d48')
  farmer.addChild(arm, body)
  farmer.arm = arm
  farmer.visible = false
  return farmer
}

function setUpFarm(road, i) {
  const offset = ROAD_WIDTH / 2 + 130
  const side = sideThatFits(road, i, offset)
  if (!side) return null
  const { at, n } = roadFrame(road, i)
  const [hx, hy] = at(0, side * offset)
  const facing = Math.atan2(-n.y * side, -n.x * side)
  const c = Math.cos(facing)
  const s = Math.sin(facing)
  const pt = (fx, fy) => [hx + fx * c - fy * s, hy + fx * s + fy * c]
  const solids = [-24, 0, 24].map((fy) => {
    const [x, y] = pt(0, fy)
    return { x, y, radius: 31 }
  })
  const [yx, yy] = pt(70, 0) // the yard between house and road
  return { at, pt, hx, hy, yx, yy, facing, solids }
}

function farmerReward(farm, view) {
  const farmer = drawFarmer()
  const [dx, dy] = farm.pt(40, 0)
  farmer.position.set(dx, dy)
  farmer.rotation = farm.facing
  view.addChild(farmer)
  return {
    farmer,
    reward: { gold: REWARD, x: dx, y: dy },
    onCleared() {
      farmer.visible = true
    },
    wave(time) {
      if (farmer.visible) farmer.arm.rotation = -0.6 + Math.sin(time * 9) * 0.6
    },
  }
}

// Bandit house raid: the door kicked in, the family's goods hauled out to a
// waiting cart, and bandits picking over the yard.
export function banditHouseRaid({ layer, road, i, difficulty, enemies }) {
  const farm = setUpFarm(road, i)
  if (!farm) return null
  const { pt } = farm

  const view = new Container()
  const g = new Graphics()
  view.addChild(g)
  drawFarmstead(g, pt, { brokenFence: false, charred: false })
  // Broken door planks on the step
  g.moveTo(...pt(34, -6)).lineTo(...pt(44, -12)).moveTo(...pt(36, 4)).lineTo(...pt(46, 10))
  g.stroke({ width: 4, color: '#6e4a28', cap: 'round' })
  // Loot heaped in the yard and a bandit cart to carry it off
  for (const [fx, fy] of [[62, -26], [70, -18], [58, -14]]) g.ellipse(...pt(fx, fy), 7, 6)
  g.fill('#c9b28a')
  const cart = [[86, -40], [112, -40], [112, -10], [86, -10]].flatMap(([fx, fy]) => pt(fx, fy))
  g.poly(cart.map((v) => v + 4)).fill({ color: '#000', alpha: 0.2 })
  g.poly(cart).fill('#5e3f22')
  for (const [fx, fy] of [[94, -30], [104, -22]]) g.ellipse(...pt(fx, fy), 6, 5)
  g.fill('#c9b28a')
  g.circle(...pt(99, -18), 3).fill('#e8b923')
  const loot = []
  addProp(view, 'crate', ...pt(66, 26), 15)
  addProp(view, 'barrel', ...pt(80, 34), 7)
  maybeAddChest(loot, view, ...pt(60, -40)) // the family strongbox, dragged out
  layer.addChild(view)

  const thanks = farmerReward(farm, view)
  const wander = { x: farm.yx, y: farm.yy, min: 10, max: 42 }
  const members = []
  for (let k = 0; k < Math.min(6, 3 + Math.floor(difficulty)); k++) {
    const a = rand(0, Math.PI * 2)
    members.push(enemies.add('bandit', farm.yx + Math.cos(a) * 30, farm.yy + Math.sin(a) * 30, { x: farm.yx, y: farm.yy, wander }))
  }
  if (difficulty >= 1.5 && Math.random() < 0.5) {
    const [x, y] = pt(50, 0)
    members.push(enemies.add('captain', x, y, { x, y, facing: farm.facing }))
  }

  const [cx, cy] = farm.at(0, 0)
  return {
    view,
    members,
    solids: [...farm.solids, { x: (cart[0] + cart[4]) / 2, y: (cart[1] + cart[5]) / 2, radius: 18 }],
    loot,
    zone: { x: farm.hx, y: farm.hy, radius: 170 },
    trigger: { x: cx, y: cy, radius: 380 },
    reward: thanks.reward,
    onCleared: thanks.onCleared,
    animate: thanks.wave,
  }
}

// Goblin house raid: the thatch is ablaze, smoke pours off the roof and the
// goblins caper round the yard, whooping.
export function goblinHouseRaid({ layer, road, i, difficulty, enemies }) {
  const farm = setUpFarm(road, i)
  if (!farm) return null
  const { pt } = farm

  const view = new Container()
  const g = new Graphics()
  view.addChild(g)
  drawFarmstead(g, pt, { brokenFence: true, charred: true })
  // Torches dropped in the yard
  for (const [fx, fy] of [[60, -30], [74, 22]]) {
    g.moveTo(...pt(fx, fy)).lineTo(...pt(fx + 10, fy + 4)).stroke({ width: 3, color: '#5e3f22', cap: 'round' })
    g.circle(...pt(fx + 10, fy + 4), 3).fill('#e8641e')
  }

  const fires = []
  for (let k = 0; k < randInt(3, 4); k++) {
    const flame = new Graphics()
    flame.circle(0, 0, 11).fill({ color: '#e8641e', alpha: 0.85 })
    flame.circle(1, -1, 7).fill('#ffb02e')
    flame.circle(1, -2, 3.5).fill('#fff1a8')
    flame.position.set(...pt(rand(-18, 18), rand(-30, 30)))
    flame.seed = rand(0, 10)
    fires.push(flame)
  }
  const glow = new Graphics().circle(0, 0, 110).fill({ color: '#ff8a2c', alpha: 0.14 })
  glow.position.set(farm.hx, farm.hy)
  const smoke = new Container()
  const loot = []
  addProp(view, 'barrel', ...pt(64, 34), 8)
  maybeAddChest(loot, view, ...pt(-60, -50)) // buried in the vegetable patch
  view.addChild(glow, ...fires, smoke)
  layer.addChild(view)

  const thanks = farmerReward(farm, view)
  const wander = { x: farm.yx, y: farm.yy, min: 12, max: 50 }
  const members = []
  for (let k = 0; k < Math.min(8, 4 + Math.floor(difficulty * 1.5)); k++) {
    const a = rand(0, Math.PI * 2)
    members.push(enemies.add('goblin', farm.yx + Math.cos(a) * 35, farm.yy + Math.sin(a) * 35, { x: farm.yx, y: farm.yy, wander }))
  }

  const puffs = []
  let nextPuff = 0
  const [cx, cy] = farm.at(0, 0)
  return {
    view,
    members,
    solids: farm.solids,
    loot,
    zone: { x: farm.hx, y: farm.hy, radius: 170 },
    trigger: { x: cx, y: cy, radius: 380 },
    reward: thanks.reward,
    onCleared: thanks.onCleared,
    animate(time, dt) {
      thanks.wave(time)
      for (const f of fires) {
        f.scale.set(1 + Math.sin(time * 15 + f.seed) * 0.15 + Math.sin(time * 6 + f.seed) * 0.1)
        f.rotation = time * 1.5 + f.seed
      }
      glow.alpha = 0.85 + Math.sin(time * 9) * 0.15

      // Smoke drifts off the roof, swelling and thinning as it goes.
      if (time > nextPuff) {
        const src = fires[Math.floor(Math.random() * fires.length)]
        const puff = new Graphics().circle(0, 0, 9).fill({ color: '#5a5550', alpha: 0.5 })
        puff.position.set(src.x, src.y)
        puff.life = 0
        smoke.addChild(puff)
        puffs.push(puff)
        nextPuff = time + 0.12
      }
      for (let k = puffs.length - 1; k >= 0; k--) {
        const p = puffs[k]
        p.life += dt
        p.x += dt * 22
        p.y -= dt * 30
        p.scale.set(1 + p.life * 1.4)
        p.alpha = Math.max(0, 1 - p.life / 2.6)
        if (p.life > 2.6) {
          p.destroy()
          puffs.splice(k, 1)
        }
      }
    },
  }
}
