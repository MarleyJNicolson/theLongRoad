import { Container, Graphics, Text } from 'pixi.js'
import { maybeAddChest, addProp } from '../loot.js'
import { rollItem } from '../items.js'
import { rand, randInt, campfire } from './helpers.js'
import { drawHouse, drawFarmer } from './raids.js'
import { drawLeanTo, drawWatchtower } from './bandits.js'
import { drawHideTent, drawSkullTotem, scatterBones } from './goblins.js'

// The big places at the end of side roads. Each builder gets the spot the
// side road arrives at and returns the encounter's contents.

export const DEST_RADIUS = 240

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)]
const VILLAGES = ['Millbrook', 'Ashford', 'Hollowmere', 'Thornby', 'Wexley', 'Barrowfield', 'Oakhurst', 'Fenwick', 'Dunmere', 'Coldharbour']
const STRONGHOLDS = ['Redhand Stronghold', 'The Crow’s Nest', 'Blackfen Hold', 'Gallows Keep', 'Cutthroat Hold']
const WARCAMPS = ['Gorefang Warcamp', 'Skullpile Warcamp', 'Grimtusk Camp', 'The Bonepit', 'Rotjaw Warcamp']

const SIGN_TEXT = { fontFamily: 'Georgia, serif', fontWeight: 'bold', fontSize: 13, fill: '#2a1f14' }

// --- Shared pieces -------------------------------------------------------

function ring(g, cx, cy, r, colour, alpha = 0.55) {
  for (let k = 0; k < 9; k++) {
    const a = (k / 9) * Math.PI * 2
    g.circle(cx + Math.cos(a) * r * 0.45, cy + Math.sin(a) * r * 0.45, r * 0.62)
  }
  g.fill({ color: colour, alpha })
}

// Spread `count` things evenly round a circle, skipping the entrance.
function around(count, radius, entrance, gap = 0.7, jitter = 0.15) {
  const spots = []
  const span = Math.PI * 2 - gap * 2
  for (let k = 0; k < count; k++) {
    const a = entrance + gap + (span * (k + 0.5)) / count + rand(-jitter, jitter)
    spots.push({ a, x: Math.cos(a) * radius, y: Math.sin(a) * radius })
  }
  return spots
}

// A ring of sharpened stakes with a gate toward the side road.
function palisade(g, cx, cy, radius, entrance, colour, solids, skulls = false) {
  const steps = Math.floor((Math.PI * 2 * radius) / 15)
  for (let k = 0; k < steps; k++) {
    const a = (k / steps) * Math.PI * 2
    let off = a - entrance
    off = Math.atan2(Math.sin(off), Math.cos(off))
    if (Math.abs(off) < 0.32) continue
    const x = cx + Math.cos(a) * radius
    const y = cy + Math.sin(a) * radius
    g.circle(x + 2, y + 2, 7).fill({ color: '#000', alpha: 0.2 })
    g.circle(x, y, 7).fill(colour).circle(x, y, 3).fill('#a8875c')
    if (skulls && k % 7 === 0) g.circle(x, y, 4).fill('#e8e0c8')
    solids.push({ x, y, radius: 8 })
  }
  // Gate posts
  for (const s of [-1, 1]) {
    const a = entrance + s * 0.34
    g.circle(cx + Math.cos(a) * radius, cy + Math.sin(a) * radius, 10).fill('#4a3220')
  }
}

function addSign(view, x, y, text, hostile) {
  const sign = new Container()
  const g = new Graphics()
  g.moveTo(0, 6).lineTo(0, -14).stroke({ width: 3, color: '#5e3f22' })
  g.roundRect(-72, -34, 144, 22, 3).fill(hostile ? '#7a4a3a' : '#a8875c').stroke({ width: 2, color: '#4a3220' })
  const label = new Text({ text, style: { ...SIGN_TEXT, fill: hostile ? '#f3e3c0' : '#2a1f14' } })
  label.anchor.set(0.5)
  label.y = -23
  sign.addChild(g, label)
  sign.position.set(x, y)
  view.addChild(sign)
}

// Flames and smoke rising off a roof; returns an animate(time, dt) and a
// way to put the fires out.
function burning(view, spots) {
  const fires = spots.map(([x, y]) => {
    const f = new Graphics()
    f.circle(0, 0, 11).fill({ color: '#e8641e', alpha: 0.85 })
    f.circle(1, -1, 7).fill('#ffb02e')
    f.circle(1, -2, 3.5).fill('#fff1a8')
    f.position.set(x, y)
    f.seed = rand(0, 10)
    return f
  })
  const smoke = new Container()
  view.addChild(...fires, smoke)
  const puffs = []
  let nextPuff = 0
  let dousing = false
  return {
    douse() {
      dousing = true
    },
    animate(time, dt) {
      for (const f of fires) {
        if (dousing) f.alpha = Math.max(0, f.alpha - dt * 0.5)
        f.scale.set(1 + Math.sin(time * 15 + f.seed) * 0.15 + Math.sin(time * 6 + f.seed) * 0.1)
      }
      if (time > nextPuff && fires.length && fires[0].alpha > 0.1) {
        const src = pick(fires)
        const puff = new Graphics().circle(0, 0, 9).fill({ color: '#5a5550', alpha: 0.5 })
        puff.position.set(src.x, src.y)
        puff.life = 0
        smoke.addChild(puff)
        puffs.push(puff)
        nextPuff = time + 0.15
      }
      for (let k = puffs.length - 1; k >= 0; k--) {
        const p = puffs[k]
        p.life += dt
        p.x += dt * 22
        p.y -= dt * 30
        p.scale.set(1 + p.life * 1.4)
        p.alpha = Math.max(0, 1 - p.life / 2.6)
        if (p.life > 2.6) {
          p.destroy()
          puffs.splice(k, 1)
        }
      }
    },
  }
}

// --- Traders ---------------------------------------------------------------

function stall(g, x, y, facing, colour) {
  const c = Math.cos(facing)
  const s = Math.sin(facing)
  const pt = (fx, fy) => [x + fx * c - fy * s, y + fx * s + fy * c]
  const rect = (x1, y1, x2, y2) => [...pt(x1, y1), ...pt(x2, y1), ...pt(x2, y2), ...pt(x1, y2)]
  g.poly(rect(-12, -26, 18, 26).map((v) => v + 4)).fill({ color: '#000', alpha: 0.2 })
  // Striped awning over the counter
  for (let k = 0; k < 6; k++) {
    g.poly(rect(-12, -26 + k * (52 / 6), 14, -26 + (k + 1) * (52 / 6))).fill(k % 2 ? '#f3e3c0' : colour)
  }
  g.poly(rect(12, -24, 18, 24)).fill('#8b6236')
}

function makeTrader(view, x, y, facing, name, stock) {
  const figure = drawFarmer()
  figure.visible = true
  figure.position.set(x, y)
  figure.rotation = facing
  view.addChild(figure)
  return { name, x, y, stock, figure, open: true }
}

// What a village sells. Gear is one of a kind; everything else is endless.
function stockFor(metres) {
  const smith = []
  for (let k = 0; k < 4; k++) {
    const item = rollItem(metres)
    smith.push({ kind: 'gear', item, price: item.tier * 10 + randInt(0, 4) })
  }
  const store = [
    { kind: 'consumable', type: 'poultice', price: 6 },
    { kind: 'consumable', type: 'planks', price: 6 },
    { kind: 'service', type: 'ammo', name: 'Restock stones, arrows and bolts', price: 5 },
    { kind: 'service', type: 'repair', name: 'Mend the cart fully', price: 2, per: 'cart point' },
    { kind: 'service', type: 'heal', name: 'See the healer', price: 4, per: 'heart' },
  ]
  return { smith, store }
}

// --- Villages --------------------------------------------------------------

function village({ view, cx, cy, entrance, metres, raid }) {
  const name = pick(VILLAGES)
  const g = new Graphics()
  view.addChild(g)
  ring(g, cx, cy, DEST_RADIUS * 0.9, '#a89466', 0.45)
  g.circle(cx, cy, 70).fill({ color: '#b9a57a', alpha: 0.7 }) // the square

  const solids = []
  const roofs = []
  for (const spot of around(5, 150, entrance, 0.55)) {
    const hx = cx + spot.x
    const hy = cy + spot.y
    const facing = spot.a + Math.PI // door toward the square
    const c = Math.cos(facing)
    const s = Math.sin(facing)
    const pt = (fx, fy) => [hx + fx * c - fy * s, hy + fx * s + fy * c]
    const charred = raid && Math.random() < 0.6
    drawHouse(g, pt, charred)
    for (const fy of [-24, 0, 24]) {
      const [x, y] = pt(0, fy)
      solids.push({ x, y, radius: 31 })
    }
    if (charred) roofs.push(pt(rand(-12, 12), rand(-20, 20)))
  }
  // The well
  g.circle(cx, cy, 15).fill('#8d8a80').circle(cx, cy, 10).fill('#1d2a33')
  solids.push({ x: cx, y: cy, radius: 16 })

  // Two market stalls on the square: the smith and the general store
  const stock = stockFor(metres)
  const traders = []
  const stallSpots = around(2, 52, entrance + Math.PI / 2, 0.2, 0)
  ;[
    ['Blacksmith', stock.smith, '#7d8590'],
    ['General store', stock.store, '#c0392b'],
  ].forEach(([title, goods, colour], k) => {
    const { a } = stallSpots[k]
    const x = cx + Math.cos(a) * 52
    const y = cy + Math.sin(a) * 52
    stall(g, x, y, a + Math.PI, colour)
    solids.push({ x, y, radius: 14 })
    traders.push(makeTrader(view, cx + Math.cos(a) * 70, cy + Math.sin(a) * 70, a + Math.PI, title, goods))
  })

  // Villagers about the square
  const villagers = around(4, 95, entrance, 0.4, 0.4).map(({ x, y, a }) => {
    const v = drawFarmer()
    v.visible = true
    v.position.set(cx + x, cy + y)
    v.rotation = a + Math.PI
    view.addChild(v)
    return v
  })

  addSign(view, cx + Math.cos(entrance) * (DEST_RADIUS - 20), cy + Math.sin(entrance) * (DEST_RADIUS - 20), name, false)
  const fire = raid ? burning(view, roofs) : null

  // While raided, the villagers are hiding and the stalls are shut.
  const setPeace = (peaceful) => {
    for (const t of traders) {
      t.open = peaceful
      t.figure.visible = peaceful
    }
    for (const v of villagers) v.visible = peaceful
  }
  setPeace(!raid)

  return {
    name,
    solids,
    traders,
    setPeace,
    villagers,
    animate(time, dt) {
      fire?.animate(time, dt)
      villagers.forEach((v, k) => {
        if (v.visible) v.arm.rotation = Math.sin(time * 2 + k) * 0.25
      })
    },
    douse: () => fire?.douse(),
  }
}

export function friendlyVillage({ view, cx, cy, entrance, metres }) {
  const v = village({ view, cx, cy, entrance, metres, raid: false })
  return {
    title: `${v.name} – traders`,
    hostile: false,
    members: [],
    solids: v.solids,
    traders: v.traders,
    loot: [],
    animate: v.animate,
  }
}

export function raidedVillage({ view, cx, cy, entrance, metres, enemies, extra, km, faction }) {
  const v = village({ view, cx, cy, entrance, metres, raid: true })
  const members = []
  const wander = { x: cx, y: cy, min: 20, max: 110 }
  const small = faction === 'goblin' ? 'goblin' : 'bandit'
  const big = faction === 'goblin' ? 'orc' : 'brute'
  for (let k = 0; k < Math.min(14, 6 + extra * 2); k++) {
    const a = rand(0, Math.PI * 2)
    members.push(enemies.add(small, cx + Math.cos(a) * 80, cy + Math.sin(a) * 80, { x: cx, y: cy, wander }))
  }
  for (let k = 0; k < Math.min(4, 1 + Math.floor(km / 4)); k++) {
    members.push(enemies.add(big, cx + rand(-40, 40), cy + rand(-40, 40), { x: cx, y: cy, wander }))
  }
  const loot = []
  maybeAddChest(loot, view, cx + rand(-30, 30), cy + 110, 1)
  return {
    title: `${v.name} – under attack!`,
    hostile: true,
    members,
    solids: v.solids,
    traders: v.traders,
    loot,
    trigger: 380,
    reward: { gold: 15 + Math.floor(km * 2), x: cx, y: cy, message: `The people of ${v.name} reward you` },
    onCleared() {
      v.douse()
      v.setPeace(true)
    },
    animate: v.animate,
  }
}

// --- Bandit stronghold -----------------------------------------------------

export function banditStronghold({ view, cx, cy, entrance, enemies, extra, km }) {
  const g = new Graphics()
  view.addChild(g)
  ring(g, cx, cy, DEST_RADIUS * 0.85, '#8a7f55')
  const solids = []
  palisade(g, cx, cy, 200, entrance, '#6e4a28', solids)

  for (const spot of around(4, 130, entrance, 0.6)) {
    drawLeanTo(g, cx + spot.x, cy + spot.y, spot.a)
    solids.push({ x: cx + spot.x, y: cy + spot.y, radius: 22 })
  }
  const towers = [-0.6, 0.6].map((s) => {
    const a = entrance + s
    const x = cx + Math.cos(a) * 168
    const y = cy + Math.sin(a) * 168
    drawWatchtower(g, x, y)
    solids.push({ x, y, radius: 20 })
    return { x, y }
  })
  const flicker = campfire(g, view, cx, cy)
  solids.push({ x: cx, y: cy, radius: 16 })

  // Their hoard, piled at the back
  const loot = []
  const back = entrance + Math.PI
  for (const s of [-0.35, 0, 0.35]) {
    const x = cx + Math.cos(back + s) * 95
    const y = cy + Math.sin(back + s) * 95
    maybeAddChest(loot, view, x, y, 1)
  }
  addProp(view, 'crate', cx + Math.cos(back) * 125, cy + Math.sin(back) * 125)
  addProp(view, 'barrel', cx + Math.cos(back + 0.2) * 128, cy + Math.sin(back + 0.2) * 128)

  const members = []
  for (const t of towers) members.push(enemies.add('bandit', t.x, t.y, { x: t.x, y: t.y, facing: entrance }))
  const yard = { x: cx, y: cy, min: 30, max: 120 }
  for (let k = 0; k < Math.min(16, 6 + extra * 2 + Math.floor(km)); k++) {
    const a = rand(0, Math.PI * 2)
    members.push(enemies.add('bandit', cx + Math.cos(a) * 70, cy + Math.sin(a) * 70, { x: cx, y: cy, wander: yard }))
  }
  for (let k = 0; k < Math.min(5, 2 + Math.floor(km / 3)); k++) {
    const a = entrance + rand(-0.4, 0.4)
    const x = cx + Math.cos(a) * 120
    const y = cy + Math.sin(a) * 120
    members.push(enemies.add('brute', x, y, { x, y, facing: entrance }))
  }
  members.push(enemies.add('captain', cx + Math.cos(back) * 60, cy + Math.sin(back) * 60, { x: cx, y: cy, facing: entrance }))
  if (km > 5) members.push(enemies.add('captain', cx, cy + 40, { x: cx, y: cy, facing: entrance }))

  return {
    title: pick(STRONGHOLDS),
    hostile: true,
    members,
    solids,
    loot,
    trigger: 430,
    reward: { gold: 20 + Math.floor(km * 3), x: cx, y: cy, message: 'The stronghold has fallen' },
    animate: flicker,
  }
}

// --- Goblin warcamp ----------------------------------------------------------

export function goblinWarcamp({ view, cx, cy, entrance, enemies, extra, km }) {
  const g = new Graphics()
  view.addChild(g)
  ring(g, cx, cy, DEST_RADIUS * 0.85, '#6f6a3a')
  const solids = []
  palisade(g, cx, cy, 200, entrance, '#3a2a1a', solids, true)

  for (const spot of around(5, 130, entrance, 0.6)) {
    drawHideTent(g, cx + spot.x, cy + spot.y, spot.a + Math.PI)
    solids.push({ x: cx + spot.x, y: cy + spot.y, radius: 22 })
  }
  // Cages for their captives
  for (const s of [-0.9, 0.9]) {
    const a = entrance + Math.PI + s
    const x = cx + Math.cos(a) * 80
    const y = cy + Math.sin(a) * 80
    g.rect(x - 12, y - 12, 24, 24).fill({ color: '#2a1f14', alpha: 0.5 })
    for (let k = -12; k <= 12; k += 6) g.moveTo(x + k, y - 12).lineTo(x + k, y + 12)
    g.stroke({ width: 2, color: '#5e3f22' })
    solids.push({ x, y, radius: 14 })
  }
  scatterBones(g, cx, cy, 140, 140, 18)
  for (const s of [-0.5, 0.5]) {
    drawSkullTotem(g, cx + Math.cos(entrance + s) * 215, cy + Math.sin(entrance + s) * 215)
  }
  const flicker = campfire(g, view, cx, cy)
  solids.push({ x: cx, y: cy, radius: 16 })

  const loot = []
  const back = entrance + Math.PI
  for (const s of [-0.3, 0.3, 0]) {
    maybeAddChest(loot, view, cx + Math.cos(back + s) * 100, cy + Math.sin(back + s) * 100, s === 0 ? 0.6 : 1)
  }

  const members = []
  const yard = { x: cx, y: cy, min: 30, max: 125 }
  for (let k = 0; k < Math.min(18, 8 + extra * 2 + Math.floor(km)); k++) {
    const a = rand(0, Math.PI * 2)
    members.push(enemies.add('goblin', cx + Math.cos(a) * 80, cy + Math.sin(a) * 80, { x: cx, y: cy, wander: yard }))
  }
  for (let k = 0; k < Math.min(5, 2 + Math.floor(km / 3)); k++) {
    const a = rand(0, Math.PI * 2)
    members.push(enemies.add('orc', cx + Math.cos(a) * 50, cy + Math.sin(a) * 50, { x: cx, y: cy, wander: { x: cx, y: cy, min: 10, max: 60 } }))
  }

  return {
    title: pick(WARCAMPS),
    hostile: true,
    members,
    solids,
    loot,
    trigger: 430,
    reward: { gold: 20 + Math.floor(km * 3), x: cx, y: cy, message: 'The warcamp is broken' },
    animate: flicker,
  }
}
