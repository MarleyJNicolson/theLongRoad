import { Container, Graphics } from 'pixi.js'
import { WeaponHolder } from './weapon.js'

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

function drawHorse() {
  const horse = new Container()
  const legs = []
  for (const [x, y] of [[12, -7], [12, 7], [-12, -7], [-12, 7]]) {
    const leg = new Graphics().roundRect(-3, -2.5, 6, 5, 2).fill('#3b2414')
    leg.position.set(x, y)
    leg.baseX = x
    horse.addChild(leg)
    legs.push(leg)
  }
  const body = new Graphics()
  body.ellipse(2, 3, 24, 11).fill({ color: '#000', alpha: 0.18 })
  body.moveTo(-22, 0).quadraticCurveTo(-34, 0, -38, 3).stroke({ width: 4, color: '#2a180c', cap: 'round' })
  body.ellipse(0, 0, 23, 10).fill('#8a5a33')
  body.ellipse(-4, 0, 14, 6).fill({ color: '#9c6a3e', alpha: 0.7 })
  body.ellipse(26, 0, 9, 5.5).fill('#8a5a33')
  body.ellipse(33, 0, 6, 4.5).fill('#7a4d2a')
  body.moveTo(6, 0).lineTo(30, 0).stroke({ width: 3, color: '#2a180c', cap: 'round' })
  body.circle(28, -4.5, 2).fill('#7a4d2a')
  body.circle(28, 4.5, 2).fill('#7a4d2a')
  // collar
  body.roundRect(15, -8, 4, 16, 2).fill('#5a3a1a')
  horse.addChild(body)
  return { horse, legs }
}

function drawCart() {
  const cart = new Container()
  const g = new Graphics()
  g.roundRect(-22, -21, 46, 46, 4).fill({ color: '#000', alpha: 0.2 })
  // wheels
  g.roundRect(-10, -24, 20, 6, 2).fill('#3a2a1a')
  g.roundRect(-10, 18, 20, 6, 2).fill('#3a2a1a')
  // bed
  g.roundRect(-24, -18, 44, 36, 3).fill('#6e4a28')
  g.roundRect(-21, -15, 38, 30, 2).fill('#8b6236')
  for (let x = -14; x < 17; x += 8) g.moveTo(x, -15).lineTo(x, 15)
  g.stroke({ width: 1, color: '#6e4a28' })
  // cargo: hay and sacks
  g.ellipse(-12, -4, 9, 10).fill('#d9b44a')
  g.ellipse(-14, -6, 5, 5).fill('#e6c766')
  g.ellipse(-9, 9, 6, 5).fill('#c9b28a')
  g.ellipse(-2, -9, 5, 5).fill('#bfa67c')
  // peasant on the driving bench (hidden while they're off the cart)
  g.roundRect(6, -12, 6, 24, 2).fill('#5a3a1a')
  const driver = new Graphics()
  driver.ellipse(9, 0, 7, 9).fill('#6b5b3e')
  driver.circle(10, 0, 8).fill({ color: '#000', alpha: 0.15 })
  driver.circle(9, 0, 7.5).fill('#d4b25e')
  driver.circle(9, 0, 4).fill('#c29d48')
  // arms holding reins
  driver.moveTo(10, -6).lineTo(16, -4).moveTo(10, 6).lineTo(16, 4).stroke({ width: 3, color: '#6b5b3e', cap: 'round' })
  cart.addChild(g)
  // The driver and the weapon in their hand come and go together.
  const seat = new Container()
  seat.addChild(driver)
  cart.addChild(seat)
  cart.driver = seat
  cart.weapon = new WeaponHolder(seat, 9, 0)
  seat.setChildIndex(cart.weapon.pivot, 0)
  return cart
}

// The player: a horse pulling a cart. The horse is steered like a car;
// the cart trails behind on a hitch, so it cuts corners naturally.
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

    this.shafts = new Graphics()
    this.cart = drawCart()
    const { horse, legs } = drawHorse()
    this.horse = horse
    this.legs = legs
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
    const hitchX = this.x - Math.cos(this.heading) * 20
    const hitchY = this.y - Math.sin(this.heading) * 20
    const dx = hitchX - this.cartX
    const dy = hitchY - this.cartY
    const len = Math.hypot(dx, dy) || 1
    this.cartX = hitchX - (dx / len) * HITCH_LENGTH
    this.cartY = hitchY - (dy / len) * HITCH_LENGTH
    this.cartHeading = Math.atan2(dy, dx)

    this.collide(obstacles)
    this.render()
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

  render() {
    this.horse.position.set(this.x, this.y)
    this.horse.rotation = this.heading
    this.cart.position.set(this.cartX, this.cartY)
    this.cart.rotation = this.cartHeading

    const phase = this.stride * 0.18
    const swing = Math.min(1, Math.abs(this.speed) / 40) * 4
    this.legs.forEach((leg, i) => {
      const diagonal = i === 0 || i === 3 ? 1 : -1
      leg.x = leg.baseX + Math.sin(phase) * swing * diagonal
    })

    // Shafts from the cart's front corners to the horse's flanks, plus reins.
    const cc = Math.cos(this.cartHeading)
    const cs = Math.sin(this.cartHeading)
    const hc = Math.cos(this.heading)
    const hs = Math.sin(this.heading)
    const s = this.shafts.clear()
    for (const side of [-1, 1]) {
      const fx = this.cartX + cc * 20 - cs * 13 * side
      const fy = this.cartY + cs * 20 + cc * 13 * side
      const tx = this.x + hc * 12 - hs * 11 * side
      const ty = this.y + hs * 12 + hc * 11 * side
      s.moveTo(fx, fy).lineTo(tx, ty)
    }
    s.stroke({ width: 3, color: '#5a3a1a', cap: 'round' })
    for (const side of [-1, 1]) {
      s.moveTo(this.cartX + cc * 16 - cs * 4 * side, this.cartY + cs * 16 + cc * 4 * side)
      s.lineTo(this.x + hc * 26 - hs * 4 * side, this.y + hs * 26 + hc * 4 * side)
    }
    s.stroke({ width: 1, color: '#2a180c' })
  }
}
