// Colours and names for each quality of gear (0 = bare hands / empty).
export const TIER_COLOURS = [
  { fill: '#7d725c', edge: 'rgba(243, 227, 192, 0.25)', name: '' },
  { fill: '#a87a48', edge: '#a87a48', name: 'Common' },
  { fill: '#a6b0bb', edge: '#7fa0c8', name: 'Sturdy' },
  { fill: '#e3e9ef', edge: '#d4a32a', name: 'Fine' },
]

// How each melee weapon fights.
const STYLES = {
  swing: 'A single sweeping blow',
  double: 'A fast double slash',
  jab: 'A long jab – can skewer two',
  heavy: 'One heavy, wide blow – knocks foes flying',
}

// Stat lines for an item's tooltip.
export function describe(item) {
  if (item.desc) return [item.desc]
  if (item.armour !== undefined) return [`+${item.armour} armour`]
  if (item.range) {
    return [
      `Damage ${item.damage}`,
      `Range ${Math.round(item.range / 20)} m`,
      `${(1 / item.cooldown).toFixed(1)} shots / s`,
      `Uses ${item.ammo}`,
    ]
  }
  const reach = item.reach >= 45 ? 'long' : item.reach >= 30 ? 'medium' : 'short'
  const style = STYLES[item.style] ?? STYLES.swing
  const damage = item.style === 'double' ? `Damage ${item.damage} × 2` : `Damage ${item.damage}`
  return [style, damage, `Reach ${reach}`, `${(1 / item.cooldown).toFixed(1)} attacks / s`]
}
