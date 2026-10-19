import { Graphics } from 'pixi.js'
import { crate, barrel as drawBarrel, chest as drawChest } from './structures.js'

// Chance that a point of interest has a treasure chest to search.
export const CHEST_CHANCE = 0.5

const randInt = (min, max) => Math.floor(min + Math.random() * (max - min + 1))

// Always some gold; sometimes a healing poultice, tools to mend the cart,
// or a bundle of arrows or bolts.
function rollChest() {
  return {
    gold: randInt(3, 7),
    health: Math.random() < 0.35 ? 1 : 0,
    repair: Math.random() < 0.35 ? 2 : 0,
    arrows: Math.random() < 0.4 ? randInt(8, 16) : 0,
    bolts: Math.random() < 0.15 ? randInt(4, 8) : 0,
  }
}

// Crates and barrels are just set dressing. `stand` puts something upright
// on the map (see Encounters.place).
export function addProp(stand, kind, x, y, size) {
  const g = kind === 'crate' ? crate(size ?? 18) : drawBarrel(size ?? 9).g
  return stand(g, x, y)
}

// Maybe place a treasure chest here (CHEST_CHANCE unless told otherwise). If placed, it's added
// to the map and to the encounter's `list` of loot.
export function maybeAddChest(list, stand, x, y, chance = CHEST_CHANCE) {
  if (Math.random() >= chance) return null

  const g = stand(drawChest(false), x, y)
  const glint = new Graphics()
    .moveTo(-4, 0).lineTo(4, 0).moveTo(0, -4).lineTo(0, 4)
    .stroke({ width: 1.5, color: '#fff8d0', cap: 'round' })
  stand(glint, x + 9, y - 14, { depth: y + 0.5 })

  const chest = {
    kind: 'chest',
    x,
    y,
    opened: false,
    // A twinkle every so often to catch the player's eye.
    animate(time) {
      const t = (time + x * 0.01) % 2.5
      glint.alpha = chest.opened ? 0 : t < 0.4 ? Math.sin((t / 0.4) * Math.PI) : 0
      glint.rotation = time * 2
    },
    // Search it: returns what was inside, e.g. { gold: 4, health: 1, repair: 0 }.
    open() {
      chest.opened = true
      drawChest(true, g.clear())
      return rollChest()
    },
  }
  list.push(chest)
  return chest
}

// A barrel of arrows kept by a camp's archers (and the odd bundle of bolts).
// Whatever doesn't fit in your bag stays in it for later.
export function addArrowBarrel(list, stand, x, y) {
  const g = stand(new Graphics(), x, y)
  const barrel = {
    kind: 'arrows',
    x,
    y,
    opened: false,
    contents: { arrows: randInt(12, 24), bolts: Math.random() < 0.3 ? randInt(5, 10) : 0 },
    // Redraw to match what's left; empty means opened.
    update() {
      const { arrows, bolts } = barrel.contents
      barrel.opened = !arrows && !bolts
      const { top } = drawBarrel(10, g.clear())
      g.ellipse(0, -top, 6.5, 2.8).fill('#2a1f14')
      // Fletchings poking out of the top
      const shafts = Math.min(7, Math.ceil(arrows / 3))
      for (let k = 0; k < shafts; k++) {
        const a = (k / Math.max(1, shafts)) * Math.PI * 2
        const fx = Math.cos(a) * 3.5
        const fy = Math.sin(a) * 1.5 - top
        g.moveTo(fx, fy).lineTo(fx * 1.5, fy - 8).stroke({ width: 1.5, color: '#8b6236' })
        g.circle(fx * 1.5, fy - 8, 1.6).fill(k % 2 ? '#e8e0c8' : '#a3331f')
      }
      if (bolts) g.rect(-2, -top - 3, 4, 4).fill('#5e3f22')
    },
    animate() {},
  }
  barrel.update()
  list.push(barrel)
  return barrel
}
