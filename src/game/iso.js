// Building blocks for drawing solid things in the three-quarter view (see
// rig.js): boxes, roofs, cones and cylinders described as faces in 3D (x and
// y on the ground, z up), drawn by lifting each point by its height. Faces
// turned away from the camera are skipped and the rest are lit from the top
// left, so everything built from these looks consistent.

// Towards the camera (it looks down from the south) and towards the light.
const VIEW = norm([0, 1, 1.2])
const LIGHT = norm([-0.55, -0.45, 1])

function norm([x, y, z]) {
  const l = Math.hypot(x, y, z) || 1
  return [x / l, y / l, z / l]
}
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

// Lighten (k > 1) or darken (k < 1) a #rrggbb colour.
export function shade(hex, k) {
  const n = parseInt(hex.slice(1), 16)
  const c = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => Math.max(0, Math.min(255, Math.round(v * k))))
  return '#' + c.map((v) => v.toString(16).padStart(2, '0')).join('')
}

export const project = ([x, y, z]) => [x, y - z]

// Turn a footprint by `angle` about the origin.
export function turn(angle) {
  const c = Math.cos(angle)
  const s = Math.sin(angle)
  return ([u, v, z]) => [u * c - v * s, u * s + v * c, z]
}

// Draw a convex solid: `faces` are { pts: [[x, y, z], ...], colour }. Only
// faces turned towards the camera are drawn (so on a convex shape none of
// them overlap), each shaded by how much light it catches.
export function drawSolid(g, faces, { outline = null } = {}) {
  const all = faces.flatMap((f) => f.pts)
  const centre = [0, 1, 2].map((i) => all.reduce((s, p) => s + p[i], 0) / all.length)
  for (const f of faces) {
    const n = normal(f.pts, centre)
    if (dot(n, VIEW) <= 0.02) continue
    const light = f.flat ? 1 : 0.68 + 0.42 * Math.max(0, dot(n, LIGHT))
    g.poly(f.pts.flatMap(project)).fill(shade(f.colour, light))
    if (outline) g.poly(f.pts.flatMap(project)).stroke({ width: 1, color: outline, alpha: 0.5 })
  }
}

// Outward normal of a flat face (Newell's method), pointing away from the
// solid's centre.
function normal(pts, centre) {
  let n = [0, 0, 0]
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i]
    const b = pts[(i + 1) % pts.length]
    n = [n[0] + (a[1] - b[1]) * (a[2] + b[2]), n[1] + (a[2] - b[2]) * (a[0] + b[0]), n[2] + (a[0] - b[0]) * (a[1] + b[1])]
  }
  n = norm(n)
  const mid = [0, 1, 2].map((i) => pts.reduce((s, p) => s + p[i], 0) / pts.length)
  const out = [mid[0] - centre[0], mid[1] - centre[1], mid[2] - centre[2]]
  return dot(n, out) < 0 ? [-n[0], -n[1], -n[2]] : n
}

// Is a face with this outward normal turned towards the camera?
export const facesCamera = (n) => dot(norm(n), VIEW) > 0.02

// --- Shapes (all footprints centred on the origin, turned by `angle`) ---------

// A box `long` × `wide` on the ground, `high` tall, sitting at height `z0`.
export function box(long, wide, high, angle, colour, { z0 = 0, top = colour } = {}) {
  const T = turn(angle)
  const [l, w] = [long / 2, wide / 2]
  const c = (u, v, z) => T([u, v, z])
  const b = [c(-l, -w, z0), c(l, -w, z0), c(l, w, z0), c(-l, w, z0)]
  const t = [c(-l, -w, z0 + high), c(l, -w, z0 + high), c(l, w, z0 + high), c(-l, w, z0 + high)]
  return [
    { pts: t, colour: top },
    { pts: [b[0], b[1], t[1], t[0]], colour },
    { pts: [b[1], b[2], t[2], t[1]], colour },
    { pts: [b[2], b[3], t[3], t[2]], colour },
    { pts: [b[3], b[0], t[0], t[3]], colour },
    { pts: [...b].reverse(), colour },
  ]
}

// A gabled roof: ridge along the long side, eaves overhanging by `over`.
export function gable(long, wide, rise, angle, colour, { z0 = 0, over = 2, ends = colour } = {}) {
  const T = turn(angle)
  const [l, w] = [long / 2 + over, wide / 2 + over]
  const c = (u, v, z) => T([u, v, z])
  const e = [c(-l, -w, z0), c(l, -w, z0), c(l, w, z0), c(-l, w, z0)]
  const r = [c(-l, 0, z0 + rise), c(l, 0, z0 + rise)]
  return [
    { pts: [e[0], e[1], r[1], r[0]], colour },
    { pts: [e[3], e[2], r[1], r[0]], colour },
    { pts: [e[0], r[0], e[3]], colour: ends },
    { pts: [e[1], r[1], e[2]], colour: ends },
    { pts: [...e].reverse(), colour },
  ]
}

// A sloping roof (a lean-to): high along one long side, low along the other.
export function slope(long, wide, high, low, angle, colour) {
  const T = turn(angle)
  const [l, w] = [long / 2, wide / 2]
  const c = (u, v, z) => T([u, v, z])
  const top = [c(-l, -w, high), c(l, -w, high), c(l, w, low), c(-l, w, low)]
  const under = top.map(([x, y, z]) => [x, y, z - 1.5])
  return [
    { pts: top, colour },
    { pts: [...under].reverse(), colour: shade(colour, 0.6) },
    { pts: [top[0], top[1], under[1], under[0]], colour: shade(colour, 0.8) },
    { pts: [top[2], top[3], under[3], under[2]], colour: shade(colour, 0.8) },
    { pts: [top[1], top[2], under[2], under[1]], colour: shade(colour, 0.8) },
    { pts: [top[3], top[0], under[0], under[3]], colour: shade(colour, 0.8) },
  ]
}

// A cone (a hide tent): `sides`-sided, apex `high` above the ground.
export function cone(radius, high, colour, { sides = 8, angle = 0, z0 = 0 } = {}) {
  const ring = []
  for (let k = 0; k < sides; k++) {
    const a = angle + (k / sides) * Math.PI * 2
    ring.push([Math.cos(a) * radius, Math.sin(a) * radius, z0])
  }
  const apex = [0, 0, z0 + high]
  return [
    ...ring.map((p, k) => ({ pts: [p, ring[(k + 1) % sides], apex], colour })),
    { pts: [...ring].reverse(), colour },
  ]
}

// An upright cylinder (a barrel, a well, a post), `sides`-sided.
export function cylinder(radius, high, colour, { sides = 10, z0 = 0, top = colour } = {}) {
  const bottom = []
  const upper = []
  for (let k = 0; k < sides; k++) {
    const a = (k / sides) * Math.PI * 2
    bottom.push([Math.cos(a) * radius, Math.sin(a) * radius, z0])
    upper.push([Math.cos(a) * radius, Math.sin(a) * radius, z0 + high])
  }
  return [
    { pts: upper, colour: top },
    ...bottom.map((p, k) => ({ pts: [p, bottom[(k + 1) % sides], upper[(k + 1) % sides], upper[k]], colour })),
    { pts: [...bottom].reverse(), colour },
  ]
}

// A shadow on the ground beside something standing (the light is top left).
export function groundShadow(g, w, h, alpha = 0.22, dx = 0.25) {
  g.ellipse(w * dx, h * 0.25, w, h).fill({ color: '#000', alpha })
}
