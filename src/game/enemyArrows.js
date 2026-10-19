import { Graphics } from 'pixi.js'

// Arrows loosed by enemy archers. They fly flat and fairly slowly, so you
// can dodge them, and they thud into any tree or building in the way.
export class EnemyArrows {
  constructor(layer) {
    this.layer = layer
    this.list = []
  }

  fire({ x, y, aimX, aimY, speed, range, damage, faction }) {
    const dx = aimX - x
    const dy = aimY - y
    const len = Math.hypot(dx, dy) || 1
    const g = new Graphics()
    g.moveTo(-9, 0).lineTo(9, 0).stroke({ width: 2, color: '#5e3f22', cap: 'round' })
    g.poly([13, 0, 8, -3, 8, 3]).fill('#9aa3ad')
    g.poly([-9, 0, -13, -3.5, -6, 0, -13, 3.5]).fill(faction === 'goblin' ? '#6fa83a' : '#c0392b')
    g.position.set(x, y)
    g.rotation = Math.atan2(dy, dx)
    this.layer.addChild(g)
    this.list.push({ g, x, y, vx: (dx / len) * speed, vy: (dy / len) * speed, left: range, damage, faction, stuck: 0, flown: 0 })
  }

  // `victims` are circles that get hurt ({ x, y, r }); `obstacles` stop arrows
  // dead ({ x, y, radius }). Returns the hits: [{ damage, faction }].
  update(dt, victims, obstacles) {
    const hits = []
    for (const a of this.list) {
      if (a.stuck) {
        a.stuck += dt
        a.g.alpha = Math.max(0, 1 - a.stuck / 1.2)
        continue
      }
      a.x += a.vx * dt
      a.y += a.vy * dt
      const step = Math.hypot(a.vx, a.vy) * dt
      a.left -= step
      a.flown += step
      a.g.position.set(a.x, a.y)
      if (victims.some((v) => Math.hypot(v.x - a.x, v.y - a.y) < v.r + 3)) {
        hits.push({ damage: a.damage, faction: a.faction })
        a.stuck = 1.2 // gone at once
      } else if (a.left <= 0 || (a.flown > 30 && obstacles.some((o) => Math.hypot(o.x - a.x, o.y - a.y) < o.radius))) {
        // Drops spent, or sticks in cover (once clear of the archer's own
        // perch, such as a watchtower), then fades.
        a.stuck = dt
      }
    }
    this.list = this.list.filter((a) => {
      if (a.stuck < 1.2) return true
      a.g.destroy()
      return false
    })
    return hits
  }
}
