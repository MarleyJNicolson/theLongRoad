<script setup>
import { onMounted, onUnmounted, reactive, ref, useTemplateRef } from 'vue'
import { Application } from 'pixi.js'
import { Game } from '../game/Game.js'
import { PIXEL_SIZE, createPixelArtFilter } from '../game/pixelArt.js'
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
  breath: 1,
  outOfBreath: false,
  sprinting: false,
  galloping: false,
  equipment: [],
  bare: {},
  armour: 0,
  block: 0,
  bag: [],
  bagOpen: false,
  cartStore: [],
  cartOpen: false,
  nearCart: true,
  active: 'ranged',
  trade: null,
  ammo: 0,
  ammoFrom: 'cart + bag',
  ammoKind: 'stones',
  ammoName: 'Stones',
  kills: 0,
  gold: 0,
  onFoot: false,
  prompt: '',
  toast: '',
  over: false,
  overTitle: '',
  overText: '',
  scoreboard: null,
})
let app
let game
let resizeObserver

// Your name for the scoreboard, remembered for next time on this browser
const NAME_KEY = 'scoreboard-name'
const playerName = ref('')
try {
  playerName.value = localStorage.getItem(NAME_KEY) ?? ''
} catch {}

function signRun() {
  const name = playerName.value.trim()
  try {
    if (name) localStorage.setItem(NAME_KEY, name)
  } catch {}
  game.lastName = name
  game.saveRun(name)
  document.activeElement?.blur() // so Space goes back to the game (to try again)
}

// Focus the name box as soon as it appears
const vFocus = { mounted: (el) => el.focus() }

onMounted(async () => {
  app = new Application()
  // Render at a fraction of the screen's resolution and let the browser scale
  // it up without smoothing: each art pixel covers a whole number of device
  // pixels (PIXEL_SIZE screen pixels, near enough on high-DPI displays).
  const dpr = window.devicePixelRatio || 1
  const devicePixelsPerArtPixel = Math.max(1, Math.round(PIXEL_SIZE * dpr))
  // Pixel fonts must be ready before any in-world text is drawn.
  await Promise.all(['16px "Pixelify Sans"', '16px "Jacquard 24"'].map((f) => document.fonts.load(f).catch(() => {})))
  await app.init({
    preference: 'webgl',
    background: '#0e0b0a',
    antialias: false,
    resolution: dpr / devicePixelsPerArtPixel,
    autoDensity: true,
    roundPixels: true,
  })
  app.pixelSize = devicePixelsPerArtPixel / dpr // art pixel size in screen units
  container.value.appendChild(app.canvas)

  // Size the game to a whole number of art pixels. An odd window size would
  // otherwise leave a half art pixel over, misaligning the pixel grid; the
  // pixel-art pass then rounds differently on each half of the screen and
  // shows a seam along the diagonal.
  const fit = () => {
    const cols = Math.floor((container.value.clientWidth * dpr) / devicePixelsPerArtPixel)
    const rows = Math.floor((container.value.clientHeight * dpr) / devicePixelsPerArtPixel)
    app.renderer.resize(cols * app.pixelSize, rows * app.pixelSize)
  }
  fit()
  resizeObserver = new ResizeObserver(fit)
  resizeObserver.observe(container.value)
  app.stage.filters = [createPixelArtFilter()]
  app.stage.filterArea = app.screen
  game = new Game(app, (state) => Object.assign(hud, state))
  game.lastName = playerName.value.trim()
})

onUnmounted(() => {
  resizeObserver?.disconnect()
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
    <div class="row" :class="{ active: hud.onFoot }">
      <label>Stamina</label>
      <div class="bar stamina-bar" :class="{ winded: hud.outOfBreath, galloping: hud.sprinting }">
        <div class="fill" :style="{ width: hud.breath * 100 + '%' }"></div>
      </div>
    </div>
    <div class="row" :class="{ active: !hud.onFoot }">
      <label>Horse</label>
      <div class="bar stamina-bar" :class="{ winded: hud.winded, galloping: hud.galloping }">
        <div class="fill" :style="{ width: hud.stamina * 100 + '%' }"></div>
      </div>
    </div>
    <div class="row">
      <label>{{ hud.ammoName }}</label>
      <span class="pebble" :class="hud.ammoKind"></span>
      <b class="ammo-count" :class="{ empty: !hud.ammo }">{{ hud.ammo }}</b>
      <small class="ammo-from">from {{ hud.ammoFrom }}</small>
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
    :cart-open="hud.cartOpen"
    :near-cart="hud.nearCart"
    @toggle-cart="game?.toggleCart()"
  />
  <InventoryPanel
    v-if="hud.bagOpen && !hud.over"
    :bag="hud.bag"
    :gold="hud.gold"
    :equipment="hud.equipment"
    :cart-open="hud.cartOpen"
    @use="(i) => game?.useBagItem(i)"
    @sell="(i) => game?.sellBagItem(i)"
    @move="(from, i, to, j) => game?.moveItem(from, i, to, j)"
    @close="game?.toggleBag()"
  />
  <InventoryPanel
    v-if="hud.cartOpen && !hud.over"
    container="cart"
    title="Cart storage"
    :columns="4"
    close-key="C"
    :bag="hud.cartStore"
    :equipment="hud.equipment"
    @sell="(i) => game?.sellBagItem(i, 'cart')"
    @move="(from, i, to, j) => game?.moveItem(from, i, to, j)"
    @close="game?.toggleCart()"
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
      WASD – walk &nbsp;·&nbsp; Shift – sprint &nbsp;·&nbsp; Ctrl / Space – dash &nbsp;·&nbsp; E – open chest / climb on &nbsp;·&nbsp; Click – attack &nbsp;·&nbsp; Q / right-click – switch weapon &nbsp;·&nbsp; B – bag &nbsp;·&nbsp; C – cart storage
    </template>
    <template v-else>
      W / S – faster / slower &nbsp;·&nbsp; Shift – gallop &nbsp;·&nbsp; A / D – steer &nbsp;·&nbsp; E – get off &nbsp;·&nbsp; Click – attack &nbsp;·&nbsp; Q / right-click – switch weapon &nbsp;·&nbsp; B – bag &nbsp;·&nbsp; C – cart storage
    </template>
  </div>

  <div
    v-if="hud.tether?.arrow && !hud.over"
    class="cart-arrow"
    :class="{ warn: hud.tether.warn }"
    :style="{ left: hud.tether.arrow.x + 'px', top: hud.tether.arrow.y + 'px' }"
  >
    <div class="pointer" :style="{ transform: `rotate(${hud.tether.arrow.angle}deg)` }"></div>
    <span>Cart · {{ hud.tether.metres }} m</span>
  </div>
  <div v-if="hud.tether?.warn && !hud.over" class="tether-warning">
    {{ hud.tether.atLimit ? 'You can go no further from your cart' : 'You are straying too far from your cart' }} – head back!
  </div>

  <div v-if="hud.over" class="overlay">
    <h1>{{ hud.overTitle }}</h1>
    <p class="reached">You reached {{ hud.stage }} – stage {{ hud.stageNumber }}</p>
    <p>You travelled {{ hud.distance }} m and felled {{ hud.kills }} raiders before {{ hud.overText }}.</p>
    <p>{{ hud.gold }} gold was lost along with everything else.</p>
    <div v-if="hud.scoreboard" class="scores">
      <form v-if="hud.scoreboard.naming" class="sign" @submit.prevent="signRun">
        <label for="run-name">Sign the scoreboard</label>
        <input id="run-name" v-model="playerName" v-focus maxlength="20" placeholder="Your name" autocomplete="off" @keydown.enter.prevent="signRun" />
        <button type="submit">Save</button>
      </form>
      <p v-else-if="hud.scoreboard.pending">Writing your run on the scoreboard…</p>
      <p v-else-if="hud.scoreboard.error">The scoreboard couldn't be reached.</p>
      <template v-else>
        <p class="score">
          Score {{ hud.scoreboard.score }}
          <span v-if="hud.scoreboard.rank"> · #{{ hud.scoreboard.rank }} on the board</span>
        </p>
        <table>
          <tr v-for="(run, k) in hud.scoreboard.top.slice(0, 5)" :key="k" :class="{ you: k + 1 === hud.scoreboard.rank }">
            <td>{{ k + 1 }}.</td>
            <td>{{ run.name }}</td>
            <td class="num">{{ run.score }}</td>
            <td>{{ run.distance }} m</td>
            <td>{{ run.kills }} felled</td>
            <td>{{ run.region }}</td>
          </tr>
        </table>
      </template>
    </div>
    <p class="hint">{{ hud.scoreboard?.naming ? 'Enter to save · click away and press Space to try again' : 'Press Space to try again' }}</p>
  </div>
</template>

<style scoped>
.pixi-container {
  width: 100%;
  height: 100vh;
  display: block;
  overflow: hidden;
  background: #0e0b0a; /* shows in the sliver left when the game is snapped to whole art pixels */
  cursor: crosshair;
}

.pixi-container :deep(canvas) {
  image-rendering: pixelated;
}

.vitals {
  position: fixed;
  top: 16px;
  right: 16px;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 8px;
  background: var(--panel);
  padding: 8px 12px;
  border-radius: 0;
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
  font-family: var(--font-ui);
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
  border-radius: 0;
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
  border-radius: 0;
  box-shadow: none;
  background: linear-gradient(#b9c0c8 0 22%, #8b6236 22% 80%, #e8e0c8 80%);
}

.pebble.bolts {
  width: 5px;
  height: 12px;
  background: linear-gradient(#b9c0c8 0 25%, #6e4a28 25% 82%, #5e3f22 82%);
}

.ammo-count {
  color: #f3e3c0;
  font-size: 18px;
  min-width: 26px;
  text-align: right;
}

.ammo-count.empty {
  color: #cf5528;
}

.ammo-from {
  color: #f3e3c0;
  font-size: 10px;
  opacity: 0.6;
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
  font-family: var(--font-ui);
  pointer-events: none;
}

.stat {
  background: var(--panel);
  color: #f3e3c0;
  padding: 8px 14px;
  border-radius: 0;
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
  background: var(--panel);
  color: #f3e3c0;
  padding: 6px 14px;
  border-radius: 0;
  font-family: var(--font-ui);
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
  font-family: var(--font-ui);
  color: #fff4d6;
  text-shadow: 0 2px 8px rgba(0, 0, 0, 0.7);
  pointer-events: none;
}

.banner h2 {
  font-family: var(--font-title);
  font-size: 64px;
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
  border-radius: 0;
  font-family: var(--font-ui);
  pointer-events: none;
  white-space: nowrap;
}

.prompt {
  bottom: 60px;
  background: var(--panel);
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

.cart-arrow {
  position: fixed;
  transform: translate(-50%, -50%);
  pointer-events: none;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 2px;
  font-family: var(--font-ui);
  font-size: 15px;
  color: #f3e3c0;
  text-shadow: 0 1px 0 #1c1714, 0 -1px 0 #1c1714, 1px 0 0 #1c1714, -1px 0 0 #1c1714;
}

/* A chunky arrowhead pointing right, turned towards the cart */
.cart-arrow .pointer {
  width: 0;
  height: 0;
  border-top: 16px solid transparent;
  border-bottom: 16px solid transparent;
  border-left: 30px solid #e8b923;
  filter: drop-shadow(0 0 0 #1c1714) drop-shadow(2px 2px 0 #1c1714);
}

.cart-arrow.warn .pointer {
  border-left-color: #e0463a;
  animation: tether-pulse 0.6s ease-in-out infinite alternate;
}

.cart-arrow.warn span {
  color: #ffb3a8;
}

.tether-warning {
  position: fixed;
  top: 96px;
  left: 50%;
  transform: translateX(-50%);
  padding: 6px 16px;
  font-family: var(--font-ui);
  font-size: 16px;
  color: #ffe2d8;
  background: rgba(90, 24, 16, 0.85);
  border: 2px solid #e0463a;
  pointer-events: none;
  animation: tether-pulse 0.6s ease-in-out infinite alternate;
}

@keyframes tether-pulse {
  from {
    opacity: 1;
  }
  to {
    opacity: 0.55;
  }
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
  font-family: var(--font-ui);
  text-align: center;
}

.overlay h1 {
  font-family: var(--font-title);
  font-size: 72px;
  font-weight: normal;
  color: #cf5528;
}

.overlay .scores {
  margin-top: 8px;
  padding: 10px 18px;
  background: rgba(20, 14, 8, 0.6);
  border: 2px solid #5e4a33;
}

.overlay .sign {
  display: flex;
  align-items: center;
  gap: 10px;
}

.overlay .sign input {
  font: inherit;
  font-size: 18px;
  width: 220px;
  padding: 4px 8px;
  color: #2a1f14;
  background: #f3e3c0;
  border: 2px solid #5e4a33;
  outline: none;
}

.overlay .sign input:focus {
  border-color: #ffd75e;
}

.overlay .sign button {
  font: inherit;
  padding: 4px 14px;
  color: #2a1f14;
  background: #d4a32a;
  border: 2px solid #5e3f22;
  cursor: pointer;
}

.overlay .score {
  font-size: 22px;
  color: #ffd75e;
  margin-bottom: 6px;
}

.overlay table {
  border-collapse: collapse;
  font-size: 14px;
}

.overlay td {
  padding: 2px 10px;
  text-align: left;
}

.overlay td.num {
  text-align: right;
}

.overlay tr.you {
  color: #ffd75e;
}

.overlay .hint {
  margin-top: 12px;
  opacity: 0.8;
}
</style>
