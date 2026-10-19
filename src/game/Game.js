import { Container, Graphics, Sprite, Texture, TilingSprite } from 'pixi.js'
import { Input } from './input.js'
import { Road, ROAD_WIDTH } from './road.js'
import { Scenery } from './scenery.js'
import { HorseCart } from './cart.js'
import { Peasant, PEASANT_RADIUS, DASH_TIME } from './peasant.js'
import { Enemies } from './enemies.js'
import { Stones } from './stones.js'
import { EnemyArrows } from './enemyArrows.js'
import { Encounters } from './encounters/index.js'
import { WORLD_ZOOM } from './pixelArt.js'
import { grassTexture } from './textures.js'
import { stageAt, threatAt } from './threat.js'
import { AMMO, BARE, SLOTS, SLOT_NAMES, CONSUMABLES, BAG_SIZE, CART_SIZE, rollItem, sellValue, totalArmour, blockChance } from './items.js'

const PX_PER_METRE = 20
const MAX_HEALTH = 5 // the peasant's hearts, hurt only on foot
const MAX_CART_HEALTH = 10 // the cart takes the blows while you ride
const STAMINA_DRAIN = 1 / 4 // a full bar lasts 4 s of galloping
const STAMINA_REGEN = 1 / 7 // and refills in 7 s
const STAMINA_REGEN_DELAY = 0.8
const WINDED_UNTIL = 0.3 // once emptied, the horse must recover this much first
const KMH_PER_PX = 15 / 230
const INVULNERABLE = 0.8 // seconds of grace after being hit
const STAGE_BANNER_TIME = 4
const ITEM_CHANCE = 0.45 // chance a chest also holds armour or a weapon
const CART_REACH = 22 // extra melee reach swinging down from the cart
const CAMERA_MARGIN = 90 // closest the player gets to the screen edge
const LOOT_REACH = 34 // how close to stand to search a container
const MOUNT_REACH = 48 // how close to the cart to climb back on
const TOAST_TIME = 1.8
// The peasant's own stamina (the horse has its own): sprinting drains it,
// a dash takes a chunk at once, and it comes back after a short rest.
const SPRINT_DRAIN = 1 / 4.5 // a full bar lasts 4.5 s of sprinting
const DASH_COST = 0.3
const DASH_COOLDOWN = 0.45
const BREATH_REGEN = 1 / 3
const BREATH_REGEN_DELAY = 0.6
const TRADE_REACH = 46 // how close to stand to a trader
const STORAGE_REACH = 90 // how close to stand to the cart to use its storage


// Blend two 0xRRGGBB colours; snaps to `b` once close enough.
function mixColour(a, b, t) {
  const ch = (c, shift) => (c >> shift) & 0xff
  let done = true
  const mixed = [16, 8, 0].reduce((out, shift) => {
    const from = ch(a, shift)
    const to = ch(b, shift)
    const v = Math.round(from + (to - from) * t)
    if (Math.abs(to - v) > 1) done = false
    return out | (v << shift)
  }, 0)
  return done ? b : mixed
}

// A bag or cart slot as the HUD sees it.
function snapshot(e) {
  if (!e) return null
  return e.type === 'gear'
    ? { ...e, value: sellValue(e.item) }
    : { ...e, item: CONSUMABLES[e.type], value: CONSUMABLES[e.type].value }
}

export class Game {
  constructor(app, onHud) {
    this.app = app
    this.onHud = onHud
    this.input = new Input(app.canvas)
    // The ground: a screen-filling sheet of grass texture behind the world,
    // scrolling with it and tinted to the region's colour (part of the
    // scene, so the pixel-art pass covers it). Plain colour without a canvas.
    const grass = grassTexture()
    this.backdrop = grass ? new TilingSprite({ texture: grass }) : new Sprite(Texture.WHITE)
    this.world = new Container()
    app.stage.addChild(this.backdrop, this.world)
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
    this.fx = new Container() // dust and such at ground level
    this.world.addChild(ground, roadEdge, roadFill, props, aim, this.fx, raiders, actors, canopy, air)
    this.aim = aim

    this.road = new Road(roadEdge, roadFill)
    this.road.ensureAhead(0)
    this.enemies = new Enemies(raiders)
    this.encounters = new Encounters(props, raiders, this.road, this.enemies)
    this.encounters.place()
    this.scenery = new Scenery(ground, raiders, this.road, () => this.encounters.zones) // trees stand among the people
    this.encounters.onNewZones = (zones) => this.scenery.clear(zones)
    this.scenery.update(0)
    this.stones = new Stones(air)
    this.enemyArrows = new EnemyArrows(air)
    this.air = air
    this.pickups = []

    const start = this.road.points[3]
    this.cart = new HorseCart(raiders, start.x, start.y, -Math.PI / 2) // depth-sorted with the people
    this.peasant = new Peasant(raiders) // among the raiders, so they overlap by depth
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
    this.breath = 1 // the peasant's stamina, 0..1
    this.breathRest = 0
    this.outOfBreath = false
    this.dashCooldown = 0
    this.dashGuard = 0 // untouchable while dashing
    this.puffs = []
    this.throwCooldown = 0
    this.invulnerable = 0
    this.shake = 0
    this.kills = 0
    this.gold = 0
    this.equipment = Object.fromEntries(SLOTS.map((slot) => [slot, null]))
    this.meleeCooldown = 0
    this.active = 'ranged' // which weapon is in hand: 'ranged' or 'melee'
    this.swings = []
    this.strikes = [] // melee blows waiting to land (see updateMelee)
    this.blockFlash = 0
    this.bag = Array(BAG_SIZE).fill(null)
    this.bagOpen = false
    this.cartStore = Array(CART_SIZE).fill(null)
    // Setting out with a few stones to throw
    this.bag[0] = { type: 'stones', count: 20 }
    this.cartStore[0] = { type: 'stones', count: 30 }
    this.outOfAmmoAt = -9
    this.cartOpen = false
    this.trading = null // the trader whose wares are on show
    this.toast = null
    this.time = 0
    this.state = 'playing'
    this.overReason = {}
    this.camX = start.x
    this.camY = start.y
    this.stage = stageAt(0)
    this.banner = { title: this.stage.name, sub: this.stage.biome.tagline, t: STAGE_BANNER_TIME }
    this.groundColour = this.stage.biome.ground
    this.backdrop.tint = this.groundColour
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
    if (!this.onFoot) this.updateBreath(dt, keys)
    this.updatePuffs(dt)
    const obstacles = [...this.scenery.obstacles, ...this.encounters.obstacles]
    const interaction = this.interaction()
    if (this.input.pressed('interact') && interaction) interaction.act()
    if (this.input.pressed('bag')) this.toggleBag()
    if (this.input.pressed('cart')) this.toggleCart()
    if (this.cartOpen && !this.nearCart()) {
      this.cartOpen = false
      this.say('You walk away from the cart')
    }
    if (this.input.pressed('close')) {
      this.trading = null
      this.bagOpen = false
      this.cartOpen = false
    }
    if (this.input.pressed('swap')) this.swapWeapon()

    const near = this.road.nearest(this.cart.x, this.cart.y, this.roadIndex)
    this.roadIndex = near.index
    const onMainRoad = near.dist < ROAD_WIDTH / 2 + 4
    const onRoad = onMainRoad || this.encounters.onSideRoad(this.cart.x, this.cart.y)

    this.cart.update(dt, this.onFoot ? {} : keys, onRoad, obstacles, this.onFoot)
    if (this.onFoot) {
      const aim = this.pointerWorld()
      const cartSolids = this.cart.bodies().map((b) => ({ x: b.x, y: b.y, radius: b.r }))
      const sprinting = this.updateBreath(dt, keys)
      this.peasant.update(dt, keys, aim.x, aim.y, [...obstacles, ...cartSolids], sprinting)
      if (this.peasant.dashing && Math.random() < 0.6) this.puff(this.peasant.x, this.peasant.y)
    }

    if (onMainRoad) this.best = Math.max(this.best, near.along)
    const metres = Math.floor(this.best / PX_PER_METRE)

    this.road.ensureAhead(this.roadIndex)
    this.road.cull(this.roadIndex)
    this.encounters.place()
    this.scenery.update(this.roadIndex, 3)

    const player = this.player()
    this.updateThrowing(dt, player)
    this.encounters.update(dt, player, this.roadIndex)
    // On foot, the cart is just in the way and raiders go round it.
    const bodies = this.cart.bodies().map((b) => ({ ...b, slide: this.onFoot }))
    if (this.onFoot) bodies.push({ x: this.peasant.x, y: this.peasant.y, r: PEASANT_RADIUS })
    // On foot they'll hunt you down however far you go; a cart can outrun them.
    // Whatever raiders' weapons and arrows can hurt: you on foot, the horse
    // and cart while you ride.
    const targets = this.onFoot ? [{ x: this.peasant.x, y: this.peasant.y, r: PEASANT_RADIUS }] : this.cart.bodies()
    const { volleys, blows } = this.enemies.update(dt, player, bodies, this.onFoot, targets)
    volleys.forEach((v) => this.enemyArrows.fire(v))
    for (const blow of blows) this.hurt(blow.damage, blow.faction, false)
    for (const hit of this.enemyArrows.update(dt, targets, [...this.scenery.obstacles, ...this.encounters.obstacles])) {
      this.hurt(hit.damage, hit.faction, true)
    }
    for (const fallen of this.stones.update(dt, this.enemies.list)) this.onKill(fallen)
    this.updateMelee(dt, player)
    this.updateHeldWeapon(dt)
    for (const reward of this.encounters.rewards.splice(0)) {
      this.gold += reward.gold
      this.scatter('coin', reward.gold, reward.x, reward.y)
      this.say(`${reward.message ?? 'The farmer thanks you'}: +${reward.gold} gold`, 1.5)
    }
    this.updatePickups(dt)
    this.updateAttacks(dt)
    this.drawMarker(this.interaction())

    this.updateStage(dt, metres)
    // Trees between you and the camera fade so you can see yourself
    const me = this.player()
    this.scenery.fadeAround(me.x, me.y)
    this.encounters.fadeAround(me.x, me.y)
    this.updateCamera(dt)
    if (this.toast && (this.toast.t -= dt) <= 0) this.toast = null
    this.onHud({
      speed: this.onFoot ? 0 : Math.round(Math.max(0, this.cart.speed) * KMH_PER_PX),
      distance: metres,
      stage: this.stage.name,
      stageNumber: this.stage.number,
      threat: threatAt(metres).level,
      banner: this.banner && this.banner.t > 0 ? this.banner : null,
      health: this.health,
      maxHealth: MAX_HEALTH,
      cartHealth: this.cartHealth,
      maxCartHealth: MAX_CART_HEALTH,
      stamina: this.stamina,
      winded: this.winded,
      breath: this.breath,
      outOfBreath: this.outOfBreath,
      sprinting: this.onFoot && this.input.is('boost') && !this.outOfBreath && this.breath > 0,
      galloping: keys.boost,
      equipment: SLOTS.map((slot) => ({ slot, label: SLOT_NAMES[slot], item: this.equipment[slot] })),
      bare: BARE,
      armour: totalArmour(this.equipment),
      block: Math.round(blockChance(this.equipment) * 100),
      active: this.active,
      bag: this.bag.map(snapshot),
      bagOpen: this.bagOpen,
      cartStore: this.cartStore.map(snapshot),
      cartOpen: this.cartOpen,
      nearCart: this.nearCart(),
      trade: this.tradeView(),
      ammo: this.ammoCount(this.ranged.ammo),
      ammoFrom: this.onFoot ? 'bag' : 'cart + bag',
      ammoKind: this.ranged.ammo,
      ammoName: AMMO[this.ranged.ammo].name,
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

  // Crossing into a new region: announce it and fade the land to its colour.
  updateStage(dt, metres) {
    const stage = stageAt(metres)
    if (stage.index !== this.stage.index) {
      this.stage = stage
      this.banner = { title: stage.name, sub: `Stage ${stage.number} · ${stage.biome.tagline}`, t: STAGE_BANNER_TIME }
    }
    if (this.banner) this.banner.t -= dt
    const target = stage.biome.ground
    if (this.groundColour !== target) {
      this.groundColour = mixColour(this.groundColour, target, 1 - Math.exp(-dt * 1.5))
      this.backdrop.tint = this.groundColour
    }
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
    if (best?.kind === 'arrows') {
      return { label: 'E – Take arrows from the barrel', x: best.x, y: best.y, act: () => this.raidBarrel(best) }
    }
    if (best) {
      return { label: 'E – Open the treasure chest', x: best.x, y: best.y, act: () => this.search(best) }
    }
    const trader = this.encounters.traders.find((t) => Math.hypot(t.x - p.x, t.y - p.y) < TRADE_REACH)
    if (trader) {
      const open = this.trading === trader
      return {
        label: open ? 'E – Stop trading' : `E – Trade with the ${trader.name.toLowerCase()}`,
        x: trader.x,
        y: trader.y,
        act: () => (this.trading = open ? null : trader),
      }
    }
    const rock = this.scenery.gatherableNear(p.x, p.y, LOOT_REACH)
    if (rock) {
      return { label: 'E – Gather stones', x: rock.x, y: rock.y, act: () => this.gather(rock) }
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
    for (const kind of ['arrows', 'bolts']) {
      if (!found[kind]) continue
      const lost = this.stash(this.bag, kind, found[kind])
      parts.push(lost ? `${found[kind] - lost} ${kind} (bag full, ${lost} left behind)` : `${found[kind]} ${kind}`)
    }

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

  // --- Ammunition ------------------------------------------------------------

  // Where you can reach ammunition from: the cart's storage (then your bag)
  // while riding, only your bag on foot.
  ammoSources() {
    return this.onFoot ? [this.bag] : [this.cartStore, this.bag]
  }

  ammoCount(kind) {
    return this.ammoSources().reduce((n, list) => n + list.reduce((m, e) => m + (e?.type === kind ? e.count : 0), 0), 0)
  }

  // Spend one round from the first stack found. False if there's none.
  takeAmmo(kind) {
    for (const list of this.ammoSources()) {
      for (let k = list.length - 1; k >= 0; k--) {
        const e = list[k]
        if (e?.type !== kind) continue
        if (--e.count <= 0) list[k] = null
        return true
      }
    }
    return false
  }

  // Put `count` of a stackable into a bag or cart: topping up part stacks
  // first, then filling empty slots. Returns how many didn't fit.
  stash(list, type, count) {
    const max = CONSUMABLES[type].stack
    for (const e of list) {
      if (!count) break
      if (e?.type !== type || e.count >= max) continue
      const moved = Math.min(max - e.count, count)
      e.count += moved
      count -= moved
    }
    while (count > 0) {
      const free = list.indexOf(null)
      if (free < 0) break
      const moved = Math.min(max, count)
      list[free] = { type, count: moved }
      count -= moved
    }
    return count
  }

  // How many more of a stackable would fit.
  roomFor(list, type) {
    const max = CONSUMABLES[type].stack
    return list.reduce((n, e) => n + (e === null ? max : e.type === type ? max - e.count : 0), 0)
  }

  // E at a rock or boulder: prise out what stones your bag has room for.
  gather(rock) {
    const take = Math.min(rock.gather, this.roomFor(this.bag, 'stones'))
    if (!take) return this.say('Your bag has no room for more stones')
    this.stash(this.bag, 'stones', take)
    this.scenery.quarry(rock, take)
    this.say(`Gathered ${take} stones${rock.gather ? ` – your bag is full, ${rock.gather} left` : ''}`)
  }

  // E at an arrow barrel: take what fits, leave the rest in the barrel.
  raidBarrel(barrel) {
    const took = []
    for (const kind of ['arrows', 'bolts']) {
      const have = barrel.contents[kind]
      if (!have) continue
      const left = this.stash(this.bag, kind, have)
      if (have - left) took.push(`${have - left} ${kind}`)
      barrel.contents[kind] = left
    }
    barrel.update()
    if (!took.length) return this.say('Your bag is full')
    this.say(`Took ${took.join(' and ')}${barrel.opened ? '' : ' – your bag is full, some are left'}`)
  }

  // --- Bag -----------------------------------------------------------------

  // --- Trading ---------------------------------------------------------------

  // What the open trader's stall looks like to the HUD, or null.
  tradeView() {
    const t = this.trading
    if (!t) return null
    const p = this.peasant
    // Walking off (or climbing on the cart) ends the conversation.
    if (!this.onFoot || !t.open || Math.hypot(t.x - p.x, t.y - p.y) > TRADE_REACH + 40) {
      this.trading = null
      return null
    }
    return {
      name: t.name,
      offers: t.stock.map((offer, i) => {
        const price = this.priceOf(offer)
        const why = this.cannotBuy(offer, price)
        const item = offer.kind === 'gear' ? offer.item : offer.kind === 'consumable' ? CONSUMABLES[offer.type] : null
        const name = offer.qty ? `${offer.qty} ${item.name}` : (item?.name ?? offer.name)
        return { i, kind: offer.kind, type: offer.type, name, item, price, sold: !!offer.sold, why }
      }),
    }
  }

  priceOf(offer) {
    if (offer.type === 'repair') return offer.price * (MAX_CART_HEALTH - this.cartHealth)
    if (offer.type === 'heal') return offer.price * (MAX_HEALTH - this.health)
    return offer.price
  }

  // Why an offer can't be bought right now, or '' if it can.
  cannotBuy(offer, price) {
    if (offer.sold) return 'Sold'
    if (offer.type === 'repair' && this.cartHealth >= MAX_CART_HEALTH) return 'Cart is sound'
    if (offer.type === 'heal' && this.health >= MAX_HEALTH) return 'Already hale'
    if (price > this.gold) return 'Not enough gold'
    if (offer.kind === 'gear' && !this.bag.includes(null)) return 'Bag full'
    if (offer.kind === 'consumable' && this.roomFor(this.bag, offer.type) < (offer.qty ?? 1)) return 'Bag full'
    return ''
  }

  buy(i) {
    const offer = this.trading?.stock[i]
    if (!offer) return
    const price = this.priceOf(offer)
    if (this.cannotBuy(offer, price)) return
    this.gold -= price
    if (offer.kind === 'gear') {
      this.addToBag({ type: 'gear', item: offer.item })
      offer.sold = true
      this.say(`Bought ${offer.item.name} – it's in your bag`)
    } else if (offer.kind === 'consumable') {
      this.stash(this.bag, offer.type, offer.qty ?? 1)
      this.say(`Bought ${offer.qty ?? 'a'} ${CONSUMABLES[offer.type].name}`)
    } else if (offer.type === 'repair') {
      this.cartHealth = MAX_CART_HEALTH
      this.say('The wheelwright sets your cart to rights')
    } else if (offer.type === 'heal') {
      this.health = MAX_HEALTH
      this.say('The healer binds your wounds')
    }
  }

  toggleBag() {
    this.bagOpen = !this.bagOpen
  }

  // --- Cart storage ----------------------------------------------------------

  // The cart's storage can only be reached from the cart or right beside it.
  nearCart() {
    if (!this.onFoot) return true
    return Math.hypot(this.cart.cartX - this.peasant.x, this.cart.cartY - this.peasant.y) < STORAGE_REACH
  }

  toggleCart() {
    if (this.cartOpen) return (this.cartOpen = false)
    if (!this.nearCart()) return this.say('You need to be at the cart')
    this.cartOpen = true
    this.bagOpen = true // so there's somewhere to move things to
  }

  container(name) {
    return name === 'cart' ? this.cartStore : this.bag
  }

  // Pour a stack of supplies into any part-filled stacks of the same kind.
  // Returns how many are left over.
  topUp(list, entry) {
    const max = CONSUMABLES[entry.type].stack
    for (const other of list) {
      if (!entry.count) break
      if (other === entry || other?.type !== entry.type) continue
      const moved = Math.min(max - other.count, entry.count)
      other.count += moved
      entry.count -= moved
    }
    return entry.count
  }

  // Move something between (or within) the bag and the cart. With a slot
  // `j` it goes there (swapping with whatever is in it); without, it goes
  // wherever it fits. Anything involving the cart needs you to be at it.
  moveItem(from, i, to, j = null) {
    if (this.state === 'over') return
    if ((from === 'cart' || to === 'cart') && !(this.cartOpen && this.nearCart())) return this.say('You need to be at the cart')
    const src = this.container(from)
    const dst = this.container(to)
    const entry = src[i]
    if (!entry || (from === to && (j === null || j === i))) return
    if (j !== null) {
      const there = dst[j]
      if (there && there.type === entry.type && entry.type !== 'gear') {
        // Same supplies: stack them, leaving any overflow where it was
        const moved = Math.min(CONSUMABLES[entry.type].stack - there.count, entry.count)
        there.count += moved
        entry.count -= moved
        if (!entry.count) src[i] = null
      } else {
        dst[j] = entry
        src[i] = there
      }
      return
    }
    if (entry.type !== 'gear' && this.topUp(dst, entry) === 0) {
      src[i] = null
      return
    }
    const free = dst.indexOf(null)
    if (free < 0) return this.say(to === 'cart' ? 'The cart is full' : 'Your bag is full')
    dst[free] = entry
    src[i] = null
  }

  valueOf(entry) {
    if (entry.type === 'gear') return sellValue(entry.item)
    const info = CONSUMABLES[entry.type]
    return info.ammo ? Math.floor((entry.count / 10) * info.value) : info.value
  }

  // Stack consumables, otherwise take the first free slot. False if full.
  addToBag(entry) {
    if (entry.type !== 'gear') {
      if (this.roomFor(this.bag, entry.type) < (entry.count ?? 1)) return false
      this.stash(this.bag, entry.type, entry.count ?? 1)
      return true
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
    if (CONSUMABLES[entry.type].ammo) return this.say('Ammunition is used up as you shoot')
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

  // Right-click on a bag (or cart) slot: sell one of it.
  sellBagItem(i, from = 'bag') {
    const list = this.container(from)
    const entry = list[i]
    if (!entry || this.state === 'over') return
    if (from === 'cart' && !(this.cartOpen && this.nearCart())) return
    const value = this.valueOf(entry)
    this.gold += value
    const info = CONSUMABLES[entry.type]
    const name = entry.type === 'gear' ? entry.item.name : info.ammo ? `${entry.count} ${info.name.toLowerCase()}` : info.name
    // Ammunition goes as a whole stack; everything else one at a time
    if (entry.type === 'gear' || info.ammo || --entry.count <= 0) list[i] = null
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

  // Show the equipped weapons in hand, on foot or on the driver's bench:
  // melee in the right hand, a bow, crossbow or sling in the left.
  updateHeldWeapon(dt) {
    const melee = this.equipment.melee
    const ranged = this.equipment.ranged
    const stocked = this.ammoCount(this.ranged.ammo) > 0
    // The next shot is drawn back as the weapon reloads: full draw = ready
    const draw = Math.min(1, Math.max(0, 1 - this.throwCooldown / this.ranged.cooldown))
    const { weapon, bow } = this.cart.cart
    // Only the weapon in hand is drawn; the other is slung on your back.
    const inHand = this.active
    const rangedInHand = inHand === 'ranged' ? ranged : null
    for (const holder of [this.peasant.weapon, weapon]) holder.set(inHand === 'melee' ? melee : null)
    this.peasant.bow.set(rangedInHand, stocked, draw)
    bow.set(rangedInHand, stocked && draw >= 1)
    if (!this.onFoot) {
      const aim = this.pointerWorld()
      const { cartX, cartY, cartHeading } = this.cart
      const facing = Math.atan2(aim.y - cartY, aim.x - cartX) - cartHeading
      weapon.update(dt, facing)
      bow.update(dt, facing)
    }
  }

  // Q: put away one weapon and take out the other.
  swapWeapon() {
    this.active = this.active === 'ranged' ? 'melee' : 'ranged'
    const weapon = this.active === 'ranged' ? this.ranged : this.melee
    this.say(`${weapon.name} in hand`)
  }

  onKill(enemy) {
    this.kills++
    this.gold += enemy.gold
    this.scatter('coin', enemy.gold, enemy.x, enemy.y)
  }

  // Attacking with the melee weapon in hand. Each weapon fights its own way
  // (its `style`): a single swing; a fast double cut; a long, narrow jab
  // that can run through two foes; or a wound-up heavy blow. A click lines
  // up one or more strikes, each landing when the animation does.
  updateMelee(dt, from) {
    this.meleeCooldown -= dt
    const weapon = this.melee
    const holder = this.onFoot ? this.peasant.weapon : this.cart.cart.weapon
    if (this.active === 'melee' && this.input.pointer.down && this.meleeCooldown <= 0) {
      this.meleeCooldown = weapon.cooldown
      const aim = this.pointerWorld()
      const facing = Math.atan2(aim.y - from.y, aim.x - from.x)
      const blow = { facing, reach: weapon.reach, arc: weapon.arc, damage: weapon.damage }
      if (weapon.style === 'double') {
        this.strikes.push({ at: 0, ...blow, fx: 'slash', anim: () => holder.play('slash') })
        this.strikes.push({ at: weapon.gap, ...blow, fx: 'slash', back: true, anim: () => holder.play('slash', { back: true }) })
      } else if (weapon.style === 'jab') {
        holder.play('jab')
        this.strikes.push({ at: 0.07, ...blow, fx: 'jab', pierce: weapon.pierce })
      } else if (weapon.style === 'heavy') {
        holder.play('heavy', { windup: weapon.windup })
        this.strikes.push({ at: weapon.windup, ...blow, fx: 'heavy', force: weapon.force })
      } else {
        this.strikes.push({ at: 0, ...blow, fx: 'swing', anim: () => holder.play('swing') })
      }
    }

    for (const s of this.strikes) {
      s.at -= dt
      if (s.at <= 0) {
        s.anim?.()
        this.strike(this.player(), s)
      }
    }
    this.strikes = this.strikes.filter((s) => s.at > 0)

    this.swings = this.swings.filter((s) => {
      s.t += dt
      s.g.alpha = Math.max(0, 1 - s.t / s.life)
      s.g.scale.set(0.85 + (s.t / s.life) * 0.22)
      if (s.t < s.life) return true
      s.g.destroy()
      return false
    })
  }

  // Land one blow: hit whatever is in its reach and arc (a jab: in a narrow
  // line, the nearest `pierce` of them), and show it.
  strike(from, s) {
    const reach = s.reach + (this.onFoot ? PEASANT_RADIUS : CART_REACH)
    const ax = Math.cos(s.facing)
    const ay = Math.sin(s.facing)
    const targets = []
    for (const e of this.enemies.list) {
      if (!e.alive || e.hidden) continue
      const dx = e.x - from.x
      const dy = e.y - from.y
      const dist = Math.hypot(dx, dy)
      if (dist > reach + e.radius) continue
      if (s.fx === 'jab') {
        // A line, not a wedge: ahead of you and close to the shaft
        const along = dx * ax + dy * ay
        const across = Math.abs(dx * -ay + dy * ax)
        if (along < 0 || across > e.radius + 6) continue
      } else {
        let off = Math.atan2(dy, dx) - s.facing
        off = Math.atan2(Math.sin(off), Math.cos(off))
        if (Math.abs(off) > s.arc + 0.1) continue
      }
      targets.push({ e, dist, dx, dy })
    }
    targets.sort((a, b) => a.dist - b.dist)
    const hit = s.pierce ? targets.slice(0, s.pierce) : targets
    for (const { e, dist, dx, dy } of hit) {
      e.hit(dx / (dist || 1), dy / (dist || 1), s.damage, s.force ?? 1)
      if (!e.alive) this.onKill(e)
    }
    if (s.fx === 'heavy' && hit.length) this.shake = Math.max(this.shake, 0.15)

    // The visible stroke of the blow
    const g = new Graphics()
    const paint = { color: '#fff4d6', cap: 'round' }
    if (s.fx === 'jab') {
      g.moveTo(reach * 0.35, 0).lineTo(reach, 0).stroke({ ...paint, width: 3, alpha: 0.85 })
      g.poly([reach + 6, 0, reach - 3, -4, reach - 3, 4]).fill({ color: '#fff4d6', alpha: 0.9 })
    } else if (s.fx === 'heavy') {
      g.arc(0, 0, reach, -s.arc, s.arc).stroke({ ...paint, width: 9, alpha: 0.85 })
      g.arc(0, 0, reach * 0.72, -s.arc * 0.85, s.arc * 0.85).stroke({ ...paint, width: 3, alpha: 0.45 })
      for (let k = 0; k < 5; k++) {
        const a = s.arc * (k / 2 - 1)
        g.circle(Math.cos(a) * reach * 1.08, Math.sin(a) * reach * 1.08, 2.5).fill({ color: '#c9ad80', alpha: 0.7 })
      }
    } else {
      // A cut: brighter at the end it finishes on
      const [a0, a1] = s.back ? [s.arc, -s.arc] : [-s.arc, s.arc]
      g.arc(0, 0, reach, Math.min(a0, a1), Math.max(a0, a1)).stroke({ ...paint, width: s.fx === 'slash' ? 3 : 5, alpha: 0.75 })
      g.circle(Math.cos(a1) * reach, Math.sin(a1) * reach, 3).fill({ color: '#fff4d6', alpha: 0.9 })
    }
    g.position.set(from.x, from.y)
    g.rotation = s.facing
    this.air.addChild(g)
    this.swings.push({ g, t: 0, life: s.fx === 'heavy' ? 0.28 : s.fx === 'jab' ? 0.14 : 0.16 })
  }

  // The peasant's stamina on foot: Shift sprints (draining it while you
  // move), Ctrl or Space dashes (a chunk at once). Empty it and you're out of
  // breath until it's back to a third. Returns whether you're sprinting.
  updateBreath(dt, keys) {
    this.dashCooldown -= dt
    this.dashGuard -= dt
    const moving = keys.up || keys.down || keys.left || keys.right
    let spent = false
    if (this.onFoot && this.input.pressed('dash') && this.dashCooldown <= 0 && !this.peasant.dashing) {
      if (this.breath >= DASH_COST) {
        // Along the keys held, or towards the mouse if standing still
        const aim = this.pointerWorld()
        const dx = moving ? (keys.right ? 1 : 0) - (keys.left ? 1 : 0) : aim.x - this.peasant.x
        const dy = moving ? (keys.down ? 1 : 0) - (keys.up ? 1 : 0) : aim.y - this.peasant.y
        this.peasant.dash(dx, dy)
        this.breath -= DASH_COST
        this.dashCooldown = DASH_COOLDOWN
        this.dashGuard = DASH_TIME + 0.05
        spent = true
        for (let k = 0; k < 4; k++) this.puff(this.peasant.x, this.peasant.y)
      } else {
        this.say('Too out of breath to dash')
      }
    }
    const sprinting = this.onFoot && this.input.is('boost') && moving && !this.outOfBreath && this.breath > 0
    if (sprinting) {
      this.breath = Math.max(0, this.breath - SPRINT_DRAIN * dt)
      spent = true
    }
    if (spent) {
      this.breathRest = 0
      if (this.breath <= 0) this.outOfBreath = true
    } else {
      this.breathRest += dt
      if (this.breathRest > BREATH_REGEN_DELAY) this.breath = Math.min(1, this.breath + BREATH_REGEN * dt)
      if (this.outOfBreath && this.breath >= 0.33) this.outOfBreath = false
    }
    return sprinting
  }

  // Dust kicked up from the feet.
  puff(x, y) {
    const g = new Graphics().circle(0, 0, 2.5 + Math.random() * 2).fill({ color: '#c9ad80', alpha: 0.6 })
    g.position.set(x + (Math.random() - 0.5) * 10, y + (Math.random() - 0.5) * 6)
    this.fx.addChild(g)
    this.puffs.push({ g, t: 0 })
  }

  updatePuffs(dt) {
    this.puffs = this.puffs.filter((p) => {
      p.t += dt
      p.g.scale.set(1 + p.t * 3)
      p.g.alpha = Math.max(0, 1 - p.t / 0.45)
      if (p.t < 0.45) return true
      p.g.destroy()
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
      x: (this.input.pointer.x - this.world.x) / WORLD_ZOOM,
      y: (this.input.pointer.y - this.world.y) / WORLD_ZOOM,
    }
  }

  updateThrowing(dt, from) {
    this.throwCooldown -= dt
    const weapon = this.ranged
    const target = this.pointerWorld()
    const loaded = this.ammoCount(weapon.ammo) > 0
    const inHand = this.active === 'ranged'
    if (inHand && this.input.pointer.down && !loaded && this.time - this.outOfAmmoAt > 2) {
      this.outOfAmmoAt = this.time
      this.say(`Out of ${AMMO[weapon.ammo].name.toLowerCase()}${this.onFoot ? ' in your bag' : ''}!`)
    }
    if (inHand && this.input.pointer.down && this.throwCooldown <= 0 && loaded) {
      this.stones.throw(from.x, from.y, target.x, target.y, from.vx, from.vy, weapon)
      this.takeAmmo(weapon.ammo)
      ;(this.onFoot ? this.peasant.bow : this.cart.cart.bow).fire()
      this.throwCooldown = weapon.cooldown
    }

    // Dotted aim line out to the throwing range.
    const a = this.aim.clear()
    // Only while the mouse is over the game: otherwise there's nothing to aim at
    if (!inHand || !this.input.pointer.inside) return
    const dx = target.x - from.x
    const dy = target.y - from.y
    const len = Math.hypot(dx, dy) || 1
    const reach = Math.min(weapon.range, len)
    for (let d = 30; d < reach; d += 18) {
      a.circle(from.x + (dx / len) * d, from.y + (dy / len) * d, 1.8)
    }
    a.fill({ color: '#fff4d6', alpha: loaded ? 0.55 : 0.15 })
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
    // (Blows themselves land in Enemies.update, only when a weapon connects.)
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

  // A blow or an arrow lands: on foot it's you, on the cart it's the cart.
  hurt(damage, faction, arrow) {
    if (this.invulnerable > 0 || this.state === 'over') return
    if (this.onFoot && this.dashGuard > 0) return // dashed clear of it
    // Armour only protects the peasant, not the cart.
    if (this.onFoot && Math.random() < blockChance(this.equipment)) {
      this.blockFlash = 0.25
      return
    }
    this.invulnerable = INVULNERABLE
    this.shake = 0.3
    const goblins = faction === 'goblin'
    if (this.onFoot) {
      this.health = Math.max(0, this.health - damage)
      if (this.health > 0) return
      if (arrow) {
        this.end('Shot down', goblins ? 'a goblin arrow found its mark' : 'a bandit archer shot you down')
      } else {
        goblins
          ? this.end('Overrun by goblins', 'the goblins caught you on foot')
          : this.end('Robbed by bandits', 'the bandits cut you down by the road')
      }
    } else if ((this.cartHealth = Math.max(0, this.cartHealth - damage)) <= 0) {
      goblins
        ? this.end('Cart torn apart', 'the goblins hacked your cart to kindling')
        : this.end('Cart smashed', 'the bandits smashed your cart and took the horse')
    }
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
    const zoom = WORLD_ZOOM
    const halfW = this.app.screen.width / 2
    const halfH = this.app.screen.height / 2
    // Half the view, and the edge margin, in world units
    const viewW = halfW / zoom
    const viewH = halfH / zoom
    const margin = CAMERA_MARGIN / zoom
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
      tx += clamp((input.pointer.x - halfW) / halfW, -1, 1) * (viewW - margin)
      ty += clamp((input.pointer.y - halfH) / halfH, -1, 1) * (viewH - margin)
    }

    const k = 1 - Math.exp(-dt * 4)
    this.camX += (tx - this.camX) * k
    this.camY += (ty - this.camY) * k

    const reachX = Math.max(0, viewW - margin)
    const reachY = Math.max(0, viewH - margin)
    const xs = keep.map((p) => p.x)
    const ys = keep.map((p) => p.y)
    this.camX = clamp(this.camX, Math.max(...xs) - reachX, Math.min(...xs) + reachX)
    this.camY = clamp(this.camY, Math.max(...ys) - reachY, Math.min(...ys) + reachY)

    this.shake = Math.max(0, this.shake - dt)
    const jolt = this.shake * 20
    // Snap to whole art pixels so the picture doesn't shimmer as it scrolls.
    const px = this.app.pixelSize ?? 1
    this.world.scale.set(zoom)
    this.world.position.set(
      Math.round((halfW - this.camX * zoom + (Math.random() - 0.5) * jolt) / px) * px,
      Math.round((halfH - this.camY * zoom + (Math.random() - 0.5) * jolt) / px) * px,
    )
    this.backdrop.width = this.app.screen.width
    this.backdrop.height = this.app.screen.height
    if (this.backdrop.tilePosition) {
      this.backdrop.tilePosition.set(this.world.x, this.world.y)
      this.backdrop.tileScale.set(zoom)
    }
  }

  destroy() {
    this.app.ticker.remove(this.tick)
    this.input.destroy()
  }
}
