const KEYS = {
  up: ['KeyW', 'ArrowUp'],
  down: ['KeyS', 'ArrowDown'],
  left: ['KeyA', 'ArrowLeft'],
  right: ['KeyD', 'ArrowRight'],
  restart: ['Space', 'KeyR'],
  interact: ['KeyE'],
  bag: ['KeyB', 'KeyI'],
  boost: ['ShiftLeft', 'ShiftRight'],
  melee: ['KeyF'],
}

export class Input {
  constructor(canvas) {
    this.canvas = canvas
    this.held = new Set()
    this.justPressed = new Set()
    this.pointer = { x: 0, y: 0, down: false, rightDown: false, active: false }
    this.onPointerMove = (e) => {
      const rect = canvas.getBoundingClientRect()
      this.pointer.active = true
      this.pointer.x = e.clientX - rect.left
      this.pointer.y = e.clientY - rect.top
    }
    this.onPointerDown = (e) => {
      this.onPointerMove(e)
      if (e.button === 0) this.pointer.down = true
      if (e.button === 2) this.pointer.rightDown = true
    }
    this.onPointerUp = (e) => {
      if (e.button === 0) this.pointer.down = false
      if (e.button === 2) this.pointer.rightDown = false
    }
    this.onContextMenu = (e) => e.preventDefault() // right-click is for melee
    canvas.addEventListener('pointermove', this.onPointerMove)
    canvas.addEventListener('pointerdown', this.onPointerDown)
    canvas.addEventListener('contextmenu', this.onContextMenu)
    window.addEventListener('pointerup', this.onPointerUp)
    this.onDown = (e) => {
      if (!e.repeat) this.justPressed.add(e.code)
      this.held.add(e.code)
      if (Object.values(KEYS).flat().includes(e.code)) e.preventDefault()
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
    this.canvas.removeEventListener('pointerdown', this.onPointerDown)
    this.canvas.removeEventListener('contextmenu', this.onContextMenu)
    window.removeEventListener('pointerup', this.onPointerUp)
    window.removeEventListener('keydown', this.onDown)
    window.removeEventListener('keyup', this.onUp)
    window.removeEventListener('blur', this.onBlur)
  }
}
