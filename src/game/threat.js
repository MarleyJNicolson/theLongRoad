// How dangerous the road is at a given distance, and which region it runs
// through. Everything here keeps rising for as long as the road goes on.

export const STAGE_LENGTH = 2500 // metres per region

// Regions repeat in this order; each time round they come back harder.
// `weights` scale how often each encounter kind turns up there.
export const BIOMES = [
  {
    name: 'The Meadows',
    tagline: 'Farmland and open road',
    ground: 0x5f9a45,
    road: { edge: '#6f5130', fill: '#b9925e', rut: '#9c7646', crown: '#c4a06c' },
    trees: ['#2f6b2a', '#386f2e', '#2b5e30'],
    leaf: '#4c8a3a',
    bush: ['#467a32', '#4f8a38', '#3f7030'],
    grass: '#4e8a36',
    scenery: { tree: 0.3, bush: 0.2, rock: 0.12 },
    weights: {},
  },
  {
    name: 'The Darkwood',
    tagline: 'Goblin country',
    ground: 0x3f6e34,
    road: { edge: '#4a3620', fill: '#8a6c45', rut: '#6e5435', crown: '#977852' },
    trees: ['#1f4a22', '#24502a', '#1b3f1f'],
    leaf: '#2f6530',
    bush: ['#2f5a28', '#356530', '#294f24'],
    grass: '#356a2c',
    scenery: { tree: 0.55, bush: 0.2, rock: 0.08 },
    weights: { goblinCamp: 1.8, goblinBurrows: 1.8, goblinLooters: 1.5, goblinHouseRaid: 1.2, banditCamp: 0.5, banditRoadblock: 0.5, banditAmbush: 0.6, banditHouseRaid: 0.4 },
  },
  {
    name: 'The Barrens',
    tagline: 'Bandit country',
    ground: 0xa89a5a,
    road: { edge: '#7a5c38', fill: '#d0b07a', rut: '#b59460', crown: '#dcc08e' },
    trees: ['#6b7a3a', '#5e6e34', '#75803e'],
    leaf: '#8a9448',
    bush: ['#8a8a48', '#7d7d40', '#96904e'],
    grass: '#8c8442',
    scenery: { tree: 0.08, bush: 0.18, rock: 0.3 },
    weights: { banditCamp: 1.8, banditRoadblock: 1.6, banditAmbush: 1.5, banditHouseRaid: 1.3, goblinCamp: 0.5, goblinBurrows: 0.5, goblinLooters: 0.6, goblinHouseRaid: 0.4 },
  },
  {
    name: 'The Frostmarch',
    tagline: 'Cold hills where everything is hungry',
    ground: 0xc9d3cf,
    road: { edge: '#6f6a62', fill: '#a49c8e', rut: '#8a8478', crown: '#b8b2a6' },
    trees: ['#2e4a3e', '#35543f', '#2a4438'],
    leaf: '#e8eef0',
    bush: ['#7d8c84', '#8a998f', '#71807a'],
    grass: '#9aa8a0',
    scenery: { tree: 0.35, bush: 0.12, rock: 0.25 },
    weights: { goblinCamp: 1.3, banditCamp: 1.3, banditRoadblock: 1.2, goblinBurrows: 1.1 },
  },
]

const NUMERALS = ['', ' II', ' III', ' IV', ' V', ' VI', ' VII', ' VIII', ' IX', ' X']

export function stageAt(metres) {
  const index = Math.floor(Math.max(0, metres) / STAGE_LENGTH)
  const biome = BIOMES[index % BIOMES.length]
  const lap = Math.floor(index / BIOMES.length)
  return {
    index,
    number: index + 1,
    biome,
    name: biome.name + (NUMERALS[lap] ?? ` ${lap + 1}`),
  }
}

// Scaling applied to raiders and encounters at a given distance.
export function threatAt(metres) {
  const km = Math.max(0, metres) / 1000
  return {
    level: km,
    // Extra hit points for every 2.5 km travelled
    hpBonus: Math.floor(km / 2.5),
    // A little quicker each km, but never faster than a galloping horse
    // (fastest goblin: 165 × 1.1 × 1.25 ≈ 227 px/s vs a 245 px/s gallop)
    speedMult: 1 + Math.min(0.25, km * 0.03),
    // Blows land harder deeper in
    damage: 1 + Math.floor(km / 6),
    // Bigger, tougher raiders worth more gold
    eliteChance: Math.min(0.45, Math.max(0, km - 1) * 0.05),
    // Room for bigger groups than the base caps allow
    extraMembers: Math.floor(km / 3),
    // Road points between encounters: closer together, but never on top of each other
    spacing: Math.max(22, 60 - km * 5),
  }
}
