import { Container } from 'pixi.js'
import { Rig } from './rig.js'

const WALK_SPEED = 120
export const PEASANT_RADIUS = 8

// Equipped items drawn in the peasant's hands (rig.js weapon names).
const MELEE = { club: 'club', sword: 'sword', spear: 'spear', axe: 'axe' }
const RANGED = { bow: 'bow', crossbow: 'crossbow', sling: 'sling' }

// The peasant on foot: walks with WASD, faces the mouse, and bumps into
// trees, buildings and the horse and cart. Drawn as a jointed figure in a
// straw hat (see rig.js).
export class Peasant {
  constructor(layer) {
    this.x = 0
    this.y = 0
    this.vx = 0
    this.vy = 0
    this.facing = 0

    this.rig = new Rig({ skin: '#d9b08c', shirt: '#6b5b3e', legs: '#4a3a2b', head: 'straw' })
    this.view = new Container()
    this.view.addChild(this.rig.view)
    this.view.visible = false
    layer.addChild(this.view)

    // What Game uses to put weapons in hand and play attacks
    const rig = this.rig
    this.weapon = {
      set: (item) => (rig.weapon = MELEE[item?.icon] ?? null),
      play: (move, opts) => rig.play(move, opts),
    }
    this.bow = {
      set: (item, loaded) => {
        rig.offhand = RANGED[item?.icon] ?? null
        rig.loaded = loaded
        rig.aiming = !!rig.offhand
      },
      fire: () => rig.loose(),
    }
  }

  get active() {
    return this.view.visible
  }

  place(x, y) {
    this.x = x
    this.y = y
    this.vx = this.vy = 0
    this.view.visible = true
    this.render(0)
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
    this.render(dt)
  }

  render(dt) {
    this.rig.update(dt, this.facing, Math.hypot(this.vx, this.vy))
    this.view.position.set(this.x, this.y)
    this.view.zIndex = this.y // sorted with the raiders by depth
  }
}
