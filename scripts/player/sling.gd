## 乌尔朵（BEHAVIOR §6.2）粗版。
## 鼠标瞄准地面落点，射程夹在 [min_range, max_range]，左键甩出。
## 手柄：以玩家朝向前方 gamepad_range 米为落点。
extends Node3D

@export var min_range: float = 4.0
@export var max_range: float = 40.0
@export var gamepad_range: float = 25.0
@export var cooldown: float = 2.0
@export var flight_time: float = 1.0
@export var arc_height: float = 6.0
@export var impact_radius: float = 4.0
@export var impact_push: float = 7.0
@export var impact_fear: float = 0.7

@onready var _player: CharacterBody3D = get_parent()
@onready var _marker: Node3D = $AimMarker
@onready var _stone: Node3D = $Stone

var _cooldown_left: float = 0.0
var _aim_point: Vector3
var _flying: bool = false
var _flight_t: float = 0.0
var _from: Vector3
var _to: Vector3

func _process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	_update_aim()
	_marker.visible = not _flying
	_marker.global_position = _aim_point + Vector3.UP * 0.05
	if _flying:
		_advance_stone(delta)
	elif Input.is_action_just_pressed("sling_throw") and _cooldown_left <= 0.0:
		_throw()

func _update_aim() -> void:
	var origin := _player.global_position
	var point := origin - _player.global_basis.z * gamepad_range
	var cam := get_viewport().get_camera_3d()
	var last_mouse := get_viewport().get_mouse_position()
	if cam and last_mouse != Vector2.ZERO:
		var ray_o := cam.project_ray_origin(last_mouse)
		var ray_d := cam.project_ray_normal(last_mouse)
		var hit = Plane(Vector3.UP, 0.0).intersects_ray(ray_o, ray_d)
		if hit != null:
			point = hit
	var flat := point - origin
	flat.y = 0.0
	var dist := clampf(flat.length(), min_range, max_range)
	if flat.length_squared() < 0.001:
		flat = -_player.global_basis.z
	_aim_point = origin + flat.normalized() * dist
	_aim_point.y = 0.0

func _throw() -> void:
	_flying = true
	_flight_t = 0.0
	_from = _player.global_position + Vector3.UP * 1.5
	_to = _aim_point
	_stone.visible = true
	_cooldown_left = cooldown

func _advance_stone(delta: float) -> void:
	_flight_t += delta / flight_time
	var t := minf(_flight_t, 1.0)
	var pos := _from.lerp(_to, t)
	pos.y += arc_height * 4.0 * t * (1.0 - t)
	_stone.global_position = pos
	if t >= 1.0:
		_flying = false
		_stone.visible = false
		_land(_to)

func _land(point: Vector3) -> void:
	for cow in get_tree().get_nodes_in_group("cows"):
		cow.apply_sling_impact(point, impact_radius, impact_push, impact_fear)
