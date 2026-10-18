<script setup>
import { onMounted, onUnmounted, reactive, useTemplateRef } from 'vue'
import { Application } from 'pixi.js'
import { Game } from '../game/Game.js'
import EquipmentPanel from './EquipmentPanel.vue'
import InventoryPanel from './InventoryPanel.vue'
import TradePanel from './TradePanel.vue'

const container = useTemplateRef('container')
const hud = reactive({
  speed: 0,
  distance: 0,
  stage: '',
  stageNumber: 1,
  threat: 0,
  banner: null,
  health: 5,
  maxHealth: 5,
  cartHealth: 10,
  maxCartHealth: 10,
  stamina: 1,
  winded: false,
  galloping: false,
  equipment: [],
  bare: {},
  armour: 0,
  block: 0,
  bag: [],
  bagOpen: false,
  active: 'ranged',
  trade: null,
  ammo: 8,
  ammoKind: 'stones',
  ammoName: 'Stones',
  maxAmmo: 8,
  kills: 0,
  gold: 0,
  onFoot: false,
  prompt: '',
  toast: '',
  over: false,
  overTitle: '',
  overText: '',
})
let app
let game

onMounted(async () => {
  app = new Application()
  await app.init({
    resizeTo: container.value,
    background: '#5f9a45',
    antialias: true,
  })
  container.value.appendChild(app.canvas)
  game = new Game(app, (state) => Object.assign(hud, state))
})

onUnmounted(() => {
  game?.destroy()
  app?.destroy(true, { children: true })
})
</script>

<template>
  <div ref="container" class="pixi-container"></div>

  <div class="hud">
    <div class="stat stage"><span>Stage {{ hud.stageNumber }} · Threat {{ hud.threat.toFixed(1) }}</span>{{ hud.stage }}</div>
    <div class="stat"><span>Distance</span>{{ hud.distance }} m</div>
    <div class="stat"><span>Speed</span>{{ hud.speed }} km/h</div>
    <div class="stat"><span>Raiders felled</span>{{ hud.kills }}</div>
    <div class="stat gold"><span>Gold</span><i class="coin"></i>{{ hud.gold }}</div>
  </div>

  <div class="vitals">
    <div class="row" :class="{ active: hud.onFoot }">
      <label>You</label>
      <span v-for="i in hud.maxHealth" :key="'h' + i" class="heart" :class="{ lost: i > hud.health }">♥</span>
    </div>
    <div class="row" :class="{ active: !hud.onFoot }">
      <label>Cart</label>
      <div class="bar cart-bar">
        <div class="fill" :style="{ width: (hud.cartHealth / hud.maxCartHealth) * 100 + '%' }"></div>
        <i v-for="i in hud.maxCartHealth - 1" :key="'c' + i" class="tick" :style="{ left: (i / hud.maxCartHealth) * 100 + '%' }"></i>
      </div>
    </div>
    <div class="row">
      <label>Stamina</label>
      <div class="bar stamina-bar" :class="{ winded: hud.winded, galloping: hud.galloping }">
        <div class="fill" :style="{ width: hud.stamina * 100 + '%' }"></div>
      </div>
    </div>
    <div class="row">
      <label>{{ hud.ammoName }}</label>
      <span v-for="i in hud.maxAmmo" :key="hud.ammoKind + i" class="pebble" :class="[hud.ammoKind, { lost: i > hud.ammo }]"></span>
    </div>
  </div>

  <EquipmentPanel
    v-if="hud.equipment.length"
    :equipment="hud.equipment"
    :bare="hud.bare"
    :armour="hud.armour"
    :block="hud.block"
    :bag-open="hud.bagOpen"
    :active="hud.active"
    @unequip="(slot) => game?.unequip(slot)"
    @toggle-bag="game?.toggleBag()"
  />
  <InventoryPanel
    v-if="hud.bagOpen && !hud.over"
    :bag="hud.bag"
    :gold="hud.gold"
    :equipment="hud.equipment"
    @use="(i) => game?.useBagItem(i)"
    @sell="(i) => game?.sellBagItem(i)"
    @close="game?.toggleBag()"
  />

  <TradePanel
    v-if="hud.trade && !hud.over"
    :trade="hud.trade"
    :gold="hud.gold"
    @buy="(i) => game?.buy(i)"
    @close="game && (game.trading = null)"
  />

  <Transition name="banner" mode="out-in">
    <div v-if="hud.banner && !hud.over" :key="hud.banner.title" class="banner">
      <h2>{{ hud.banner.title }}</h2>
      <p>{{ hud.banner.sub }}</p>
    </div>
  </Transition>

  <div v-if="hud.toast" class="toast">{{ hud.toast }}</div>
  <div v-if="hud.prompt" class="prompt">{{ hud.prompt }}</div>

  <div class="controls">
    <template v-if="hud.onFoot">
      WASD – walk &nbsp;·&nbsp; E – open chest / climb on &nbsp;·&nbsp; Click – attack &nbsp;·&nbsp; Q / right-click – switch weapon &nbsp;·&nbsp; B – bag
    </template>
    <template v-else>
      W / S – faster / slower &nbsp;·&nbsp; Shift – gallop &nbsp;·&nbsp; A / D – steer &nbsp;·&nbsp; E – get off &nbsp;·&nbsp; Click – attack &nbsp;·&nbsp; Q / right-click – switch weapon &nbsp;·&nbsp; B – bag
    </template>
  </div>

  <div v-if="hud.over" class="overlay">
    <h1>{{ hud.overTitle }}</h1>
    <p class="reached">You reached {{ hud.stage }} – stage {{ hud.stageNumber }}</p>
    <p>You travelled {{ hud.distance }} m and felled {{ hud.kills }} raiders before {{ hud.overText }}.</p>
    <p>{{ hud.gold }} gold was lost along with everything else.</p>
    <p class="hint">Press Space to try again</p>
  </div>
</template>

<style scoped>
.pixi-container {
  width: 100%;
  height: 100vh;
  display: block;
  cursor: crosshair;
}

.vitals {
  position: fixed;
  top: 16px;
  right: 16px;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 8px;
  background: rgba(40, 26, 12, 0.75);
  padding: 8px 12px;
  border-radius: 6px;
  pointer-events: none;
}

.vitals .row {
  display: flex;
  gap: 5px;
  align-items: center;
  opacity: 0.85;
}

/* Whichever of you or the cart is taking the hits stands out. */
.vitals .row.active {
  opacity: 1;
}

.vitals label {
  color: #f3e3c0;
  font-family: Georgia, serif;
  font-size: 11px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  opacity: 0.7;
  margin-right: 6px;
}

.bar {
  position: relative;
  width: 130px;
  height: 12px;
  background: rgba(0, 0, 0, 0.45);
  border-radius: 3px;
  overflow: hidden;
}

.bar .fill {
  height: 100%;
  transition: width 0.15s linear;
}

.cart-bar .fill {
  background: linear-gradient(#b98a52, #8b6236);
}

.cart-bar .tick {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 1px;
  background: rgba(0, 0, 0, 0.4);
}

.stamina-bar .fill {
  background: linear-gradient(#f0d36a, #c9a227);
}

.stamina-bar.galloping .fill {
  background: linear-gradient(#ffe98a, #e8b923);
}

.stamina-bar.winded .fill {
  background: #8a7a5a;
}

.heart {
  color: #e0463a;
  font-size: 22px;
  line-height: 1;
}

.pebble {
  width: 12px;
  height: 10px;
  border-radius: 50%;
  background: #a9a59a;
  box-shadow: inset -2px -2px 0 #77736a;
}

/* Arrows and bolts stand upright in the quiver */
.pebble.arrows,
.pebble.bolts {
  width: 4px;
  height: 16px;
  border-radius: 1px;
  box-shadow: none;
  background: linear-gradient(#b9c0c8 0 22%, #8b6236 22% 80%, #e8e0c8 80%);
}

.pebble.bolts {
  width: 5px;
  height: 12px;
  background: linear-gradient(#b9c0c8 0 25%, #6e4a28 25% 82%, #5e3f22 82%);
}

.heart.lost,
.pebble.lost {
  opacity: 0.2;
}

.hud {
  position: fixed;
  top: 16px;
  left: 16px;
  display: flex;
  gap: 12px;
  font-family: Georgia, serif;
  pointer-events: none;
}

.stat {
  background: rgba(40, 26, 12, 0.75);
  color: #f3e3c0;
  padding: 8px 14px;
  border-radius: 6px;
  font-size: 20px;
  min-width: 120px;
}

.stat .coin {
  display: inline-block;
  width: 14px;
  height: 14px;
  margin-right: 6px;
  border-radius: 50%;
  background: #e8b923;
  box-shadow: inset -2px -2px 0 #9c7412;
  vertical-align: -1px;
}

.stat.gold {
  color: #ffd75e;
}

.stat span {
  display: block;
  font-size: 11px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  opacity: 0.7;
}

.controls {
  position: fixed;
  bottom: 16px;
  left: 50%;
  transform: translateX(-50%);
  background: rgba(40, 26, 12, 0.6);
  color: #f3e3c0;
  padding: 6px 14px;
  border-radius: 6px;
  font-family: Georgia, serif;
  font-size: 14px;
  pointer-events: none;
}

.stat.stage {
  min-width: 190px;
}

.banner {
  position: fixed;
  top: 22%;
  left: 50%;
  transform: translateX(-50%);
  text-align: center;
  font-family: Georgia, serif;
  color: #fff4d6;
  text-shadow: 0 2px 8px rgba(0, 0, 0, 0.7);
  pointer-events: none;
}

.banner h2 {
  font-size: 44px;
  font-weight: normal;
  letter-spacing: 0.06em;
}

.banner p {
  margin-top: 4px;
  font-size: 16px;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  opacity: 0.85;
}

.banner-enter-active,
.banner-leave-active {
  transition: opacity 0.8s ease;
}

.banner-enter-from,
.banner-leave-to {
  opacity: 0;
}

.prompt,
.toast {
  position: fixed;
  left: 50%;
  transform: translateX(-50%);
  padding: 8px 16px;
  border-radius: 6px;
  font-family: Georgia, serif;
  pointer-events: none;
  white-space: nowrap;
}

.prompt {
  bottom: 60px;
  background: rgba(40, 26, 12, 0.85);
  color: #fff4d6;
  font-size: 17px;
  border: 1px solid rgba(255, 244, 214, 0.4);
}

.toast {
  top: 84px;
  background: rgba(120, 88, 20, 0.85);
  color: #ffe9a8;
  font-size: 18px;
}

.overlay {
  position: fixed;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 10px;
  background: rgba(30, 20, 10, 0.6);
  color: #f3e3c0;
  font-family: Georgia, serif;
  text-align: center;
}

.overlay h1 {
  font-size: 48px;
}

.overlay .hint {
  margin-top: 12px;
  opacity: 0.8;
}
</style>
