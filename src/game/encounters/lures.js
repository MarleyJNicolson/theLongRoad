import { Container, Graphics } from 'pixi.js'
import { ROAD_WIDTH } from '../road.js'
import { bush } from '../scenery.js'
import { stageAt } from '../threat.js'
import { addProp, maybeAddChest } from '../loot.js'
import { log } from '../structures.js'
import { rand, randInt, setBack } from './helpers.js'
import { scatterBones } from './goblins.js'

// Ambushes out in the wilds, away from the road: a treasure chest left
// glinting in a little clearing, there for the taking. It's bait. Bandits
// lie in the thicket round it (or goblins in their burrows) and spring out
// once you're close enough to reach for it. Worth it if you're ready: the
// chest is always there, and well stocked.

const SPRING = 95 // how close to the chest before they jump you

function lure(ctx, faction) {
  const { layer, stand, road, i, difficulty, extra, enemies } = ctx
  const spot = setBack(ctx, ROAD_WIDTH / 2 + 160, 140, { deepOnly: true, far: 260 })
  if (!spot) return null
  const { x: cx, y: cy } = spot
  const biome = stageAt(road.points[i].along / 20).biome

  const view = new Container()
  const g = new Graphics()
  view.addChild(g)
  // A small clearing, and whatever its last visitor left behind
  for (let k = 0; k < 5; k++) {
    const a = (k / 5) * Math.PI * 2
    g.circle(cx + Math.cos(a) * 22, cy + Math.sin(a) * 16, rand(34, 44))
  }
  g.fill({ color: faction === 'goblin' ? '#6f6a3a' : '#8a7f55', alpha: 0.4 })
  const loot = []
  maybeAddChest(loot, stand, cx, cy, 1)
  if (faction === 'goblin') {
    scatterBones(g, cx, cy, 45, 35, 6)
    addProp(stand, 'barrel', cx + 26, cy - 10, 8)
  } else {
    // A dead fire, a bedroll and a pack: someone camped here and never left
    g.ellipse(cx - 30, cy + 14, 9, 6).fill('#2a1f14')
    g.ellipse(cx + 24, cy + 18, 9, 4).fill('#6e4a3a')
    stand(log(26, 4.5, rand(0, Math.PI)), cx - 34, cy - 18)
    addProp(stand, 'crate', cx + 28, cy - 12, 14)
  }

  // Hiding places in a ring round the clearing
  const count = Math.min(6 + extra, 3 + Math.floor(difficulty))
  const hides = []
  const members = []
  const start = rand(0, Math.PI * 2)
  for (let k = 0; k < count; k++) {
    const a = start + (k / count) * Math.PI * 2 + rand(-0.2, 0.2)
    const d = rand(70, 95)
    const x = cx + Math.cos(a) * d
    const y = cy + Math.sin(a) * d * 0.85
    const facing = a + Math.PI
    if (faction === 'goblin') {
      // A burrow mound with a dark mouth
      g.ellipse(x, y, 17, 13).fill('#7a5c3a')
      g.ellipse(x - 3, y - 3, 9, 7).fill('#8c6b45')
      g.ellipse(x, y, 7, 6).fill('#1a1008')
      members.push(enemies.add(Math.random() < 0.2 ? 'goblinArcher' : 'goblin', x, y, { x, y, facing, hidden: true }))
    } else {
      const b = bush(rand(20, 25), biome)
      stand(b, x, y)
      hides.push(b)
      members.push(enemies.add(k === 0 && difficulty >= 1 ? 'captain' : 'bandit', x, y, { x, y, facing, hidden: true }))
    }
  }
  // Fill out the thicket so the hiding bushes don't stand out
  if (faction !== 'goblin') {
    for (let k = 0; k < randInt(4, 6); k++) {
      const a = rand(0, Math.PI * 2)
      const d = rand(100, 130)
      stand(bush(rand(14, 22), biome), cx + Math.cos(a) * d, cy + Math.sin(a) * d * 0.85)
    }
  }
  layer.addChild(view)

  let rustle = rand(1, 3)
  let shaking = null
  return {
    view,
    members,
    solids: [],
    loot,
    zone: { x: cx, y: cy, radius: 150 },
    zones: [{ x: cx, y: cy, radius: 150 }],
    trigger: { x: cx, y: cy, radius: SPRING },
    animate(time, dt) {
      // Now and then a hiding bush gives itself away with a rustle
      rustle -= dt
      if (rustle <= 0 && hides.length) {
        shaking = { bush: hides[Math.floor(Math.random() * hides.length)], until: time + 0.5 }
        rustle = rand(2.5, 5)
      }
      hides.forEach((b, k) => {
        b.rotation = shaking?.bush === b && time < shaking.until && members[k].hidden ? Math.sin(time * 40) * 0.12 : 0
      })
    },
  }
}

export const banditLure = (ctx) => lure(ctx, 'bandit')
export const goblinLure = (ctx) => lure(ctx, 'goblin')
