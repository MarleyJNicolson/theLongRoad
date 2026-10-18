import { Container, Graphics } from 'pixi.js'
import { Input } from './input.js'
import { Road, ROAD_WIDTH } from './road.js'
import { Scenery } from './scenery.js'
import { HorseCart } from './cart.js'
import { Peasant, PEASANT_RADIUS } from './peasant.js'
import { Enemies } from './enemies.js'
import { Stones } from './stones.js'
import { Encounters } from './encounters/index.js'
import { BARE, SLOTS, SLOT_NAMES, CONSUMABLES, BAG_SIZE, rollItem, sellValue, totalArmour, blockChance } from './items.js'

const PX_PER_METRE = 20
const MAX_HEALTH = 5 // the peasant's hearts, hurt only on foot
const MAX_CART_HEALTH = 10 // the cart takes the blows while you ride
const STAMINA_DRAIN = 1 / 4 // a full bar lasts 4 s of galloping
const STAMINA_REGEN = 1 / 7 // and refills in 7 s
const STAMINA_REGEN_DELAY = 0.8
const WINDED_UNTIL = 0.3 // once emptied, the horse must recover this much first
const KMH_PER_PX = 15 / 230
const MAX_STONES = 8
const STONE_REFILL = 1.4 // seconds to dig another stone out of the cart
const INVULNERABLE = 0.8 // seconds of grace after being hit
const GOLD_PER_KILL = 1
const ITEM_CHANCE = 0.45 // chance a chest also holds armour or a weapon
const CART_REACH = 22 // extra melee reach swinging down from the cart
const CAMERA_MARGIN = 90 // closest the player gets to the screen edge
const LOOT_REACH = 34 // how close to stand to search a container
const MOUNT_REACH = 48 // how close to the cart to climb back on
const TOAST_TIME = 1.8


export class Game {
  constructor(app, onHud) {
    this.app = app
    this.onHud = onHud
    this.input = new Input(app.canvas)
    this.world = new Container()
    app.stage.addChild(this.world)
    this.tick = (ticker) => this.update(Math.min(ticker.deltaMS / 1000, 0.05))
    app.ticker.add(this.tick)
    this.reset()
  }

  reset() {
    this.world.removeChildren().forEach((c) => c.destroy({ children: true }))

    const ground = new Container()
    const roadEdge = new Container()
    const roadFill = new Container()
    const props = new Container()
    const aim = new Graphics()
    const raiders = new Container()
    const actors = new Container()
    const canopy = new Container()
    const air = new Container()
    this.world.addChild(ground, roadEdge, roadFill, props, aim, raiders, actors, canopy, air)
    this.aim = aim

    this.road = new Road(roadEdge, roadFill)
    this.road.ensureAhead(0)
    this.enemies = new Enemies(raiders)
    this.encounters = new Encounters(props, this.road, this.enemies)
    this.encounters.place()
    this.scenery = new Scenery(ground, canopy, this.road, () => this.encounters.zones)
    this.scenery.update(0)
    this.stones = new Stones(air)
    this.air = air
    this.pickups = []

    const start = this.road.points[3]
    this.cart = new HorseCart(actors, start.x, start.y, -Math.PI / 2)
    this.peasant = new Peasant(actors)
    this.marker = new Graphics()
    actors.addChild(this.marker)
    this.onFoot = false
    this.roadIndex = 3
    this.best = 0
    this.health = MAX_HEALTH
    this.cartHealth = MAX_CART_HEALTH
    this.stamina = 1
    this.staminaRest = 0
    this.winded = false
    this.ammo = MAX_STONES
    this.refill = 0
    this.throwCooldown = 0
    this.invulnerable = 0
    this.shake = 0
    this.kills = 0
    this.gold = 0
    this.equipment = Object.fromEntries(SLOTS.map((slot) => [slot, null]))
    this.meleeCooldown = 0
    this.swings = []
    this.blockFlash = 0
    this.bag = Array(BAG_SIZE).fill(null)
    this.bagOpen = false
    this.toast = null
    this.time = 0
    this.state = 'playing'
    this.overReason = {}
    this.camX = start.x
    this.camY = start.y
  }

  update(dt) {
    if (this.state === 'over') {
      if (this.input.is('restart')) this.reset()
      this.input.endFrame()
      return
    }
    this.time += dt

    const keys = {
      up: this.input.is('up'),
      down: this.input.is('down'),
      left: this.input.is('left'),
      right: this.input.is('right'),
    }
    keys.boost = this.updateStamina(dt, keys)
    const obstacles = [...this.scenery.obstacles, ...this.encounters.obstacles]
    const interaction = this.interaction()
    if (this.input.pressed('interact') && interaction) interaction.act()
    if (this.input.pressed('bag')) this.toggleBag()

    const near = this.road.nearest(this.cart.x, this.cart.y, this.roadIndex)
    this.roadIndex = near.index
    const onRoad = near.dist < ROAD_WIDTH / 2 + 4

    this.cart.update(dt, this.onFoot ? {} : keys, onRoad, obstacles, this.onFoot)
    if (this.onFoot) {
      const aim = this.pointerWorld()
      const cartSolids = this.cart.bodies().map((b) => ({ x: b.x, y: b.y, radius: b.r }))
      this.peasant.update(dt, keys, aim.x, aim.y, [...obstacles, ...cartSolids])
    }

    if (onRoad) this.best = Math.max(this.best, near.along)
    const metres = Math.floor(this.best / PX_PER_METRE)

    this.road.ensureAhead(this.roadIndex)
    this.road.cull(this.roadIndex)
    this.encounters.place()
    this.scenery.update(this.roadIndex)

    const player = this.player()
    this.updateThrowing(dt, player)
    this.encounters.update(dt, player, this.roadIndex)
    const bodies = this.cart.bodies()
    if (this.onFoot) bodies.push({ x: this.peasant.x, y: this.peasant.y, r: PEASANT_RADIUS })
    this.enemies.update(dt, player, bodies)
    for (const fallen of this.stones.update(dt, this.enemies.list)) this.onKill(fallen)
    this.updateMelee(dt, player)
    this.updateHeldWeapon(dt)
    for (const reward of this.encounters.rewards.splice(0)) {
      this.gold += reward.gold
      this.scatter('coin', reward.gold, reward.x, reward.y)
      this.say(`The farmer thanks you: +${reward.gold} gold`)
    }
    this.updatePickups(dt)
    this.updateAttacks(dt)
    this.drawMarker(this.interaction())

    this.updateCamera(dt)
    if (this.toast && (this.toast.t -= dt) <= 0) this.toast = null
    this.onHud({
      speed: this.onFoot ? 0 : Math.round(Math.max(0, this.cart.speed) * KMH_PER_PX),
      distance: metres,
      health: this.health,
      maxHealth: MAX_HEALTH,
      cartHealth: this.cartHealth,
      maxCartHealth: MAX_CART_HEALTH,
      stamina: this.stamina,
      winded: this.winded,
      galloping: keys.boost,
      equipment: SLOTS.map((slot) => ({ slot, label: SLOT_NAMES[slot], item: this.equipment[slot] })),
      bare: BARE,
      armour: totalArmour(this.equipment),
      block: Math.round(blockChance(this.equipment) * 100),
      bag: this.bag.map((e) =>
        e && (e.type === 'gear' ? { ...e, value: sellValue(e.item) } : { ...e, item: CONSUMABLES[e.type], value: CONSUMABLES[e.type].value }),
      ),
      bagOpen: this.bagOpen,
      ammo: this.ammo,
      maxAmmo: MAX_STONES,
      kills: this.kills,
      gold: this.gold,
      onFoot: this.onFoot,
      prompt: this.interaction()?.label ?? '',
      toast: this.toast?.text ?? '',
      over: this.state === 'over',
      overTitle: this.overReason.title,
      overText: this.overReason.text,
    })
    this.input.endFrame()
  }

  // Where the peasant is right now, and how they're moving.
  player() {
    if (this.onFoot) {
      const p = this.peasant
      return { x: p.x, y: p.y, vx: p.vx, vy: p.vy }
    }
    const c = this.cart
    return { x: c.cartX, y: c.cartY, vx: Math.cos(c.heading) * c.speed, vy: Math.sin(c.heading) * c.speed }
  }

  // What pressing E would do right now, if anything.
  interaction() {
    if (!this.onFoot) {
      return { label: '', act: () => this.dismount() } // listed in the controls bar
    }
    const p = this.peasant
    let best = null
    let bestDist = LOOT_REACH
    for (const loot of this.encounters.loot) {
      const d = Math.hypot(loot.x - p.x, loot.y - p.y)
      if (d < bestDist) {
        best = loot
        bestDist = d
      }
    }
    if (best) {
      return { label: 'E – Open the treasure chest', x: best.x, y: best.y, act: () => this.search(best) }
    }
    const { cartX, cartY } = this.cart
    if (Math.hypot(cartX - p.x, cartY - p.y) < MOUNT_REACH) {
      return { label: 'E – Climb back on the cart', x: cartX, y: cartY, act: () => this.mount() }
    }
    return null
  }

  dismount() {
    const c = this.cart
    // Step down on whichever side of the cart is clear.
    const obstacles = [...this.scenery.obstacles, ...this.encounters.obstacles]
    const sides = [1, -1].map((side) => {
      const a = c.cartHeading + (side * Math.PI) / 2
      return { x: c.cartX + Math.cos(a) * 36, y: c.cartY + Math.sin(a) * 36 }
    })
    const spot =
      sides.find((s) => obstacles.every((o) => Math.hypot(o.x - s.x, o.y - s.y) > o.radius + PEASANT_RADIUS)) ?? sides[0]
    this.peasant.place(spot.x, spot.y)
    this.cart.cart.driver.visible = false
    this.onFoot = true
  }

  mount() {
    this.peasant.hide()
    this.cart.cart.driver.visible = true
    this.onFoot = false
  }

  // Open a chest: gold goes in the purse; poultices, planks and gear go in
  // the bag. Better gear is put on straight away (the old piece is bagged).
  search(chest) {
    const found = chest.open()
    const parts = []
    let gold = found.gold
    const stow = (entry, label) => {
      if (this.addToBag(entry)) return parts.push(label)
      gold += this.valueOf(entry)
      parts.push(`${label} (bag full, sold)`)
    }
    if (found.health) stow({ type: 'poultice', count: 1 }, 'a healing poultice')
    if (found.repair) stow({ type: 'planks', count: 1 }, 'planks & nails')

    let note = ''
    if (Math.random() < ITEM_CHANCE) {
      const item = rollItem(this.best / PX_PER_METRE)
      const worn = this.equipment[item.slot]
      if (!worn || item.tier > worn.tier) {
        this.equipment[item.slot] = item
        parts.push(`a ${item.name}`)
        note = ' – equipped'
        if (worn) {
          if (this.addToBag({ type: 'gear', item: worn })) {
            note += `, ${worn.name} put in your bag`
          } else {
            gold += sellValue(worn)
            note += `, sold your ${worn.name} (bag full)`
          }
        }
      } else {
        stow({ type: 'gear', item }, `a ${item.name}`)
      }
    }
    this.gold += gold
    this.scatter('coin', gold, chest.x, chest.y)
    parts.unshift(`${gold} gold`)
    this.say(`Found ${parts.length > 1 ? parts.slice(0, -1).join(', ') + ' and ' + parts.at(-1) : parts[0]}${note}`, 2)
  }

  // --- Bag -----------------------------------------------------------------

  toggleBag() {
    this.bagOpen = !this.bagOpen
  }

  valueOf(entry) {
    return entry.type === 'gear' ? sellValue(entry.item) : CONSUMABLES[entry.type].value
  }

  // Stack consumables, otherwise take the first free slot. False if full.
  addToBag(entry) {
    if (entry.type !== 'gear') {
      const stack = this.bag.find((e) => e?.type === entry.type && e.count < CONSUMABLES[entry.type].stack)
      if (stack) {
        stack.count++
        return true
      }
    }
    const free = this.bag.indexOf(null)
    if (free < 0) return false
    this.bag[free] = { ...entry }
    return true
  }

  // Click on a bag slot: put gear on (swapping with what's worn), or use
  // a poultice or planks.
  useBagItem(i) {
    const entry = this.bag[i]
    if (!entry || this.state === 'over') return
    if (entry.type === 'gear') {
      const { item } = entry
      const worn = this.equipment[item.slot]
      this.equipment[item.slot] = item
      this.bag[i] = worn ? { type: 'gear', item: worn } : null
      this.say(`Equipped ${item.name}`)
      return
    }
    if (entry.type === 'poultice') {
      if (this.health >= MAX_HEALTH) return this.say('You are already in good health')
      this.health++
      this.drop('heart', this.player().x, this.player().y)
      this.say('You bind your wounds (+1 ♥)')
    } else {
      if (this.cartHealth >= MAX_CART_HEALTH) return this.say('The cart needs no mending')
      this.cartHealth = Math.min(MAX_CART_HEALTH, this.cartHealth + 2)
      this.drop('plank', this.cart.cartX, this.cart.cartY)
      this.say('You patch up the cart (+2)')
    }
    if (--entry.count <= 0) this.bag[i] = null
  }

  // Right-click on a bag slot: sell one of it.
  sellBagItem(i) {
    const entry = this.bag[i]
    if (!entry || this.state === 'over') return
    const value = this.valueOf(entry)
    this.gold += value
    const name = entry.type === 'gear' ? entry.item.name : CONSUMABLES[entry.type].name
    if (entry.type === 'gear' || --entry.count <= 0) this.bag[i] = null
    this.say(`Sold ${name} for ${value} gold`)
  }

  // Click on an equipped slot: take it off and put it in the bag.
  unequip(slot) {
    const item = this.equipment[slot]
    if (!item || this.state === 'over') return
    if (!this.addToBag({ type: 'gear', item })) return this.say('Your bag is full')
    this.equipment[slot] = null
    this.say(`Took off ${item.name}`)
  }

  get ranged() {
    return this.equipment.ranged ?? BARE.ranged
  }

  get melee() {
    return this.equipment.melee ?? BARE.melee
  }

  // Show the equipped melee weapon in hand, on foot or on the driver's bench.
  updateHeldWeapon(dt) {
    const item = this.equipment.melee
    this.peasant.weapon.set(item)
    const held = this.cart.cart.weapon
    held.set(item)
    if (!this.onFoot) {
      const aim = this.pointerWorld()
      const { cartX, cartY, cartHeading } = this.cart
      held.update(dt, Math.atan2(aim.y - cartY, aim.x - cartX) - cartHeading)
    }
  }

  onKill(enemy) {
    this.kills++
    this.gold += GOLD_PER_KILL
    this.drop('coin', enemy.x, enemy.y)
  }

  // Right-click (or F) swings the melee weapon toward the mouse, striking
  // everything in a wide arc in front of you.
  updateMelee(dt, from) {
    this.meleeCooldown -= dt
    const weapon = this.melee
    if ((this.input.pointer.rightDown || this.input.is('melee')) && this.meleeCooldown <= 0) {
      this.meleeCooldown = weapon.cooldown
      const aim = this.pointerWorld()
      const facing = Math.atan2(aim.y - from.y, aim.x - from.x)
      const reach = weapon.reach + (this.onFoot ? PEASANT_RADIUS : CART_REACH)
      for (const e of this.enemies.list) {
        if (!e.alive || e.hidden) continue
        const dx = e.x - from.x
        const dy = e.y - from.y
        const dist = Math.hypot(dx, dy)
        let off = Math.atan2(dy, dx) - facing
        off = Math.atan2(Math.sin(off), Math.cos(off))
        if (dist > reach + e.radius || Math.abs(off) > 1.2) continue
        e.hit(dx / (dist || 1), dy / (dist || 1), weapon.damage)
        if (!e.alive) this.onKill(e)
      }
      const g = new Graphics()
      g.arc(0, 0, reach, -1.1, 1.1).stroke({ width: 5, color: '#fff4d6', alpha: 0.8, cap: 'round' })
      g.arc(0, 0, reach * 0.7, -0.8, 0.8).stroke({ width: 2, color: '#fff4d6', alpha: 0.4 })
      g.position.set(from.x, from.y)
      g.rotation = facing
      this.air.addChild(g)
      this.swings.push({ g, t: 0 })
      ;(this.onFoot ? this.peasant.weapon : this.cart.cart.weapon).swing()
    }
    this.swings = this.swings.filter((s) => {
      s.t += dt
      s.g.alpha = Math.max(0, 1 - s.t / 0.18)
      s.g.scale.set(0.85 + s.t * 1.2)
      if (s.t < 0.18) return true
      s.g.destroy()
      return false
    })
  }

  // Shift gallops while the horse has wind; empty the bar and it's winded
  // until it has recovered a little. Returns whether it's galloping now.
  updateStamina(dt, keys) {
    const galloping = this.input.is('boost') && !this.onFoot && !this.winded && keys.up && this.cart.speed > 20
    if (galloping) {
      this.stamina = Math.max(0, this.stamina - STAMINA_DRAIN * dt)
      this.staminaRest = 0
      if (this.stamina === 0) this.winded = true
    } else {
      this.staminaRest += dt
      if (this.staminaRest > STAMINA_REGEN_DELAY) this.stamina = Math.min(1, this.stamina + STAMINA_REGEN * dt)
      if (this.winded && this.stamina >= WINDED_UNTIL) this.winded = false
    }
    return galloping
  }

  say(text, extra = 0) {
    this.toast = { text, t: TOAST_TIME + extra }
  }

  // Pulsing ring round whatever E would act on.
  drawMarker(interaction) {
    const m = this.marker.clear()
    if (!interaction?.x) return
    const r = 16 + Math.sin(this.time * 6) * 2.5
    m.circle(interaction.x, interaction.y, r).stroke({ width: 2, color: '#fff4d6', alpha: 0.8 })
  }

  // Where the mouse is, in world coordinates.
  pointerWorld() {
    return {
      x: this.input.pointer.x - this.world.x,
      y: this.input.pointer.y - this.world.y,
    }
  }

  updateThrowing(dt, from) {
    this.throwCooldown -= dt
    if (this.ammo < MAX_STONES) {
      this.refill += dt
      if (this.refill >= STONE_REFILL) {
        this.refill = 0
        this.ammo++
      }
    }

    const weapon = this.ranged
    const target = this.pointerWorld()
    if (this.input.pointer.down && this.throwCooldown <= 0 && this.ammo > 0) {
      this.stones.throw(from.x, from.y, target.x, target.y, from.vx, from.vy, weapon)
      this.ammo--
      this.throwCooldown = weapon.cooldown
    }

    // Dotted aim line out to the throwing range.
    const dx = target.x - from.x
    const dy = target.y - from.y
    const len = Math.hypot(dx, dy) || 1
    const reach = Math.min(weapon.range, len)
    const a = this.aim.clear()
    for (let d = 30; d < reach; d += 18) {
      a.circle(from.x + (dx / len) * d, from.y + (dy / len) * d, 1.8)
    }
    a.fill({ color: '#fff4d6', alpha: this.ammo > 0 ? 0.55 : 0.15 })
    a.circle(from.x + (dx / len) * reach, from.y + (dy / len) * reach, 7).stroke({ width: 1.5, color: '#fff4d6', alpha: 0.7 })
  }

  // A coin or heart pops up, spinning upward as it fades.
  drop(kind, x, y) {
    const g = new Graphics()
    if (kind === 'coin') {
      g.circle(0, 0, 7).fill('#e8b923').circle(0, 0, 7).stroke({ width: 1.5, color: '#9c7412' })
      g.circle(-2, -2, 2.2).fill({ color: '#fff4b0', alpha: 0.8 })
    } else if (kind === 'plank') {
      g.roundRect(-11, -7, 22, 5, 1).fill('#a8875c').roundRect(-11, 1, 22, 5, 1).fill('#8b6236')
      g.circle(-7, -4.5, 1).circle(7, -4.5, 1).circle(-7, 3.5, 1).circle(7, 3.5, 1).fill('#d0d0d0')
    } else {
      g.circle(-4, -2, 5).fill('#e0463a').circle(4, -2, 5).fill('#e0463a')
      g.poly([-8.5, 0, 8.5, 0, 0, 9]).fill('#e0463a')
      g.circle(-5, -4, 1.6).fill({ color: '#ffffff', alpha: 0.7 })
    }
    g.position.set(x, y)
    this.air.addChild(g)
    this.pickups.push({ g, kind, t: 0 })
  }

  scatter(kind, count, x, y) {
    for (let k = 0; k < count; k++) {
      const a = (k / count) * Math.PI * 2
      this.drop(kind, x + (count > 1 ? Math.cos(a) * 14 : 0), y + (count > 1 ? Math.sin(a) * 14 : 0))
    }
  }

  updatePickups(dt) {
    this.pickups = this.pickups.filter((p) => {
      p.t += dt
      p.g.y -= dt * 45
      if (p.kind === 'coin') p.g.scale.x = Math.cos(p.t * 10)
      else p.g.scale.set(1 + Math.sin(p.t * 12) * 0.12)
      p.g.alpha = Math.max(0, 1 - Math.max(0, p.t - 0.5) / 0.5)
      if (p.t < 1) return true
      p.g.destroy()
      return false
    })
  }

  updateAttacks(dt) {
    this.invulnerable -= dt
    const { cart, peasant } = this
    for (const e of this.enemies.list) {
      if (!e.alive || e.attackCooldown > 0) continue
      // On the cart they hack at the horse and cart; on foot, at you.
      const inReach = this.onFoot
        ? Math.hypot(e.x - peasant.x, e.y - peasant.y) < e.radius + PEASANT_RADIUS + 5
        : Math.hypot(e.x - cart.cartX, e.y - cart.cartY) < e.radius + 26 ||
          Math.hypot(e.x - cart.x, e.y - cart.y) < e.radius + 20
      if (!inReach) continue

      e.attackCooldown = 1.2
      if (this.invulnerable > 0) continue
      // Armour only protects the peasant, not the cart.
      if (this.onFoot && Math.random() < blockChance(this.equipment)) {
        this.blockFlash = 0.25
        continue
      }
      this.invulnerable = INVULNERABLE
      this.shake = 0.3
      const goblins = e.type === 'goblin'
      if (this.onFoot) {
        if (--this.health <= 0) {
          goblins
            ? this.end('Overrun by goblins', 'the goblins caught you on foot')
            : this.end('Robbed by bandits', 'the bandits cut you down by the road')
        }
      } else if (--this.cartHealth <= 0) {
        goblins
          ? this.end('Cart torn apart', 'the goblins hacked your cart to kindling')
          : this.end('Cart smashed', 'the bandits smashed your cart and took the horse')
      }
    }

    const hurt = this.invulnerable > INVULNERABLE - 0.2
    const blink = this.invulnerable > 0 && Math.floor(this.invulnerable * 12) % 2 ? 0.6 : 1
    const victims = this.onFoot ? [peasant.view] : [cart.horse, cart.cart]
    for (const v of [peasant.view, cart.horse, cart.cart]) {
      const hit = victims.includes(v)
      v.tint = hit && hurt ? 0xff6655 : 0xffffff
      v.alpha = hit ? blink : 1
    }
    // A blow turned aside by armour flashes steel-blue.
    this.blockFlash -= dt
    if (this.blockFlash > 0) peasant.view.tint = 0x9cc8ff
  }

  end(title, text) {
    if (this.state === 'over') return
    this.state = 'over'
    this.cart.speed = 0
    this.overReason = { title, text }
    this.aim.clear()
    this.marker.clear()
  }

  updateCamera(dt) {
    const { cart, input } = this
    const halfW = this.app.screen.width / 2
    const halfH = this.app.screen.height / 2
    const clamp = (v, min, max) => Math.max(min, Math.min(max, v))

    // Follow the peasant on foot; on the cart, look ahead along the road.
    let tx, ty, keep
    if (this.onFoot) {
      tx = this.peasant.x
      ty = this.peasant.y
      keep = [this.peasant]
    } else {
      const lead = Math.max(0, cart.speed) * 0.7
      tx = cart.x + Math.cos(cart.heading) * lead
      ty = cart.y + Math.sin(cart.heading) * lead
      keep = [cart, { x: cart.cartX, y: cart.cartY }]
    }

    // Pan toward the mouse: at the edge of the screen the view shifts as far
    // as it can while still keeping the player in shot.
    if (input.pointer.active) {
      tx += clamp((input.pointer.x - halfW) / halfW, -1, 1) * (halfW - CAMERA_MARGIN)
      ty += clamp((input.pointer.y - halfH) / halfH, -1, 1) * (halfH - CAMERA_MARGIN)
    }

    const k = 1 - Math.exp(-dt * 4)
    this.camX += (tx - this.camX) * k
    this.camY += (ty - this.camY) * k

    const reachX = Math.max(0, halfW - CAMERA_MARGIN)
    const reachY = Math.max(0, halfH - CAMERA_MARGIN)
    const xs = keep.map((p) => p.x)
    const ys = keep.map((p) => p.y)
    this.camX = clamp(this.camX, Math.max(...xs) - reachX, Math.min(...xs) + reachX)
    this.camY = clamp(this.camY, Math.max(...ys) - reachY, Math.min(...ys) + reachY)

    this.shake = Math.max(0, this.shake - dt)
    const jolt = this.shake * 20
    this.world.position.set(
      Math.round(halfW - this.camX + (Math.random() - 0.5) * jolt),
      Math.round(halfH - this.camY + (Math.random() - 0.5) * jolt),
    )
  }

  destroy() {
    this.app.ticker.remove(this.tick)
    this.input.destroy()
  }
}
