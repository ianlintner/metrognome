extends Node3D
class_name MushroomSway

# Gentle procedural "dance" for static mushroom models. The node pivots at its
# origin (placed at ground level), so the mushroom sways from its base. A child
# model should sit at local +half_height so it rests on the ground.
#
# Pure ambient sway — no beat pulse. Only animates while the metronome plays
# (toggled via set_playing); frozen in place otherwise.

@export var amp: float = 0.07        # ambient sway angle in radians
@export var speed: float = 1.8       # ambient sway speed
@export var bob: float = 0.04        # ambient vertical bob (world units)

var _phase: float = 0.0
var _t: float = 0.0
var _base_y: float = 0.0


func _ready() -> void:
	_phase = randf() * TAU
	_base_y = position.y
	set_process(false)  # start paused — only sways while the metronome plays


# Sway only while the metronome is playing; freeze in place when paused.
func set_playing(p: bool) -> void:
	set_process(p)


func _process(delta: float) -> void:
	_t += delta
	var a := _t * speed + _phase
	rotation.z = sin(a) * amp
	rotation.x = cos(a * 0.8) * amp * 0.5
	position.y = _base_y + (sin(a * 2.0) * 0.5 + 0.5) * bob
