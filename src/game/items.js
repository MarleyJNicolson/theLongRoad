// Equipment the peasant can find in treasure chests.

export const SLOTS = ['helmet', 'shoulders', 'body', 'legs', 'ranged', 'melee']

export const SLOT_NAMES = {
  helmet: 'Helmet',
  shoulders: 'Shoulders',
  body: 'Upper body',
  legs: 'Legs',
  ranged: 'Ranged weapon',
  melee: 'Melee weapon',
}

// Each kind of ranged weapon draws on its own supply, which slowly refills:
// stones dug out of the cart bed, arrows and bolts from the quiver.
export const AMMO = {
  stones: { name: 'Stones', max: 8, refill: 1.4 },
  arrows: { name: 'Arrows', max: 10, refill: 1.6 },
  bolts: { name: 'Bolts', max: 6, refill: 2.4 },
}

export const BLOCK_PER_ARMOUR = 0.05 // chance to block a blow, per point
export const MAX_BLOCK = 0.6

// What you fight with when the slot is empty.
export const BARE = {
  ranged: { name: 'Thrown stones', icon: 'stone', tier: 0, damage: 1, range: 460, cooldown: 0.3, speed: 560, shot: 'stone', ammo: 'stones' },
  melee: { name: 'Fists', icon: 'fist', tier: 0, damage: 1, reach: 20, cooldown: 0.5 },
}

const armour = (slot, icon, list) => list.map(([name, tier]) => ({ slot, icon, name, tier, armour: tier }))

export const ITEMS = [
  ...armour('helmet', 'helmet', [['Leather Cap', 1], ['Iron Pot Helm', 2], ['Steel Bascinet', 3]]),
  ...armour('shoulders', 'shoulders', [['Padded Mantle', 1], ['Leather Pauldrons', 2], ['Steel Spaulders', 3]]),
  ...armour('body', 'body', [['Padded Gambeson', 1], ['Mail Shirt', 2], ['Steel Breastplate', 3]]),
  ...armour('legs', 'legs', [['Leather Breeches', 1], ['Mail Chausses', 2], ['Steel Greaves', 3]]),

  { slot: 'ranged', icon: 'sling', name: 'Shepherd’s Sling', tier: 1, damage: 1, range: 600, cooldown: 0.22, speed: 660, shot: 'stone', ammo: 'stones' },
  { slot: 'ranged', icon: 'bow', name: 'Hunting Bow', tier: 2, damage: 2, range: 650, cooldown: 0.36, speed: 820, shot: 'arrow', ammo: 'arrows' },
  { slot: 'ranged', icon: 'crossbow', name: 'Crossbow', tier: 3, damage: 3, range: 720, cooldown: 0.8, speed: 980, shot: 'bolt', ammo: 'bolts' },

  { slot: 'melee', icon: 'club', name: 'Cudgel', tier: 1, damage: 1, reach: 30, cooldown: 0.4 },
  { slot: 'melee', icon: 'sword', name: 'Short Sword', tier: 2, damage: 2, reach: 32, cooldown: 0.42 },
  { slot: 'melee', icon: 'spear', name: 'Boar Spear', tier: 2, damage: 2, reach: 48, cooldown: 0.55 },
  { slot: 'melee', icon: 'axe', name: 'Bearded Axe', tier: 3, damage: 3, reach: 32, cooldown: 0.7 },
]

// Gold a merchant would give for an item you don't need.
export const sellValue = (item) => item.tier * 3

// Better gear turns up further along the road.
export function rollItem(metres) {
  const luck = Math.random() + metres / 2500
  const tier = luck > 1.15 ? 3 : luck > 0.75 ? 2 : 1
  const weapon = Math.random() < 0.4
  const pool = ITEMS.filter((it) => it.tier === tier && (weapon ? it.armour === undefined : it.armour !== undefined))
  return { ...pool[Math.floor(Math.random() * pool.length)] }
}

export function totalArmour(equipment) {
  return SLOTS.reduce((sum, slot) => sum + (equipment[slot]?.armour ?? 0), 0)
}

export function blockChance(equipment) {
  return Math.min(MAX_BLOCK, totalArmour(equipment) * BLOCK_PER_ARMOUR)
}

// Things that stack in the bag and get used up.
export const CONSUMABLES = {
  poultice: { name: 'Healing Poultice', icon: 'poultice', tier: 1, desc: 'Click to restore 1 heart', stack: 5, value: 1 },
  planks: { name: 'Planks & Nails', icon: 'planks', tier: 1, desc: 'Click to mend 2 cart damage', stack: 5, value: 1 },
}

export const BAG_SIZE = 6
