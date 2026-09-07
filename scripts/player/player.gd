## 玩家。步行 / 奔跑两档，移动方向相对相机。
## 牛只读取 velocity 与位置来计算身位施压（BEHAVIOR §6.1）。
class_name Player
extends CharacterBody3D

@export var walk_speed: float = 2.0
@export var run_speed: float = 5.0
@export var accel: float = 10.0
@export var turn_speed: float = 10.0

@onready var camera_rig: Node3D = get_node("../CameraRig")

## 吆喝模式：开着时靠近牛的驱赶力更强、半径更大（BEHAVIOR §6.1 的主动施压档）。
var driving: bool = false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("drive_toggle"):
		driving = not driving

func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var yaw: float = camera_rig.global_rotation.y
	var dir := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)
	var target_speed := run_speed if Input.is_action_pressed("run") else walk_speed
	var target_vel := dir * target_speed

	velocity.x = move_toward(velocity.x, target_vel.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, accel * delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	if dir.length_squared() > 0.01:
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)

	move_and_slide()

func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()
