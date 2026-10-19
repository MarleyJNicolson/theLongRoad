import { Container, Graphics } from 'pixi.js'

// A jointed humanoid seen in three-quarter view: legs, arms, torso and head,
// posed procedurally (walking, swinging weapons, flinching) and turned into
// a verlet ragdoll when it dies.
//
// Poses are worked out in the figure's own 3D frame: `a` forward along the
// way it faces, `b` to its right, `z` up. They're drawn by putting the
// ground position on the map and lifting it by its height, so a figure seen
// from any direction shows its limbs, and parts nearer the camera (lower on
// the screen) are drawn over the ones further away.

// Body proportions for a figure of scale 1 (an adult).
export const BODY = {
  hip: 15, // height of the hips
  thigh: 7.8,
  shin: 7.8,
  torso: 11,
  neck: 2.5,
  head: 4.6, // radius
  hipW: 3,
  shoulderW: 5.2,
  upperArm: 6.2,
  foreArm: 6.2,
  stride: 5.5,
  lift: 3,
}

// How far each kind of weapon reaches from the hand, and how it's drawn.
export const WEAPON_LENGTH = { dagger: 9, club: 14, sword: 18, cleaver: 18, mace: 15, spear: 30, axe: 16 }

const GRAVITY = 900
const RAGDOLL_TIME = 1.8 // seconds before a corpse settles for good

const add = (p, q) => ({ a: p.a + q.a, b: p.b + q.b, z: p.z + q.z })
const scale = (p, k) => ({ a: p.a * k, b: p.b * k, z: p.z * k })
const lerp = (x, y, t) => x + (y - x) * t
const ease = (t) => 1 - (1 - t) * (1 - t)

// Two-bone limb: where the middle joint sits, bending towards `bend`
// (+1 forwards, -1 backwards) in the limb's own vertical plane.
export function joint(from, to, upper, lower, bend) {
  const da = to.a - from.a
  const dz = to.z - from.z
  const db = to.b - from.b
  const len = Math.min(Math.hypot(da, db, dz), upper + lower - 0.01) || 0.01
  const reach = Math.hypot(da, db, dz) || 0.01
  // distance along the limb to the joint, and how far it pokes out
  const x = (upper * upper - lower * lower + len * len) / (2 * len)
  const h = Math.sqrt(Math.max(0, upper * upper - x * x))
  const ua = da / reach
  const ub = db / reach
  const uz = dz / reach
  // perpendicular in the forward/up plane
  let pa = -uz * bend
  let pz = ua * bend
  const pl = Math.hypot(pa, pz) || 1
  pa /= pl
  pz /= pl
  return { a: from.a + ua * x + pa * h, b: from.b + ub * x, z: from.z + uz * x + pz * h }
}

export class Rig {
  // `style`: { scale, skin, shirt, legs, boots, head: 'straw'|'hood'|'goblin'|'orc'|'helm'|'hat',
  //            headColour, extras: ['quiver', 'cape', 'ears', 'tusks'], capeColour }
  constructor(style) {
    this.style = { scale: 1, boots: '#2b221c', ...style }
    this.k = this.style.scale
    this.view = new Container()
    this.g = new Graphics()
    this.view.addChild(this.g)
    this.facing = Math.PI / 2
    this.phase = Math.random() * Math.PI * 2
    this.speed = 0
    this.weapon = null // dagger, club, sword, cleaver, mace, spear, axe (or null: fists)
    this.offhand = null // bow, crossbow, sling, shield
    this.loaded = true // an arrow nocked on the bow
    this.aiming = false
    this.pull = 0 // how far the bow (or crossbow) string is drawn back, 0..1
    this.spin = 0 // a sling's whirl
    this.lean = 0 // leaning into a sprint or dash, 0..1
    this.seated = false // sitting (on the cart's bench), hips at `seatZ`
    this.seatZ = 0
    this.wave = 0 // waving (a villager's greeting), 0 for not; counts up while waving
    this.move = null // a player's attack: { name, t, back, windup }
    this.strike = null // a raider's attack: { phase, p }
    this.trail = null // the arc of a swing, while it lasts
    this.kick = 0 // bow recoil
    this.flinch = 0
    this.ragdoll = null
    this.stuck = [] // arrows and bolts sticking out of it
  }

  get height() {
    const b = BODY
    return (b.hip + b.torso + b.neck + b.head * 2) * this.k
  }

  // --- Driving it -------------------------------------------------------------

  play(move, { back = false, windup = 0 } = {}) {
    this.move = { name: move, t: 0, back, windup }
  }

  setStrike(phase, p) {
    this.strike = phase ? { phase, p } : null
  }

  loose() {
    this.kick = 1
  }

  hitBy() {
    this.flinch = 1
  }

  // Go limp: start the ragdoll from the current pose, flung along (dx, dy).
  die(dx = 0, dy = 0, force = 1) {
    if (this.ragdoll) return
    const pose = this.pose()
    const f = { x: Math.cos(this.facing), y: Math.sin(this.facing) }
    const l = { x: -f.y, y: f.x }
    const parts = {}
    for (const [name, p] of Object.entries(pose.joints)) {
      const x = f.x * p.a + l.x * p.b
      const y = f.y * p.a + l.y * p.b
      // Knocked along the blow, the upper body most, with a little lift
      const push = (60 + 90 * force) * (0.4 + p.z / this.height)
      const vx = dx * push + (Math.random() - 0.5) * 30
      const vy = dy * push + (Math.random() - 0.5) * 30
      const vz = 40 + Math.random() * 30
      const dt = 1 / 60
      parts[name] = { x, y, z: p.z, px: x - vx * dt, py: y - vy * dt, pz: p.z - vz * dt }
    }
    const sticks = [
      ['hipL', 'kneeL'], ['kneeL', 'footL'], ['hipR', 'kneeR'], ['kneeR', 'footR'],
      ['shL', 'elbL'], ['elbL', 'handL'], ['shR', 'elbR'], ['elbR', 'handR'],
      ['neck', 'head'], ['shL', 'shR'], ['hipL', 'hipR'], ['shL', 'hipL'], ['shR', 'hipR'],
      ['shL', 'hipR'], ['shR', 'hipL'], ['neck', 'shL'], ['neck', 'shR'], ['neck', 'hipL'], ['neck', 'hipR'],
    ].map(([p, q]) => [parts[p], parts[q], Math.hypot(parts[p].x - parts[q].x, parts[p].y - parts[q].y, parts[p].z - parts[q].z)])
    this.ragdoll = { parts, sticks, t: 0, weapon: this.weapon, offhand: this.offhand }
    this.move = this.strike = this.trail = null
  }

  // An arrow or bolt flying along (dirX, dirY) sticks in somewhere on the
  // body and stays there, through death and all.
  stickShaft(dirX, dirY, kind = 'arrow') {
    const spots = [
      ['neck', 'hipL', 0.2, 0.7], ['neck', 'hipR', 0.2, 0.7], ['neck', 'hipL', 0.3, 0.6], // the trunk, most of all
      ['shL', 'elbL', 0.2, 0.8], ['shR', 'elbR', 0.2, 0.8],
      ['hipL', 'kneeL', 0.2, 0.8], ['hipR', 'kneeR', 0.2, 0.8],
    ]
    const [a, b, lo, hi] = spots[Math.floor(Math.random() * spots.length)]
    this.stuck.push({
      a,
      b,
      t: lo + Math.random() * (hi - lo),
      rel: Math.atan2(dirY, dirX) - this.facing + (Math.random() - 0.5) * 0.5, // which way it came, relative to the body
      tilt: Math.random() * 0.5,
      kind,
    })
    if (this.stuck.length > 8) this.stuck.shift()
  }

  drawShaft(g, pts, s) {
    const k = this.k
    const p = { x: lerp(pts[s.a].x, pts[s.b].x, s.t), y: lerp(pts[s.a].y, pts[s.b].y, s.t) }
    const ang = this.facing + s.rel
    // What shows is the back end, pointing back the way it came
    const len = (s.kind === 'bolt' ? 5 : 8) * k
    const end = { x: p.x - Math.cos(ang) * len, y: p.y - Math.sin(ang) * len - s.tilt * len }
    g.moveTo(p.x, p.y).lineTo(end.x, end.y).stroke({ width: 1.2 * k, color: s.kind === 'bolt' ? '#5e3f22' : '#8b6236', cap: 'round' })
    const feather = s.kind === 'bolt' ? '#5e3f22' : '#e8e0c8'
    const nx = -Math.sin(ang) * 1.6 * k
    const ny = Math.cos(ang) * 0.8 * k
    const back = { x: end.x + Math.cos(ang) * 2.5 * k, y: end.y + Math.sin(ang) * 2.5 * k }
    g.poly([end.x, end.y, back.x + nx, back.y + ny, back.x - nx, back.y - ny]).fill(feather)
  }

  // Where the weapon is, as points on the ground relative to the figure, from
  // near the hand out to the tip (used to tell whether a blow connects).
  weaponPoints() {
    const { hand, dir } = this.pose().weapon
    const len = (WEAPON_LENGTH[this.weapon] ?? 3) * this.k
    const f = { x: Math.cos(this.facing), y: Math.sin(this.facing) }
    const l = { x: -f.y, y: f.x }
    return [0.35, 0.7, 1].map((t) => {
      const p = add(hand, scale(dir, len * t))
      return { x: f.x * p.a + l.x * p.b, y: f.y * p.a + l.y * p.b }
    })
  }

  // --- Each frame -------------------------------------------------------------

  update(dt, facing, speed) {
    if (this.ragdoll) {
      this.simulate(dt)
    } else {
      this.facing = facing
      this.speed = speed
      this.phase += (speed * dt) / (5.5 * this.k)
      if (this.move) this.move.t += dt
      if (this.wave) this.wave += dt
      this.kick = Math.max(0, this.kick - dt * 6)
      // A sling whirls faster the closer it is to being let fly
      if (this.offhand === 'sling' && this.aiming) this.spin += dt * (6 + this.pull * 22)
      this.flinch = Math.max(0, this.flinch - dt * 4)
    }
    this.draw()
  }

  // The figure's joints right now, plus where its weapon hand and weapon point.
  pose() {
    const k = this.k
    const B = BODY
    const walk = Math.min(1, this.speed / 40)
    const bob = Math.abs(Math.sin(this.phase)) * 1.2 * walk
    // Knocked back on the heels by a blow; leaning in to a sprint or dash
    const lean = -this.flinch * 3 + this.lean * 3.5
    const hipZ = this.seated ? this.seatZ : (B.hip + bob - this.flinch * 1.5) * k
    const chest = { a: lean * k, b: 0, z: hipZ + B.torso * k }
    const j = {}
    j.neck = add(chest, { a: lean * 0.5 * k, b: 0, z: B.neck * 0.3 * k })
    j.head = add(chest, { a: lean * 0.8 * k, b: 0, z: (B.neck + B.head) * k })

    for (const [side, s] of [['L', -1], ['R', 1]]) {
      const legPhase = this.phase + (s > 0 ? Math.PI : 0)
      const hip = { a: 0, b: s * B.hipW * k, z: hipZ }
      // Sitting: feet planted on the footboard in front
      const foot = this.seated
        ? { a: 6 * k, b: s * (B.hipW + 0.5) * k, z: hipZ - 9 * k }
        : {
            a: Math.sin(legPhase) * B.stride * walk * k,
            b: s * B.hipW * k,
            z: Math.max(0, Math.cos(legPhase)) * B.lift * walk * k,
          }
      j['hip' + side] = hip
      j['foot' + side] = foot
      j['knee' + side] = joint(hip, foot, B.thigh * k, B.shin * k, 1)
      const sh = { a: chest.a, b: s * B.shoulderW * k, z: chest.z - 1 * k }
      j['sh' + side] = sh
      // Hanging, swinging opposite the legs (or holding the reins out in front)
      j['hand' + side] = this.seated
        ? { a: 7 * k, b: s * 3 * k, z: hipZ + 6 * k }
        : {
        a: sh.a - Math.sin(legPhase) * 3.5 * walk * k + 1.5 * k,
        b: s * (B.shoulderW + 1.2) * k,
        z: sh.z - (B.upperArm + B.foreArm - 2.5) * k,
      }
    }

    // Weapon hand (right)
    let weapon = this.weaponHand(j.shR)
    // (A seated driver with nothing in hand keeps it on the reins)
    if (!(this.seated && !this.weapon && !this.move && !this.strike)) j.handR = weapon.hand
    // Off hand (left): a bow held up to shoot, or a shield held before you
    if (this.offhand === 'shield') {
      j.handL = { a: j.shL.a + 7 * k, b: -3 * k, z: j.shL.z - 4 * k }
    } else if (this.offhand && (this.aiming || this.offhand === 'crossbow')) {
      j.handL = { a: j.shL.a + (10 - this.kick * 2) * k, b: -1.5 * k, z: j.shL.z - 1 * k }
    }
    // Drawing a bow: the right hand pulls the string back towards the cheek.
    // Spanning a crossbow: hauls the string back to the latch, then takes
    // the stock once it's cocked.
    const drawing = this.aiming && !this.move && !this.strike
    if (drawing && this.offhand === 'bow') {
      j.handR = add(j.handL, { a: -(2 + this.pull * 8) * k, b: 1 * k, z: (1 + this.pull) * k })
      weapon = { hand: j.handR, dir: weapon.dir }
    } else if (drawing && this.offhand === 'crossbow') {
      j.handR = add(j.handL, { a: -(this.pull < 1 ? this.pull * 6 : 6) * k, b: 1.5 * k, z: this.pull < 1 ? 1.5 * k : -1 * k })
      weapon = { hand: j.handR, dir: weapon.dir }
    }
    // Waving: the right hand up above the head, swaying side to side
    if (this.wave && !this.weapon) {
      j.handR = { a: 2 * k, b: (B.shoulderW + 2.5 + Math.sin(this.wave * 9) * 2.5) * k, z: chest.z + 8 * k }
    }
    for (const [side, bend] of [['L', -1], ['R', -1]]) {
      j['elb' + side] = joint(j['sh' + side], j['hand' + side], B.upperArm * k, B.foreArm * k, bend)
    }
    return { joints: j, weapon }
  }

  // Where the weapon hand is and which way the weapon points, for the attack
  // in progress (if any).
  weaponHand(sh) {
    const k = this.k
    const R = (BODY.upperArm + BODY.foreArm - 1.5) * k
    // A sweep round the shoulder at angle α (0 = straight ahead, + = to the right)
    const sweep = (alpha, lift = 0, tilt = 0.05) => ({
      hand: add(sh, { a: Math.cos(alpha) * R * 0.9, b: Math.sin(alpha) * R * 0.9, z: -2 * k + lift * k }),
      dir: { a: Math.cos(alpha), b: Math.sin(alpha), z: tilt },
    })
    const rest = {
      hand: add(sh, { a: 3 * k, b: 1.5 * k, z: -(BODY.upperArm + BODY.foreArm - 4) * k }),
      dir: { a: 0.55, b: 0.2, z: 0.81 },
    }
    this.trail = null
    const m = this.move
    const s = this.strike
    if (s) {
      // A raider: wind up, swing through, recover
      if (s.phase === 'windup') return sweep(lerp(0.6, 1.9, ease(s.p)), 5 * s.p, 0.4 * s.p)
      if (s.phase === 'swing') {
        const alpha = lerp(1.9, -1.0, s.p * s.p)
        this.trail = [1.9, alpha]
        return sweep(alpha, 5 - 6 * s.p)
      }
      return sweep(lerp(-1.0, 0.6, ease(s.p)), -1 + s.p)
    }
    if (m) {
      const T = { swing: 0.18, slash: 0.11, jab: 0.2, heavy: 0.16 }[m.name]
      if (m.name === 'swing' || m.name === 'slash') {
        const p = m.t / T
        if (p < 1) {
          const [from, to] = m.back ? [-1.1, 1.3] : [1.3, -1.1]
          const alpha = lerp(from, to, ease(p))
          this.trail = [from, alpha]
          return sweep(alpha)
        }
      } else if (m.name === 'jab') {
        const p = m.t / T
        if (p < 1) {
          const out = Math.sin(p * Math.PI)
          return { hand: add(sh, { a: (4 + 10 * out) * k, b: 0.5 * k, z: -3 * k }), dir: { a: 1, b: -0.05, z: 0.02 } }
        }
      } else if (m.name === 'heavy') {
        if (m.t < m.windup) {
          const p = ease(m.t / m.windup)
          return sweep(lerp(0.6, 2.2, p), 9 * p, 0.9 * p)
        }
        const p = (m.t - m.windup) / T
        if (p < 1) {
          const alpha = lerp(2.2, -1.2, p * p)
          this.trail = [2.2, alpha]
          return sweep(alpha, 9 - 12 * p, 0.9 - 1.2 * p)
        }
      }
      this.move = null
    }
    return rest
  }

  // --- Ragdoll ----------------------------------------------------------------

  simulate(dt) {
    const r = this.ragdoll
    if (r.t > RAGDOLL_TIME) return
    r.t += dt
    const steps = 2
    const h = Math.min(dt, 1 / 30) / steps
    for (let s = 0; s < steps; s++) {
      for (const p of Object.values(r.parts)) {
        const vx = (p.x - p.px) * 0.99
        const vy = (p.y - p.py) * 0.99
        const vz = (p.z - p.pz) * 0.99
        p.px = p.x
        p.py = p.y
        p.pz = p.z
        p.x += vx
        p.y += vy
        p.z += vz - GRAVITY * h * h
        if (p.z < 0) {
          // Hit the ground: stop falling, and drag
          p.z = 0
          p.pz = 0
          p.px = p.x - vx * 0.55
          p.py = p.y - vy * 0.55
        }
      }
      for (let it = 0; it < 6; it++) {
        for (const [p, q, len] of r.sticks) {
          const dx = q.x - p.x
          const dy = q.y - p.y
          const dz = q.z - p.z
          const d = Math.hypot(dx, dy, dz) || 0.001
          const diff = (d - len) / d / 2
          p.x += dx * diff
          p.y += dy * diff
          p.z += dz * diff
          q.x -= dx * diff
          q.y -= dy * diff
          q.z -= dz * diff
        }
      }
    }
  }

  // --- Drawing ----------------------------------------------------------------

  draw() {
    const g = this.g.clear()
    const st = this.style
    const k = this.k
    let pts // screen position of each joint: { x, y, d (depth: higher is nearer) }
    let weaponLine = null
    if (this.ragdoll) {
      pts = {}
      for (const [n, p] of Object.entries(this.ragdoll.parts)) pts[n] = { x: p.x, y: p.y - p.z, d: p.y, z: p.z }
      const hand = this.ragdoll.parts.handR
      const elb = this.ragdoll.parts.elbR
      if (this.ragdoll.weapon) weaponLine = this.weaponFrom(pts.handR, { x: hand.x - elb.x, y: hand.y - elb.y, z: hand.z - elb.z }, true)
    } else {
      const { joints, weapon } = this.pose()
      const f = { x: Math.cos(this.facing), y: Math.sin(this.facing) }
      const l = { x: -f.y, y: f.x }
      const proj = (p) => {
        const x = f.x * p.a + l.x * p.b
        const y = f.y * p.a + l.y * p.b
        return { x, y: y - p.z, d: y, z: p.z }
      }
      pts = {}
      for (const [n, p] of Object.entries(joints)) pts[n] = proj(p)
      if (this.weapon) {
        const w = { x: f.x * weapon.dir.a + l.x * weapon.dir.b, y: f.y * weapon.dir.a + l.y * weapon.dir.b, z: weapon.dir.z }
        weaponLine = this.weaponFrom(pts.handR, w)
      }
      // A faint trail along the path of a swing
      if (this.trail) {
        const R = (BODY.upperArm + BODY.foreArm + (WEAPON_LENGTH[this.weapon] ?? 3)) * k
        const [from, to] = this.trail
        const steps = 8
        const sh = joints.shR
        for (let n = 0; n <= steps; n++) {
          const al = lerp(from, to, n / steps)
          const q = proj(add(sh, { a: Math.cos(al) * R, b: Math.sin(al) * R, z: -2 * k }))
          n === 0 ? g.moveTo(q.x, q.y) : g.lineTo(q.x, q.y)
        }
        g.stroke({ width: 2.5, color: '#fff4d6', alpha: 0.6, cap: 'round' })
      }
    }

    // Shadow on the ground under the body
    const cx = (pts.hipL.x + pts.hipR.x) / 2
    const cy = (pts.hipL.d + pts.hipR.d) / 2
    if (!this.ragdoll && !this.seated) g.ellipse(cx, cy, 7 * k, 3 * k).fill({ color: '#000', alpha: 0.25 })

    // Parts, drawn far to near
    const parts = []
    const limb = (a, b, c, width, colour, end) => {
      parts.push({
        d: (pts[a].d + pts[b].d + pts[c].d) / 3,
        draw: () => {
          g.moveTo(pts[a].x, pts[a].y).lineTo(pts[b].x, pts[b].y).lineTo(pts[c].x, pts[c].y)
          g.stroke({ width: width * k, color: colour, cap: 'round', join: 'round' })
          if (end) g.circle(pts[c].x, pts[c].y, end.r * k).fill(end.colour)
        },
      })
    }
    limb('hipL', 'kneeL', 'footL', 3.4, st.legs, { r: 1.9, colour: st.boots })
    limb('hipR', 'kneeR', 'footR', 3.4, st.legs, { r: 1.9, colour: st.boots })
    limb('shL', 'elbL', 'handL', 2.8, st.shirt, { r: 1.6, colour: st.skin })
    limb('shR', 'elbR', 'handR', 2.8, st.shirt, { r: 1.6, colour: st.skin })

    const torsoDepth = (pts.shL.d + pts.shR.d + pts.hipL.d + pts.hipR.d) / 4
    const neck = this.ragdoll ? pts.neck : pts.neck
    parts.push({
      d: torsoDepth,
      draw: () => {
        const hipMid = { x: (pts.hipL.x + pts.hipR.x) / 2, y: (pts.hipL.y + pts.hipR.y) / 2 }
        g.moveTo(hipMid.x, hipMid.y).lineTo(neck.x, neck.y).stroke({ width: 8 * k, color: st.shirt, cap: 'round' })
        g.poly([pts.shL.x, pts.shL.y, pts.shR.x, pts.shR.y, pts.hipR.x, pts.hipR.y, pts.hipL.x, pts.hipL.y]).fill(st.shirt)
        // Belt
        g.moveTo(pts.hipL.x, pts.hipL.y).lineTo(pts.hipR.x, pts.hipR.y).stroke({ width: 2 * k, color: '#2b221c', cap: 'round' })
        if (st.extras?.includes('apron')) {
          const lo = (p, t) => ({ x: lerp(neck.x, p.x, t), y: lerp(neck.y, p.y, t) + 4 * k * t })
          const [a, b] = [lo(pts.hipL, 1.15), lo(pts.hipR, 1.15)]
          g.poly([lerp(pts.shL.x, pts.hipL.x, 0.4), lerp(pts.shL.y, pts.hipL.y, 0.4), lerp(pts.shR.x, pts.hipR.x, 0.4), lerp(pts.shR.y, pts.hipR.y, 0.4), b.x, b.y, a.x, a.y])
          g.fill(st.apron ?? '#d8cfb4')
        }
        if (st.extras?.includes('cape')) {
          g.poly([pts.shL.x, pts.shL.y, pts.shR.x, pts.shR.y, pts.hipR.x, pts.hipR.y + 3 * k, pts.hipL.x, pts.hipL.y + 3 * k])
          g.fill({ color: st.capeColour, alpha: 0.9 })
        }
      },
    })
    if (st.extras?.includes('quiver')) {
      parts.push({
        d: torsoDepth - 2 * k * Math.sin(this.facing),
        draw: () => {
          const x = (pts.shL.x + pts.shR.x) / 2 - Math.cos(this.facing) * 3 * k
          const y = (pts.shL.y + pts.shR.y) / 2 - Math.sin(this.facing) * 1.5 * k
          g.roundRect(x - 2 * k, y - 2 * k, 4 * k, 9 * k, 1).fill('#6e4a28')
          g.moveTo(x - 1 * k, y - 2 * k).lineTo(x - 1.5 * k, y - 5 * k).moveTo(x + 1 * k, y - 2 * k).lineTo(x + 1.5 * k, y - 5 * k)
          g.stroke({ width: 1, color: '#e8e0c8' })
        },
      })
    }
    parts.push({ d: pts.head.d + 0.01, draw: () => this.drawHead(g, pts.head) })
    if (weaponLine) parts.push({ d: pts.handR.d + 0.02, draw: weaponLine })
    const off = this.offhand && (this.ragdoll ? this.ragdoll.offhand : this.offhand)
    if (off) parts.push({ d: pts.handL.d + 0.02, draw: () => this.drawOffhand(g, pts, off) })

    for (const s of this.stuck) {
      const d = lerp(pts[s.a].d, pts[s.b].d, s.t) - Math.sin(this.facing + s.rel) * 2
      parts.push({ d, draw: () => this.drawShaft(g, pts, s) })
    }

    parts.sort((p, q) => p.d - q.d)
    for (const p of parts) p.draw()
  }

  drawHead(g, at) {
    const st = this.style
    const k = this.k
    const r = BODY.head * k * (st.head === 'orc' ? 1.25 : st.head === 'goblin' ? 1.15 : 1)
    const f = { x: Math.cos(this.facing), y: Math.sin(this.facing) }
    const facesUs = !this.ragdoll && f.y > -0.25 // can we see the face?
    const fx = f.x * r * 0.45
    const skin = st.skin
    if (st.head === 'goblin' || st.extras?.includes('ears')) {
      g.poly([at.x - r * 0.6, at.y, at.x - r * 1.9, at.y - r * 0.7, at.x - r * 0.4, at.y - r * 0.3]).fill(skin)
      g.poly([at.x + r * 0.6, at.y, at.x + r * 1.9, at.y - r * 0.7, at.x + r * 0.4, at.y - r * 0.3]).fill(skin)
    }
    g.circle(at.x, at.y, r).fill(skin)
    const eyes = (colour, size = 0.8) => {
      if (!facesUs) return
      for (const s of [-1, 1]) g.circle(at.x + fx + s * r * 0.38 * Math.abs(f.y), at.y - r * 0.1, size * k).fill(colour)
    }
    switch (st.head) {
      case 'straw':
        eyes('#1c1714')
        g.ellipse(at.x, at.y - r * 0.6, r * 1.9, r * 0.75).fill('#d4b25e')
        g.ellipse(at.x, at.y - r * 0.85, r * 1.0, r * 0.6).fill('#c29d48')
        break
      case 'hood':
        g.circle(at.x, at.y - r * 0.1, r * 1.12).fill(st.headColour)
        if (facesUs) {
          g.circle(at.x + fx, at.y + r * 0.1, r * 0.7).fill(skin)
          eyes('#1c1714')
          if (st.mask) g.rect(at.x + fx - r * 0.7, at.y + r * 0.15, r * 1.4, r * 0.45).fill(st.mask)
        }
        break
      case 'helm':
        g.circle(at.x, at.y - r * 0.1, r * 1.12).fill('#a6aeb7')
        if (facesUs) g.rect(at.x + fx - r * 0.6, at.y - r * 0.15, r * 1.2, r * 0.22).fill('#1c1714')
        g.rect(at.x - r * 0.15, at.y - r * 1.2, r * 0.3, r * 0.6).fill('#7d8590')
        break
      case 'hat':
        eyes('#1c1714')
        g.ellipse(at.x, at.y - r * 0.55, r * 2.1, r * 0.7).fill(st.headColour)
        g.ellipse(at.x, at.y - r * 0.85, r * 1.0, r * 0.65).fill(st.headColour)
        g.rect(at.x - r, at.y - r * 0.75, r * 2, r * 0.2).fill('#c9a227')
        break
      case 'goblin':
        eyes('#ffe14d', 1)
        break
      case 'orc':
        eyes('#ffcf3a', 1)
        if (facesUs) {
          for (const s of [-1, 1]) g.poly([at.x + fx + s * r * 0.35, at.y + r * 0.35, at.x + fx + s * r * 0.5, at.y - r * 0.15, at.x + fx + s * r * 0.15, at.y + r * 0.3]).fill('#efe6cf')
        }
        g.rect(at.x - r * 0.9, at.y - r * 1.0, r * 1.8, r * 0.35).fill('#3a3620') // brow
        break
      case 'hair':
        g.circle(at.x - fx * 0.4, at.y - r * 0.25, r * 1.02).fill(st.headColour)
        if (facesUs) {
          g.circle(at.x + fx, at.y + r * 0.12, r * 0.72).fill(skin)
          eyes('#1c1714')
        }
        break
      case 'kerchief':
        if (facesUs) eyes('#1c1714')
        g.ellipse(at.x - fx * 0.3, at.y - r * 0.45, r * 1.08, r * 0.7).fill(st.headColour)
        break
      default:
        eyes('#1c1714')
    }
  }

  // Returns a function drawing the weapon from the hand along `dir`
  // (screen x/y on the ground plus height z).
  weaponFrom(hand, dir, fallen = false) {
    const kind = this.ragdoll ? this.ragdoll.weapon : this.weapon
    const len = (WEAPON_LENGTH[kind] ?? 3) * this.k
    const n = Math.hypot(dir.x, dir.y, dir.z) || 1
    const ux = dir.x / n
    const uy = (dir.y - (fallen ? 0 : dir.z)) / n
    const tip = { x: hand.x + ux * len, y: hand.y + uy * len }
    const at = (t) => ({ x: hand.x + ux * len * t, y: hand.y + uy * len * t })
    const g = this.g
    const k = this.k
    return () => {
      const line = (p, q, width, colour) => g.moveTo(p.x, p.y).lineTo(q.x, q.y).stroke({ width: width * k, color: colour, cap: 'round' })
      switch (kind) {
        case 'dagger':
          line(hand, tip, 1.8, '#c9c9c9')
          break
        case 'sword':
          line(hand, at(0.15), 2.2, '#5e3f22')
          line(at(0.15), tip, 2.4, '#d8dde2')
          g.moveTo(at(0.15).x - uy * 3.5 * k, at(0.15).y + ux * 3.5 * k).lineTo(at(0.15).x + uy * 3.5 * k, at(0.15).y - ux * 3.5 * k)
          g.stroke({ width: 1.8 * k, color: '#c9a227', cap: 'round' })
          break
        case 'club':
          line(hand, at(0.5), 2.4, '#6b4a2a')
          line(at(0.5), tip, 4, '#6b4a2a')
          break
        case 'mace':
          line(hand, at(0.75), 2, '#4a3220')
          g.circle(tip.x, tip.y, 3.2 * k).fill('#8a9096')
          break
        case 'cleaver': {
          line(hand, at(0.3), 2.6, '#4a3220')
          const w = 4.5 * k
          g.poly([at(0.3).x, at(0.3).y, tip.x, tip.y, tip.x - uy * w, tip.y + ux * w, at(0.3).x - uy * w, at(0.3).y + ux * w]).fill('#8a9096')
          break
        }
        case 'spear':
          line(hand, tip, 1.8, '#8b6236')
          g.poly([tip.x + ux * 5 * k, tip.y + uy * 5 * k, tip.x - uy * 2.2 * k, tip.y + ux * 2.2 * k, tip.x + uy * 2.2 * k, tip.y - ux * 2.2 * k]).fill('#d8dde2')
          line({ x: hand.x - ux * 6 * k, y: hand.y - uy * 6 * k }, hand, 1.8, '#8b6236')
          break
        case 'axe': {
          line(hand, tip, 2.2, '#6b4a2a')
          const w = 4.5 * k
          g.poly([at(0.75).x, at(0.75).y, tip.x, tip.y, tip.x - uy * w + ux * 2, tip.y + ux * w + uy * 2, at(0.75).x - uy * w, at(0.75).y + ux * w]).fill('#b9c0c8')
          break
        }
      }
    }
  }

  drawOffhand(g, pts, kind) {
    const k = this.k
    const h = pts.handL
    const f = { x: Math.cos(this.facing), y: Math.sin(this.facing) }
    if (kind === 'shield') {
      g.ellipse(h.x + f.x * 2 * k, h.y + f.y * 1 * k, 5.5 * k, 7 * k).fill('#6e4a28').stroke({ width: 1.5 * k, color: '#a6aeb7' })
      g.circle(h.x + f.x * 2 * k, h.y + f.y * 1 * k, 1.5 * k).fill('#a6aeb7')
      return
    }
    if (kind === 'bow') {
      // Held upright. While aiming, the string is drawn back with the arrow
      // nocked (`draw` 0..1); just after a shot it shivers.
      const drawn = this.aiming ? this.pull : 0
      const bend = 5 + drawn * 2 // the limbs flex as it's drawn
      const top = { x: h.x - f.x * drawn * 1.5 * k, y: h.y - (10 - drawn) * k }
      const bottom = { x: h.x - f.x * drawn * 1.5 * k, y: h.y + (8 - drawn) * k }
      const bulge = { x: h.x + f.x * bend * k, y: h.y - 1 * k + f.y * 2 * k }
      g.moveTo(top.x, top.y).quadraticCurveTo(bulge.x, bulge.y, bottom.x, bottom.y).stroke({ width: 1.8 * k, color: '#8b6236', cap: 'round' })
      const shiver = this.kick > 0 ? Math.sin(this.kick * 40) * this.kick * 2 : 0
      const pull = drawn * 9 - shiver
      const nock = { x: h.x - f.x * pull * k, y: h.y - 1 * k - f.y * pull * 0.5 * k }
      g.moveTo(top.x, top.y).lineTo(nock.x, nock.y).lineTo(bottom.x, bottom.y).stroke({ width: 0.8, color: '#e8e0c8' })
      if (this.aiming && this.loaded && drawn > 0.1) {
        const tip = { x: nock.x + f.x * 14 * k, y: nock.y + f.y * 6 * k }
        g.moveTo(nock.x, nock.y).lineTo(tip.x, tip.y).stroke({ width: 1.2 * k, color: '#8b6236' })
        g.circle(tip.x, tip.y, 1.2 * k).fill('#d8dde2')
      }
      return
    }
    if (kind === 'crossbow') {
      // Spanned by hauling the string back to the latch; the bolt goes on
      // once it's cocked
      g.moveTo(h.x - f.x * 4 * k, h.y - f.y * 2 * k).lineTo(h.x + f.x * 9 * k, h.y + f.y * 4 * k).stroke({ width: 3 * k, color: '#6e4a28', cap: 'round' })
      const px = h.x + f.x * 7 * k
      const py = h.y + f.y * 3 * k
      const cocked = this.aiming ? this.pull : 1
      const sx = px - f.x * cocked * 6 * k
      const sy = py - f.y * cocked * 3 * k
      g.moveTo(px - f.y * 7 * k, py + f.x * 3 * k - 1).quadraticCurveTo(px + f.x * 2 * k, py + f.y * 1 * k, px + f.y * 7 * k, py - f.x * 3 * k - 1)
      g.stroke({ width: 2 * k, color: '#b9c0c8', cap: 'round' })
      g.moveTo(px - f.y * 7 * k, py + f.x * 3 * k - 1).lineTo(sx, sy).lineTo(px + f.y * 7 * k, py - f.x * 3 * k - 1).stroke({ width: 0.8, color: '#e8e0c8' })
      if (this.loaded && cocked >= 1) g.moveTo(sx, sy).lineTo(px + f.x * 3 * k, py + f.y * 1.5 * k).stroke({ width: 1.4 * k, color: '#5e3f22' })
      return
    }
    if (kind === 'sling') {
      // Whirled round the hand, faster as the throw comes
      const r = (this.aiming ? 4 + this.pull * 3 : 0) * k
      const px = h.x + Math.cos(this.spin) * r
      const py = h.y + (this.aiming ? Math.sin(this.spin) * r * 0.5 - 6 * k : 6 * k)
      g.moveTo(h.x, h.y).lineTo(px, py).stroke({ width: 0.8, color: '#c9b28a' })
      g.ellipse(px, py, 2 * k, 1.6 * k).fill('#6e4a28')
      if (this.loaded) g.circle(px, py, 1.2 * k).fill('#9a968c')
    }
  }
}
