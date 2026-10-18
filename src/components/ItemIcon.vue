<script setup>
import { computed } from 'vue'
import { TIER_COLOURS } from './describe.js'

const props = defineProps({
  item: { type: Object, default: null }, // anything with { icon, tier }
  silhouette: { type: String, default: '' }, // shape to show when empty
})

// Simple silhouettes in a 40×40 box. `trim` parts turn gold on fine gear;
// `color` fixes a part's colour regardless of tier.
const ICONS = {
  helmet: [{ d: 'M8 26 Q8 7 20 7 Q32 7 32 26 Z' }, { d: 'M5 25 H35 V30 H5 Z' }, { d: 'M18.5 26 H21.5 V35 H18.5 Z', trim: true }],
  shoulders: [{ d: 'M3 27 Q4 12 17 11 L17 29 Z' }, { d: 'M37 27 Q36 12 23 11 L23 29 Z' }, { d: 'M8 17 L13 15 M27 15 L32 17', line: true, trim: true }],
  body: [{ d: 'M10 7 L30 7 L34 16 L29 18 L29 34 L11 34 L11 18 L6 16 Z' }, { d: 'M20 9 V32 M13 22 H27', line: true, trim: true }],
  legs: [{ d: 'M11 5 H29 V13 L26.5 35 H21.5 L20 17 L18.5 35 H13.5 L11 13 Z' }, { d: 'M11 10 H29', line: true, trim: true }],
  stone: [{ d: 'M13 22 Q12 13 20 12 Q29 12 28 21 Q28 29 20 29 Q13 29 13 22 Z' }],
  fist: [{ d: 'M11 14 Q11 10 15 10 H27 Q30 10 30 14 V24 Q30 31 23 31 H17 Q11 31 11 25 Z' }, { d: 'M17 10 V18 M23 10 V18', line: true }],
  sling: [{ d: 'M8 5 Q20 30 32 5', line: true, wide: true }, { d: 'M15 27 Q20 35 25 27 Q20 31 15 27 Z' }],
  bow: [{ d: 'M13 4 Q37 20 13 36', line: true, wide: true }, { d: 'M13 4 L13 36', line: true, trim: true }, { d: 'M8 20 H32 M28 17 L32 20 L28 23', line: true }],
  crossbow: [{ d: 'M20 9 V36', line: true, wide: true }, { d: 'M5 15 Q20 5 35 15', line: true, wide: true }, { d: 'M5 15 L20 19 L35 15', line: true, trim: true }],
  club: [{ d: 'M9 33 L12 36 L31 14 Q33 6 26 6 Z' }, { d: 'M24 12 L27 15 M27 9 L30 12', line: true, trim: true }],
  sword: [{ d: 'M28 5 L33 7 L31 12 L16 27 L12 23 Z' }, { d: 'M8 20 L19 31', line: true, wide: true, trim: true }, { d: 'M13 27 L7 33', line: true, wide: true }],
  spear: [{ d: 'M6 35 L28 10', line: true, wide: true }, { d: 'M25 9 L36 3 L31 15 Z', trim: true }],
  axe: [{ d: 'M10 35 L26 7', line: true, wide: true }, { d: 'M21 5 Q36 4 33 20 L25 14 Z', trim: true }],
  poultice: [
    { d: 'M9 20 Q9 11 20 11 Q31 11 31 20 Q31 33 20 33 Q9 33 9 20 Z', color: '#c9b98c' },
    { d: 'M15 11 Q20 4 25 11', line: true, color: '#7a5a34' },
    { d: 'M20 16 V28 M14 22 H26', line: true, wide: true, color: '#c0392b' },
  ],
  planks: [
    { d: 'M5 12 L33 6 L35 13 L7 19 Z', color: '#b98a52' },
    { d: 'M5 24 L33 18 L35 25 L7 31 Z', color: '#8b6236' },
    { d: 'M11 13 V14 M28 9 V10 M11 25 V26 M28 21 V22', line: true, wide: true, color: '#d0d0d0' },
  ],
}

const parts = computed(() => {
  const icon = ICONS[props.item?.icon ?? props.silhouette] ?? []
  const tier = props.item?.tier ?? 0
  const base = TIER_COLOURS[tier].fill
  return icon.map((p) => {
    const colour = p.color ?? (p.trim && tier === 3 ? '#d4a32a' : base)
    return {
      d: p.d,
      fill: p.line ? 'none' : colour,
      stroke: p.line ? colour : 'rgba(0,0,0,0.45)',
      width: p.line ? (p.wide ? 3.5 : 2) : 1.2,
    }
  })
})
</script>

<template>
  <svg viewBox="0 0 40 40" aria-hidden="true">
    <path
      v-for="(p, k) in parts"
      :key="k"
      :d="p.d"
      :fill="p.fill"
      :stroke="p.stroke"
      :stroke-width="p.width"
      stroke-linecap="round"
      stroke-linejoin="round"
    />
  </svg>
</template>
