import { SEGMENT } from '../road.js'
import { rand } from './helpers.js'
import { goblinCamp, goblinBurrows, goblinLooters } from './goblins.js'
import { banditCamp, banditRoadblock, banditAmbush } from './bandits.js'
import { banditHouseRaid, goblinHouseRaid } from './raids.js'

const FIRST_AT = 45 // road point index of the first encounter

// Some encounters need room beside the road and can fail to fit; each
// faction's fallback always fits.
const TABLE = [
  { kind: 'goblinCamp', make: goblinCamp, faction: 'goblin', weight: 20 },
  { kind: 'goblinBurrows', make: goblinBurrows, faction: 'goblin', weight: 16 },
  { kind: 'goblinLooters', make: goblinLooters, faction: 'goblin', weight: 16 },
  { kind: 'goblinHouseRaid', make: goblinHouseRaid, faction: 'goblin', weight: 13 },
  { kind: 'banditCamp', make: banditCamp, faction: 'bandit', weight: 14 },
  { kind: 'banditAmbush', make: banditAmbush, faction: 'bandit', weight: 20 },
  { kind: 'banditRoadblock', make: banditRoadblock, faction: 'bandit', weight: 14 },
  { kind: 'banditHouseRaid', make: banditHouseRaid, faction: 'bandit', weight: 13 },
]
const FALLBACK = {
  goblin: TABLE.find((t) => t.kind === 'goblinLooters'),
  bandit: TABLE.find((t) => t.kind === 'banditAmbush'),
}

function pick(exclude) {
  const options = TABLE.filter((t) => t !== exclude)
  let roll = Math.random() * options.reduce((sum, t) => sum + t.weight, 0)
  for (const t of options) {
    if ((roll -= t.weight) < 0) return t
  }
  return options[0]
}

// Places goblin and bandit encounters along the road ahead, keeps trees out
// of their way, and alerts each group when the cart arrives.
export class Encounters {
  constructor(layer, road, enemies) {
    this.layer = layer
    this.road = road
    this.enemies = enemies
    this.list = []
    this.nextIndex = FIRST_AT
    this.last = null
    this.time = 0
    this.rewards = [] // { gold, x, y } earned by clearing out raids
  }

  get zones() {
    return this.list.map((e) => e.zone)
  }

  get obstacles() {
    return this.list.flatMap((e) => e.solids)
  }

  // Unopened treasure chests.
  get loot() {
    return this.list.flatMap((e) => (e.loot ?? []).filter((l) => !l.opened))
  }

  // Place new encounters as soon as their stretch of road exists. Call this
  // before the scenery fills that stretch in, so trees are kept clear.
  place() {
    while (this.nextIndex < this.road.points.length - 5) {
      const i = this.nextIndex
      const ctx = {
        layer: this.layer,
        road: this.road,
        i,
        difficulty: (i * SEGMENT) / 20 / 500, // +1 per 500 m
        enemies: this.enemies,
      }
      // Never the same kind twice in a row.
      let entry = pick(this.last)
      let enc = entry.make(ctx)
      if (!enc) {
        entry = FALLBACK[entry.faction]
        enc = entry.make(ctx)
      }
      enc.index = i
      enc.kind = entry.kind
      this.list.push(enc)
      this.last = entry
      this.nextIndex += Math.floor(Math.max(32, 60 - i / 30) * rand(0.85, 1.2))
    }
  }

  // `player` is wherever the peasant is: on the cart or on foot.
  update(dt, player, roadIndex) {
    this.time += dt
    for (const enc of this.list) {
      enc.animate(this.time, dt)
      for (const chest of enc.loot ?? []) chest.animate(this.time)
      const near = Math.hypot(player.x - enc.trigger.x, player.y - enc.trigger.y) < enc.trigger.radius
      if (near || enc.members.some((m) => m.provoked)) {
        enc.engage ? enc.engage() : enc.members.forEach((m) => m.engage())
        enc.members.forEach((m) => (m.provoked = false))
      }
      if (enc.reward && !enc.cleared && enc.members.every((m) => !m.alive)) {
        enc.cleared = true
        enc.onCleared?.()
        this.rewards.push(enc.reward)
      }
    }

    this.list = this.list.filter((enc) => {
      if (enc.index >= roadIndex - 70) return true
      enc.view.destroy({ children: true })
      enc.members.forEach((m) => (m.removed = true))
      return false
    })
  }
}
