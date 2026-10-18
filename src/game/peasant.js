import { Container, Graphics } from 'pixi.js'
import { WeaponHolder } from './weapon.js'

const WALK_SPEED = 120
export const PEASANT_RADIUS = 8

// The peasant on foot: walks with WASD, faces the mouse, and bumps into
// trees, buildings and the horse and cart.
export class Peasant {
  constructor(layer) {
    this.x = 0
    this.y = 0
    this.vx = 0
    this.vy = 0
    this.facing = 0
    this.step = 0

    this.view = new Container()
    this.arms = [-1, 1].map((side) => {
      const arm = new Graphics().circle(0, 0, 3).fill('#6b5b3e')
      arm.position.set(1, side * 8)
      arm.baseX = 1
      return arm
    })
    const body = new Graphics()
    body.ellipse(2, 2, 9, 11).fill({ color: '#000', alpha: 0.2 })
    body.ellipse(-1, 0, 6.5, 9).fill('#6b5b3e')
    body.circle(0, 0, 7.5).fill('#d4b25e')
    body.circle(0, 0, 4).fill('#c29d48')
    body.moveTo(-6, 0).lineTo(6, 0).stroke({ width: 1, color: '#a8853a', alpha: 0.6 })
    this.view.addChild(...this.arms, body)
    // Weapon sits under the body so the grip disappears into the hand.
    this.weapon = new WeaponHolder(this.view)
    this.view.setChildIndex(this.weapon.pivot, 0)
    this.view.visible = false
    layer.addChild(this.view)
  }

  get active() {
    return this.view.visible
  }

  place(x, y) {
    this.x = x
    this.y = y
    this.vx = this.vy = 0
    this.view.visible = true
    this.render()
  }

  hide() {
    this.view.visible = false
  }

  update(dt, input, aimX, aimY, obstacles) {
    const mx = (input.right ? 1 : 0) - (input.left ? 1 : 0)
    const my = (input.down ? 1 : 0) - (input.up ? 1 : 0)
    const len = Math.hypot(mx, my) || 1
    const k = 1 - Math.exp(-dt * 12)
    this.vx += ((mx / len) * WALK_SPEED - this.vx) * k
    this.vy += ((my / len) * WALK_SPEED - this.vy) * k
    this.x += this.vx * dt
    this.y += this.vy * dt

    for (const ob of obstacles) {
      const dx = this.x - ob.x
      const dy = this.y - ob.y
      const d = Math.hypot(dx, dy) || 1
      const overlap = ob.radius + PEASANT_RADIUS - d
      if (overlap > 0) {
        this.x += (dx / d) * overlap
        this.y += (dy / d) * overlap
      }
    }

    this.facing = Math.atan2(aimY - this.y, aimX - this.x)
    this.step += Math.hypot(this.vx, this.vy) * dt * 0.2
    this.weapon.update(dt)
    this.render()
  }

  render() {
    this.view.position.set(this.x, this.y)
    this.view.rotation = this.facing
    const swing = Math.min(3, Math.hypot(this.vx, this.vy) / 25)
    this.arms.forEach((arm, i) => {
      arm.x = arm.baseX + Math.sin(this.step + i * Math.PI) * swing
    })
  }
}
