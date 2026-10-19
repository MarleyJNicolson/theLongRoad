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

// Each kind of ranged weapon uses its own ammunition, carried as stacks in
// the bag or the cart (see CONSUMABLES). It doesn't come back on its own:
// gather stones from rocks, buy or loot arrows and bolts.
export const AMMO = {
  stones: { name: 'Stones' },
  arrows: { name: 'Arrows' },
  bolts: { name: 'Bolts' },
}

export const BLOCK_PER_ARMOUR = 0.05 // chance to block a blow, per point
export const MAX_BLOCK = 0.6

// What you fight with when the slot is empty.
export const BARE = {
  ranged: { name: 'Thrown stones', icon: 'stone', tier: 0, damage: 1, range: 460, cooldown: 0.3, speed: 560, shot: 'stone', ammo: 'stones' },
  melee: { name: 'Fists', icon: 'fist', tier: 0, damage: 1, reach: 20, cooldown: 0.5, style: 'swing', arc: 1.1 },
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

  // Melee `style`s (see Game.updateMelee): swing – one sweep; double – two
  // quick cuts, `damage` each; jab – a narrow thrust that can run through
  // `pierce` foes; heavy – a wound-up wide blow that knocks foes flying.
  // `arc` is how far either side of the aim line it reaches (radians).
  { slot: 'melee', icon: 'club', name: 'Cudgel', tier: 1, damage: 1, reach: 30, cooldown: 0.4, style: 'swing', arc: 1.1 },
  { slot: 'melee', icon: 'sword', name: 'Short Sword', tier: 2, damage: 1, reach: 32, cooldown: 0.45, style: 'double', arc: 1.0, gap: 0.13 },
  { slot: 'melee', icon: 'spear', name: 'Boar Spear', tier: 2, damage: 2, reach: 70, cooldown: 0.5, style: 'jab', arc: 0.22, pierce: 2 },
  { slot: 'melee', icon: 'axe', name: 'Bearded Axe', tier: 3, damage: 3, reach: 36, cooldown: 0.9, style: 'heavy', arc: 1.5, windup: 0.2, force: 2.2 },
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
  // Ammunition: `value` is per 10, and the whole stack sells at once.
  stones: { name: 'Stones', icon: 'stones', tier: 0, desc: 'For throwing by hand or with a sling', stack: 30, value: 1, ammo: true },
  arrows: { name: 'Arrows', icon: 'arrows', tier: 1, desc: 'For a bow', stack: 30, value: 3, ammo: true },
  bolts: { name: 'Bolts', icon: 'bolts', tier: 2, desc: 'For a crossbow', stack: 30, value: 4, ammo: true },
}

export const BAG_SIZE = 6
export const CART_SIZE = 12 // the cart holds more, but only while you're at it
