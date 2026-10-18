import { Container, Graphics } from 'pixi.js'

const ARC_HEIGHT = 28
const HIT_RADIUS = 6

function drawShot(shot) {
  const g = new Graphics()
  if (shot === 'stone') {
    g.circle(0, 0, 4).fill('#8f8b82').circle(-1.2, -1.2, 1.6).fill('#b5b1a6')
  } else {
    // Arrow or bolt, drawn pointing along +x
    const len = shot === 'bolt' ? 12 : 16
    g.moveTo(-len / 2, 0).lineTo(len / 2, 0).stroke({ width: 2, color: '#6e4a28' })
    g.poly([len / 2 + 4, 0, len / 2 - 1, -2.5, len / 2 - 1, 2.5]).fill('#9a9a9a')
    g.poly([-len / 2, 0, -len / 2 - 4, -3, -len / 2 + 2, 0, -len / 2 - 4, 3]).fill(shot === 'bolt' ? '#5e3f22' : '#e8e0c8')
  }
  return g
}

// Missiles loosed by the peasant: stones are lobbed in an arc, arrows and
// bolts fly flat. Each carries the thrower's momentum and the weapon's damage.
export class Stones {
  constructor(layer) {
    this.layer = layer
    this.list = []
  }

  // `weapon` supplies range, speed, damage and the kind of shot.
  throw(fromX, fromY, toX, toY, carryX, carryY, weapon) {
    const dx = toX - fromX
    const dy = toY - fromY
    const len = Math.hypot(dx, dy) || 1
    const dist = Math.min(weapon.range, Math.max(80, len))
    const lobbed = weapon.shot === 'stone'

    const view = new Container()
    const shadow = new Graphics().ellipse(0, 0, 4, 3).fill({ color: '#000', alpha: 0.25 })
    const stone = drawShot(weapon.shot)
    view.addChild(shadow, stone)
    this.layer.addChild(view)

    const vx = (dx / len) * weapon.speed + (lobbed ? carryX : 0)
    const vy = (dy / len) * weapon.speed + (lobbed ? carryY : 0)
    if (!lobbed) stone.rotation = Math.atan2(vy, vx)
    this.list.push({
      view,
      stone,
      shadow,
      lobbed,
      damage: weapon.damage,
      x: fromX,
      y: fromY,
      vx,
      vy,
      t: 0,
      duration: dist / weapon.speed,
      landed: 0,
    })
  }

  // Returns the enemies knocked out this frame.
  update(dt, enemies) {
    const kills = []
    for (const s of this.list) {
      if (s.landed) {
        s.landed += dt
        s.view.alpha = Math.max(0, 1 - s.landed / 0.8)
        continue
      }
      s.t += dt
      s.x += s.vx * dt
      s.y += s.vy * dt
      const f = Math.min(1, s.t / s.duration)
      const height = s.lobbed ? 4 * ARC_HEIGHT * f * (1 - f) : 6
      s.view.position.set(s.x, s.y)
      s.stone.y = -height
      if (s.lobbed) s.stone.scale.set(1 + height / 50)

      // Anything hiding fills the whole bush or burrow it is in.
      const target = enemies.find(
        (e) => e.alive && Math.hypot(e.x - s.x, e.y - s.y) < (e.hidden ? 24 : e.radius) + HIT_RADIUS,
      )
      if (target) {
        const speed = Math.hypot(s.vx, s.vy) || 1
        target.hit(s.vx / speed, s.vy / speed, s.damage)
        if (!target.alive) kills.push(target)
        s.landed = 0.4
        s.stone.y = 0
      } else if (f >= 1) {
        s.landed = dt
        s.stone.y = 0
      }
    }

    this.list = this.list.filter((s) => {
      if (s.landed < 0.8) return true
      s.view.destroy({ children: true })
      return false
    })
    return kills
  }
}
