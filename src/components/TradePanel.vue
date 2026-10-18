<script setup>
import ItemIcon from './ItemIcon.vue'
import { describe, TIER_COLOURS } from './describe.js'

defineProps({
  trade: { type: Object, required: true }, // { name, offers: [{ i, kind, type, name, item, price, sold, why }] }
  gold: { type: Number, default: 0 },
})
const emit = defineEmits(['buy', 'close'])

// Services have no item of their own; borrow a fitting icon.
const SERVICE_ICON = { repair: 'planks', heal: 'poultice', ammo: 'stone' }
const iconFor = (offer) => offer.item ?? { icon: SERVICE_ICON[offer.type], tier: 1 }
const detail = (offer) => {
  if (offer.kind === 'service') return offer.type === 'ammo' ? 'Fills every quiver and pouch' : 'Price depends on the damage'
  const lines = describe(offer.item)
  return offer.kind === 'gear' ? [TIER_COLOURS[offer.item.tier].name, ...lines].join(' · ') : lines.join(' · ')
}
</script>

<template>
  <div class="trade">
    <div class="title">
      <span>{{ trade.name }}</span>
      <span class="purse"><i class="coin"></i>{{ gold }} gold</span>
      <button type="button" class="close" title="Close (Esc)" @click="emit('close')">×</button>
    </div>
    <ul>
      <li v-for="offer in trade.offers" :key="offer.i" :class="{ sold: offer.sold }">
        <div class="icon" :style="offer.kind === 'gear' ? { borderColor: TIER_COLOURS[offer.item.tier].edge } : null">
          <ItemIcon :item="iconFor(offer)" />
        </div>
        <div class="text">
          <strong>{{ offer.name }}</strong>
          <span>{{ detail(offer) }}</span>
        </div>
        <button type="button" class="buy" :disabled="!!offer.why" :title="offer.why" @click="emit('buy', offer.i)">
          <template v-if="offer.sold">Sold</template>
          <template v-else><i class="coin"></i>{{ offer.price }}</template>
        </button>
        <em v-if="offer.why && !offer.sold" class="why">{{ offer.why }}</em>
      </li>
    </ul>
  </div>
</template>

<style scoped>
.trade {
  position: fixed;
  right: 16px;
  top: 50%;
  transform: translateY(-50%);
  width: 340px;
  max-width: calc(100vw - 32px);
  background: rgba(40, 26, 12, 0.92);
  border: 1px solid rgba(212, 163, 42, 0.6);
  border-radius: 8px;
  padding: 12px;
  font-family: Georgia, serif;
  color: #f3e3c0;
  user-select: none;
}

.title {
  display: flex;
  align-items: center;
  gap: 12px;
  font-size: 13px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  margin-bottom: 10px;
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
  width: 11px;
  height: 11px;
  margin-right: 4px;
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
  opacity: 0.7;
}

ul {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

li {
  position: relative;
  display: grid;
  grid-template-columns: 40px 1fr auto;
  align-items: center;
  gap: 10px;
  padding: 6px;
  border-radius: 6px;
  background: rgba(0, 0, 0, 0.25);
}

li.sold {
  opacity: 0.45;
}

.icon {
  width: 40px;
  height: 40px;
  border: 2px solid rgba(243, 227, 192, 0.2);
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.icon :deep(svg) {
  width: 30px;
  height: 30px;
}

.text {
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.text strong {
  font-size: 14px;
}

.text span {
  font-size: 11px;
  opacity: 0.7;
}

.buy {
  min-width: 58px;
  padding: 6px 10px;
  border-radius: 5px;
  border: 1px solid #d4a32a;
  background: rgba(212, 163, 42, 0.2);
  color: #ffe9a8;
  font: inherit;
  font-size: 14px;
  cursor: pointer;
}

.buy:hover:not(:disabled) {
  background: rgba(212, 163, 42, 0.4);
}

.buy:disabled {
  cursor: default;
  border-color: rgba(243, 227, 192, 0.25);
  background: none;
  color: rgba(243, 227, 192, 0.5);
}

.why {
  position: absolute;
  right: 8px;
  bottom: -2px;
  font-size: 9px;
  font-style: normal;
  opacity: 0.6;
}
</style>
