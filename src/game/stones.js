import { Container, Graphics } from 'pixi.js'

const ARC_HEIGHT = 28
const HIT_RADIUS = 6

function drawShot(shot) {
  const g = new Graphics()
  if (shot === 'stone') {
    g.circle(0, 0, 4).fill('#8f8b82').circle(-1.2, -1.2, 1.6).fill('#b5b1a6')
  } else {
    // Arrow or bolt, drawn pointing along +x at the same size as the one
    // on the bow: shaft, steel head, fletching
    const bolt = shot === 'bolt'
    const half = bolt ? 4.5 : 6.5
    g.moveTo(-half, 0).lineTo(half, 0).stroke({ width: bolt ? 1.6 : 1.3, color: bolt ? '#5e3f22' : '#8b6236', cap: 'round' })
    g.poly([half + 3, 0, half - 0.5, -1.6, half - 0.5, 1.6]).fill('#d8dde2')
    const feather = bolt ? '#5e3f22' : '#ffffff'
    g.poly([-half, 0, -half - 3, -2.2, -half + 2.5, 0]).fill(feather)
    g.poly([-half, 0, -half - 3, 2.2, -half + 2.5, 0]).fill(feather)
  }
  return g
}

function drawShadow(shot) {
  const g = new Graphics()
  if (shot === 'stone') return g.ellipse(0, 0, 4, 3).fill({ color: '#000', alpha: 0.25 })
  return g.moveTo(-7, 0).lineTo(8, 0).stroke({ width: 1.5, color: '#000', alpha: 0.2, cap: 'round' })
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
    const shadow = drawShadow(weapon.shot)
    const stone = drawShot(weapon.shot)
    view.addChild(shadow, stone)
    this.layer.addChild(view)

    const vx = (dx / len) * weapon.speed + (lobbed ? carryX : 0)
    const vy = (dy / len) * weapon.speed + (lobbed ? carryY : 0)
    if (!lobbed) stone.rotation = shadow.rotation = Math.atan2(vy, vx)
    this.list.push({
      view,
      stone,
      shadow,
      lobbed,
      shot: weapon.shot,
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
      const height = s.lobbed ? 4 * ARC_HEIGHT * f * (1 - f) : 15 // arrows fly flat, at chest height
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
        // Arrows and bolts stay stuck in whoever they hit
        if (!s.lobbed) {
          target.rig?.stickShaft(s.vx, s.vy, s.shot)
          s.view.visible = false
        }
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
