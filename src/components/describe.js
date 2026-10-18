// Colours and names for each quality of gear (0 = bare hands / empty).
export const TIER_COLOURS = [
  { fill: '#7d725c', edge: 'rgba(243, 227, 192, 0.25)', name: '' },
  { fill: '#a87a48', edge: '#a87a48', name: 'Common' },
  { fill: '#a6b0bb', edge: '#7fa0c8', name: 'Sturdy' },
  { fill: '#e3e9ef', edge: '#d4a32a', name: 'Fine' },
]

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
  return [`Damage ${item.damage}`, `Reach ${reach}`, `${(1 / item.cooldown).toFixed(1)} swings / s`]
}
