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

// Ranged weapons held out in front, pointing along +x at the target.
function drawRanged(g, icon, loaded) {
  const wood = '#8b6236'
  switch (icon) {
    case 'bow':
      g.moveTo(2, -13).quadraticCurveTo(14, 0, 2, 13).stroke({ width: 3, color: wood, cap: 'round' })
      g.moveTo(2, -13).lineTo(loaded ? -4 : 2, 0).lineTo(2, 13).stroke({ width: 1, color: '#f3e3c0' })
      if (loaded) {
        g.moveTo(-4, 0).lineTo(16, 0).stroke({ width: 2, color: wood })
        g.poly([19, 0, 15, -2.5, 15, 2.5]).fill('#d8dde2')
      }
      break
    case 'crossbow':
      g.moveTo(-6, 0).lineTo(14, 0).stroke({ width: 4, color: '#6e4a28', cap: 'round' })
      g.moveTo(9, -11).quadraticCurveTo(14, 0, 9, 11).stroke({ width: 2.5, color: '#b9c0c8', cap: 'round' })
      g.moveTo(9, -11).lineTo(loaded ? 2 : 9, 0).lineTo(9, 11).stroke({ width: 1, color: '#f3e3c0' })
      if (loaded) g.moveTo(2, 0).lineTo(15, 0).stroke({ width: 2, color: '#5e3f22' })
      break
    case 'sling':
      g.moveTo(-2, -2).lineTo(8, -1).moveTo(-2, 2).lineTo(8, 1).stroke({ width: 1, color: '#c9b28a' })
      g.ellipse(9, 0, 3.5, 3).fill('#6e4a28')
      if (loaded) g.circle(9, 0, 2).fill('#9a968c')
      break
  }
}

// Holds the equipped ranged weapon in the left hand, aimed at the mouse,
// with a kick back each time it's loosed.
export class RangedHolder {
  constructor(parent, x = 0, y = -4) {
    this.pivot = new Container()
    this.pivot.position.set(x, y)
    this.g = new Graphics()
    this.pivot.addChild(this.g)
    parent.addChild(this.pivot)
    this.key = undefined
    this.kick = 0
  }

  set(item, loaded) {
    const icon = item?.icon ?? null
    const key = `${icon}:${loaded}`
    if (key === this.key) return
    this.key = key
    this.g.clear()
    if (icon) drawRanged(this.g, icon, loaded)
  }

  fire() {
    this.kick = 1
  }

  // `facing` is the aim direction relative to the parent's own rotation.
  update(dt, facing = 0) {
    this.kick = Math.max(0, this.kick - dt * 6)
    this.pivot.rotation = facing
    this.g.x = HAND - this.kick * 5
  }
}
