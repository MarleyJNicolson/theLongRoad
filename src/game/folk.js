import { Rig } from './rig.js'

// Ordinary folk (villagers, traders, the farmer) on the same jointed figure
// as everyone else. They stand about, now and then stroll a few steps, and
// wave when there's something to be glad about.

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)]
const rand = (min, max) => min + Math.random() * (max - min)

const SKINS = ['#e0b896', '#d9b08c', '#c9a27a', '#a87b56', '#8a5f3e']
const SHIRTS = ['#6b5b3e', '#7d4a3a', '#4a5a6e', '#5e6b3a', '#8a7a5a', '#6e3f4a', '#9a8a6a']
const LEGS = ['#4a3a2b', '#3d3a33', '#5a4632', '#3a3f4a']
const HAIR = ['#2b221c', '#5a3a1a', '#8a6a3a', '#c9a24a', '#9a948a']
const KERCHIEFS = ['#a3331f', '#c9b28a', '#4a5a6e', '#e8e0c8']

const STROLL = 22 // px/s

export function folkLook(role = 'villager') {
  const base = { skin: pick(SKINS), shirt: pick(SHIRTS), legs: pick(LEGS) }
  if (role === 'farmer') return { ...base, head: 'straw', shirt: '#7a5a3a' }
  if (role === 'smith') return { ...base, head: 'hair', headColour: pick(HAIR), shirt: '#5a4a3e', extras: ['apron'], apron: '#3a2f26' }
  if (role === 'merchant') return { ...base, head: 'hat', headColour: pick(['#5e3f22', '#3a4a2a', '#6e3f4a']), extras: ['apron'] }
  return pick([
    { ...base, head: 'hair', headColour: pick(HAIR) },
    { ...base, head: 'kerchief', headColour: pick(KERCHIEFS) },
    { ...base, head: 'straw' },
    { ...base, head: 'hair', headColour: pick(HAIR), extras: ['apron'] },
  ])
}

export class Folk {
  // `wander`: how far from home they stroll (0 to stay put).
  constructor(look, x, y, facing, { wander = 0, scale = 1 } = {}) {
    this.rig = new Rig({ scale, ...look })
    this.view = this.rig.view
    this.x = x
    this.y = y
    this.home = { x, y }
    this.facing = facing
    this.restFacing = facing
    this.wander = wander
    this.target = null
    this.idle = rand(1, 5)
    this.view.position.set(x, y)
    this.view.zIndex = y
    this.rig.update(0, facing, 0)
  }

  set visible(v) {
    this.view.visible = v
  }

  get visible() {
    return this.view.visible
  }

  waving(on) {
    this.rig.wave = on ? this.rig.wave || 0.001 : 0
  }

  update(dt) {
    if (!this.view.visible) return
    let speed = 0
    if (this.target) {
      const dx = this.target.x - this.x
      const dy = this.target.y - this.y
      const d = Math.hypot(dx, dy)
      if (d < 2) {
        this.target = null
        this.idle = rand(2, 6)
      } else {
        speed = STROLL
        this.facing = Math.atan2(dy, dx)
        this.x += (dx / d) * speed * dt
        this.y += (dy / d) * speed * dt
      }
    } else if (this.wander) {
      this.idle -= dt
      if (this.idle <= 0) {
        // Off for a few steps, or back home to face the way they were
        const a = rand(0, Math.PI * 2)
        const r = Math.random() < 0.4 ? 0 : rand(0.3, 1) * this.wander
        this.target = { x: this.home.x + Math.cos(a) * r, y: this.home.y + Math.sin(a) * r }
      } else if (Math.hypot(this.x - this.home.x, this.y - this.home.y) < 2) {
        this.facing = this.restFacing
      }
    }
    this.rig.update(dt, this.facing, speed)
    this.view.position.set(this.x, this.y)
    this.view.zIndex = this.y
  }
}
