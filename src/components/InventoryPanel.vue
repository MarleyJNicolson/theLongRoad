<script setup>
import { computed, ref } from 'vue'
import ItemIcon from './ItemIcon.vue'
import { describe, TIER_COLOURS } from './describe.js'

// One panel for both the bag and the cart's storage. Items can be dragged
// between (or within) them.
const props = defineProps({
  bag: { type: Array, required: true }, // [{ type, item, count?, value } | null]
  container: { type: String, default: 'bag' }, // 'bag' or 'cart'
  title: { type: String, default: 'Bag' },
  columns: { type: Number, default: 3 },
  gold: { type: Number, default: null }, // shows the purse when given
  equipment: { type: Array, required: true },
  cartOpen: { type: Boolean, default: false },
  closeKey: { type: String, default: 'B' },
})
const emit = defineEmits(['use', 'sell', 'close', 'move'])
const isCart = computed(() => props.container === 'cart')

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
  }
  if (isCart.value) {
    lines.push('Click to take it into your bag')
  } else {
    if (isGear) lines.push('Click to equip')
    if (props.cartOpen) lines.push('Shift-click to stow it in the cart')
  }
  lines.push(`Right-click to sell (${entry.value} gold)`)
  return { title: item.name, sub: isGear ? tier.name : 'Supplies', lines, color: tier.edge }
})

function click(i, event) {
  if (!props.bag[i]) return
  if (isCart.value) emit('move', 'cart', i, 'bag', null)
  else if (event.shiftKey && props.cartOpen) emit('move', 'bag', i, 'cart', null)
  else emit('use', i)
}

// Drag and drop between slots
function dragStart(i, event) {
  event.dataTransfer.setData('text/plain', JSON.stringify({ from: props.container, i }))
  event.dataTransfer.effectAllowed = 'move'
  hovered.value = null
}
function drop(j, event) {
  try {
    const { from, i } = JSON.parse(event.dataTransfer.getData('text/plain'))
    emit('move', from, i, props.container, j)
  } catch {
    // not one of ours
  }
}
</script>

<template>
  <div class="inventory" :class="{ cart: isCart }" @contextmenu.prevent>
    <div class="title">
      <span>{{ title }}</span>
      <span v-if="gold !== null" class="purse"><i class="coin"></i>{{ gold }} gold</span>
      <span v-else class="purse"></span>
      <button type="button" class="close" :title="`Close (${closeKey})`" @click="emit('close')">×</button>
    </div>
    <div class="grid" :style="{ gridTemplateColumns: `repeat(${columns}, var(--slot))` }">
      <button
        v-for="(entry, i) in bag"
        :key="i"
        type="button"
        class="slot"
        :class="{ empty: !entry }"
        :style="entry ? { borderColor: TIER_COLOURS[entry.item.tier].edge } : null"
        :draggable="!!entry"
        @dragstart="dragStart(i, $event)"
        @dragover.prevent
        @drop.prevent="drop(i, $event)"
        @pointerenter="hovered = i"
        @pointerleave="hovered = null"
        @click="click(i, $event)"
        @contextmenu.prevent="entry && emit('sell', i)"
      >
        <ItemIcon v-if="entry" :item="entry.item" />
        <span v-if="entry?.count > 1" class="count">{{ entry.count }}</span>
      </button>
    </div>
    <p class="hint">
      <template v-if="isCart">Click to take · Drag to move · Right-click to sell</template>
      <template v-else-if="cartOpen">Click to use · Shift-click or drag to the cart</template>
      <template v-else>Click to use or equip · Right-click to sell</template>
    </p>

    <div v-if="tip" class="tip" :style="{ borderColor: tip.color }">
      <strong>{{ tip.title }}</strong>
      <em>{{ tip.sub }}</em>
      <span v-for="line in tip.lines" :key="line">{{ line }}</span>
    </div>
  </div>
</template>

<style scoped>
.inventory {
  --slot: 52px;
  position: fixed;
  left: 16px;
  bottom: 300px;
  background: var(--panel);
  border: 1px solid rgba(212, 163, 42, 0.5);
  border-radius: 0;
  padding: 10px 12px 10px;
  font-family: var(--font-ui);
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

/* The cart's storage opens beside the bag. */
.inventory.cart {
  left: 228px;
  border-color: rgba(168, 135, 92, 0.7);
}

.grid {
  display: grid;
  gap: 6px;
}

.slot {
  position: relative;
  width: var(--slot);
  height: var(--slot);
  border: 2px solid rgba(243, 227, 192, 0.2);
  border-radius: 0;
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
  border-radius: 0;
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
    --slot: 40px;
    bottom: 240px;
  }
  .inventory.cart {
    left: 180px;
  }
}
</style>
