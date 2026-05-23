extends Node3D
class_name GnomePulse

@export var base_bounce_height: float = 0.25
@export var accent_bounce_height: float = 1.2
@export var bounce_duration: float = 0.12

var _original_position: Vector3
var _bounce_timer: float = 0.0
var _is_bouncing: bool = false
var _is_accented: bool = false


func _ready() -> void:
	_original_position = position


func on_tick(is_accent: bool) -> void:
	_bounce_timer = 0.0
	_is_bouncing = true
	_is_accented = is_accent


func _process(delta: float) -> void:
	if not _is_bouncing:
		return
	_bounce_timer += delta
	if _bounce_timer >= bounce_duration:
		_bounce_timer = bounce_duration
		_is_bouncing = false
		position = _original_position
		return
	var t := _bounce_timer / bounce_duration
	var height := sin(t * PI)
	var max_height := accent_bounce_height if _is_accented else base_bounce_height
	position = _original_position + Vector3.UP * height * max_height
