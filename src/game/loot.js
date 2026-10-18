import { Graphics } from 'pixi.js'

// Chance that a point of interest has a treasure chest to search.
export const CHEST_CHANCE = 0.5

const randInt = (min, max) => Math.floor(min + Math.random() * (max - min + 1))

// Always some gold; sometimes a healing poultice or tools to mend the cart.
function rollChest() {
  return {
    gold: randInt(3, 7),
    health: Math.random() < 0.35 ? 1 : 0,
    repair: Math.random() < 0.35 ? 2 : 0,
  }
}

function drawCrate(g, size) {
  const h = size / 2
  g.rect(-h + 3, -h + 3, size, size).fill({ color: '#000', alpha: 0.2 })
  g.rect(-h, -h, size, size).fill('#8b6236').stroke({ width: 2, color: '#5e3f22' })
  g.moveTo(-h, -h).lineTo(h, h).stroke({ width: 1.5, color: '#5e3f22' })
}

function drawBarrel(g, r) {
  g.circle(2, 2, r).fill({ color: '#000', alpha: 0.2 })
  g.circle(0, 0, r).fill('#6e4a28')
  g.circle(0, 0, r * 0.65).stroke({ width: 2, color: '#3a2a1a' })
}

// Iron-banded treasure chest with a gold lock; open, the lid is thrown back.
function drawChest(g, open) {
  g.roundRect(-11, -6, 26, 18, 3).fill({ color: '#000', alpha: 0.25 })
  if (open) {
    g.roundRect(-13, -20, 26, 10, 3).fill('#5e3f22').stroke({ width: 2, color: '#d4a32a' })
  }
  g.roundRect(-13, -9, 26, 18, 3).fill('#7a4a22').stroke({ width: 2.5, color: '#d4a32a' })
  if (open) {
    g.roundRect(-10, -6, 20, 12, 2).fill('#2a1f14')
    g.circle(-3, 0, 2.5).fill('#e8b923').circle(3, 1, 2.5).fill('#e8b923')
  } else {
    g.moveTo(-13, -2).lineTo(13, -2).stroke({ width: 2, color: '#d4a32a' })
    for (const x of [-7, 7]) g.moveTo(x, -9).lineTo(x, 9)
    g.stroke({ width: 2, color: '#3a3a3a' })
    g.roundRect(-3, -4, 6, 6, 1).fill('#ffd75e')
    g.circle(0, 0, 1).fill('#3a2a1a')
  }
}

// Crates and barrels are just set dressing.
export function addProp(view, kind, x, y, size) {
  const g = new Graphics()
  g.position.set(x, y)
  kind === 'crate' ? drawCrate(g, size ?? 18) : drawBarrel(g, size ?? 9)
  view.addChild(g)
  return g
}

// Maybe place a treasure chest here (CHEST_CHANCE unless told otherwise). If placed, it's added
// to `view` and to the encounter's `list` of loot.
export function maybeAddChest(list, view, x, y, chance = CHEST_CHANCE) {
  if (Math.random() >= chance) return null

  const g = new Graphics()
  g.position.set(x, y)
  drawChest(g, false)
  const glint = new Graphics()
    .moveTo(-4, 0).lineTo(4, 0).moveTo(0, -4).lineTo(0, 4)
    .stroke({ width: 1.5, color: '#fff8d0', cap: 'round' })
  glint.position.set(x + 9, y - 8)
  view.addChild(g, glint)

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
      g.clear()
      drawChest(g, true)
      return rollChest()
    },
  }
  list.push(chest)
  return chest
}
