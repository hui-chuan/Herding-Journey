## 牛。状态机 + 惊吓值 + 身位施压 + 乌尔朵响应 + 灰盒牛群行为。
## M2 版先把头牛、合群、惊吓传染和傍晚归栏跑起来。
class_name Cow
extends CharacterBody3D

enum State { GRAZE, WANDER, REST, FOLLOW, FLEE, ALERT, NUDGE }

@export_group("性格 (BEHAVIOR §2)")
@export var boldness: float = 1.0
@export var greed: float = 1.0
@export var restlessness: float = 1.0
@export var sociability: float = 1.0
@export var is_leader: bool = false

@export_group("运动")
@export var wander_speed: float = 1.3
@export var follow_speed: float = 1.7
@export var flee_speed: float = 3.5
@export var turn_speed: float = 4.0
## 平静态下（含被推）的速度上限；惊跑时上限为 flee_speed。
@export var calm_speed_cap: float = 3.0
## 目标速度低于此值视为停下，避免蠕动。
@export var min_move_speed: float = 0.25
@export var accel_calm: float = 3.0
@export var accel_flee: float = 8.0
@export var decel: float = 3.5
@export var wander_min_distance: float = 3.0
@export var wander_max_distance: float = 8.0
## 一次惊跑最多跑这么远，跑到就停下张望。
@export var flee_max_distance: float = 9.0
## 被石头落点"挪开"：小跑背离落点，距离随落点远近在 [min,max] 之间。
@export var nudge_speed: float = 2.5
@export var nudge_min_distance: float = 1.5
@export var nudge_max_distance: float = 5.0

@export_group("牛群")
@export var leader_path: NodePath
@export var pen_center := Vector3(-30.0, 0.0, 30.0)
@export var leader_search_radius: float = 40.0
@export var follow_start_distance: float = 13.0
@export var follow_stop_distance: float = 7.0
@export var separation_radius: float = 3.5
@export var separation_push: float = 2.0
@export var cohesion_push: float = 0.45
@export var contagion_radius: float = 8.0
@export var contagion_fear: float = 0.3

@export_group("惊吓 (BEHAVIOR §1.1)")
@export var fear_threshold: float = 0.5
@export var fear_half_life: float = 6.0

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
var _threat_pos: Vector3
var _has_threat: bool = false
var _flee_start: Vector3
var _nudge_target: Vector3
var _external_push: Vector3
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _noise := FastNoiseLite.new()
var _noise_t: float = 0.0
var _leader: Cow
var _has_spread_fear: bool = false

@onready var _player: CharacterBody3D = get_tree().get_first_node_in_group("player")
@onready var _mesh: MeshInstance3D = $StateMarker

func _ready() -> void:
	add_to_group("cows")
	# duplicate 出来的牛共用材质资源，这里各自复制一份，否则全群同色。
	var shared := _mesh.get_surface_override_material(0)
	if shared != null:
		_mesh.set_surface_override_material(0, shared.duplicate())
	if is_leader:
		add_to_group("lead_cow")
	_noise.seed = randi()
	_noise.frequency = 0.15
	_resolve_leader()
	_enter(State.GRAZE)

func _physics_process(delta: float) -> void:
	_noise_t += delta * 0.05
	_decay_fear(delta)
	_apply_player_pressure(delta)
	if state != State.FLEE and fear >= fear_threshold * boldness:
		_enter(State.FLEE)

	_resolve_leader()
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
		State.FOLLOW:
			desired = _follow_velocity()
		State.FLEE:
			if _flat_distance_to(_flee_start) >= flee_max_distance:
				_enter(State.ALERT)
			else:
				desired = _flee_dir * flee_speed
		State.ALERT:
			desired = Vector3.ZERO
		State.NUDGE:
			var to_nudge := _nudge_target - global_position
			to_nudge.y = 0.0
			if to_nudge.length() < 0.4:
				_enter(State.GRAZE)
			else:
				desired = to_nudge.normalized() * nudge_speed

	# 最小速度只裁剪状态自身的意图，推力（分离、聚合、施压）不受此限。
	if desired.length() < min_move_speed:
		desired = Vector3.ZERO
	desired += _herd_push()
	desired += _external_push
	var pushed := _external_push.length() > 0.3
	_external_push = _external_push.move_toward(Vector3.ZERO, 5.0 * delta)

	# 速度上限 + 分开的加减速。
	var cap := flee_speed if state == State.FLEE else calm_speed_cap
	if desired.length() > cap:
		desired = desired.normalized() * cap
	var current := Vector3(velocity.x, 0.0, velocity.z)
	var rate := decel
	if desired.length() > current.length():
		rate = accel_flee if (state == State.FLEE or pushed) else accel_calm
	var next := current.move_toward(desired, rate * delta)
	velocity.x = next.x
	velocity.z = next.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() > 0.04:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), turn_speed * delta)

	move_and_slide()

	_state_time_left -= delta
	if _state_time_left <= 0.0:
		_on_state_timeout()

func _enter(s: State) -> void:
	var previous := state
	state = s
	match s:
		State.GRAZE:
			_has_spread_fear = false
			_state_time_left = _lognormal(40.0, 0.4) * greed
		State.WANDER:
			_has_spread_fear = false
			_state_time_left = 30.0
			_pick_wander_target()
		State.REST:
			_has_spread_fear = false
			_state_time_left = _lognormal(120.0, 0.3)
		State.FOLLOW:
			_has_spread_fear = false
			_state_time_left = randf_range(8.0, 20.0)
		State.FLEE:
			_state_time_left = randf_range(1.5, 3.0)
			_flee_start = global_position
			_flee_dir = Vector3.ZERO
			if _has_threat:
				_flee_dir = global_position - _threat_pos
				_flee_dir.y = 0.0
			if _flee_dir.length_squared() < 0.01:
				_flee_dir = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
			# 每头牛偏一点角度，群不会排成平行线。
			_flee_dir = _flee_dir.normalized().rotated(Vector3.UP, deg_to_rad(randf_range(-25.0, 25.0)))
			if previous != State.FLEE:
				_spread_fear()
		State.NUDGE:
			_state_time_left = 4.0
		State.ALERT:
			_state_time_left = randf_range(3.0, 8.0)
			# 跑过一段就把惊吓"跑掉"一部分，否则警觉时仍高于阈值会立刻再次惊跑。
			if previous == State.FLEE:
				fear = minf(fear, fear_threshold * boldness * 0.45)
	_update_color()

func _on_state_timeout() -> void:
	match state:
		State.GRAZE:
			if _should_follow_leader():
				_enter(State.FOLLOW)
				return
			var r := randf()
			var wander_w := (0.35 + Clock.homing_urge() * 0.35) * restlessness
			var rest_w := 0.15 if Clock.phase != Clock.Phase.NOON else 0.5
			if r < wander_w:
				_enter(State.WANDER)
			elif r < wander_w + rest_w:
				_enter(State.REST)
			else:
				_enter(State.GRAZE)
		State.WANDER, State.REST:
			if _should_follow_leader():
				_enter(State.FOLLOW)
			else:
				_enter(State.GRAZE)
		State.FOLLOW:
			_enter(State.GRAZE)
		State.FLEE:
			_enter(State.ALERT)
		State.NUDGE:
			_enter(State.GRAZE)
		State.ALERT:
			if fear < fear_threshold * boldness * 0.5:
				_enter(State.GRAZE)
			else:
				_state_time_left = 2.0

func _pick_wander_target() -> void:
	var home := Clock.homing_urge()
	if is_leader and home > 0.05:
		var to_pen := pen_center - global_position
		to_pen.y = 0.0
		var step := randf_range(6.0, 14.0)
		_wander_target = global_position + to_pen.normalized() * step * lerpf(0.5, 1.8, home)
		return
	# 缓慢变化的噪声场给出方向，头牛会把方向轻轻偏向高草/围栏。
	var angle := _noise.get_noise_2d(_noise_t * 10.0, float(get_instance_id() % 1000)) * TAU
	if is_leader:
		var grass_bias := _best_grass_dir()
		if grass_bias.length_squared() > 0.01:
			var noise_dir := Vector3(cos(angle), 0.0, sin(angle))
			var mixed := noise_dir.lerp(grass_bias, 0.55).normalized()
			angle = atan2(mixed.z, mixed.x)
	var dist := clampf(randf_range(wander_min_distance, wander_max_distance) * restlessness, wander_min_distance, wander_max_distance)
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
	add_fear(fear_rate * falloff * delta, _player.global_position)

## 惊吓来源记为位置而非方向，进入惊跑时才据此算背离方向。
func add_fear(amount: float, threat_pos: Vector3) -> void:
	fear = minf(1.0, fear + amount)
	_threat_pos = threat_pos
	_has_threat = true

## 乌尔朵落地（BEHAVIOR §6.2）。推力与惊吓随距离衰减。
func apply_sling_impact(point: Vector3, radius: float, push: float, fear_amount: float) -> void:
	var away := global_position - point
	away.y = 0.0
	var d := away.length()
	if d > radius:
		return
	var falloff := 1.0 - d / radius
	var dir := away.normalized() if d > 0.01 else Vector3.FORWARD
	add_fear(fear_amount * falloff, point)
	# 没被吓跑的牛小跑挪开；跑不跑由 _physics_process 里的阈值判断决定。
	if state != State.FLEE and fear < fear_threshold * boldness:
		_nudge_target = global_position + dir * lerpf(nudge_min_distance, nudge_max_distance, falloff)
		_enter(State.NUDGE)

func _lognormal(median: float, sigma: float) -> float:
	return median * exp(randfn(0.0, sigma))

## 头顶的状态小球，只在调试层可见。
func _update_color() -> void:
	var mat := _mesh.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	match state:
		State.GRAZE: mat.albedo_color = Color(0.95, 0.85, 0.25) if is_leader else Color(0.15, 0.12, 0.1)
		State.WANDER: mat.albedo_color = Color(0.3, 0.25, 0.2)
		State.REST: mat.albedo_color = Color(0.1, 0.1, 0.25)
		State.FOLLOW: mat.albedo_color = Color(0.25, 0.55, 0.9)
		State.FLEE: mat.albedo_color = Color(0.8, 0.2, 0.1)
		State.ALERT: mat.albedo_color = Color(0.8, 0.6, 0.1)
		State.NUDGE: mat.albedo_color = Color(0.9, 0.5, 0.3)

func refresh_marker() -> void:
	_update_color()

func state_name() -> String:
	return State.keys()[state]

func is_in_pen() -> bool:
	var flat := global_position - pen_center
	flat.y = 0.0
	return absf(flat.x) <= 10.0 and absf(flat.z) <= 10.0

func _resolve_leader() -> void:
	if is_leader:
		_leader = self
		return
	if _leader == self:
		_leader = null
	if _leader != null and is_instance_valid(_leader):
		return
	if leader_path != NodePath():
		_leader = get_node_or_null(leader_path) as Cow
	if _leader == null:
		_leader = get_tree().get_first_node_in_group("lead_cow") as Cow

func _should_follow_leader() -> bool:
	if is_leader or _leader == null or not is_instance_valid(_leader):
		return false
	if _leader.state == State.FLEE:
		return false
	var d := _flat_distance_to(_leader.global_position)
	return d > follow_start_distance or (_leader.state == State.WANDER and d > follow_stop_distance)

func _follow_velocity() -> Vector3:
	if _leader == null or not is_instance_valid(_leader):
		return Vector3.ZERO
	var to_leader := _leader.global_position - global_position
	to_leader.y = 0.0
	if to_leader.length() < follow_stop_distance:
		_enter(State.GRAZE)
		return Vector3.ZERO
	return to_leader.normalized() * follow_speed * sociability

func _herd_push() -> Vector3:
	var push := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("cows"):
		var other := node as Cow
		if other == null or other == self:
			continue
		var away := global_position - other.global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.01 and d < separation_radius:
			push += away.normalized() * (1.0 - d / separation_radius) * separation_push
	if not is_leader and _leader != null and is_instance_valid(_leader):
		var to_leader := _leader.global_position - global_position
		to_leader.y = 0.0
		var d := to_leader.length()
		if d > follow_stop_distance:
			push += to_leader.normalized() * minf(1.0, d / follow_start_distance) * cohesion_push * sociability
	return push

func _spread_fear() -> void:
	if _has_spread_fear:
		return
	_has_spread_fear = true
	for node in get_tree().get_nodes_in_group("cows"):
		var other := node as Cow
		if other == null or other == self:
			continue
		var away := other.global_position - global_position
		away.y = 0.0
		var d := away.length()
		if d <= contagion_radius:
			# 传染的是同一个威胁位置；没有来源时把自己当来源。
			var source := _threat_pos if _has_threat else global_position
			other.add_fear(contagion_fear / maxf(0.2, other.boldness), source)

func _best_grass_dir() -> Vector3:
	var best_dir := Vector3.ZERO
	var best_score := -INF
	for i in 10:
		var angle := float(i) / 10.0 * TAU + _noise_t
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var p := global_position + dir * leader_search_radius
		var grass := 1.0 - clampf(absf(p.x) + absf(p.z), 0.0, 180.0) / 360.0
		var score := grass + _noise.get_noise_2d(p.x * 0.03, p.z * 0.03) * 0.25
		if score > best_score:
			best_score = score
			best_dir = dir
	return best_dir

func _flat_distance_to(point: Vector3) -> float:
	var d := point - global_position
	d.y = 0.0
	return d.length()
