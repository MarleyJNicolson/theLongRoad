import { SEGMENT } from '../road.js'
import { rand } from './helpers.js'
import { stageAt, threatAt } from '../threat.js'
import { addArrowBarrel } from '../loot.js'
import { goblinCamp, goblinBurrows, goblinLooters } from './goblins.js'
import { banditCamp, banditRoadblock, banditAmbush } from './bandits.js'
import { banditHouseRaid, goblinHouseRaid } from './raids.js'
import { sideRoad, onSideRoad } from './sideroads.js'

const FIRST_AT = 45 // road point index of the first encounter
const SIDE_ROAD_CHANCE = 0.22 // of an encounter being a turning to somewhere bigger
const SIDE_ROADS_FROM = 300 // metres
const FIRST_SIDE_ROAD_BY = 450 // metres: there's always one early on
const MAX_SIDE_ROAD_GAP = 600 // metres: never longer than this without one

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

// Weighted pick, leaning toward whatever the region is known for.
function pick(exclude, biome) {
  const options = TABLE.filter((t) => t !== exclude)
  const weight = (t) => t.weight * (biome.weights[t.kind] ?? 1)
  let roll = Math.random() * options.reduce((sum, t) => sum + weight(t), 0)
  for (const t of options) {
    if ((roll -= weight(t)) < 0) return t
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
    this.rewards = [] // { gold, x, y, message? } earned by clearing out raids
    this.onNewZones = null // called with zones that appear where scenery already is
    this.lastSideRoad = FIRST_SIDE_ROAD_BY - MAX_SIDE_ROAD_GAP // metres
  }

  get zones() {
    return this.list.flatMap((e) => e.zones ?? [e.zone])
  }

  // Traders open for business (villages at the end of side roads).
  get traders() {
    return this.list.flatMap((e) => (e.traders ?? []).filter((t) => t.open))
  }

  // Is (x, y) on any side road?
  onSideRoad(x, y) {
    return this.list.some((e) => e.sideRoad && onSideRoad(e, x, y))
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
      // Raiders are as tough as the stretch of road they're found on.
      const metres = (i * SEGMENT) / 20
      const threat = threatAt(metres)
      const { biome } = stageAt(metres)
      this.enemies.threat = threat
      const ctx = {
        layer: this.layer,
        road: this.road,
        i,
        difficulty: metres / 500, // +1 per 500 m
        extra: threat.extraMembers,
        enemies: this.enemies,
      }
      // Now and then, a turning off to a village or a big camp. Its road
      // runs back alongside existing road, so clear any trees already there.
      let enc = null
      let entry = null
      const overdue = metres - this.lastSideRoad >= MAX_SIDE_ROAD_GAP
      if (metres > SIDE_ROADS_FROM && (overdue || Math.random() < SIDE_ROAD_CHANCE)) {
        enc = sideRoad({ ...ctx, zones: this.zones })
        if (enc) {
          this.onNewZones?.(enc.zones)
          this.lastSideRoad = metres
        }
      }
      if (!enc) {
        // Never the same kind twice in a row.
        entry = pick(this.last, biome)
        enc = entry.make(ctx)
        if (!enc) {
          entry = FALLBACK[entry.faction]
          enc = entry.make(ctx)
        }
      }
      enc.index = i
      enc.kind = entry?.kind ?? 'sideRoad'
      // Wherever archers are posted, their spare arrows are kept to hand.
      const archer = enc.members.find((m) => m.shoots)
      if (archer && enc.view) {
        const a = Math.random() * Math.PI * 2
        addArrowBarrel((enc.loot ??= []), enc.view, archer.home.x + Math.cos(a) * 30, archer.home.y + Math.sin(a) * 30)
      }
      this.list.push(enc)
      this.last = entry ?? this.last
      this.nextIndex += Math.floor(threat.spacing * rand(0.85, 1.2))
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
      enc.roadViews?.forEach((v) => v.destroy())
      enc.members.forEach((m) => (m.removed = true))
      return false
    })
  }
}
