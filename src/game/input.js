const KEYS = {
  up: ['KeyW', 'ArrowUp'],
  down: ['KeyS', 'ArrowDown'],
  left: ['KeyA', 'ArrowLeft'],
  right: ['KeyD', 'ArrowRight'],
  restart: ['Space', 'KeyR'],
  interact: ['KeyE'],
  bag: ['KeyB', 'KeyI'],
  cart: ['KeyC'],
  boost: ['ShiftLeft', 'ShiftRight'], // gallop on the cart, sprint on foot
  dash: ['ControlLeft', 'ControlRight', 'Space'],
  swap: ['KeyQ', 'MouseRight'],
  close: ['Escape'],
}

export class Input {
  constructor(canvas) {
    this.canvas = canvas
    this.held = new Set()
    this.justPressed = new Set()
    // `active`: the mouse has been over the game at least once;
    // `inside`: it's over the game right now (not off-window or over a panel)
    this.pointer = { x: 0, y: 0, down: false, rightDown: false, active: false, inside: false }
    this.onPointerMove = (e) => {
      const rect = canvas.getBoundingClientRect()
      this.pointer.active = true
      this.pointer.inside = true
      this.pointer.x = e.clientX - rect.left
      this.pointer.y = e.clientY - rect.top
    }
    this.onPointerDown = (e) => {
      this.onPointerMove(e)
      if (e.button === 0) this.pointer.down = true
      if (e.button === 2) {
        this.pointer.rightDown = true
        this.justPressed.add('MouseRight')
      }
    }
    this.onPointerUp = (e) => {
      if (e.button === 0) this.pointer.down = false
      if (e.button === 2) this.pointer.rightDown = false
    }
    this.onContextMenu = (e) => e.preventDefault() // right-click swaps weapons
    this.onPointerLeave = () => (this.pointer.inside = false)
    canvas.addEventListener('pointermove', this.onPointerMove)
    canvas.addEventListener('pointerleave', this.onPointerLeave)
    canvas.addEventListener('pointerdown', this.onPointerDown)
    canvas.addEventListener('contextmenu', this.onContextMenu)
    window.addEventListener('pointerup', this.onPointerUp)
    this.onDown = (e) => {
      // Typing in a text box (your name on the scoreboard) isn't for the game
      if (e.target.closest?.('input, textarea')) return
      if (!e.repeat) this.justPressed.add(e.code)
      this.held.add(e.code)
      // Our keys shouldn't scroll or trigger browser shortcuts (Ctrl+S, Ctrl+D...;
      // browsers never let a page stop Ctrl+W closing the tab)
      if (Object.values(KEYS).flat().includes(e.code) || e.ctrlKey) e.preventDefault()
    }
    this.onUp = (e) => this.held.delete(e.code)
    this.onBlur = () => {
      this.held.clear()
      this.pointer.down = false
      this.pointer.rightDown = false
    }
    window.addEventListener('keydown', this.onDown)
    window.addEventListener('keyup', this.onUp)
    window.addEventListener('blur', this.onBlur)
  }

  is(action) {
    return KEYS[action].some((code) => this.held.has(code))
  }

  // True only on the frame the key went down.
  pressed(action) {
    return KEYS[action].some((code) => this.justPressed.has(code))
  }

  endFrame() {
    this.justPressed.clear()
  }

  destroy() {
    this.canvas.removeEventListener('pointermove', this.onPointerMove)
    this.canvas.removeEventListener('pointerleave', this.onPointerLeave)
    this.canvas.removeEventListener('pointerdown', this.onPointerDown)
    this.canvas.removeEventListener('contextmenu', this.onContextMenu)
    window.removeEventListener('pointerup', this.onPointerUp)
    window.removeEventListener('keydown', this.onDown)
    window.removeEventListener('keyup', this.onUp)
    window.removeEventListener('blur', this.onBlur)
  }
}
