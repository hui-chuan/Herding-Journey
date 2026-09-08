## 第三人称固定俯角跟随相机（DECISIONS T10）。
## 可转水平方向，玩家不可自由调俯仰——但俯角随距离自动加大，
## 因为远观时需要更"从上往下看"才能看清整群的分布（BEHAVIOR §6.3）。
extends Node3D

## 三档距离：近（跟人）、中（看群）、远（看群在草场上的位置）。
## 牛群散开后半径可到 20 m，28 m 的旧上限只够框住半个群，所以加了第三档。
enum Zoom { NEAR, MID, FAR }

@export var target_path: NodePath
@export var yaw_speed_deg: float = 120.0
@export var mouse_sensitivity: float = 0.25
@export var zoom_distances: PackedFloat32Array = [12.0, 28.0, 52.0]
## 各档的俯角（度）。越远越俯，远观才看得出群的分布而不是一排背影。
@export var zoom_pitch_deg: PackedFloat32Array = [40.0, 46.0, 55.0]
## 各档的视野角。远档略收窄，抵消一部分广角带来的"人变小、地变空"。
@export var zoom_fov: PackedFloat32Array = [60.0, 60.0, 52.0]
@export var zoom_speed: float = 2.5
## 静止这么久后自动进入中档远观；一动就拉回（BEHAVIOR §6.3）。
@export var auto_far_after: float = 3.0

@onready var _target: Node3D = get_node(target_path)
@onready var _pitch: Node3D = $Pitch
@onready var _camera: Camera3D = $Pitch/Camera3D

var zoom_level: Zoom = Zoom.NEAR
var _distance: float
var _pitch_deg: float
var _fov: float
var _still_time: float = 0.0

func _ready() -> void:
	add_to_group("camera_rig")
	_distance = zoom_distances[zoom_level]
	_pitch_deg = zoom_pitch_deg[zoom_level]
	_fov = zoom_fov[zoom_level]
	global_position = _target.global_position
	_apply()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_action_pressed("camera_drag"):
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))

func _process(delta: float) -> void:
	var yaw_input := Input.get_axis("camera_left", "camera_right")
	rotate_y(deg_to_rad(-yaw_input * yaw_speed_deg * delta))

	global_position = _target.global_position

	# Tab / R3 在三档间循环。
	if Input.is_action_just_pressed("camera_zoom_toggle"):
		zoom_level = ((zoom_level + 1) % Zoom.size()) as Zoom

	if _target.has_method("horizontal_speed") and _target.horizontal_speed() < 0.1:
		_still_time += delta
	else:
		_still_time = 0.0

	# 自动远观只把近档抬到中档：玩家手动选了远档就尊重他的选择，别自作主张拉回来。
	var level := zoom_level
	if level == Zoom.NEAR and _still_time >= auto_far_after:
		level = Zoom.MID

	var t := zoom_speed * delta
	_distance = lerpf(_distance, zoom_distances[level], t)
	_pitch_deg = lerpf(_pitch_deg, zoom_pitch_deg[level], t)
	_fov = lerpf(_fov, zoom_fov[level], t)
	_apply()

func _apply() -> void:
	_camera.position.z = _distance
	_pitch.rotation.x = -deg_to_rad(_pitch_deg)
	_camera.fov = _fov

func zoom_name() -> String:
	return Zoom.keys()[zoom_level]
