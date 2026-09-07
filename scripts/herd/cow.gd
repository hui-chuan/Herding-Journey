## 牛（M1 单头版）。状态机 + 惊吓值 + 身位施压 + 乌尔朵响应。
## 群体力、头牛、草场在 M2/M3 加。参数是 BEHAVIOR.md 的暂定初值。
class_name Cow
extends CharacterBody3D

enum State { GRAZE, WANDER, REST, FLEE, ALERT }

@export_group("性格 (BEHAVIOR §2)")
@export var boldness: float = 1.0
@export var greed: float = 1.0
@export var restlessness: float = 1.0

@export_group("运动")
@export var wander_speed: float = 0.8
@export var flee_speed: float = 4.5
@export var turn_speed: float = 4.0

@export_group("惊吓 (BEHAVIOR §1.1)")
@export var fear_threshold: float = 0.5
@export var fear_half_life: float = 8.0

@export_group("身位施压 (BEHAVIOR §6.1)")
@export var pressure_radius: float = 6.0
@export var pressure_push_walk: float = 0.6
@export var pressure_push_run: float = 2.0
@export var pressure_fear_walk: float = 0.05
@export var pressure_fear_run: float = 0.25

var state: State = State.GRAZE
var fear: float = 0.0
var _state_time_left: float = 0.0
var _wander_target: Vector3
var _flee_dir: Vector3
var _external_push: Vector3
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _noise := FastNoiseLite.new()
var _noise_t: float = 0.0

@onready var _player: CharacterBody3D = get_tree().get_first_node_in_group("player")
@onready var _mesh: MeshInstance3D = $StateMarker

func _ready() -> void:
	add_to_group("cows")
	_noise.seed = randi()
	_noise.frequency = 0.15
	_enter(State.GRAZE)

func _physics_process(delta: float) -> void:
	_noise_t += delta * 0.05
	_decay_fear(delta)
	_apply_player_pressure(delta)
	if state != State.FLEE and fear >= fear_threshold * boldness:
		_enter(State.FLEE)

	var desired := Vector3.ZERO
	match state:
		State.GRAZE, State.REST:
			desired = Vector3.ZERO
		State.WANDER:
			var to_target := _wander_target - global_position
			to_target.y = 0.0
			if to_target.length() < 0.5:
				_enter(State.GRAZE)
			else:
				desired = to_target.normalized() * wander_speed
		State.FLEE:
			desired = _flee_dir * flee_speed
		State.ALERT:
			desired = Vector3.ZERO

	desired += _external_push
	_external_push = _external_push.move_toward(Vector3.ZERO, 8.0 * delta)

	velocity.x = move_toward(velocity.x, desired.x, 6.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 6.0 * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() > 0.04:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), turn_speed * delta)

	move_and_slide()

	_state_time_left -= delta
	if _state_time_left <= 0.0:
		_on_state_timeout()

func _enter(s: State) -> void:
	state = s
	match s:
		State.GRAZE:
			_state_time_left = _lognormal(40.0, 0.4) * greed
		State.WANDER:
			_state_time_left = 30.0
			_pick_wander_target()
		State.REST:
			_state_time_left = _lognormal(120.0, 0.3)
		State.FLEE:
			_state_time_left = randf_range(3.0, 5.0)
			if _flee_dir.length_squared() < 0.01:
				_flee_dir = Vector3(randf() - 0.5, 0.0, randf() - 0.5).normalized()
		State.ALERT:
			_state_time_left = randf_range(5.0, 15.0)
	_update_color()

func _on_state_timeout() -> void:
	match state:
		State.GRAZE:
			var r := randf()
			var wander_w := 0.35 * restlessness
			var rest_w := 0.15 if Clock.phase != Clock.Phase.NOON else 0.5
			if r < wander_w:
				_enter(State.WANDER)
			elif r < wander_w + rest_w:
				_enter(State.REST)
			else:
				_enter(State.GRAZE)
		State.WANDER, State.REST:
			_enter(State.GRAZE)
		State.FLEE:
			_enter(State.ALERT)
		State.ALERT:
			if fear < fear_threshold * boldness * 0.5:
				_enter(State.GRAZE)
			else:
				_state_time_left = 3.0

func _pick_wander_target() -> void:
	# 缓慢变化的噪声场给出方向，走出来是弧线而不是折线。
	var angle := _noise.get_noise_2d(_noise_t * 10.0, float(get_instance_id() % 1000)) * TAU
	var dist := randf_range(3.0, 8.0) * restlessness
	_wander_target = global_position + Vector3(cos(angle), 0.0, sin(angle)) * dist

func _decay_fear(delta: float) -> void:
	fear *= pow(0.5, delta / fear_half_life)

func _apply_player_pressure(delta: float) -> void:
	if _player == null:
		return
	var away := global_position - _player.global_position
	away.y = 0.0
	var d := away.length()
	if d > pressure_radius or d < 0.01:
		return
	var speed: float = _player.horizontal_speed()
	if speed < 0.1:
		return
	var running: bool = speed > 3.0
	var falloff := 1.0 - d / pressure_radius
	var push := pressure_push_run if running else pressure_push_walk
	var fear_rate := pressure_fear_run if running else pressure_fear_walk
	_external_push += away.normalized() * push * falloff
	add_fear(fear_rate * falloff * delta, away.normalized())

func add_fear(amount: float, from_dir: Vector3) -> void:
	fear = minf(1.0, fear + amount)
	if from_dir.length_squared() > 0.01:
		_flee_dir = from_dir.normalized()

## 乌尔朵落地（BEHAVIOR §6.2）。推力与惊吓随距离衰减。
func apply_sling_impact(point: Vector3, radius: float, push: float, fear_amount: float) -> void:
	var away := global_position - point
	away.y = 0.0
	var d := away.length()
	if d > radius:
		return
	var falloff := 1.0 - d / radius
	var dir := away.normalized() if d > 0.01 else Vector3.FORWARD
	_external_push += dir * push * falloff
	add_fear(fear_amount * falloff, dir)

func _lognormal(median: float, sigma: float) -> float:
	return median * exp(randfn(0.0, sigma))

## 头顶的状态小球，只在调试层可见。
func _update_color() -> void:
	var mat := _mesh.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	match state:
		State.GRAZE: mat.albedo_color = Color(0.15, 0.12, 0.1)
		State.WANDER: mat.albedo_color = Color(0.3, 0.25, 0.2)
		State.REST: mat.albedo_color = Color(0.1, 0.1, 0.25)
		State.FLEE: mat.albedo_color = Color(0.8, 0.2, 0.1)
		State.ALERT: mat.albedo_color = Color(0.8, 0.6, 0.1)

func state_name() -> String:
	return State.keys()[state]
