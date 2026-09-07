## 牛。状态机 + 惊吓值 + 身位施压 + 乌尔朵响应 + 灰盒牛群行为。
## M2 版先把头牛、合群、惊吓传染和傍晚归栏跑起来。
class_name Cow
extends CharacterBody3D

enum State { GRAZE, WANDER, REST, FOLLOW, FLEE, ALERT, NUDGE }

const DEFAULT_SPECIES := "res://data/species/yak.tres"

@export_group("性格 (BEHAVIOR §2)")
@export var boldness: float = 1.0
@export var greed: float = 1.0
@export var restlessness: float = 1.0
@export var sociability: float = 1.0
@export var is_leader: bool = false

@export_group("种类 (DECISIONS T16)")
## 全部行为参数的来源。同种共享一份 .tres，调参只改那一个文件。
@export var species: SpeciesData
## 个体的跟随触发距离倍率：让"爱走远的牛"更晚才去追头牛。
@export var follow_distance_scale: float = 1.0

@export_group("牛群")
@export var leader_path: NodePath
@export var pen_center := Vector3(-30.0, 0.0, 30.0)

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
	if species == null:
		species = load(DEFAULT_SPECIES) as SpeciesData
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
	if state != State.FLEE and fear >= species.fear_threshold * boldness:
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
				desired = to_target.normalized() * species.wander_speed
		State.FOLLOW:
			desired = _follow_velocity()
		State.FLEE:
			if _flat_distance_to(_flee_start) >= species.flee_max_distance:
				_enter(State.ALERT)
			else:
				desired = _flee_dir * species.flee_speed
		State.ALERT:
			desired = Vector3.ZERO
		State.NUDGE:
			var to_nudge := _nudge_target - global_position
			to_nudge.y = 0.0
			if to_nudge.length() < 0.4:
				_enter(State.GRAZE)
			else:
				desired = to_nudge.normalized() * species.nudge_speed

	# 最小速度只裁剪状态自身的意图，推力（分离、聚合、施压）不受此限。
	if desired.length() < species.min_move_speed:
		desired = Vector3.ZERO
	desired += _herd_push()
	desired += _external_push
	var pushed := _external_push.length() > 0.3
	_external_push = _external_push.move_toward(Vector3.ZERO, 5.0 * delta)

	# 速度上限 + 分开的加减速。
	var cap: float = species.flee_speed if state == State.FLEE else species.calm_speed_cap
	if desired.length() > cap:
		desired = desired.normalized() * cap
	var current := Vector3(velocity.x, 0.0, velocity.z)
	var rate: float = species.decel
	if desired.length() > current.length():
		rate = species.accel_flee if (state == State.FLEE or pushed) else species.accel_calm
	var next := current.move_toward(desired, rate * delta)
	velocity.x = next.x
	velocity.z = next.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() > 0.04:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), species.turn_speed * delta)

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
			_state_time_left = _lognormal(20.0, 0.4) * greed
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
				fear = minf(fear, species.fear_threshold * boldness * 0.45)
	_update_color()

func _on_state_timeout() -> void:
	match state:
		State.GRAZE:
			if _should_follow_leader():
				_enter(State.FOLLOW)
				return
			var r := randf()
			var wander_w := (0.55 + Clock.homing_urge() * 0.3) * restlessness
			var rest_w := 0.08 if Clock.phase != Clock.Phase.NOON else 0.35
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
			if fear < species.fear_threshold * boldness * 0.5:
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
	var dist := clampf(randf_range(species.wander_min_distance, species.wander_max_distance) * restlessness, species.wander_min_distance, species.wander_max_distance)
	# 以噪声方向为中心撒若干候选点，按"离头牛/群近"加权抽取（BEHAVIOR §1.2）。
	var anchor := _cohesion_anchor()
	var best := global_position + Vector3(cos(angle), 0.0, sin(angle)) * dist
	var best_score := -INF
	for i in species.wander_samples:
		var a := angle + randf_range(-PI * 0.75, PI * 0.75)
		var cand := global_position + Vector3(cos(a), 0.0, sin(a)) * dist * randf_range(0.6, 1.0)
		var score := randf() * 0.5
		if anchor != Vector3.INF:
			var d_now := _flat_distance_to(anchor)
			var d_cand := cand.distance_to(anchor)
			score += (d_now - d_cand) / dist * species.wander_cohesion_weight * sociability
		if score > best_score:
			best_score = score
			best = cand
	_wander_target = best

func _decay_fear(delta: float) -> void:
	fear *= pow(0.5, delta / species.fear_half_life)

func _apply_player_pressure(delta: float) -> void:
	if _player == null:
		return
	var away := global_position - _player.global_position
	away.y = 0.0
	var d := away.length()
	if d < 0.01:
		return
	var driving: bool = _player.get("driving") == true
	if driving:
		apply_area_pressure(_player.global_position, species.drive_radius, species.drive_fear_per_sec * delta)
		return
	if d > species.pressure_radius:
		return
	var speed: float = _player.horizontal_speed()
	if speed < 0.1:
		return
	var running: bool = speed > 3.0
	var falloff: float = 1.0 - d / species.pressure_radius
	_external_push += away.normalized() * (species.pressure_push_run if running else species.pressure_push_walk) * falloff
	if running:
		add_fear(species.pressure_fear_run * falloff * delta, _player.global_position)

## 惊吓来源记为位置而非方向，进入惊跑时才据此算背离方向。
func add_fear(amount: float, threat_pos: Vector3) -> void:
	fear = minf(1.0, fear + amount)
	_threat_pos = threat_pos
	_has_threat = true

## 区域压力（吆喝与乌尔朵共用）：源点半径内的牛背离源点挪开，越近挪越远，并获得惊吓。
## 已在挪开中则刷新目标，持续施压就持续前进；半径外的牛不受影响。
func apply_area_pressure(source: Vector3, radius: float, fear_amount: float) -> void:
	var away := global_position - source
	away.y = 0.0
	var d := away.length()
	if d > radius:
		return
	var falloff := 1.0 - d / radius
	var dir := away.normalized() if d > 0.01 else Vector3.FORWARD
	add_fear(fear_amount * falloff, source)
	if state == State.FLEE or fear >= species.fear_threshold * boldness:
		return
	_nudge_target = global_position + dir * lerpf(species.nudge_min_distance, species.nudge_max_distance, falloff)
	if state == State.NUDGE:
		_state_time_left = 4.0
	else:
		_enter(State.NUDGE)

## 乌尔朵落地（BEHAVIOR §6.2）。推力与惊吓随距离衰减。
func apply_sling_impact(point: Vector3, radius: float, fear_amount: float) -> void:
	apply_area_pressure(point, radius, fear_amount)

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
	return d > follow_start_distance() or (_leader.state == State.WANDER and d > species.follow_stop_distance)

func _follow_velocity() -> Vector3:
	if _leader == null or not is_instance_valid(_leader):
		return Vector3.ZERO
	var to_leader := _leader.global_position - global_position
	to_leader.y = 0.0
	if to_leader.length() < species.follow_stop_distance:
		_enter(State.GRAZE)
		return Vector3.ZERO
	return to_leader.normalized() * species.follow_speed * sociability

func _herd_push() -> Vector3:
	var push := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("cows"):
		var other := node as Cow
		if other == null or other == self:
			continue
		var away := global_position - other.global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.01 and d < species.separation_radius:
			push += away.normalized() * (1.0 - d / species.separation_radius) * species.separation_push
	if not is_leader and _leader != null and is_instance_valid(_leader):
		var to_leader := _leader.global_position - global_position
		to_leader.y = 0.0
		var d := to_leader.length()
		if d > species.cohesion_start:
			var t := clampf((d - species.cohesion_start) / maxf(0.1, follow_start_distance() - species.cohesion_start), 0.0, 1.0)
			push += to_leader.normalized() * t * species.cohesion_push * sociability
	elif is_leader:
		var centroid := _herd_centroid()
		if centroid != Vector3.INF:
			var to_c := centroid - global_position
			to_c.y = 0.0
			if to_c.length() > species.cohesion_start:
				push += to_c.normalized() * species.leader_cohesion_push
	return push

## 聚合的参照点：普通牛看头牛，头牛看群体质心。
func _cohesion_anchor() -> Vector3:
	if is_leader:
		return _herd_centroid()
	if _leader != null and is_instance_valid(_leader):
		return _leader.global_position
	return Vector3.INF

func _herd_centroid() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for node in get_tree().get_nodes_in_group("cows"):
		if node != self:
			sum += (node as Node3D).global_position
			n += 1
	return sum / n if n > 0 else Vector3.INF

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
		if d <= species.contagion_radius:
			# 传染的是同一个威胁位置；没有来源时把自己当来源。
			var source := _threat_pos if _has_threat else global_position
			other.add_fear(species.contagion_fear / maxf(0.2, other.boldness), source)

func _best_grass_dir() -> Vector3:
	var best_dir := Vector3.ZERO
	var best_score := -INF
	for i in 10:
		var angle := float(i) / 10.0 * TAU + _noise_t
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var p: Vector3 = global_position + dir * species.leader_search_radius
		var grass := 1.0 - clampf(absf(p.x) + absf(p.z), 0.0, 180.0) / 360.0
		var score := grass + _noise.get_noise_2d(p.x * 0.03, p.z * 0.03) * 0.25
		if score > best_score:
			best_score = score
			best_dir = dir
	return best_dir

## 跟随触发距离 = 种类基准 × 个体倍率。
func follow_start_distance() -> float:
	return species.follow_start_distance * follow_distance_scale

func _flat_distance_to(point: Vector3) -> float:
	var d := point - global_position
	d.y = 0.0
	return d.length()
