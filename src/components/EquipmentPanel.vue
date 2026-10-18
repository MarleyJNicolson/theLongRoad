<script setup>
import { computed, ref } from 'vue'
import ItemIcon from './ItemIcon.vue'
import { describe, TIER_COLOURS } from './describe.js'

const props = defineProps({
  equipment: { type: Array, required: true }, // [{ slot, label, item }]
  bare: { type: Object, required: true }, // what's used when a weapon slot is empty
  armour: { type: Number, default: 0 },
  block: { type: Number, default: 0 },
  bagOpen: { type: Boolean, default: false },
  active: { type: String, default: 'ranged' }, // weapon in hand
})
const emit = defineEmits(['unequip', 'toggle-bag'])

const slots = computed(() =>
  Object.fromEntries(
    props.equipment.map((s) => {
      const shown = s.item ?? props.bare[s.slot] ?? null
      return [s.slot, { ...s, shown, empty: !s.item, tier: TIER_COLOURS[shown?.tier ?? 0] }]
    }),
  ),
)

const hovered = ref(null)
const tip = computed(() => {
  const s = hovered.value && slots.value[hovered.value]
  if (!s) return null
  if (!s.shown) return { title: s.label, lines: ['Empty – find armour in treasure chests'] }
  const sub = [s.empty ? '' : s.tier.name, s.label].filter(Boolean).join(' · ')
  const lines = describe(s.shown)
  if (!s.empty) lines.push('Click to take off')
  return { title: s.shown.name, sub, lines, color: s.tier.edge }
})

const ROWS = [
  [null, 'helmet', null],
  ['shoulders', 'body', null],
  [null, 'legs', null],
  ['ranged', null, 'melee'],
]
</script>

<template>
  <div class="equipment">
    <div class="title">
      <span>Equipment</span>
      <span class="totals">Armour {{ armour }} · Block {{ block }}%</span>
    </div>
    <div class="doll">
      <template v-for="(row, r) in ROWS" :key="r">
        <template v-for="(slot, c) in row" :key="r + '-' + c">
          <button
            v-if="slot"
            type="button"
            class="slot"
            :class="{
              empty: slots[slot].empty,
              weapon: slot === 'ranged' || slot === 'melee',
              'in-hand': slot === active,
              stowed: (slot === 'ranged' || slot === 'melee') && slot !== active,
            }"
            :style="{ borderColor: slots[slot].tier.edge }"
            @pointerenter="hovered = slot"
            @pointerleave="hovered = null"
            @click="emit('unequip', slot)"
          >
            <ItemIcon :item="slots[slot].shown" :silhouette="slot" />
            <span class="slot-label">{{ slots[slot].label.split(' ')[0] }}</span>
            <span v-if="slot === active" class="hand-badge">In hand</span>
          </button>
          <button
            v-else-if="r === 0 && c === 2"
            type="button"
            class="bag-button"
            :class="{ open: bagOpen }"
            title="Bag (B)"
            @click="emit('toggle-bag')"
          >
            <svg viewBox="0 0 40 40" aria-hidden="true">
              <path d="M14 13 Q14 5 20 5 Q26 5 26 13" fill="none" stroke="#5e3f22" stroke-width="3" stroke-linecap="round" />
              <path d="M7 15 Q7 12 10 12 H30 Q33 12 33 15 L31 33 Q31 36 28 36 H12 Q9 36 9 33 Z" fill="#8b6236" stroke="rgba(0,0,0,0.45)" stroke-width="1.2" />
              <path d="M7 16 Q20 24 33 16" fill="none" stroke="#5e3f22" stroke-width="2" />
              <rect x="17.5" y="18" width="5" height="5" rx="1" fill="#d4a32a" />
            </svg>
            <span class="slot-label">Bag (B)</span>
          </button>
          <div v-else-if="r === 3 && c === 1" class="swap-hint">⇄<br />Q</div>
          <div v-else class="gap"></div>
        </template>
      </template>
    </div>

    <div v-if="tip" class="tip" :style="{ borderColor: tip.color }">
      <strong>{{ tip.title }}</strong>
      <em v-if="tip.sub">{{ tip.sub }}</em>
      <span v-for="line in tip.lines" :key="line">{{ line }}</span>
    </div>
  </div>
</template>

<style scoped>
.equipment {
  position: fixed;
  left: 16px;
  bottom: 16px;
  background: rgba(40, 26, 12, 0.8);
  border-radius: 8px;
  padding: 10px 12px 12px;
  font-family: Georgia, serif;
  color: #f3e3c0;
  user-select: none;
}

.title {
  font-size: 11px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  opacity: 0.85;
  margin-bottom: 8px;
  display: flex;
  justify-content: space-between;
  gap: 12px;
}

.totals {
  letter-spacing: 0.02em;
  text-transform: none;
  opacity: 0.8;
}

.doll {
  display: grid;
  grid-template-columns: repeat(3, 52px);
  gap: 6px;
}

.slot,
.bag-button {
  position: relative;
  width: 52px;
  height: 52px;
  border: 2px solid;
  border-radius: 6px;
  background: rgba(0, 0, 0, 0.35);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  color: inherit;
  font: inherit;
  cursor: pointer;
}

.slot.empty {
  cursor: default;
}

.slot:hover,
.bag-button:hover {
  background: rgba(255, 244, 214, 0.08);
}

.slot.weapon {
  background: rgba(60, 40, 20, 0.55);
}

.slot.in-hand {
  box-shadow: 0 0 0 2px #fff4d6, 0 0 10px rgba(255, 244, 214, 0.5);
}

.slot.stowed :deep(svg) {
  opacity: 0.45;
}

.hand-badge {
  position: absolute;
  top: -9px;
  left: 50%;
  transform: translateX(-50%);
  background: #fff4d6;
  color: #3a2a1a;
  font-size: 8px;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  padding: 1px 4px;
  border-radius: 3px;
  white-space: nowrap;
}

.swap-hint {
  display: flex;
  align-items: center;
  justify-content: center;
  text-align: center;
  font-size: 11px;
  line-height: 1.3;
  opacity: 0.6;
}

.bag-button {
  border-color: rgba(243, 227, 192, 0.35);
  border-style: dashed;
}

.bag-button.open {
  border-style: solid;
  border-color: #d4a32a;
  background: rgba(212, 163, 42, 0.15);
}

.slot :deep(svg),
.bag-button svg {
  width: 34px;
  height: 34px;
  margin-bottom: 8px;
}

.slot.empty :deep(svg) {
  opacity: 0.35;
}

.slot-label {
  position: absolute;
  bottom: 2px;
  left: 0;
  right: 0;
  text-align: center;
  font-size: 9px;
  letter-spacing: 0.04em;
  opacity: 0.7;
}

.tip {
  position: absolute;
  left: calc(100% + 8px);
  bottom: 0;
  width: 190px;
  background: rgba(30, 20, 10, 0.95);
  border: 1px solid;
  border-radius: 6px;
  padding: 8px 10px;
  display: flex;
  flex-direction: column;
  gap: 2px;
  font-size: 13px;
  pointer-events: none;
  z-index: 2;
}

.tip strong {
  font-size: 15px;
}

.tip em {
  font-size: 11px;
  opacity: 0.7;
  margin-bottom: 4px;
}

@media (max-width: 640px) {
  .doll {
    grid-template-columns: repeat(3, 40px);
  }
  .slot,
  .bag-button {
    width: 40px;
    height: 40px;
  }
  .slot :deep(svg),
  .bag-button svg {
    width: 26px;
    height: 26px;
  }
}
</style>
