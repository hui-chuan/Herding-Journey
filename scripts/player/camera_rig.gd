## 第三人称固定俯角跟随相机（DECISIONS T10）。
## 可转水平方向，不可调俯仰。静止 3 s 后缓慢拉远（BEHAVIOR §6.3）。
extends Node3D

@export var target_path: NodePath
@export var follow_speed: float = 5.0
@export var yaw_speed_deg: float = 120.0
@export var mouse_sensitivity: float = 0.25
@export var near_distance: float = 12.0
@export var far_distance: float = 28.0
@export var idle_seconds_to_zoom_out: float = 3.0
@export var zoom_speed: float = 0.6

@onready var _target: Node3D = get_node(target_path)
@onready var _camera: Camera3D = $Pitch/Camera3D

var _idle_time: float = 0.0
var _distance: float = 12.0

func _ready() -> void:
	_distance = near_distance
	global_position = _target.global_position

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_action_pressed("camera_drag"):
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))

func _process(delta: float) -> void:
	var yaw_input := Input.get_axis("camera_left", "camera_right")
	rotate_y(deg_to_rad(-yaw_input * yaw_speed_deg * delta))

	global_position = global_position.lerp(_target.global_position, follow_speed * delta)

	var moving: bool = false
	if _target is CharacterBody3D:
		moving = (_target as CharacterBody3D).velocity.length_squared() > 0.05
	if moving:
		_idle_time = 0.0
	else:
		_idle_time += delta
	var want := far_distance if _idle_time > idle_seconds_to_zoom_out else near_distance
	_distance = lerpf(_distance, want, zoom_speed * delta)
	_camera.position.z = _distance
