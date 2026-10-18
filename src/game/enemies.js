import { Container, Graphics } from 'pixi.js'

const rand = (min, max) => min + Math.random() * (max - min)

export const TYPES = {
  goblin: { hp: 2, speed: 165, radius: 10, healthBar: true, leash: 650 },
  bandit: { hp: 2, speed: 125, radius: 13, healthBar: false, leash: 800 },
  captain: { hp: 4, speed: 115, radius: 15, healthBar: true, leash: 900 },
  // Heavies, found in the big camps down side roads. `armour` is taken off
  // every hit they take (always at least 1 gets through); `heavy` adds to
  // the damage they deal.
  orc: { hp: 7, speed: 118, radius: 17, healthBar: true, leash: 850, heavy: 1, faction: 'goblin' },
  brute: { hp: 6, speed: 100, radius: 15, healthBar: true, leash: 900, heavy: 1, armour: 1, faction: 'bandit' },
}

const BAR_WIDTH = 22
const BAR_HEIGHT = 4
const ALERT_TIME = 1.2

// Both are drawn top-down facing +x so rotation = direction of travel.
function drawGoblin(body, arms) {
  body.ellipse(2, 3, 9, 11).fill({ color: '#000', alpha: 0.2 })
  body.ellipse(-1, 0, 7, 9).fill('#5b4a2a')
  body.poly([0, -5, -3, -14, 4, -5]).fill('#5e9632')
  body.poly([0, 5, -3, 14, 4, 5]).fill('#5e9632')
  body.circle(1, 0, 6).fill('#6fa83a')
  body.circle(5, -2, 1.2).fill('#ffe14d')
  body.circle(5, 2, 1.2).fill('#ffe14d')
  arms[0].circle(0, 0, 2.5).fill('#6fa83a')
  arms[1].circle(0, 0, 2.5).fill('#6fa83a')
  arms[1].moveTo(0, 0).lineTo(9, 0).stroke({ width: 2, color: '#c9c9c9', cap: 'round' })
  arms[0].position.set(2, -8)
  arms[1].position.set(2, 8)
}

function drawBandit(body, arms) {
  body.ellipse(2, 3, 11, 14).fill({ color: '#000', alpha: 0.2 })
  body.ellipse(-1, 0, 8, 12).fill('#4a3b30')
  body.circle(1, 0, 7).fill('#2d2a26')
  body.roundRect(4, -5, 3, 10, 1).fill('#8c2f22')
  arms[0].circle(0, 0, 3).fill('#4a3b30')
  arms[1].circle(0, 0, 3).fill('#4a3b30')
  arms[1].moveTo(0, 0).lineTo(14, 2).stroke({ width: 4, color: '#6b4a2a', cap: 'round' })
  arms[0].position.set(2, -11)
  arms[1].position.set(2, 11)
}

// Bandit captain: broad, red-cloaked, wide-brimmed hat and a sword.
function drawCaptain(body, arms) {
  body.ellipse(2, 3, 13, 16).fill({ color: '#000', alpha: 0.2 })
  body.ellipse(-3, 0, 10, 15).fill('#7a1f1a')
  body.ellipse(0, 0, 8, 12).fill('#3d2e26')
  body.circle(1, 0, 10).fill('#2a1f14')
  body.circle(1, 0, 6).fill('#3d2e26')
  body.poly([7, -2, 13, 0, 7, 2]).fill('#c9a227')
  arms[0].circle(0, 0, 3.5).fill('#3d2e26')
  arms[1].circle(0, 0, 3.5).fill('#3d2e26')
  arms[1].moveTo(0, 0).lineTo(20, 1).stroke({ width: 3, color: '#d0d0d0', cap: 'round' })
  arms[1].moveTo(1, -3).lineTo(1, 3).stroke({ width: 2, color: '#c9a227' })
  arms[0].position.set(2, -13)
  arms[1].position.set(2, 13)
}

// Orc: hulking, grey-green, tusked, with a heavy cleaver.
function drawOrc(body, arms) {
  body.ellipse(3, 4, 15, 19).fill({ color: '#000', alpha: 0.22 })
  body.ellipse(-2, 0, 11, 17).fill('#4a3a2a')
  body.ellipse(-4, 0, 6, 15).fill('#5e4a34')
  body.circle(3, 0, 9).fill('#5f7a4a')
  body.circle(7, -4, 1.6).fill('#ffcf3a')
  body.circle(7, 4, 1.6).fill('#ffcf3a')
  body.poly([10, -4, 14, -6, 11, -2]).fill('#efe6cf')
  body.poly([10, 4, 14, 6, 11, 2]).fill('#efe6cf')
  arms[0].circle(0, 0, 4.5).fill('#5f7a4a')
  arms[1].circle(0, 0, 4.5).fill('#5f7a4a')
  arms[1].moveTo(0, 0).lineTo(12, 0).stroke({ width: 3, color: '#4a3220', cap: 'round' })
  arms[1].poly([10, -2, 22, -5, 23, 4, 10, 3]).fill('#8a9096')
  arms[0].position.set(3, -15)
  arms[1].position.set(3, 15)
}

// Armoured bandit: steel plate, helm with a visor slit, shield and mace.
function drawBrute(body, arms) {
  body.ellipse(2, 3, 13, 16).fill({ color: '#000', alpha: 0.22 })
  body.ellipse(-1, 0, 9, 13).fill('#7d8590')
  body.moveTo(-8, -6).lineTo(6, -6).moveTo(-8, 6).lineTo(6, 6).stroke({ width: 1.5, color: '#5a6068' })
  body.circle(1, 0, 7.5).fill('#a6aeb7')
  body.rect(5, -4, 2, 8).fill('#2a2a2a')
  arms[0].ellipse(4, 0, 4, 9).fill('#6e4a28').stroke({ width: 1.5, color: '#a6aeb7' })
  arms[1].circle(0, 0, 3.5).fill('#7d8590')
  arms[1].moveTo(0, 0).lineTo(14, 0).stroke({ width: 2.5, color: '#4a3220', cap: 'round' })
  arms[1].circle(15, 0, 4).fill('#8a9096')
  arms[0].position.set(4, -12)
  arms[1].position.set(2, 12)
}

const DRAW = { goblin: drawGoblin, bandit: drawBandit, captain: drawCaptain, orc: drawOrc, brute: drawBrute }

// A raider belongs to a home (camp or roadblock). It idles there until
// alerted, chases the cart, and gives up once dragged too far from home.
class Enemy {
  // `threat` (see threat.js) toughens raiders the further along the road
  // they're found; some turn up as elites.
  constructor(layer, type, x, y, home, threat = null) {
    Object.assign(this, TYPES[type])
    this.type = type
    this.x = x
    this.y = y
    this.vx = 0
    this.vy = 0
    this.speed *= rand(0.85, 1.1) * (threat?.speedMult ?? 1)
    this.hp += threat?.hpBonus ?? 0
    this.damage = (threat?.damage ?? 1) + (this.heavy ?? 0)
    this.faction ??= type === 'goblin' ? 'goblin' : 'bandit'
    this.elite = Math.random() < (threat?.eliteChance ?? 0)
    if (this.elite) {
      this.hp = Math.ceil(this.hp * 1.8)
      this.radius = Math.round(this.radius * 1.2)
      this.healthBar = true
    }
    this.gold = (this.elite ? 3 : 1) + (this.heavy ? 2 : 0)
    this.maxHp = this.hp
    this.home = home // { x, y, facing, wander?: { x, y, min, max } }
    this.state = 'idle'
    this.wanderTarget = null
    this.wanderTimer = rand(0, 3)
    this.attackCooldown = 0
    this.flash = 0
    this.alert = 0
    this.dying = 0
    this.provoked = false
    this.hidden = !!home.hidden // lying in wait, unseen and unhittable
    this.step = Math.random() * 10

    // view holds the rotating figure plus upright markers above it.
    this.view = new Container()
    this.figure = new Container()
    const body = new Graphics()
    const arms = [new Graphics(), new Graphics()]
    DRAW[type](body, arms)
    this.arms = arms
    this.armBase = arms.map((a) => a.x)
    this.figure.addChild(arms[0], arms[1], body)
    if (this.elite) {
      // A smouldering red ring marks out the tough ones.
      const aura = new Graphics()
        .circle(0, 0, this.radius + 5).fill({ color: '#c0392b', alpha: 0.18 })
        .circle(0, 0, this.radius + 5).stroke({ width: 2, color: '#e8b923', alpha: 0.8 })
      this.figure.addChildAt(aura, 0)
      this.figure.scale.set(1.2)
    }
    this.figure.rotation = home.facing ?? 0

    this.bar = new Graphics()
    this.bar.y = -this.radius - 12
    this.bar.visible = this.healthBar
    this.marker = new Graphics()
      .roundRect(-2, -14, 4, 9, 1.5)
      .fill('#e0463a')
      .circle(0, -1.5, 2.2)
      .fill('#e0463a')
    this.marker.y = -this.radius - 16
    this.marker.visible = false
    this.view.addChild(this.figure, this.bar, this.marker)
    this.drawBar()
    this.view.position.set(x, y)
    layer.addChild(this.view)
  }

  get alive() {
    return this.hp > 0
  }

  drawBar() {
    const fill = Math.max(0, this.hp / this.maxHp)
    this.bar
      .clear()
      .rect(-BAR_WIDTH / 2 - 1, -1, BAR_WIDTH + 2, BAR_HEIGHT + 2)
      .fill({ color: '#1a1008', alpha: 0.8 })
      .rect(-BAR_WIDTH / 2, 0, BAR_WIDTH * fill, BAR_HEIGHT)
      .fill(fill > 0.5 ? '#7ccf3a' : '#e0463a')
  }

  engage() {
    if (!this.alive || this.state === 'chase') return
    if (this.state === 'idle') this.alert = ALERT_TIME
    this.state = 'chase'
    if (this.hidden) {
      // Burst out of hiding toward the road.
      this.hidden = false
      const f = this.home.facing ?? 0
      this.vx = Math.cos(f) * 220
      this.vy = Math.sin(f) * 220
    }
  }

  update(dt, tx, ty) {
    this.attackCooldown -= dt
    this.flash -= dt
    this.alert -= dt

    if (!this.alive) {
      this.dying += dt
      this.figure.rotation += dt * 6
      this.view.alpha = Math.max(0, 1 - this.dying / 0.6)
      this.drift(dt, 0.9)
    } else if (this.state === 'chase') {
      if (Math.hypot(this.x - this.home.x, this.y - this.home.y) > this.leash) this.state = 'return'
      this.seek(dt, tx, ty, this.speed)
    } else if (this.state === 'return') {
      const d = this.seek(dt, this.home.x, this.home.y, this.speed * 0.6)
      if (d < 12) this.state = 'idle'
    } else {
      this.idle(dt)
    }

    this.view.position.set(this.x, this.y)
    this.view.visible = !this.hidden
    this.figure.tint = this.flash > 0 ? 0xff7766 : 0xffffff
    this.marker.visible = this.alive && this.alert > 0
    this.marker.scale.set(1 + Math.max(0, this.alert - ALERT_TIME + 0.2) * 3)
  }

  idle(dt) {
    const w = this.home.wander
    if (!w) {
      this.seek(dt, this.home.x, this.home.y, 40, true)
      return
    }
    // Mill about the camp, facing its centre when standing still.
    this.wanderTimer -= dt
    if (this.wanderTimer <= 0) {
      const a = rand(0, Math.PI * 2)
      const r = rand(w.min, w.max)
      this.wanderTarget = { x: w.x + Math.cos(a) * r, y: w.y + Math.sin(a) * r }
      this.wanderTimer = rand(2.5, 6)
    }
    const t = this.wanderTarget ?? this
    if (this.seek(dt, t.x, t.y, 35, true) < 6) {
      this.figure.rotation = Math.atan2(w.y - this.y, w.x - this.x)
    }
  }

  // Accelerate toward a point; returns the remaining distance.
  seek(dt, tx, ty, speed, arrive = false) {
    const dx = tx - this.x
    const dy = ty - this.y
    const dist = Math.hypot(dx, dy) || 1
    const want = arrive && dist < 6 ? 0 : speed
    const k = 1 - Math.exp(-dt * 5)
    this.vx += ((dx / dist) * want - this.vx) * k
    this.vy += ((dy / dist) * want - this.vy) * k
    this.drift(dt, 1)
    const moving = Math.hypot(this.vx, this.vy)
    if (moving > 8) this.figure.rotation = Math.atan2(this.vy, this.vx)
    else if (!this.home.wander && this.state === 'idle') this.figure.rotation = this.home.facing ?? 0
    this.step += moving * dt * 0.15
    this.arms.forEach((arm, i) => {
      arm.x = this.armBase[i] + Math.sin(this.step + i * Math.PI) * Math.min(3, moving / 15)
    })
    return dist
  }

  drift(dt, damping) {
    this.x += this.vx * dt
    this.y += this.vy * dt
    this.vx *= damping
    this.vy *= damping
  }

  hit(dirX, dirY, damage = 1) {
    this.hp -= Math.max(1, damage - (this.armour ?? 0))
    this.provoked = true
    this.drawBar()
    if (!this.alive) this.bar.visible = false
    this.flash = 0.15
    // Heavies barely budge.
    const shove = this.heavy ? 90 : 260
    this.vx = dirX * shove
    this.vy = dirY * shove
  }
}

export class Enemies {
  constructor(layer) {
    this.layer = layer
    this.list = []
    this.threat = null // set by whoever is spawning (see Encounters.place)
  }

  get alive() {
    return this.list.filter((e) => e.alive)
  }

  add(type, x, y, home) {
    const enemy = new Enemy(this.layer, type, x, y, home, this.threat)
    this.list.push(enemy)
    return enemy
  }

  // `target` is who they're after ({ x, y, vx, vy }); `bodies` are solid
  // circles they can't walk through (the horse, the cart, the peasant).
  update(dt, target, bodies) {
    // Aim a little ahead of the target so chasers try to cut it off.
    const lead = 0.4
    const tx = target.x + target.vx * lead
    const ty = target.y + target.vy * lead
    for (const e of this.list) e.update(dt, tx, ty)
    this.separate()
    this.keepOff(bodies)

    this.list = this.list.filter((e) => {
      const gone = e.removed || (!e.alive && e.dying > 0.6)
      if (!gone) return true
      e.view.destroy({ children: true })
      return false
    })
  }

  // The horse and cart are solid: push raiders out to their edge and stop
  // them pressing inward, so they crowd round instead of walking through.
  keepOff(bodies) {
    for (const e of this.list) {
      if (e.hidden) continue
      for (const b of bodies) {
        const dx = e.x - b.x
        const dy = e.y - b.y
        const d = Math.hypot(dx, dy) || 1
        const overlap = e.radius + b.r - d
        if (overlap <= 0) continue
        const nx = dx / d
        const ny = dy / d
        e.x += nx * overlap
        e.y += ny * overlap
        const inward = e.vx * nx + e.vy * ny
        if (inward < 0) {
          e.vx -= inward * nx
          e.vy -= inward * ny
        }
        e.view.position.set(e.x, e.y)
      }
    }
  }

  separate() {
    const alive = this.alive
    for (let a = 0; a < alive.length; a++) {
      for (let b = a + 1; b < alive.length; b++) {
        const e1 = alive[a]
        const e2 = alive[b]
        const dx = e2.x - e1.x
        const dy = e2.y - e1.y
        const d = Math.hypot(dx, dy) || 1
        const overlap = e1.radius + e2.radius - d
        if (overlap > 0) {
          e1.x -= (dx / d) * overlap * 0.5
          e1.y -= (dy / d) * overlap * 0.5
          e2.x += (dx / d) * overlap * 0.5
          e2.y += (dy / d) * overlap * 0.5
        }
      }
    }
  }
}
