class_name Controls
extends RefCounted

# The game's controls (port of input.js) as InputMap actions. Physical keys,
# as the JS used e.code, so WASD stays put on other keyboard layouts.

const KEYS := {
	"up": [KEY_W, KEY_UP],
	"down": [KEY_S, KEY_DOWN],
	"left": [KEY_A, KEY_LEFT],
	"right": [KEY_D, KEY_RIGHT],
	"restart": [KEY_SPACE, KEY_R],
	"interact": [KEY_E],
	"bag": [KEY_B, KEY_I],
	"cart": [KEY_C],
	"boost": [KEY_SHIFT], # gallop on the cart, sprint on foot
	"dash": [KEY_CTRL, KEY_SPACE],
	"swap": [KEY_Q],
	"close": [KEY_ESCAPE],
}
const BUTTONS := {
	"attack": [MOUSE_BUTTON_LEFT],
	# Right-click swaps weapons too, but not over a panel (where it sells), so
	# it's its own action
	"swap_click": [MOUSE_BUTTON_RIGHT],
}


static func setup() -> void:
	for action in KEYS.keys() + BUTTONS.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	for action in KEYS:
		for key in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	for action in BUTTONS:
		for button in BUTTONS[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)


# Held down right now.
static func held(action: String) -> bool:
	return Input.is_action_pressed(action)


# True only on the frame it went down.
static func pressed(action: String) -> bool:
	return Input.is_action_just_pressed(action)
