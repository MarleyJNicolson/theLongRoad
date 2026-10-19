import { Container, Graphics } from 'pixi.js'
import { Rig, BODY, WEAPON_LENGTH } from './rig.js'

const rand = (min, max) => min + Math.random() * (max - min)

// `leash` is how far from home they'll chase a cart before giving up; a
// peasant on foot they chase forever.
export const TYPES = {
  goblin: { hp: 2, speed: 165, radius: 10, healthBar: true, leash: 1300 },
  bandit: { hp: 2, speed: 125, radius: 13, healthBar: false, leash: 1500 },
  captain: { hp: 4, speed: 115, radius: 15, healthBar: true, leash: 1700 },
  // Archers hang back at `keep` distance and shoot from up to `range`.
  archer: {
    hp: 2, speed: 120, radius: 12, healthBar: false, leash: 1500, faction: 'bandit',
    shoots: { range: 620, keep: 430, speed: 480, aim: 0.75, step: 80 },
  },
  goblinArcher: {
    hp: 2, speed: 150, radius: 10, healthBar: true, leash: 1300, faction: 'goblin',
    shoots: { range: 540, keep: 370, speed: 450, aim: 0.6, step: 70 },
  },
  // Heavies, found in the big camps down side roads. `armour` is taken off
  // every hit they take (always at least 1 gets through); `heavy` adds to
  // the damage they deal.
  orc: { hp: 7, speed: 118, radius: 17, healthBar: true, leash: 1500, heavy: 1, faction: 'goblin' },
  brute: { hp: 6, speed: 100, radius: 15, healthBar: true, leash: 1600, heavy: 1, armour: 1, faction: 'bandit' },
}

// How each raider looks: build, clothes, head and what they carry.
const LOOKS = {
  goblin: { scale: 0.75, skin: '#6fa83a', shirt: '#5b4a2a', legs: '#4a3a22', head: 'goblin', weapon: 'dagger' },
  goblinArcher: { scale: 0.75, skin: '#6fa83a', shirt: '#4a3a22', legs: '#3d2f1e', head: 'goblin', offhand: 'bow', extras: ['quiver'] },
  bandit: { scale: 1, skin: '#c9a27a', shirt: '#4a3b30', legs: '#3a2f26', head: 'hood', headColour: '#2d2a26', mask: '#8c2f22', weapon: 'club' },
  archer: { scale: 1, skin: '#c9a27a', shirt: '#4a5230', legs: '#3a3f26', head: 'hood', headColour: '#3d4a2a', offhand: 'bow', extras: ['quiver'] },
  captain: { scale: 1.12, skin: '#c9a27a', shirt: '#3d2e26', legs: '#2a1f14', head: 'hat', headColour: '#2a1f14', weapon: 'sword', extras: ['cape'], capeColour: '#7a1f1a' },
  brute: { scale: 1.1, skin: '#c9a27a', shirt: '#7d8590', legs: '#575f6b', boots: '#3c424d', head: 'helm', weapon: 'mace', offhand: 'shield' },
  orc: { scale: 1.35, skin: '#5f7a4a', shirt: '#4a3a2a', legs: '#3d2f25', head: 'orc', weapon: 'cleaver' },
}

const BAR_WIDTH = 22
const BAR_HEIGHT = 4
const ALERT_TIME = 1.2
const MAX_CORPSES = 120

// How each raider fights hand to hand: the `windup` (the weapon drawn back:
// your chance to get clear), the `swing` (when it can actually hit), and the
// `cooldown` between attacks. Damage only counts if the drawn weapon (or
// fist) actually passes through you during the swing.
const ATTACKS = {
  goblin: { windup: 0.25, swing: 0.13, cooldown: 0.9 }, // dagger stab
  bandit: { windup: 0.35, swing: 0.17, cooldown: 1.2 }, // club
  captain: { windup: 0.3, swing: 0.15, cooldown: 1.0 }, // sword
  orc: { windup: 0.55, swing: 0.22, cooldown: 1.6 }, // cleaver
  brute: { windup: 0.45, swing: 0.2, cooldown: 1.4 }, // mace
  archer: { windup: 0.3, swing: 0.14, cooldown: 1.1 }, // a punch
  goblinArcher: { windup: 0.25, swing: 0.13, cooldown: 1.0 },
}
const RECOVER = 0.2 // seconds to bring the arm back
// Archers fight hand to hand inside this distance (from their edge), and go
// back to the bow once you're beyond MELEE_LEAVE.
const MELEE_ENTER = 34
const MELEE_LEAVE = 80
const RECOVER_TIME = 0.35 // pause after loosing an arrow

// A raider belongs to a home (camp or roadblock). It idles there until
// alerted, chases the cart, and gives up once dragged too far from home.
// It's drawn as a jointed figure (see rig.js) that walks, swings its weapon
// from the shoulder, flinches when hit and falls as a ragdoll.
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
    this.facing = home.facing ?? Math.PI / 2
    this.lastHit = { x: 0, y: 0, force: 1 }

    const look = LOOKS[type]
    this.rig = new Rig({ ...look, scale: look.scale * (this.elite ? 1.15 : 1) })
    this.rig.weapon = look.weapon ?? null
    this.rig.offhand = look.offhand ?? null
    this.rig.facing = this.facing

    // view: a ground layer (aura, blood), the figure, and markers above its head
    this.view = new Container()
    this.figure = new Container()
    this.figure.addChild(this.rig.view)
    if (this.elite) {
      // A smouldering red ring at their feet marks out the tough ones.
      this.view.addChild(
        new Graphics()
          .ellipse(0, 0, this.radius + 5, (this.radius + 5) * 0.5).fill({ color: '#c0392b', alpha: 0.2 })
          .ellipse(0, 0, this.radius + 5, (this.radius + 5) * 0.5).stroke({ width: 2, color: '#e8b923', alpha: 0.8 }),
      )
    }
    const top = -this.rig.height
    this.bar = new Graphics()
    this.bar.y = top - 8
    this.bar.visible = this.healthBar
    this.marker = new Graphics()
      .roundRect(-2, -14, 4, 9, 1.5)
      .fill('#e0463a')
      .circle(0, -1.5, 2.2)
      .fill('#e0463a')
    this.marker.y = top - 12
    this.marker.visible = false
    if (this.shoots) this.archery = { mode: 'decide', timer: 0 }
    this.attack = ATTACKS[type]
    this.blow = null // { phase: 'windup' | 'swing' | 'recover', t, landed }
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
    if (this.archery) this.archery.mode = 'decide'
    if (this.hidden) {
      // Burst out of hiding toward the road.
      this.hidden = false
      const f = this.home.facing ?? 0
      this.vx = Math.cos(f) * 220
      this.vy = Math.sin(f) * 220
    }
  }

  // `target` is who they're after ({ x, y, vx, vy }); `relentless` means
  // they won't give up the chase however far it leads them; `victims` are
  // the bodies their weapons can hurt ({ x, y, r }).
  update(dt, target, relentless, victims = []) {
    this.attackCooldown -= dt
    this.flash -= dt
    this.alert -= dt
    // Aim a little ahead of the target so chasers try to cut it off.
    const tx = target.x + target.vx * 0.4
    const ty = target.y + target.vy * 0.4

    if (!this.alive) {
      if (!this.dying) this.fall()
      this.dying += dt
      this.pool.scale.set(Math.min(1, this.dying / 1.5))
      // The blood gathers under the body wherever it came to rest
      const { hipL, hipR } = this.rig.ragdoll.parts
      this.pool.position.set((hipL.x + hipR.x) / 2, (hipL.y + hipR.y) / 2)
    } else if (this.state === 'chase') {
      if (!relentless && Math.hypot(this.x - this.home.x, this.y - this.home.y) > this.leash) this.state = 'return'
      // Archers only use their fists in a brawl
      const brawling = !this.shoots || this.archery.mode === 'melee'
      if (this.blow) this.fightOn(dt, target, victims)
      else if (this.shoots) this.skirmish(dt, target, tx, ty)
      else this.seek(dt, tx, ty, this.speed)
      if (brawling && !this.blow && this.attackCooldown <= 0 && this.inReach(victims)) this.startBlow(target)
    } else if (this.state === 'return') {
      if (this.blow) this.dropBlow()
      const d = this.seek(dt, this.home.x, this.home.y, this.speed * 0.6)
      if (d < 12) this.state = 'idle'
    } else {
      this.idle(dt)
    }

    this.rig.aiming = this.alive && this.state === 'chase' && this.archery?.mode === 'aim'
    this.rig.update(dt, this.facing, Math.hypot(this.vx, this.vy))
    this.view.position.set(this.x, this.y)
    // Nearer the bottom of the screen draws in front; the dead lie under all
    this.view.zIndex = this.alive ? this.y : this.y - 1e6
    this.view.visible = !this.hidden
    if (this.alive) this.figure.tint = this.flash > 0 ? 0xff7766 : 0xffffff
    this.marker.visible = this.alive && this.alert > 0
    this.marker.scale.set(1 + Math.max(0, this.alert - ALERT_TIME + 0.2) * 3)
  }

  // --- Melee ------------------------------------------------------------------

  // How far the weapon (or fist) can reach from the middle of the body.
  get reach() {
    const k = this.rig.k
    return ((BODY.upperArm + BODY.foreArm) * 0.85 + BODY.shoulderW + (WEAPON_LENGTH[this.rig.weapon] ?? 3)) * k
  }

  // Close enough that the weapon would reach one of the victims?
  inReach(victims) {
    return victims.some((v) => Math.hypot(v.x - this.x, v.y - this.y) < this.reach + v.r - 2)
  }

  startBlow(target) {
    this.blow = { phase: 'windup', t: 0, landed: false }
    this.facing = Math.atan2(target.y - this.y, target.x - this.x)
  }

  // One attack: draw the weapon back (still turning to track you), swing it
  // through (committed), then recover. Damage only if the weapon itself
  // passes through a victim during the swing.
  fightOn(dt, target, victims) {
    const b = this.blow
    const { windup, swing } = this.attack
    b.t += dt
    // Barely moving while attacking
    this.seek(dt, target.x, target.y, this.speed * 0.2, false, true)
    if (b.phase === 'windup') {
      this.facing = Math.atan2(target.y - this.y, target.x - this.x)
      this.rig.setStrike('windup', Math.min(1, b.t / windup))
      if (b.t >= windup) Object.assign(b, { phase: 'swing', t: 0 })
    } else if (b.phase === 'swing') {
      const p = Math.min(1, b.t / swing)
      this.rig.setStrike('swing', p)
      if (!b.landed && this.weaponHits(victims)) b.landed = true
      if (p >= 1) Object.assign(b, { phase: 'recover', t: 0 })
    } else {
      this.rig.setStrike('recover', Math.min(1, b.t / RECOVER))
      if (b.t >= RECOVER) {
        this.dropBlow()
        this.attackCooldown = this.attack.cooldown * (0.85 + Math.random() * 0.3)
      }
    }
  }

  // Does the weapon, as drawn right now, pass through a victim?
  weaponHits(victims) {
    return this.rig
      .weaponPoints()
      .some((p) => victims.some((v) => Math.hypot(v.x - (this.x + p.x), v.y - (this.y + p.y)) < v.r + 3))
  }

  // Interrupted (killed, or giving up the chase): put the weapon down.
  dropBlow() {
    this.blow = null
    this.rig.setStrike(null)
  }

  // An archer's fight, one step at a time:
  //   advance – walk in until within bow range
  //   aim     – stand still, arrow nocked, for `aim` seconds, then loose
  //   recover – a short pause after the shot
  //   step    – if you're too close, back off one `step` (slightly to the
  //             side) and stop again, so you can close the gap
  //   melee   – if you get right up to them, drop the bow and fight
  // They never shoot on the move. Sets `wantsShot` when an arrow is loosed.
  skirmish(dt, target, tx, ty) {
    const { keep, range, aim, step } = this.shoots
    const a = this.archery
    const dx = target.x - this.x
    const dy = target.y - this.y
    const dist = Math.hypot(dx, dy) || 1
    const gap = dist - this.radius
    const face = () => (this.facing = Math.atan2(dy, dx))
    a.timer -= dt

    if (gap < MELEE_ENTER) a.mode = 'melee'
    if (a.mode === 'melee' && gap > MELEE_LEAVE) a.mode = 'decide'
    if (a.mode === 'decide') {
      a.mode = dist > range * 0.85 ? 'advance' : 'aim'
      a.timer = aim
    }

    switch (a.mode) {
      case 'melee':
        this.seek(dt, tx, ty, this.speed)
        break
      case 'advance':
        this.seek(dt, tx, ty, this.speed)
        if (dist <= range * 0.75) {
          a.mode = 'aim'
          a.timer = aim
        }
        break
      case 'aim':
        this.seek(dt, this.x, this.y, 0, true)
        face()
        if (a.timer <= 0) {
          this.vx = this.vy = 0 // planted feet for the shot
          this.wantsShot = true
          this.rig.loose()
          a.mode = 'recover'
          a.timer = RECOVER_TIME
        }
        break
      case 'recover':
        this.seek(dt, this.x, this.y, 0, true)
        face()
        if (a.timer > 0) break
        if (dist < keep) {
          // One measured step back, angled off to one side
          const away = Math.atan2(-dy, -dx) + (Math.random() < 0.5 ? -1 : 1) * (0.3 + Math.random() * 0.4)
          a.to = { x: this.x + Math.cos(away) * step, y: this.y + Math.sin(away) * step }
          a.mode = 'step'
          a.timer = 1.5 // give up on the step if something's in the way
        } else {
          a.mode = 'decide'
        }
        break
      case 'step':
        if (this.seek(dt, a.to.x, a.to.y, this.speed * 0.85, true) < 8 || a.timer <= 0) {
          a.mode = 'aim'
          a.timer = aim
        }
        break
    }
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
      this.facing = Math.atan2(w.y - this.y, w.x - this.x)
    }
  }

  // Accelerate toward a point; returns the remaining distance. Turns to face
  // the way it's going (unless `keepFacing`).
  seek(dt, tx, ty, speed, arrive = false, keepFacing = false) {
    const dx = tx - this.x
    const dy = ty - this.y
    const dist = Math.hypot(dx, dy) || 1
    const want = arrive && dist < 6 ? 0 : speed
    const k = 1 - Math.exp(-dt * 5)
    this.vx += ((dx / dist) * want - this.vx) * k
    this.vy += ((dy / dist) * want - this.vy) * k
    this.drift(dt, 1)
    if (!keepFacing) {
      const moving = Math.hypot(this.vx, this.vy)
      if (moving > 8) this.facing = Math.atan2(this.vy, this.vx)
      else if (!this.home.wander && this.state === 'idle') this.facing = this.home.facing ?? this.facing
    }
    return dist
  }

  drift(dt, damping) {
    this.x += this.vx * dt
    this.y += this.vy * dt
    this.vx *= damping
    this.vy *= damping
  }

  // Go down: the body goes limp and falls as a ragdoll, flung by the blow
  // that killed it, darkening, in a slowly spreading pool of blood.
  fall() {
    this.rig.die(this.lastHit.x, this.lastHit.y, this.lastHit.force)
    this.vx = this.vy = 0
    this.figure.tint = 0x8a7e72
    this.pool = new Graphics()
      .ellipse(0, 0, this.radius * 1.3, this.radius * 0.7)
      .fill({ color: '#4a1514', alpha: 0.85 })
      .ellipse(this.radius * 0.4, this.radius * 0.1, this.radius * 0.6, this.radius * 0.3)
      .fill({ color: '#76201a', alpha: 0.6 })
    this.pool.scale.set(0)
    this.view.addChildAt(this.pool, 0)
    this.hidden = false // killed in their hiding place: they tumble out
    this.dropBlow()
    this.bar.visible = false
    this.marker.visible = false
  }

  // `force` scales the knockback (a heavy axe blow sends them flying).
  hit(dirX, dirY, damage = 1, force = 1) {
    this.hp -= Math.max(1, damage - (this.armour ?? 0))
    this.provoked = true
    this.lastHit = { x: dirX, y: dirY, force }
    this.drawBar()
    if (!this.alive) this.bar.visible = false
    this.flash = 0.15
    this.rig.hitBy()
    // Heavies barely budge.
    const shove = (this.heavy ? 90 : 260) * force
    this.vx = dirX * shove
    this.vy = dirY * shove
  }
}

export class Enemies {
  constructor(layer) {
    this.layer = layer
    this.layer.sortableChildren = true // figures overlap by depth (see Enemy.update)
    this.list = []
    this.threat = null // set by whoever is spawning (see Encounters.place)
  }

  get alive() {
    return this.list.filter((e) => e.alive)
  }

  // Ordinary goblins and bandits are sometimes archers instead (more so
  // further down the road).
  add(type, x, y, home) {
    if ((type === 'goblin' || type === 'bandit') && Math.random() < (this.threat?.archerChance ?? 0.12)) {
      type = type === 'goblin' ? 'goblinArcher' : 'archer'
    }
    const enemy = new Enemy(this.layer, type, x, y, home, this.threat)
    this.list.push(enemy)
    return enemy
  }

  // `target` is who they're after ({ x, y, vx, vy }); `bodies` are solid
  // circles they can't walk through (the horse, the cart, the peasant).
  // `victims` are the bodies raiders' weapons can hurt. Returns the arrows
  // loosed and melee blows landed this frame.
  update(dt, target, bodies, relentless = false, victims = []) {
    const volleys = []
    const blows = []
    for (const e of this.list) {
      const landedBefore = e.blow?.landed
      e.update(dt, target, relentless, victims)
      if (e.blow?.landed && !landedBefore) blows.push({ damage: e.damage, faction: e.faction })
      if (e.wantsShot) {
        e.wantsShot = false
        const dist = Math.hypot(target.x - e.x, target.y - e.y)
        if (e.alive && dist <= e.shoots.range) {
          // Lead the target by the arrow's flight time.
          const t = dist / e.shoots.speed
          volleys.push({
            x: e.x,
            y: e.y,
            aimX: target.x + target.vx * t,
            aimY: target.y + target.vy * t,
            speed: e.shoots.speed,
            range: e.shoots.range + 80,
            damage: e.damage,
            faction: e.faction,
          })
        }
      }
    }
    this.separate()
    this.keepOff(bodies)

    // The fallen stay where they lie (until their camp is left far behind),
    // but only so many: the oldest are cleared away first.
    let corpses = this.list.filter((e) => !e.alive).length
    this.list = this.list.filter((e) => {
      const gone = e.removed || (!e.alive && corpses > MAX_CORPSES)
      if (!e.alive && !e.removed && gone) corpses--
      if (!gone) return true
      e.view.destroy({ children: true })
      return false
    })
    return { volleys, blows }
  }

  // The horse and cart (and peasant) are solid: push raiders out to their
  // edge and stop them pressing inward, so they crowd round instead of
  // walking through.
  keepOff(bodies) {
    for (const e of this.list) {
      if (e.hidden || !e.alive) continue
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
        // Something in the way of where they're going (`slide`): work round
        // it instead of pressing into it.
        if (b.slide) {
          e.slideSide ??= Math.random() < 0.5 ? -1 : 1
          const along = e.vx * -ny + e.vy * nx
          const side = Math.abs(along) > 10 ? Math.sign(along) : e.slideSide
          const pace = Math.max(Math.abs(along), e.speed * 0.9)
          e.vx = -ny * side * pace
          e.vy = nx * side * pace
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
