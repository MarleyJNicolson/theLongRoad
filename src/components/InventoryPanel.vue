<script setup>
import { computed, ref } from 'vue'
import ItemIcon from './ItemIcon.vue'
import { describe, TIER_COLOURS } from './describe.js'

const props = defineProps({
  bag: { type: Array, required: true }, // [{ type, item, count?, value } | null]
  gold: { type: Number, default: 0 },
  equipment: { type: Array, required: true },
})
const emit = defineEmits(['use', 'sell', 'close'])

const hovered = ref(null)
const tip = computed(() => {
  const entry = hovered.value !== null && props.bag[hovered.value]
  if (!entry) return null
  const { item } = entry
  const isGear = entry.type === 'gear'
  const tier = TIER_COLOURS[item.tier]
  const lines = describe(item)
  if (isGear) {
    const worn = props.equipment.find((s) => s.slot === item.slot)
    lines.push(worn?.item ? `Wearing: ${worn.item.name}` : `${worn?.label ?? ''} slot is empty`)
    lines.push('Click to equip')
  }
  lines.push(`Right-click to sell (${entry.value} gold)`)
  return { title: item.name, sub: isGear ? tier.name : 'Supplies', lines, color: tier.edge }
})
</script>

<template>
  <div class="inventory" @contextmenu.prevent>
    <div class="title">
      <span>Bag</span>
      <span class="purse"><i class="coin"></i>{{ gold }} gold</span>
      <button type="button" class="close" title="Close (B)" @click="emit('close')">×</button>
    </div>
    <div class="grid">
      <button
        v-for="(entry, i) in bag"
        :key="i"
        type="button"
        class="slot"
        :class="{ empty: !entry }"
        :style="entry ? { borderColor: TIER_COLOURS[entry.item.tier].edge } : null"
        @pointerenter="hovered = i"
        @pointerleave="hovered = null"
        @click="entry && emit('use', i)"
        @contextmenu.prevent="entry && emit('sell', i)"
      >
        <ItemIcon v-if="entry" :item="entry.item" />
        <span v-if="entry?.count > 1" class="count">{{ entry.count }}</span>
      </button>
    </div>
    <p class="hint">Click to use or equip · Right-click to sell</p>

    <div v-if="tip" class="tip" :style="{ borderColor: tip.color }">
      <strong>{{ tip.title }}</strong>
      <em>{{ tip.sub }}</em>
      <span v-for="line in tip.lines" :key="line">{{ line }}</span>
    </div>
  </div>
</template>

<style scoped>
.inventory {
  position: fixed;
  left: 16px;
  bottom: 300px;
  background: rgba(40, 26, 12, 0.88);
  border: 1px solid rgba(212, 163, 42, 0.5);
  border-radius: 8px;
  padding: 10px 12px 10px;
  font-family: Georgia, serif;
  color: #f3e3c0;
  user-select: none;
}

.title {
  display: flex;
  align-items: center;
  gap: 12px;
  font-size: 11px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  margin-bottom: 8px;
}

.purse {
  margin-left: auto;
  color: #ffd75e;
  letter-spacing: 0.02em;
  text-transform: none;
  font-size: 14px;
}

.coin {
  display: inline-block;
  width: 12px;
  height: 12px;
  margin-right: 5px;
  border-radius: 50%;
  background: #e8b923;
  box-shadow: inset -2px -2px 0 #9c7412;
  vertical-align: -1px;
}

.close {
  background: none;
  border: none;
  color: inherit;
  font-size: 18px;
  line-height: 1;
  cursor: pointer;
  padding: 0 2px;
  opacity: 0.7;
}

.close:hover {
  opacity: 1;
}

.grid {
  display: grid;
  grid-template-columns: repeat(3, 52px);
  gap: 6px;
}

.slot {
  position: relative;
  width: 52px;
  height: 52px;
  border: 2px solid rgba(243, 227, 192, 0.2);
  border-radius: 6px;
  background: rgba(0, 0, 0, 0.35);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  cursor: pointer;
}

.slot.empty {
  cursor: default;
}

.slot:not(.empty):hover {
  background: rgba(255, 244, 214, 0.08);
}

.slot :deep(svg) {
  width: 36px;
  height: 36px;
}

.count {
  position: absolute;
  right: 4px;
  bottom: 2px;
  font-size: 12px;
  font-weight: bold;
  color: #fff4d6;
  text-shadow: 0 1px 2px #000;
}

.hint {
  margin-top: 6px;
  font-size: 10px;
  opacity: 0.6;
}

.tip {
  position: absolute;
  left: calc(100% + 8px);
  top: 0;
  width: 200px;
  background: rgba(30, 20, 10, 0.95);
  border: 1px solid;
  border-radius: 6px;
  padding: 8px 10px;
  display: flex;
  flex-direction: column;
  gap: 2px;
  font-size: 13px;
  pointer-events: none;
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
  .inventory {
    bottom: 240px;
  }
  .grid {
    grid-template-columns: repeat(3, 40px);
  }
  .slot {
    width: 40px;
    height: 40px;
  }
}
</style>
