extends Node3D
class_name MushroomSway

# Gentle procedural "dance" for static mushroom models. The node pivots at its
# origin (placed at ground level), so the mushroom sways from its base. A child
# model should sit at local +half_height so it rests on the ground.

@export var amp: float = 0.07        # ambient sway angle in radians
@export var speed: float = 1.8       # ambient sway speed
@export var bob: float = 0.04        # ambient vertical bob (world units)
@export var beat_bob: float = 0.22   # extra hop height on a beat pulse
@export var beat_tilt: float = 0.10  # extra tilt on a beat pulse

var _phase: float = 0.0
var _t: float = 0.0
var _base_y: float = 0.0
var _beat: float = 0.0  # decays 1 -> 0 after each beat pulse


func _ready() -> void:
	_phase = randf() * TAU
	_base_y = position.y


# Called from the metronome tick to make the mushroom hop on the beat.
func pulse() -> void:
	_beat = 1.0


func _process(delta: float) -> void:
	_t += delta
	_beat = maxf(0.0, _beat - delta * 4.0)
	var a := _t * speed + _phase
	# A beat hop = a quick arc (sin over the decaying window).
	var hop := sin((1.0 - _beat) * PI) * _beat
	rotation.z = sin(a) * amp + hop * beat_tilt
	rotation.x = cos(a * 0.8) * amp * 0.5
	position.y = _base_y + (sin(a * 2.0) * 0.5 + 0.5) * bob + hop * beat_bob
