import { Container, Graphics } from 'pixi.js'
import { cottage, fence, lootCart, flames } from '../structures.js'
import { Folk, folkLook } from '../folk.js'
import { ROAD_WIDTH } from '../road.js'
import { addProp, maybeAddChest } from '../loot.js'
import { rand, randInt, roadFrame, setBack, footpath, DEEP_CHEST_CHANCE } from './helpers.js'

const REWARD = 5 // gold the grateful farmer gives for driving the raiders off

// A thatched farmhouse in its fenced yard, set back from the road. `pt` maps
// house-local coordinates (+x towards the road) to world coordinates; the
// vegetable rows and path go on the ground (`g`), the house and fence stand.
function drawFarmstead(g, stand, pt, facing, { brokenFence, charred }) {
  const rect = (x1, y1, x2, y2) => [...pt(x1, y1), ...pt(x2, y1), ...pt(x2, y2), ...pt(x1, y2)]
  // Vegetable rows behind the house
  for (let row = 0; row < 4; row++) {
    for (let k = -3; k <= 3; k++) g.ellipse(...pt(-50 - row * 9, k * 9), 3.5, 2.5)
  }
  g.fill('#4f8a38')
  // Fence round the plot, with a gap for the gate facing the road
  const sides = [
    [[-88, -62], [50, -62]],
    [[-88, 62], [50, 62]],
    [[-88, -62], [-88, 62]],
    [[50, -62], [50, -16]],
    [[50, 16], [50, 62]],
  ]
  for (const [a, b] of sides) fenceLine(stand, pt(...a), pt(...b), brokenFence)
  // Path from the door to the gate
  g.poly(rect(28, -7, 50, 7)).fill({ color: '#b9925e', alpha: 0.8 })
  return house(stand, pt(0, 0), facing, charred)
}

// A fence from (x1, y1) to (x2, y2), stood up in short runs so each sorts
// properly against whoever is beside it.
export function fenceLine(stand, [x1, y1], [x2, y2], broken = false) {
  const runs = Math.max(1, Math.round(Math.hypot(x2 - x1, y2 - y1) / 36))
  for (let k = 0; k < runs; k++) {
    const [ax, ay] = [x1 + ((x2 - x1) * k) / runs, y1 + ((y2 - y1) * k) / runs]
    const [bx, by] = [x1 + ((x2 - x1) * (k + 1)) / runs, y1 + ((y2 - y1) * (k + 1)) / runs]
    stand(fence(0, 0, bx - ax, by - ay, broken), ax, ay, { depth: (ay + by) / 2 })
  }
}

// A cottage at (x, y) with its door towards `facing`; returns how tall it is.
export function house(stand, [x, y], facing, charred = false) {
  const { g, roof } = cottage(facing, { charred })
  stand(g, x, y, { fade: { r: 40, height: roof + 6 } })
  return roof
}

// The farmer, who comes out to thank you once the raiders are gone.
export function makeFarmer(stand, x, y, facing) {
  const farmer = new Folk(folkLook('farmer'), x, y, facing)
  stand(farmer.view, x, y)
  farmer.visible = false
  return farmer
}

// A homestead beside the road, or out in the wilds at the end of a cart
// track (`deep`).
function setUpFarm(ctx) {
  const { road, i } = ctx
  const spot = setBack(ctx, ROAD_WIDTH / 2 + 130, 170)
  if (!spot) return null
  const { side, deep } = spot
  const { at, n } = roadFrame(road, i)
  const [hx, hy] = [spot.x, spot.y]
  const facing = Math.atan2(-n.y * side, -n.x * side)
  const c = Math.cos(facing)
  const s = Math.sin(facing)
  const pt = (fx, fy) => [hx + fx * c - fy * s, hy + fx * s + fy * c]
  const solids = [-24, 0, 24].map((fy) => {
    const [x, y] = pt(0, fy)
    return { x, y, radius: 31 }
  })
  const [yx, yy] = pt(70, 0) // the yard between house and road
  const edge = at(0, side * (ROAD_WIDTH / 2))
  // Where the raid is noticed: from the road if it's beside it, else close by
  const trigger = deep ? { x: yx, y: yy, radius: 320 } : { x: at(0, 0)[0], y: at(0, 0)[1], radius: 380 }
  return { at, pt, hx, hy, yx, yy, facing, solids, deep, edge, trigger }
}

// The cart track out to a farm in the wilds (zones to keep trees off it).
function farmTrack(g, farm) {
  return farm.deep ? footpath(g, farm.edge, farm.pt(58, 0), '#9a8254') : []
}

function farmerReward(farm, stand) {
  const [dx, dy] = farm.pt(40, 0)
  const farmer = makeFarmer(stand, dx, dy, farm.facing)
  return {
    farmer,
    reward: { gold: REWARD, x: dx, y: dy },
    onCleared() {
      farmer.visible = true
      farmer.waving(true)
    },
    wave(time, dt) {
      farmer.update(dt)
    },
  }
}

// Bandit house raid: the door kicked in, the family's goods hauled out to a
// waiting cart, and bandits picking over the yard.
export function banditHouseRaid(ctx) {
  const { layer, stand, difficulty, extra, enemies } = ctx
  const farm = setUpFarm(ctx)
  if (!farm) return null
  const { pt } = farm

  const view = new Container()
  const g = new Graphics()
  view.addChild(g)
  const track = farmTrack(g, farm)
  drawFarmstead(g, stand, pt, farm.facing, { brokenFence: false, charred: false })
  // Broken door planks on the step
  g.moveTo(...pt(34, -6)).lineTo(...pt(44, -12)).moveTo(...pt(36, 4)).lineTo(...pt(46, 10))
  g.stroke({ width: 4, color: '#6e4a28', cap: 'round' })
  // Loot heaped in the yard and a bandit cart to carry it off
  for (const [fx, fy] of [[62, -26], [70, -18], [58, -14]]) g.ellipse(...pt(fx, fy), 7, 6)
  g.fill('#c9b28a')
  const [kx, ky] = pt(99, -25)
  stand(lootCart(farm.facing + Math.PI / 2), kx, ky)
  const loot = []
  addProp(stand, 'crate', ...pt(66, 26), 15)
  addProp(stand, 'barrel', ...pt(80, 34), 7)
  maybeAddChest(loot, stand, ...pt(60, -40), farm.deep ? DEEP_CHEST_CHANCE : undefined) // the family strongbox, dragged out
  layer.addChild(view)

  const thanks = farmerReward(farm, stand)
  const wander = { x: farm.yx, y: farm.yy, min: 10, max: 42 }
  const members = []
  for (let k = 0; k < Math.min(6 + extra, 3 + Math.floor(difficulty)); k++) {
    const a = rand(0, Math.PI * 2)
    members.push(enemies.add('bandit', farm.yx + Math.cos(a) * 30, farm.yy + Math.sin(a) * 30, { x: farm.yx, y: farm.yy, wander }))
  }
  if (difficulty >= 1.5 && Math.random() < 0.5) {
    const [x, y] = pt(50, 0)
    members.push(enemies.add('captain', x, y, { x, y, facing: farm.facing }))
  }

  return {
    view,
    members,
    solids: [...farm.solids, { x: kx, y: ky, radius: 18 }],
    loot,
    zone: { x: farm.hx, y: farm.hy, radius: 170 },
    zones: [{ x: farm.hx, y: farm.hy, radius: 170 }, ...track],
    trigger: farm.trigger,
    reward: thanks.reward,
    onCleared: thanks.onCleared,
    animate: thanks.wave,
  }
}

// Goblin house raid: the thatch is ablaze, smoke pours off the roof and the
// goblins caper round the yard, whooping.
export function goblinHouseRaid(ctx) {
  const { layer, stand, difficulty, extra, enemies } = ctx
  const farm = setUpFarm(ctx)
  if (!farm) return null
  const { pt } = farm

  const view = new Container()
  const g = new Graphics()
  view.addChild(g)
  const track = farmTrack(g, farm)
  const roof = drawFarmstead(g, stand, pt, farm.facing, { brokenFence: true, charred: true })
  // Torches dropped in the yard
  for (const [fx, fy] of [[60, -30], [74, 22]]) {
    g.moveTo(...pt(fx, fy)).lineTo(...pt(fx + 10, fy + 4)).stroke({ width: 3, color: '#5e3f22', cap: 'round' })
    g.circle(...pt(fx + 10, fy + 4), 3).fill('#e8641e')
  }

  // Flames along the thatch, drawn in front of the house; smoke above all
  const fires = []
  for (let k = 0; k < randInt(3, 4); k++) {
    const flame = flames()
    const [x, y] = pt(rand(-14, 14), rand(-28, 28))
    stand(flame, x, y - roof + rand(2, 10), { depth: farm.hy + 30 })
    flame.scale.set(1.3)
    flame.seed = rand(0, 10)
    fires.push(flame)
  }
  const glow = new Graphics().circle(0, 0, 110).fill({ color: '#ff8a2c', alpha: 0.14 })
  glow.position.set(farm.hx, farm.hy)
  const smoke = stand(new Container(), 0, 0, { depth: farm.hy + 31 })
  const loot = []
  addProp(stand, 'barrel', ...pt(64, 34), 8)
  maybeAddChest(loot, stand, ...pt(-60, -50), farm.deep ? DEEP_CHEST_CHANCE : undefined) // buried in the vegetable patch
  view.addChild(glow)
  layer.addChild(view)

  const thanks = farmerReward(farm, stand)
  const wander = { x: farm.yx, y: farm.yy, min: 12, max: 50 }
  const members = []
  for (let k = 0; k < Math.min(8 + extra, 4 + Math.floor(difficulty * 1.5)); k++) {
    const a = rand(0, Math.PI * 2)
    members.push(enemies.add('goblin', farm.yx + Math.cos(a) * 35, farm.yy + Math.sin(a) * 35, { x: farm.yx, y: farm.yy, wander }))
  }

  const puffs = []
  let nextPuff = 0
  return {
    view,
    members,
    solids: farm.solids,
    loot,
    zone: { x: farm.hx, y: farm.hy, radius: 170 },
    zones: [{ x: farm.hx, y: farm.hy, radius: 170 }, ...track],
    trigger: farm.trigger,
    reward: thanks.reward,
    onCleared: thanks.onCleared,
    animate(time, dt) {
      thanks.wave(time, dt)
      for (const f of fires) {
        f.scale.set(1.3 + Math.sin(time * 7 + f.seed) * 0.1, 1.3 + Math.sin(time * 15 + f.seed) * 0.2 + Math.sin(time * 6 + f.seed) * 0.12)
        f.skew.x = Math.sin(time * 4 + f.seed) * 0.15
      }
      glow.alpha = 0.85 + Math.sin(time * 9) * 0.15

      // Smoke drifts off the roof, swelling and thinning as it goes.
      if (time > nextPuff) {
        const src = fires[Math.floor(Math.random() * fires.length)]
        const puff = new Graphics().circle(0, 0, 9).fill({ color: '#5a5550', alpha: 0.5 })
        puff.position.set(src.x, src.y - 14)
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
