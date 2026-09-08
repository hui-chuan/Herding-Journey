## 牛。状态机 + 惊吓值 + 身位施压 + 乌尔朵响应 + 灰盒牛群行为。
## M2 版先把头牛、合群、惊吓传染和傍晚归栏跑起来。
class_name Cow
extends CharacterBody3D

enum State { GRAZE, WANDER, REST, FOLLOW, FLEE, ALERT, NUDGE }

const DEFAULT_SPECIES := "res://data/species/yak.tres"
## 非吃草时饱腹度的自然下降（每秒）。
## 定标：牛约有 39% 的时间不在吃草，一整天因此掉约 0.07——远小于正常放牧一天的摄入，
## 所以吃得到草的牛会慢慢变饱，吃不到的才会掉。初版 0.0002 是按 480 s 的一天定的，
## 换到 1800 s 后它一天要掉 0.36，比一头牛可能吃到的还多，牛必饿死。
const SATIETY_DECAY := 0.0001
## 头牛挑草场的环形采样：内环避免选中脚下这一格（原地打转），外环用 leader_search_radius。
const LEADER_PICK_MIN_RADIUS := 15.0
const LEADER_PICK_SAMPLES := 12

## 这头牛的持久数据（ARCHITECTURE §2.1）。入树前由 HerdManager 设好。
## 留空则 _ready 里自己抽一份，方便在编辑器里单独拖一头牛出来试。
var data: CowData

# 以下四项是 data 的镜像，读得频繁，摊平成变量省一层间接。
var boldness: float = 1.0
var greed: float = 1.0
var restlessness: float = 1.0
var sociability: float = 1.0
var is_leader: bool = false
var follow_distance_scale: float = 1.0

@export_group("种类 (DECISIONS T16)")
## 全部行为参数的来源。同种共享一份 .tres，调参只改那一个文件。
@export var species: SpeciesData

@export_group("牛群")
@export var leader_path: NodePath

var state: State = State.GRAZE
var fear: float = 0.0
## 饱腹度 0–1（BEHAVIOR §1.1）。吃草上升，其余时间缓慢下降。
var satiety: float = 0.5
var _grassland: Grassland
var _pen: Pen
## 头牛上次挑草场的方向，给漂移一点惯性（GRASSLAND §3）。
var _drift_dir: Vector3 = Vector3.ZERO
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
## 跟随检查的节拍。原来只在吃草计时结束时看一眼头牛，最长要等 20 s，头牛早走远了。
var _follow_check: float = 0.0
## 这一帧是否有压力源在作用。没有 → 撤压奖励，惊吓加速衰减（BEHAVIOR §6.5）。
var _pressured: bool = false

@onready var _player: CharacterBody3D = get_tree().get_first_node_in_group("player")
@onready var _mesh: MeshInstance3D = $StateMarker

func _ready() -> void:
	add_to_group("cows")
	if species == null:
		species = load(DEFAULT_SPECIES) as SpeciesData
	# 场景里的材质是共享资源，每头牛先各自复制一份，否则状态小球全群同色。
	# 必须在 apply_data() 之前——它会调 _update_color() 写这份材质。
	var shared := _mesh.get_surface_override_material(0)
	if shared != null:
		_mesh.set_surface_override_material(0, shared.duplicate())
	if data == null:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		data = CowData.roll(rng, 0, species, is_leader)
		data.position = global_position
	apply_data()
	_grassland = get_tree().get_first_node_in_group("grassland") as Grassland
	_pen = get_tree().get_first_node_in_group("pen") as Pen
	_noise.seed = randi()
	_noise.frequency = 0.15
	# 漂移方向从随机开始，头牛第一次挑草场后会被覆盖。
	var a0 := randf() * TAU
	_drift_dir = Vector3(cos(a0), 0.0, sin(a0))
	_resolve_leader()
	_enter(State.GRAZE)

func _physics_process(delta: float) -> void:
	_noise_t += delta * 0.05
	_decay_fear(delta)
	_pressured = false
	_update_satiety(delta)
	_apply_player_pressure(delta)
	if state != State.FLEE and fear >= species.fear_threshold * boldness:
		_enter(State.FLEE)

	_resolve_leader()
	_follow_check -= delta
	if _follow_check <= 0.0:
		_follow_check = 1.0
		# 头牛傍晚在栏外不卧着：已在休息也起身走。
		if is_leader and state == State.REST and Clock.homing_urge() > 0.3 and not is_in_pen():
			_enter(State.WANDER)
		if (state == State.GRAZE or state == State.REST or state == State.WANDER) and _should_follow_leader():
			_enter(State.FOLLOW)
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

	# 最小速度只裁剪状态自身的意图，推力（分离、聚合、施压）与吃草漂移不受此限。
	if desired.length() < species.min_move_speed:
		desired = Vector3.ZERO
	if state == State.GRAZE:
		desired += _graze_drift()
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
	_slide_along_walls()

	_state_time_left -= delta
	if _state_time_left <= 0.0:
		_on_state_timeout()

func _enter(s: State) -> void:
	var previous := state
	state = s
	match s:
		State.GRAZE:
			_has_spread_fear = false
			# 草好就多待，草差就短促结束（GRASSLAND §2.3）。
			_state_time_left = _lognormal(20.0, 0.4) * greed * (0.4 + 0.6 * graze_efficiency())
			# 傍晚在栏外，头牛吃草的间歇越来越短。
			if is_leader and not is_in_pen():
				_state_time_left *= 1.0 - 0.7 * Clock.homing_urge()
		State.WANDER:
			_has_spread_fear = false
			_pick_wander_target()
			# 走到目标要多久就给多久（上限 90 s）。头牛的挑草场目标有二三十米，
			# 固定 30 s 会让它每次走到一半就被打断，群永远漂移不出去。
			var trip := _flat_distance_to(_wander_target) / maxf(0.3, species.wander_speed)
			_state_time_left = clampf(trip * 1.5, 10.0, 90.0)
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
			var home := Clock.homing_urge()
			var wander_w := (0.55 + home * 0.3) * restlessness
			var rest_w := 0.08 if Clock.phase != Clock.Phase.NOON else 0.5
			# 傍晚在栏外：头牛不卧下，吃两口就走（BEHAVIOR §3 认路回家）。
			# 只靠"漫步权重加一点"回不了家——她会在 100 m 外卧到天黑。
			if is_leader and home > 0.1 and not is_in_pen():
				rest_w = 0.0
				wander_w = maxf(wander_w, 0.5 + home)
			# 草差就更想走、更不想卧下——牛群"自己离开吃秃的地方"由此涌现。
			if graze_efficiency() < 0.5:
				wander_w *= 2.5
				rest_w *= 0.3
			# 吃饱了更愿意休息，饿了更想吃（BEHAVIOR §1.1）。
			rest_w *= lerpf(0.5, 1.6, satiety)
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
		var target := home_target()
		var to_pen := target - global_position
		to_pen.y = 0.0
		# 离家越远步子越大（8–30 m），到门口收小，免得一步跨过集结点撞栅栏。
		var step := minf(to_pen.length(), clampf(to_pen.length() * 0.5, 8.0, 30.0) * lerpf(0.6, 1.5, home))
		_wander_target = global_position + to_pen.normalized() * step
		# 吃草漂移也跟着朝家走，否则白天的旧方向会在两次归栏步之间把群拖回去。
		if to_pen.length_squared() > 0.01:
			_drift_dir = to_pen.normalized()
		return
	# 头牛：直接走向挑中的那一格（GRASSLAND §3）。
	# 不要把它摊进下面的噪声采样——那样目标被稀释成十几米的随机漫步，
	# 群就只在出生点附近打转，"往草好的地方漂移"不会发生。
	if is_leader and _grassland != null:
		_wander_target = _pick_pasture()
		return
	# 缓慢变化的噪声场给出方向。
	var angle := _noise.get_noise_2d(_noise_t * 10.0, float(get_instance_id() % 1000)) * TAU
	var dist := clampf(randf_range(species.wander_min_distance, species.wander_max_distance) * restlessness, species.wander_min_distance, species.wander_max_distance)
	# 以噪声方向为中心撒若干候选点，按草量选，出了舒适半径才按合群扣分（BEHAVIOR §1.2）。
	# 早先的写法把草量乘在一个 0–0.5 的随机数上、把"靠近头牛"当 ±1 的加分项，
	# 结果头牛不动时候选点永远选离她更近的那个，草再差也不走，群守着秃格饿到 0.15。
	var anchor := _cohesion_anchor()
	var best := global_position + Vector3(cos(angle), 0.0, sin(angle)) * dist
	var best_score := -INF
	for i in species.wander_samples:
		var a := angle + randf_range(-PI * 0.75, PI * 0.75)
		var cand := global_position + Vector3(cos(a), 0.0, sin(a)) * dist * randf_range(0.6, 1.0)
		var score := randf() * 0.3
		if _grassland != null:
			score += 1.5 * _grassland.sample(cand)
		if anchor != Vector3.INF:
			var d_cand := cand.distance_to(anchor)
			var comfort: float = species.cohesion_start
			if d_cand > comfort:
				score -= (d_cand - comfort) / maxf(1.0, follow_start_distance() - comfort) * species.wander_cohesion_weight * sociability
		if score > best_score:
			best_score = score
			best = cand
	_wander_target = best

## 吃草时从所在格扣草、涨饱腹；其余时间缓慢消耗（GRASSLAND §2.1）。
## 用时钟缩放后的 delta：草的消耗属于"一天里发生的事"，快进时钟时它要跟着走（T17）。
func _update_satiety(delta: float) -> void:
	var game_delta := delta * Clock.time_scale
	if state == State.GRAZE and _grassland != null:
		# 摄入随草量衰减（GRASSLAND §2.2）：秃地上吃得慢，牛因此更早结束吃草去漫步。
		var eff := graze_efficiency()
		var rate := species.graze_rate * greed * eff
		var eaten := _grassland.consume(global_position, rate * game_delta)
		satiety = minf(1.0, satiety + eaten * species.satiety_per_grass)
		# 脚下吃到不划算就立刻挪窝，不等这一轮吃草的计时走完。
		# 没有这一条，牛会在同一格上反复进入吃草，把 25 格的压力压到三五格上。
		if eff <= species.graze_efficiency_floor + 0.01:
			_state_time_left = minf(_state_time_left, 1.0)
	else:
		satiety = maxf(0.0, satiety - SATIETY_DECAY * game_delta)

## 顶在栅栏上时沿栅栏滑向目标那一侧，而不是一直往里顶（DAY_CYCLE §3，"卡栅栏"）。
## 只对有目标的移动态生效；吃草被推到栅栏上不管，推力一消它就停了。
func _slide_along_walls() -> void:
	if not is_on_wall():
		return
	var goal := Vector3.INF
	match state:
		State.WANDER: goal = _wander_target
		State.NUDGE: goal = _nudge_target
		State.FOLLOW:
			if _leader != null and is_instance_valid(_leader):
				goal = _leader.global_position
	if goal == Vector3.INF:
		return
	var n := get_wall_normal()
	n.y = 0.0
	if n.length_squared() < 0.01:
		return
	n = n.normalized()
	var to_goal := goal - global_position
	to_goal.y = 0.0
	# 目标方向去掉法向分量就是沿墙的分量；正顶着墙时任选一侧。
	var tangent := to_goal - n * to_goal.dot(n)
	if tangent.length_squared() < 0.05:
		tangent = Vector3(-n.z, 0.0, n.x)
	_external_push += tangent.normalized() * 1.5

## 吃草漂移（BEHAVIOR §1.3）：低着头一步步往前挪，方向是头牛的漂移方向，草越差挪越快。
## 速度低于 min_move_speed，也低于移动档的判定阈值，所以它不会把群切到移动档。
func _graze_drift() -> Vector3:
	var dir := herd_drift_dir()
	if dir.length_squared() < 0.01:
		return Vector3.ZERO
	var eff := graze_efficiency()
	return dir * species.graze_drift_speed * clampf(1.5 - eff, 0.5, 1.3)

## 群的漂移方向：头牛上次挑草场的方向；普通牛读头牛的。
func herd_drift_dir() -> Vector3:
	if is_leader or _leader == null or not is_instance_valid(_leader):
		return _drift_dir
	return _leader.herd_drift_dir()

## 脚下这一格的吃草效率 0.15–1.0（GRASSLAND §2.2）。没有草场时按满效率。
func graze_efficiency() -> float:
	if _grassland == null:
		return 1.0
	return _grassland.efficiency(global_position)

func _decay_fear(delta: float) -> void:
	var half_life: float = species.fear_half_life
	if not _pressured:
		half_life *= species.release_decay_scale
	fear *= pow(0.5, delta / half_life)

func _apply_player_pressure(delta: float) -> void:
	if _player == null:
		return
	var away := global_position - _player.global_position
	away.y = 0.0
	var d := away.length()
	if d < 0.01:
		return
	# 逃离区随情绪变大（BEHAVIOR §6.0）：惊了的牛离得更远就开始动。
	var zone_scale: float = 1.0 + fear * species.flight_zone_fear_scale
	var driving: bool = _player.get("driving") == true
	if driving:
		apply_area_pressure(_player.global_position, species.drive_radius * zone_scale, species.drive_fear_per_sec * delta)
		return
	var radius: float = species.pressure_radius * zone_scale
	if d > radius:
		return
	var speed: float = _player.horizontal_speed()
	if speed < 0.1:
		return
	_pressured = true
	var running: bool = speed > 3.0
	var falloff: float = 1.0 - d / radius
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
	_pressured = true
	var falloff := 1.0 - d / radius
	var dir := away.normalized() if d > 0.01 else Vector3.FORWARD
	add_fear(fear_amount * falloff, source)
	if state == State.FLEE or fear >= species.fear_threshold * boldness:
		return
	dir = _balance_direction(dir)
	_nudge_target = global_position + dir * lerpf(species.nudge_min_distance, species.nudge_max_distance, falloff)
	if state == State.NUDGE:
		_state_time_left = 4.0
	else:
		_enter(State.NUDGE)

## 平衡点（BEHAVIOR §6.0，low-stress stockmanship）：压力源在肩后 → 牛向前走，只略微偏离源点一侧；
## 压力源在肩前 → 牛折返，背离源点。石头落在牛前方也是同一条规则："落在牛想去的方向前面，牛就折回来"。
## away 是背离源点的单位向量。
func _balance_direction(away: Vector3) -> Vector3:
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		return away
	forward = forward.normalized()
	# away 与前方同向 → 源在后方；反向 → 源在前方。
	var behind := forward.dot(away)
	if behind > 0.0:
		return (forward + away * species.balance_side_bias).normalized()
	return away

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

## 围栏中心。没有围栏时退回原点，灰盒里也不会崩。
func pen_position() -> Vector3:
	return _pen.global_position if _pen != null else Vector3.ZERO

## 此刻回栏该朝哪走：栏外先去门前集结点，再直穿门。没有围栏时退回 pen_position()。
func home_target() -> Vector3:
	return _pen.home_target(global_position) if _pen != null else pen_position()

## 归栏判定交给 Pen（DAY_CYCLE §2.2）：只有一处知道"什么算在栏里"。
func is_in_pen() -> bool:
	return _pen != null and _pen.contains(global_position)

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

## 头牛是否在"有目的移动"（BEHAVIOR §1 跟随态的进入条件）：挑草场、归栏、被赶都算，惊跑不算。
func _leader_moving() -> bool:
	if _leader == null or not is_instance_valid(_leader) or _leader == self:
		return false
	if _leader.state != State.WANDER and _leader.state != State.NUDGE and _leader.state != State.FOLLOW:
		return false
	return Vector2(_leader.velocity.x, _leader.velocity.z).length() > 0.3

## 群当前处于移动档还是吃草档（BEHAVIOR §5.1）。头牛看自己，普通牛看头牛。
func _moving_regime() -> bool:
	if is_leader:
		return (state == State.WANDER or state == State.NUDGE) and Vector2(velocity.x, velocity.z).length() > 0.3
	return _leader_moving() or state == State.FOLLOW or state == State.NUDGE

func _should_follow_leader() -> bool:
	if is_leader or _leader == null or not is_instance_valid(_leader):
		return false
	if _leader.state == State.FLEE:
		return false
	var d := _flat_distance_to(_leader.global_position)
	return d > follow_start_distance() or (_leader_moving() and d > species.follow_stop_distance)

func _follow_velocity() -> Vector3:
	if _leader == null or not is_instance_valid(_leader):
		return Vector3.ZERO
	var to_leader := _leader.global_position - global_position
	to_leader.y = 0.0
	var d := to_leader.length()
	if d < species.follow_stop_distance:
		_enter(State.GRAZE)
		return Vector3.ZERO
	# 头牛停下了、自己也在她的活动范围内，就不必追到跟前。
	if not _leader_moving() and d < follow_start_distance() * 0.7:
		_enter(State.GRAZE)
		return Vector3.ZERO
	# 落得越远追得越急，追上了就放慢，别一头撞进她怀里。
	var speed: float = species.follow_speed * sociability * clampf(d / (species.follow_stop_distance * 2.0), 0.6, 1.5)
	return to_leader.normalized() * speed

func _herd_push() -> Vector3:
	var push := Vector3.ZERO
	var moving := _moving_regime()
	var sep_r: float = species.separation_radius_moving if moving else species.separation_radius
	for node in get_tree().get_nodes_in_group("cows"):
		var other := node as Cow
		if other == null or other == self:
			continue
		var away := global_position - other.global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.01 and d < sep_r:
			push += away.normalized() * (1.0 - d / sep_r) * species.separation_push
	if not is_leader and _leader != null and is_instance_valid(_leader):
		var to_leader := _leader.global_position - global_position
		to_leader.y = 0.0
		var d := to_leader.length()
		# 移动档：拉力更强、起得更早，群收拢成一团跟着走。
		var start: float = species.cohesion_start * (0.5 if moving else 1.0)
		var strength: float = species.cohesion_push * (species.cohesion_moving_scale if moving else 1.0)
		if d > start:
			var t := clampf((d - start) / maxf(0.1, follow_start_distance() - start), 0.0, 1.0)
			push += to_leader.normalized() * t * strength * sociability
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

## 惊吓传染分级（BEHAVIOR §5.2）：单头惊跑只让邻居抬头警觉；半径内已有别的牛在惊跑
## （两头以上同时惊）才连锁，全群炸开。炸开后各自跑不远，靠跟随机制自行重聚。
func _spread_fear() -> void:
	if _has_spread_fear:
		return
	_has_spread_fear = true
	var neighbours: Array[Cow] = []
	var fleeing_nearby := 0
	for node in get_tree().get_nodes_in_group("cows"):
		var other := node as Cow
		if other == null or other == self:
			continue
		if _flat_distance_to(other.global_position) <= species.contagion_radius:
			neighbours.append(other)
			if other.state == State.FLEE:
				fleeing_nearby += 1
	var chain := fleeing_nearby >= 1
	var source := _threat_pos if _has_threat else global_position
	for other in neighbours:
		if chain:
			other.add_fear(species.contagion_fear / maxf(0.2, other.boldness), source)
		else:
			other.add_fear(species.contagion_fear_single / maxf(0.2, other.boldness), source)
			other.alert_from(source)

## 邻居惊跑时抬头张望：平静态进入警觉，不跑。
func alert_from(source: Vector3) -> void:
	if state == State.GRAZE or state == State.REST or state == State.WANDER:
		_threat_pos = source
		_has_threat = true
		_enter(State.ALERT)

## 头牛挑草场（GRASSLAND §3）：直接返回选中的目标点。
func _pick_pasture() -> Vector3:
	var dir := _best_grass_dir()
	if dir.length_squared() < 0.01:
		return global_position
	# 一次走 15–45 m 里的一段，不是一步到位；到了再挑下一块。
	var step := randf_range(LEADER_PICK_MIN_RADIUS, species.leader_search_radius) * 0.5
	return global_position + dir * step

## 头牛挑草场（GRASSLAND §3）：向草场问一个目标格，返回指向它的方向。
## 没有草场数据时回落到噪声，保证灰盒里也能跑。
func _best_grass_dir() -> Vector3:
	if _grassland == null:
		var a := _noise.get_noise_2d(_noise_t * 7.0, 31.0) * TAU
		return Vector3(cos(a), 0.0, sin(a))
	var bias_dir := Vector3.ZERO
	var home := Clock.homing_urge()
	if home > 0.0:
		bias_dir = home_target() - global_position
		bias_dir.y = 0.0
		bias_dir = bias_dir.normalized()
	var target := _grassland.best_cell_near(
		global_position,
		LEADER_PICK_MIN_RADIUS,
		species.leader_search_radius,
		LEADER_PICK_SAMPLES,
		_drift_dir,
		bias_dir,
		home)
	var dir := target - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return _drift_dir
	dir = dir.normalized()
	_drift_dir = dir
	return dir

## 把 data 摊到运行时字段上，并让外观按 body_seed 重建。
## 入树后调用；HerdManager 在 add_child 之前设好 data，_ready 里会自动调这一次。
func apply_data() -> void:
	if data == null:
		return
	if data.species != null:
		species = data.species
	boldness = data.boldness
	greed = data.greed
	restlessness = data.restlessness
	sociability = data.sociability
	follow_distance_scale = data.follow_distance_scale
	is_leader = data.is_leader
	satiety = data.satiety
	if is_leader:
		add_to_group("lead_cow")
	elif is_in_group("lead_cow"):
		remove_from_group("lead_cow")
	var body := get_node_or_null("Body")
	if body != null and data.body_seed != 0:
		body.set("seed", data.body_seed)
		if body.has_method("rebuild"):
			body.rebuild()
	_update_color()

## 把运行时状态写回 data，供结算与存档使用（ARCHITECTURE §4.2）。
func write_back() -> void:
	if data == null:
		return
	data.satiety = satiety
	data.position = global_position
	data.is_leader = is_leader

## 跟随触发距离 = 种类基准 × 个体倍率。
func follow_start_distance() -> float:
	return species.follow_start_distance * follow_distance_scale

func _flat_distance_to(point: Vector3) -> float:
	var d := point - global_position
	d.y = 0.0
	return d.length()
