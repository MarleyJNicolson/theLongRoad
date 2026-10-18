import { Container, Graphics } from 'pixi.js'

const SWING_TIME = 0.18
const IDLE_ANGLE = 0.9 // held out to the right side, pointing forward
const HAND = 7 // distance from the body's centre to the hand

// Melee weapons drawn top-down, starting at the hand and pointing along +x.
function drawWeapon(g, icon) {
  const wood = '#6b4a2a'
  const steel = '#d8dde2'
  switch (icon) {
    case 'club':
      g.poly([0, -1.5, 18, -3.5, 19, 0, 18, 3.5, 0, 1.5]).fill(wood)
      g.circle(12, -2, 1).circle(15, 2, 1).fill('#4a3220')
      break
    case 'sword':
      g.moveTo(-2, 0).lineTo(4, 0).stroke({ width: 3, color: '#5e3f22', cap: 'round' })
      g.moveTo(4, -5).lineTo(4, 5).stroke({ width: 2.5, color: '#c9a227', cap: 'round' })
      g.poly([5, -1.6, 22, -1.2, 26, 0, 22, 1.2, 5, 1.6]).fill(steel)
      g.moveTo(6, 0).lineTo(21, 0).stroke({ width: 0.8, color: '#9aa3ad' })
      break
    case 'spear':
      g.moveTo(-6, 0).lineTo(34, 0).stroke({ width: 2.2, color: wood, cap: 'round' })
      g.poly([33, -3, 43, 0, 33, 3]).fill(steel)
      g.moveTo(32, -2.5).lineTo(32, 2.5).stroke({ width: 1.5, color: '#9aa3ad' })
      break
    case 'axe':
      g.moveTo(-2, 0).lineTo(22, 0).stroke({ width: 2.5, color: wood, cap: 'round' })
      g.poly([16, 1, 24, 1, 27, 9, 20, 7]).fill('#b9c0c8')
      g.moveTo(24, 1.5).lineTo(27, 9).stroke({ width: 1, color: '#eef2f5' })
      break
  }
}

// Holds the equipped melee weapon in a figure's right hand and animates the
// swing. Add it to a container that already rotates with the figure.
export class WeaponHolder {
  constructor(parent, x = 0, y = 0) {
    this.pivot = new Container()
    this.pivot.position.set(x, y)
    this.g = new Graphics()
    this.g.x = HAND
    this.pivot.addChild(this.g)
    parent.addChild(this.pivot)
    this.icon = undefined
    this.swingT = SWING_TIME
  }

  set(item) {
    const icon = item?.icon ?? null
    if (icon === this.icon) return
    this.icon = icon
    this.g.clear()
    if (icon) drawWeapon(this.g, icon)
  }

  swing() {
    this.swingT = 0
  }

  // `facing` is the aim direction relative to the parent's own rotation.
  update(dt, facing = 0) {
    this.swingT += dt
    const t = this.swingT / SWING_TIME
    // Sweep from the left of the aim line across to the right, then rest.
    const angle = t < 1 ? -1.1 + 2.2 * (1 - (1 - t) * (1 - t)) : IDLE_ANGLE
    this.pivot.rotation = facing + angle
  }
}
