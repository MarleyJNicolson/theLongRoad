import { Container, Graphics } from 'pixi.js'
import { Rig, joint } from './rig.js'

const MAX_SPEED = 150 // px/s on the road at a steady trot
const GALLOP_SPEED = 245 // px/s while boosting (Shift)
const MUD_SPEED = 55 // px/s off the road
const REVERSE_SPEED = 45
const ACCEL = 100
const GALLOP_ACCEL = 190
const BRAKE = 260
const DRAG = 25
const TURN_RATE = 1.9 // rad/s at walking pace
const HITCH_LENGTH = 46 // horse hitch point -> cart centre

// Seen in three-quarter view like the people (see rig.js): shapes are laid
// out in a frame facing `heading` (a forward, b to the right, z up) and
// drawn on the ground, lifted by their height. `d` is depth: nearer the
// bottom of the screen is nearer the camera, and drawn later.
function view(heading) {
  const f = { x: Math.cos(heading), y: Math.sin(heading) }
  const l = { x: -f.y, y: f.x }
  return (a, b, z = 0) => {
    const x = f.x * a + l.x * b
    const y = f.y * a + l.y * b
    return { x, y: y - z, d: y }
  }
}

// --- The horse ------------------------------------------------------------------

// A dark bay, so it stands out against the dirt road
const HORSE = {
  coat: '#5c3a22',
  shade: '#3d2516',
  light: '#7a4d2a',
  mane: '#1c1714',
  hoof: '#1c1714',
  tack: '#4a3220',
}

// Leg timing for each gait, as phase offsets for [FL, FR, BL, BR]: a
// four-beat walk, a diagonal trot, a rolling gallop.
const GAITS = {
  walk: [Math.PI / 2, (3 * Math.PI) / 2, 0, Math.PI],
  trot: [0, Math.PI, Math.PI, 0],
  gallop: [1.3, 1.8, 0, 0.45],
}

function drawHorse(g, heading, stride, speed, time) {
  g.clear()
  const P = view(heading)
  const pace = Math.abs(speed)
  const gait = pace > 170 ? 'gallop' : pace > 70 ? 'trot' : 'walk'
  const moving = Math.min(1, pace / 30)
  const reach = (gait === 'gallop' ? 7 : gait === 'trot' ? 5.5 : 4) * moving
  const lift = (gait === 'gallop' ? 6 : 4) * moving
  const phase = stride / (gait === 'gallop' ? 9 : 7)
  const bob = Math.abs(Math.sin(phase)) * (gait === 'walk' ? 0.6 : 1.4) * moving
  const pitch = gait === 'gallop' ? Math.sin(phase) * 1.5 : 0 // rocking at a gallop

  // Ground shadow
  const shadow = []
  for (let t = 0; t < Math.PI * 2; t += Math.PI / 8) {
    const p = P(Math.cos(t) * 20, Math.sin(t) * 6)
    shadow.push(p.x, p.y)
  }
  g.poly(shadow).fill({ color: '#000', alpha: 0.22 })

  const parts = []
  const legs = [
    [10, -3.6, GAITS[gait][0], -1],
    [10, 3.6, GAITS[gait][1], -1],
    [-11, -3.6, GAITS[gait][2], 1],
    [-11, 3.6, GAITS[gait][3], 1],
  ]
  for (const [a0, b, offset, bend] of legs) {
    const ph = phase + offset
    const top = { a: a0, b, z: 19 + bob + (a0 > 0 ? pitch : -pitch) }
    const foot = { a: a0 + Math.sin(ph) * reach, b, z: Math.max(0, Math.cos(ph)) * lift }
    const knee = joint(top, foot, 10.5, 10.5, bend)
    const [t, k, f] = [top, knee, foot].map((p) => P(p.a, p.b, p.z))
    parts.push({
      d: (t.d + f.d) / 2,
      draw: () => {
        g.moveTo(t.x, t.y).lineTo(k.x, k.y).stroke({ width: 4, color: b * (P(0, 1).d) > 0 ? HORSE.coat : HORSE.shade, cap: 'round' })
        g.moveTo(k.x, k.y).lineTo(f.x, f.y).stroke({ width: 2.4, color: HORSE.shade, cap: 'round' })
        g.circle(f.x, f.y, 1.9).fill(HORSE.hoof)
      },
    })
  }

  const z = 21 + bob
  const rump = P(-14, 0, z + 1 - pitch)
  const chest = P(11, 0, z + pitch)
  const withers = P(9, 0, z + 4 + pitch)
  const poll = P(18, 0, z + 14 + pitch * 1.5)
  const muzzle = P(25, 0, z + 7 + pitch * 1.5)
  const tailEnd = P(-19 + Math.sin(time * 3) * 1.5, Math.sin(time * 2.3) * 2, 11)
  const body = () => {
    g.moveTo(rump.x, rump.y).lineTo(chest.x, chest.y).stroke({ width: 13, color: HORSE.coat, cap: 'round' })
    // Back lit, belly shaded
    g.moveTo(rump.x, rump.y - 4).lineTo(chest.x, chest.y - 4).stroke({ width: 3, color: HORSE.light, alpha: 0.7, cap: 'round' })
    g.moveTo(rump.x, rump.y + 4).lineTo(chest.x, chest.y + 4).stroke({ width: 3, color: HORSE.shade, alpha: 0.7, cap: 'round' })
    // Collar and the harness strap round the girth
    const collar = P(10.5, 0, z + 4 + pitch)
    g.circle(collar.x, collar.y, 5.5).stroke({ width: 2.5, color: HORSE.tack })
    const girth = P(-2, 0, z)
    g.moveTo(girth.x, girth.y - 6).lineTo(girth.x, girth.y + 6).stroke({ width: 2.5, color: HORSE.tack })
  }
  const head = () => {
    g.moveTo(withers.x, withers.y).lineTo(poll.x, poll.y).stroke({ width: 7, color: HORSE.coat, cap: 'round' })
    g.moveTo(withers.x, withers.y - 3).lineTo(poll.x, poll.y - 3).stroke({ width: 2.5, color: HORSE.mane, cap: 'round' })
    g.moveTo(poll.x, poll.y).lineTo(muzzle.x, muzzle.y).stroke({ width: 5.5, color: HORSE.coat, cap: 'round' })
    g.circle(muzzle.x, muzzle.y, 2.6).fill(HORSE.shade)
    const ear = P(17, 0, z + 18 + pitch * 1.5)
    g.poly([poll.x - 1.5, poll.y - 1, ear.x, ear.y, poll.x + 1.5, poll.y - 1]).fill(HORSE.shade)
    const eye = P(20, P(0, 1).d > 0 ? 1.6 : -1.6, z + 12 + pitch * 1.5)
    g.circle(eye.x, eye.y, 0.9).fill('#0e0b0a')
    // Bridle
    g.moveTo(poll.x, poll.y).lineTo(muzzle.x, muzzle.y).stroke({ width: 1, color: HORSE.tack, alpha: 0.9 })
  }
  const tail = () => {
    g.moveTo(rump.x, rump.y).quadraticCurveTo(rump.x + (tailEnd.x - rump.x) * 0.3, rump.y, tailEnd.x, tailEnd.y)
    g.stroke({ width: 3.2, color: HORSE.mane, cap: 'round' })
  }
  parts.push({ d: 0, draw: body })
  parts.push({ d: Math.max(withers.d, poll.d) + 0.5, draw: head })
  parts.push({ d: rump.d - 0.5, draw: tail })
  parts.sort((p, q) => p.d - q.d)
  for (const p of parts) p.draw()
}

// --- The cart -------------------------------------------------------------------

const CART = {
  long: 20, // half length
  wide: 14, // half width
  floor: 12, // height of the bed
  rim: 21, // height of the sides
  wheel: 11, // wheel radius
  wood: '#7a5230',
  inside: '#6e4a28',
  bed: '#8b6236',
  dark: '#4a3220',
  iron: '#3a2a1a',
}

// One wheel standing up at (a, b), turned by `roll`.
function drawWheel(g, P, a, b, roll) {
  const r = CART.wheel
  const rim = []
  for (let t = 0; t < Math.PI * 2 + 0.01; t += Math.PI / 10) {
    const p = P(a + Math.cos(t) * r, b, CART.wheel + Math.sin(t) * r)
    rim.push(p.x, p.y)
  }
  const hub = P(a, b, CART.wheel)
  for (let s = 0; s < 6; s++) {
    const t = roll + (s / 6) * Math.PI * 2
    const p = P(a + Math.cos(t) * r, b, CART.wheel + Math.sin(t) * r)
    g.moveTo(hub.x, hub.y).lineTo(p.x, p.y)
  }
  g.stroke({ width: 1.5, color: '#5e3f22' })
  g.poly(rim).stroke({ width: 2.5, color: CART.iron })
  g.circle(hub.x, hub.y, 2).fill(CART.iron)
}

// The cart is split around the driver: wheels, walls and cargo behind
// them, then the walls and wheel in front.
function drawCart(back, front, heading, roll) {
  const P = view(heading)
  const { long, wide, floor, rim } = CART
  const nearSide = P(0, 1).d > 0 ? 1 : -1 // which side faces the camera
  const nearEnd = P(1, 0).d > 0 ? 1 : -1 // front or back end towards us

  const quad = (g, pts, colour) => g.poly(pts.flatMap(([a, b, z]) => { const p = P(a, b, z); return [p.x, p.y] })).fill(colour)
  // Walls as quads: [corner, corner] along the bottom, raised to the rim
  const wall = (g, a1, b1, a2, b2, colour) => {
    quad(g, [[a1, b1, floor], [a2, b2, floor], [a2, b2, rim], [a1, b1, rim]], colour)
    const t1 = P(a1, b1, rim)
    const t2 = P(a2, b2, rim)
    g.moveTo(t1.x, t1.y).lineTo(t2.x, t2.y).stroke({ width: 2, color: CART.dark, cap: 'round' })
    const m1 = P(a1, b1, (floor + rim) / 2)
    const m2 = P(a2, b2, (floor + rim) / 2)
    g.moveTo(m1.x, m1.y).lineTo(m2.x, m2.y).stroke({ width: 1, color: CART.dark, alpha: 0.6 })
  }
  const walls = {
    left: [long, -wide, -long, -wide],
    right: [-long, wide, long, wide],
    front: [long, wide, long, -wide],
    back: [-long, -wide, -long, wide],
  }

  // Behind: shadow, the far wheel, the far walls' inner faces, the bed, cargo, the bench
  const g = back.clear()
  quad(g, [[long + 2, wide + 3, 0], [-long - 2, wide + 3, 0], [-long - 2, -wide - 3, 0], [long + 2, -wide - 3, 0]], { color: '#000', alpha: 0.22 })
  drawWheel(g, P, -2, -nearSide * (wide + 2), roll)
  wall(g, ...walls[nearSide > 0 ? 'left' : 'right'], CART.inside)
  wall(g, ...walls[nearEnd > 0 ? 'back' : 'front'], CART.inside)
  quad(g, [[long, wide, floor], [-long, wide, floor], [-long, -wide, floor], [long, -wide, floor]], CART.bed)
  for (let a = -long + 6; a < long; a += 7) {
    const p1 = P(a, -wide, floor)
    const p2 = P(a, wide, floor)
    g.moveTo(p1.x, p1.y).lineTo(p2.x, p2.y)
  }
  g.stroke({ width: 1, color: CART.inside })
  // Cargo: a heap of hay and two sacks
  const hay = P(-9, -3, floor + 5)
  g.ellipse(hay.x, hay.y, 10, 7).fill('#d9b44a')
  g.ellipse(hay.x - 2, hay.y - 2, 5, 3.5).fill('#e6c766')
  for (const [a, b] of [[-12, 8], [-3, -9]]) {
    const s = P(a, b, floor + 4)
    g.ellipse(s.x, s.y, 5, 4.5).fill('#c9b28a').ellipse(s.x - 1, s.y - 1.5, 2, 1.5).fill('#d6c49c')
  }
  // The driver's bench
  quad(g, [[15, -wide + 1, floor + 8], [9, -wide + 1, floor + 8], [9, wide - 1, floor + 8], [15, wide - 1, floor + 8]], CART.dark)

  // In front: the near walls' outer faces and the near wheel
  const h = front.clear()
  wall(h, ...walls[nearSide > 0 ? 'right' : 'left'], CART.wood)
  wall(h, ...walls[nearEnd > 0 ? 'front' : 'back'], CART.wood)
  drawWheel(h, P, -2, nearSide * (wide + 2), roll)
}

// The driver on the bench: a seated peasant (see rig.js), and what Game uses
// to put weapons in their hands and play attacks (as for the peasant on foot).
function makeDriver(cartView) {
  const seat = new Container()
  const rig = new Rig({ skin: '#d9b08c', shirt: '#6b5b3e', legs: '#4a3a2b', head: 'straw' })
  rig.seated = true
  rig.seatZ = CART.floor + 9
  seat.addChild(rig.view)
  cartView.driver = seat
  cartView.rig = rig
  cartView.aim = 0 // where the driver is looking, relative to the cart
  const MELEE = { club: 'club', sword: 'sword', spear: 'spear', axe: 'axe' }
  const RANGED = { bow: 'bow', crossbow: 'crossbow', sling: 'sling' }
  cartView.weapon = {
    set: (item) => (rig.weapon = MELEE[item?.icon] ?? null),
    play: (move, opts) => rig.play(move, opts),
    update: (dt, facing) => (cartView.aim = facing),
  }
  cartView.bow = {
    set: (item, loaded) => {
      rig.offhand = RANGED[item?.icon] ?? null
      rig.loaded = loaded
      rig.aiming = !!rig.offhand
      rig.pull = loaded ? 1 : 0.3
    },
    fire: () => rig.loose(),
    update: (dt, facing) => (cartView.aim = facing),
  }
  return seat
}

// The player: a horse pulling a cart. The horse is steered like a car;
// the cart trails behind on a hitch, so it cuts corners naturally. Drawn in
// three-quarter view: a walking, trotting, galloping horse, a cart with
// turning wheels, and the peasant on the driving bench.
export class HorseCart {
  constructor(layer, x, y, heading) {
    this.x = x
    this.y = y
    this.heading = heading
    this.cartHeading = heading
    this.speed = 0
    this.stride = 0
    this.cartX = x - Math.cos(heading) * (HITCH_LENGTH + 20)
    this.cartY = y - Math.sin(heading) * (HITCH_LENGTH + 20)

    this.roll = 0 // how far the wheels have turned
    this.time = 0

    // Each part is sorted by depth with the people around it (see `render`)
    this.shafts = new Graphics()
    this.cart = new Container()
    this.cartBack = new Graphics()
    this.cartFront = new Graphics()
    this.cart.addChild(this.cartBack, makeDriver(this.cart), this.cartFront)
    this.horse = new Container()
    this.horseG = new Graphics()
    this.horse.addChild(this.horseG)
    layer.addChild(this.shafts, this.cart, this.horse)
  }

  get maxSpeed() {
    return GALLOP_SPEED
  }

  // With nobody holding the reins (`parked`) the horse pulls up and waits.
  update(dt, input, onRoad, obstacles = [], parked = false) {
    // Galloping only helps on the road; in the mud the horse just flounders.
    const galloping = input.boost && onRoad
    const limit = onRoad ? (galloping ? GALLOP_SPEED : MAX_SPEED) : MUD_SPEED

    if (parked) {
      this.speed -= Math.sign(this.speed) * Math.min(Math.abs(this.speed), BRAKE * dt)
      input = {}
    } else if (input.up) {
      // Speed up to the current limit; anything above it eases off below.
      if (this.speed < limit) {
        const accel = this.speed < 0 ? BRAKE : galloping ? GALLOP_ACCEL : ACCEL
        this.speed = Math.min(limit, this.speed + accel * dt)
      }
    } else if (input.down) {
      this.speed -= (this.speed > 0 ? BRAKE : ACCEL * 0.5) * dt
    } else {
      this.speed -= Math.sign(this.speed) * Math.min(Math.abs(this.speed), DRAG * dt)
    }
    // Easing off from a gallop is gradual; hitting mud is not.
    const slowdown = onRoad ? 110 : 320
    if (this.speed > limit) this.speed = Math.max(limit, this.speed - slowdown * dt)
    this.speed = Math.max(-REVERSE_SPEED, this.speed)

    // Steering needs movement, and gets a little heavier at a gallop.
    const pace = Math.abs(this.speed)
    // A horse straining against the reins can still turn slowly when blocked.
    const throttle = (input.up ? 1 : 0) - (input.down ? 1 : 0)
    let grip = Math.min(1, pace / 60) * (1 - 0.35 * Math.min(1, pace / GALLOP_SPEED))
    if (throttle && grip < 0.35) grip = 0.35
    const direction = pace > 5 ? Math.sign(this.speed) : throttle
    const steer = (input.right ? 1 : 0) - (input.left ? 1 : 0)
    this.heading += steer * TURN_RATE * grip * direction * dt

    const step = this.speed * dt
    this.x += Math.cos(this.heading) * step
    this.y += Math.sin(this.heading) * step
    this.stride += step

    // Cart follows the hitch point behind the horse.
    const [oldX, oldY] = [this.cartX, this.cartY]
    const hitchX = this.x - Math.cos(this.heading) * 20
    const hitchY = this.y - Math.sin(this.heading) * 20
    const dx = hitchX - this.cartX
    const dy = hitchY - this.cartY
    const len = Math.hypot(dx, dy) || 1
    this.cartX = hitchX - (dx / len) * HITCH_LENGTH
    this.cartY = hitchY - (dy / len) * HITCH_LENGTH
    this.cartHeading = Math.atan2(dy, dx)
    this.roll += (Math.hypot(this.cartX - oldX, this.cartY - oldY) / 11) * Math.sign(this.speed || 1)

    this.collide(obstacles)
    this.render(dt)
  }

  // Push the whole rig out of any obstacle it overlaps, and bleed off the
  // part of its speed that drives into the obstacle so it can slide along.
  // Circles covering the horse's body, its head, and the cart.
  bodies() {
    const hc = Math.cos(this.heading)
    const hs = Math.sin(this.heading)
    return [
      { x: this.x, y: this.y, r: 13 },
      { x: this.x + hc * 28, y: this.y + hs * 28, r: 7 },
      { x: this.cartX, y: this.cartY, r: 23 },
    ]
  }

  collide(obstacles) {
    const hc = Math.cos(this.heading)
    const hs = Math.sin(this.heading)
    const bodies = this.bodies()
    for (const ob of obstacles) {
      for (const b of bodies) {
        const dx = b.x - ob.x
        const dy = b.y - ob.y
        const dist = Math.hypot(dx, dy) || 1
        const overlap = ob.radius + b.r - dist
        if (overlap <= 0) continue

        const nx = dx / dist
        const ny = dy / dist
        for (const body of bodies) {
          body.x += nx * overlap
          body.y += ny * overlap
        }
        this.x += nx * overlap
        this.y += ny * overlap
        this.cartX += nx * overlap
        this.cartY += ny * overlap

        const into = (hc * nx + hs * ny) * Math.sign(this.speed)
        if (into < 0) this.speed *= 1 + into * 0.9
      }
    }
  }

  render(dt = 0) {
    this.time += dt
    this.horse.position.set(this.x, this.y)
    drawHorse(this.horseG, this.heading, this.stride, this.speed, this.time)

    this.cart.position.set(this.cartX, this.cartY)
    drawCart(this.cartBack, this.cartFront, this.cartHeading, this.roll)
    const P = view(this.cartHeading)
    const seat = P(12, 0)
    this.cart.driver.position.set(seat.x, seat.y)
    this.cart.rig.update(dt, this.cartHeading + this.cart.aim, 0)

    // Shafts from the cart to the horse's flanks, and the reins
    const H = view(this.heading)
    const s = this.shafts.clear()
    for (const side of [-1, 1]) {
      const from = P(CART.long, side * 11, 15)
      const to = H(-3, side * 6.5, 19)
      s.moveTo(this.cartX + from.x, this.cartY + from.y).lineTo(this.x + to.x, this.y + to.y)
    }
    s.stroke({ width: 2.5, color: '#5a3a1a', cap: 'round' })
    if (this.cart.driver.visible) {
      for (const side of [-1, 1]) {
        const from = P(19, side * 3, CART.floor + 15)
        const to = H(22, side * 1.5, 30)
        s.moveTo(this.cartX + from.x, this.cartY + from.y).lineTo(this.x + to.x, this.y + to.y)
      }
      s.stroke({ width: 0.8, color: '#2a180c' })
    }

    // Nearer the bottom of the screen draws in front
    this.horse.zIndex = this.y
    this.cart.zIndex = this.cartY
    this.shafts.zIndex = (this.y + this.cartY) / 2
  }
}
