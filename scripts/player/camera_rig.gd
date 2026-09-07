## 第三人称固定俯角跟随相机（DECISIONS T10）。
## 可转水平方向，不可调俯仰。玩家静止时自动进入远观。
extends Node3D

@export var target_path: NodePath
@export var yaw_speed_deg: float = 120.0
@export var mouse_sensitivity: float = 0.25
@export var near_distance: float = 12.0
@export var far_distance: float = 28.0
@export var zoom_speed: float = 0.6
@export var auto_far_after: float = 3.0

@onready var _target: Node3D = get_node(target_path)
@onready var _camera: Camera3D = $Pitch/Camera3D

var _far: bool = false
var _distance: float = 12.0
var _still_time: float = 0.0

func _ready() -> void:
	_distance = near_distance
	global_position = _target.global_position

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_action_pressed("camera_drag"):
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))

func _process(delta: float) -> void:
	var yaw_input := Input.get_axis("camera_left", "camera_right")
	rotate_y(deg_to_rad(-yaw_input * yaw_speed_deg * delta))

	global_position = _target.global_position

	if Input.is_action_just_pressed("camera_zoom_toggle"):
		_far = not _far
	if _target.has_method("horizontal_speed") and _target.horizontal_speed() < 0.1:
		_still_time += delta
	else:
		_still_time = 0.0
	var auto_far := _still_time >= auto_far_after
	var want := far_distance if _far or auto_far else near_distance
	_distance = lerpf(_distance, want, zoom_speed * delta)
	_camera.position.z = _distance
