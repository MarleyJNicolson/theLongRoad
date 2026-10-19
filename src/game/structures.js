import { Graphics } from 'pixi.js'
import { box, gable, slope, cone, cylinder, drawSolid, groundShadow, turn, project, facesCamera, shade } from './iso.js'

// Buildings and props in the three-quarter view, built from iso.js. Each
// is drawn standing at the origin (where it meets the ground) and returns
// its Graphics; the caller places it and sorts it by depth with the people.
// `angle` is the way it faces (its door or open side).

const WOOD = '#7a5230'
const WOOD_DARK = '#4a3220'
const STONE = '#8a857a'
const THATCH = '#a8822f'
const WALL = '#ddd0ad'

const rand = (min, max) => min + Math.random() * (max - min)

// A flat decal (door, window, plank) on a wall: corners given as
// [along the wall, height] on the face whose outward direction is `out`.
function onWall(g, T, out, at, corners, colour) {
  if (!facesCamera([...T([out[0], out[1], 0]).slice(0, 2), 0])) return
  const pts = corners.map(([s, z]) => T([at[0] + s * out[1] * -1, at[1] + s * out[0], z]))
  g.poly(pts.flatMap(project)).fill(colour)
}

// --- Homes ---------------------------------------------------------------------

// A thatched cottage: lime-washed walls framed in timber, a door and
// windows on the front, a stone chimney. `charred`: the thatch is burnt
// through in places.
export function cottage(angle, { charred = false, deep = 54, front = 84, walls = 30 } = {}) {
  const g = new Graphics()
  const rise = 26
  groundShadow(g, front * 0.62, deep * 0.45, 0.25, 0.35)
  drawSolid(g, box(deep, front, walls, angle, WALL))
  const T = turn(angle)
  const front_ = [1, 0]
  const face = [deep / 2 + 0.3, 0]
  // Timber frame: corner posts and a beam under the eaves
  for (const s of [-front / 2 + 1.5, front / 2 - 1.5]) onWall(g, T, front_, face, [[s - 1.5, 0], [s + 1.5, 0], [s + 1.5, walls], [s - 1.5, walls]], WOOD_DARK)
  onWall(g, T, front_, face, [[-front / 2, walls - 3], [front / 2, walls - 3], [front / 2, walls], [-front / 2, walls]], WOOD_DARK)
  // Door and windows on the front (+u); a window on each end
  onWall(g, T, front_, face, [[-7, 0], [7, 0], [7, 21], [-7, 21]], '#5a3a1e')
  onWall(g, T, front_, face, [[-5.5, 0], [5.5, 0], [5.5, 19], [-5.5, 19]], '#3a2614')
  for (const s of [-25, 25]) {
    onWall(g, T, front_, face, [[s - 7, 11], [s + 7, 11], [s + 7, 22], [s - 7, 22]], WOOD_DARK)
    onWall(g, T, front_, face, [[s - 5.5, 12.5], [s + 5.5, 12.5], [s + 5.5, 20.5], [s - 5.5, 20.5]], '#24303a')
  }
  for (const end of [-1, 1]) {
    const at = [0, end * (front / 2 + 0.3)]
    onWall(g, T, [0, end], at, [[-6, 11], [6, 11], [6, 21], [-6, 21]], WOOD_DARK)
    onWall(g, T, [0, end], at, [[-4.5, 12.5], [4.5, 12.5], [4.5, 19.5], [-4.5, 19.5]], '#24303a')
  }
  // Chimney, then the thatch over the long side
  const [cu, cv] = T([-deep / 5, front / 3, 0])
  drawSolid(g, box(9, 9, walls + rise + 8, angle, STONE, { top: '#5a5650' }).map((f) => ({ ...f, pts: f.pts.map(([x, y, z]) => [x + cu, y + cv, z]) })))
  drawSolid(g, gable(front, deep, rise, angle + Math.PI / 2, THATCH, { z0: walls, over: 4, ends: WALL }))
  // Straw courses along each roof face, and the ridge
  const R = turn(angle + Math.PI / 2)
  const l = front / 2 + 4
  const w = deep / 2 + 4
  for (const side of [-1, 1]) {
    if (!facesCamera([...R([0, side * rise, 0]).slice(0, 2), w])) continue
    for (const t of [0.3, 0.6]) {
      const a = project(R([-l, side * w * (1 - t), walls + rise * t]))
      const b = project(R([l, side * w * (1 - t), walls + rise * t]))
      g.moveTo(...a).lineTo(...b).stroke({ width: 1, color: shade(THATCH, 0.75), alpha: 0.7 })
    }
  }
  g.moveTo(...project(R([-l, 0, walls + rise]))).lineTo(...project(R([l, 0, walls + rise]))).stroke({ width: 2.5, color: '#7a5a22' })
  if (charred) {
    for (let k = 0; k < 6; k++) {
      const [x, y] = project(R([rand(-l * 0.8, l * 0.8), rand(-w * 0.6, w * 0.6), walls + rise * rand(0.3, 0.8)]))
      const r = rand(4, 7)
      g.ellipse(x, y, r, r * 0.55).fill({ color: '#2a1f16', alpha: 0.75 })
      g.ellipse(x - r * 0.2, y - r * 0.1, r * 0.5, r * 0.3).fill({ color: '#14100c', alpha: 0.8 })
    }
  }
  return { g, roof: walls + rise, eaves: walls }
}

// A canvas lean-to: a sloping roof on four posts, open towards `angle`.
export function leanTo(angle, colour = '#c8b994') {
  const g = new Graphics()
  groundShadow(g, 30, 16, 0.2)
  const T = turn(angle)
  const P = (u, v, z) => project(T([u, v, z]))
  const poly = (pts, fill) => g.poly(pts.flatMap((p) => P(...p))).fill(fill)
  // The shade inside: the back wall seen from within, and a bedroll
  poly([[-14, -22, 0], [-14, 22, 0], [-14, 22, 8], [-14, -22, 8]], shade(colour, 0.45))
  const [bx, by] = P(-2, 4, 0)
  g.ellipse(bx, by, 8, 4).fill('#7d4a3a')
  // Canvas walls at each end (the far one first), then the posts
  const ends = [-22, 22].sort((p, q) => P(0, p, 0)[1] - P(0, q, 0)[1])
  for (const v of ends) {
    const lit = facesCamera([...T([0, Math.sign(v), 0]).slice(0, 2), 0])
    poly([[-14, v, 0], [14, v, 0], [14, v, 34], [-14, v, 8]], shade(colour, lit ? 0.9 : 0.6))
  }
  for (const [u, v, h] of [[14, -22, 34], [14, 22, 34]]) {
    const [x, y] = T([u, v, 0])
    g.moveTo(x, y).lineTo(x, y - h).stroke({ width: 2.5, color: WOOD_DARK })
  }
  // The sloping roof: tall at the open front, low at the back
  drawSolid(g, slope(52, 34, 34, 8, angle + Math.PI / 2, colour))
  return g
}

// A goblin hide tent: a cone of stitched skins, the flap open towards `angle`.
export function hideTent(angle) {
  const g = new Graphics()
  groundShadow(g, 26, 12, 0.22)
  drawSolid(g, cone(22, 42, '#8b7355', { sides: 7, angle: angle + 0.4 }))
  // The flap (if it faces us), poles poking out of the top
  const T = turn(angle)
  if (facesCamera([Math.cos(angle), Math.sin(angle), 0.6])) {
    const pts = [T([19, -7, 0]), T([19, 7, 0]), T([9, 0, 24])]
    g.poly(pts.flatMap(project)).fill('#2a1f14')
  }
  for (const a of [0.3, 2.4, 4.4]) {
    g.moveTo(0, -40).lineTo(Math.cos(a) * 5, -48 + Math.sin(a) * 2).stroke({ width: 1.5, color: WOOD_DARK })
  }
  return g
}

// A lookout's tower: four posts, a railed platform and a ladder up the front.
export function watchtower(angle) {
  const g = new Graphics()
  const h = 44
  groundShadow(g, 22, 10, 0.25, 0.6)
  const T = turn(angle)
  const posts = [[-12, -12], [12, -12], [12, 12], [-12, 12]].map(([u, v]) => T([u, v, 0]))
  // Back posts first, then the front ones
  posts.sort((p, q) => p[1] - q[1])
  for (const [x, y] of posts) g.moveTo(x, y).lineTo(x, y - h).stroke({ width: 3, color: WOOD_DARK })
  drawSolid(g, box(30, 30, 3, angle, WOOD, { z0: h, top: '#8b6236' }))
  // Railing
  const rail = [[-15, -15], [15, -15], [15, 15], [-15, 15]].map(([u, v]) => project(T([u, v, h + 8])))
  g.poly(rail.flat()).stroke({ width: 1.5, color: WOOD_DARK })
  for (const [u, v] of [[-15, -15], [15, -15], [15, 15], [-15, 15]]) {
    const [a, b] = [project(T([u, v, h + 3])), project(T([u, v, h + 8]))]
    g.moveTo(...a).lineTo(...b).stroke({ width: 1.5, color: WOOD_DARK })
  }
  // Ladder on the front
  for (const v of [-4, 4]) g.moveTo(...project(T([17, v, 0]))).lineTo(...project(T([15, v, h + 3]))).stroke({ width: 1.5, color: WOOD })
  for (let z = 4; z < h; z += 5) g.moveTo(...project(T([16.5, -4, z]))).lineTo(...project(T([16.5, 4, z]))).stroke({ width: 1, color: WOOD })
  return { g, height: h + 3 }
}

// A stone well with a little roof on two posts.
export function well() {
  const g = new Graphics()
  groundShadow(g, 15, 7, 0.22)
  drawSolid(g, cylinder(12, 9, STONE, { sides: 10, top: '#6f6b63' }))
  g.ellipse(0, -9, 8, 5).fill('#1d2a33')
  for (const v of [-11, 11]) g.moveTo(v, -9).lineTo(v, -36).stroke({ width: 2, color: WOOD_DARK })
  g.moveTo(-11, -31).lineTo(11, -31).stroke({ width: 1.5, color: WOOD_DARK })
  g.moveTo(0, -31).lineTo(0, -16).stroke({ width: 1, color: '#c9b28a' })
  drawSolid(g, gable(26, 14, 8, 0, '#6e4a28', { z0: 35, over: 1 }))
  return g
}

// A market stall: a counter under a striped awning, open towards `angle`.
export function stall(angle, colour) {
  const g = new Graphics()
  groundShadow(g, 18, 9, 0.2)
  const T = turn(angle)
  for (const [u, v] of [[-8, -15], [-8, 15], [8, -15], [8, 15]]) {
    const [x, y] = T([u, v, 0])
    g.moveTo(x, y).lineTo(x, y - (u < 0 ? 42 : 36)).stroke({ width: 2, color: WOOD_DARK })
  }
  drawSolid(g, box(8, 30, 14, angle, WOOD, { top: '#8b6236' }).map((f) => ({ ...f, pts: f.pts.map(([x, y, z]) => { const [dx, dy] = T([6, 0, 0]); return [x + dx, y + dy, z] }) })))
  // Goods on the counter
  for (let k = -2; k <= 2; k++) {
    const [x, y] = project(T([6, k * 5, 15]))
    g.circle(x, y, 2).fill(k % 2 ? '#c0392b' : '#d9b44a')
  }
  // Striped awning, in strips
  for (let k = 0; k < 6; k++) {
    const s = -16 + k * (32 / 6)
    const strip = slope(32 / 6, 18, 43, 36, angle - Math.PI / 2, k % 2 ? '#f3e3c0' : colour).map((f) => ({
      ...f,
      pts: f.pts.map(([x, y, z]) => { const [dx, dy] = T([0, s + 16 / 6, 0]); return [x + dx, y + dy, z] }),
    }))
    drawSolid(g, strip)
  }
  return g
}

// --- Camps and fortifications ----------------------------------------------------

// One sharpened stake of a palisade; `skull`: one of a goblin camp's trophies.
export function stake(colour = '#6e4a28', skull = false) {
  const g = new Graphics()
  const h = rand(30, 38)
  groundShadow(g, 7, 3, 0.25, 0.6)
  drawSolid(g, cylinder(4.5, h, colour, { sides: 6, top: shade(colour, 1.2) }))
  drawSolid(g, cone(4.5, 6, shade(colour, 1.1), { sides: 6, z0: h }))
  if (skull) g.circle(0, -h - 7, 3.5).fill('#e8e0c8').circle(-1.2, -h - 7.5, 0.9).fill('#1c1714').circle(1.2, -h - 7.5, 0.9).fill('#1c1714')
  return g
}

// A cage of lashed poles for the goblins' captives.
export function cage() {
  const g = new Graphics()
  groundShadow(g, 15, 7, 0.22)
  const corners = [[-12, -10], [12, -10], [12, 10], [-12, 10]]
  g.poly(corners.flatMap(([x, y]) => [x, y])).fill({ color: '#2a1f14', alpha: 0.6 })
  // Back bars, then front ones
  const bars = []
  for (let x = -12; x <= 12; x += 6) bars.push([x, -10], [x, 10])
  for (let y = -10; y <= 10; y += 5) bars.push([-12, y], [12, y])
  bars.sort((p, q) => p[1] - q[1])
  for (const [x, y] of bars) g.moveTo(x, y).lineTo(x, y - 30).stroke({ width: 2, color: '#5e3f22' })
  g.poly(corners.flatMap(([x, y]) => [x, y - 30])).stroke({ width: 2, color: '#4a3220' })
  return g
}

// A skull on a pole to warn travellers off.
export function skullTotem() {
  const g = new Graphics()
  groundShadow(g, 5, 2.5, 0.25, 0.8)
  g.moveTo(0, 0).lineTo(0, -24).stroke({ width: 3, color: '#5a3a1a' })
  g.moveTo(-6, -20).lineTo(6, -20).stroke({ width: 2, color: '#5a3a1a' })
  g.circle(0, -27, 5).fill('#e8e0c8')
  g.circle(-1.8, -28, 1.3).fill('#1c1714').circle(1.8, -28, 1.3).fill('#1c1714')
  g.rect(-1.5, -24, 3, 1.5).fill('#1c1714')
  return g
}

// A log lying on the ground along `angle` (a bench, or part of a barricade).
export function log(length, radius, angle) {
  const g = new Graphics()
  groundShadow(g, length * 0.5, radius, 0.2, 0.15)
  const T = turn(angle)
  const ring = []
  for (let k = 0; k < 8; k++) {
    const a = (k / 8) * Math.PI * 2
    ring.push([Math.cos(a) * radius, radius + Math.sin(a) * radius])
  }
  const end = (u) => ring.map(([v, z]) => T([u, v, z]))
  const [A, B] = [end(-length / 2), end(length / 2)]
  const faces = [{ pts: A.slice().reverse(), colour: '#a8875c' }, { pts: B, colour: '#a8875c' }]
  for (let k = 0; k < 8; k++) faces.push({ pts: [A[k], A[(k + 1) % 8], B[(k + 1) % 8], B[k]], colour: '#5e3f22' })
  drawSolid(g, faces)
  return g
}

// A fence along a line (relative to the origin): posts with two rails;
// `broken` leaves gaps.
export function fence(x1, y1, x2, y2, broken = false) {
  const g = new Graphics()
  const len = Math.hypot(x2 - x1, y2 - y1)
  const posts = Math.max(2, Math.round(len / 12) + 1)
  const pts = []
  for (let k = 0; k < posts; k++) pts.push([x1 + ((x2 - x1) * k) / (posts - 1), y1 + ((y2 - y1) * k) / (posts - 1), !broken || Math.random() > 0.3])
  for (let k = 0; k < posts - 1; k++) {
    const [a, b] = [pts[k], pts[k + 1]]
    if (!a[2] || !b[2]) continue
    for (const z of [4, 8]) g.moveTo(a[0], a[1] - z).lineTo(b[0], b[1] - z).stroke({ width: 1.5, color: '#6e4a28' })
  }
  for (const [x, y, standing] of pts) if (standing) g.moveTo(x, y).lineTo(x, y - 10).stroke({ width: 2.5, color: WOOD_DARK })
  return g
}

// --- Containers and carts --------------------------------------------------------

export function crate(size = 16) {
  const g = new Graphics()
  groundShadow(g, size * 0.7, size * 0.3, 0.25)
  drawSolid(g, box(size, size, size * 0.85, 0.15, '#8b6236', { top: '#a8875c' }))
  const h = size * 0.85
  g.moveTo(-size / 2 + 1, -1).lineTo(size / 2 - 1, -h + 1).stroke({ width: 1.2, color: '#5e3f22', alpha: 0.8 })
  return g
}

export function barrel(r = 9, g = new Graphics()) {
  groundShadow(g, r * 1.1, r * 0.45, 0.25)
  const h = r * 1.8
  drawSolid(g, cylinder(r, h, '#6e4a28', { sides: 10, top: '#8b6236' }))
  for (const z of [h * 0.2, h * 0.8]) g.ellipse(0, -z, r, r * 0.35).stroke({ width: 1.2, color: '#2a1f14', alpha: 0.8 })
  g.ellipse(0, -h, r * 0.7, r * 0.3).stroke({ width: 1, color: '#3a2a1a' })
  return { g, top: h }
}

// A treasure chest: iron-banded with a gold lock; open, the lid thrown back.
export function chest(open, g = new Graphics()) {
  groundShadow(g, 15, 6, 0.28)
  drawSolid(g, box(16, 24, 10, Math.PI / 2, '#7a4a22', { top: open ? '#2a1f14' : '#8b5a2b' }))
  if (open) {
    drawSolid(g, box(4, 24, 10, Math.PI / 2, '#5e3f22').map((f) => ({ ...f, pts: f.pts.map(([x, y, z]) => [x, y - 9, z + 6]) })))
    g.circle(-3, -11, 2.2).fill('#e8b923').circle(3, -10, 2.2).fill('#e8b923')
  } else {
    drawSolid(g, gable(24, 16, 5, 0, '#8b5a2b', { z0: 10, over: 0 }))
    g.rect(-1.5, -12, 3, 4).fill('#ffd75e')
  }
  for (const x of [-7, 7]) g.moveTo(x, 8).lineTo(x, open ? -2 : -14).stroke({ width: 1.5, color: '#3a3a3a' })
  g.rect(-12, -4, 24, 1.5).fill('#d4a32a')
  return g
}

// The bed of a merchant's wagon tipped over: its underside, axles and the
// one wheel still on.
export function overturnedWagon(angle) {
  const g = new Graphics()
  groundShadow(g, 34, 16, 0.25)
  drawSolid(g, box(60, 34, 12, angle, '#5e3f22', { top: '#3a2a1a' }))
  const T = turn(angle)
  for (const u of [-18, 18]) g.moveTo(...project(T([u, -17, 12]))).lineTo(...project(T([u, 17, 12]))).stroke({ width: 3, color: '#2a1f14' })
  // A wheel sticking up off one axle
  const hub = T([-18, -17, 14])
  const [hx, hy] = project(hub)
  g.ellipse(hx, hy - 9, 4, 11).stroke({ width: 2.5, color: '#3a2a1a' })
  return g
}

// The bandits' cart, loaded with plunder.
export function lootCart(angle) {
  const g = new Graphics()
  groundShadow(g, 18, 9, 0.22)
  drawSolid(g, box(30, 22, 8, angle, '#5e3f22', { z0: 8, top: '#6e4a28' }))
  const T = turn(angle)
  for (const v of [-12, 12]) {
    const [x, y] = project(T([0, v, 8]))
    g.ellipse(x, y, 2.5, 8).stroke({ width: 2.5, color: '#3a2a1a' })
  }
  for (const [u, v] of [[-6, -4], [4, 3], [-2, 6]]) {
    const [x, y] = project(T([u, v, 18]))
    g.ellipse(x, y, 5, 4).fill('#c9b28a')
  }
  const [cx, cy] = project(T([2, -5, 18]))
  g.circle(cx, cy, 2.5).fill('#e8b923')
  return g
}

// A flickering campfire (on top of the ring of stones drawn on the ground).
export function flames() {
  const g = new Graphics()
  g.poly([-7, 0, 0, -18, 7, 0]).fill({ color: '#e8641e', alpha: 0.9 })
  g.poly([-4, 0, 0, -12, 4, 0]).fill('#ffb02e')
  g.poly([-2, 0, 0, -6, 2, 0]).fill('#fff1a8')
  return g
}
