## 草场网格（DECISIONS D12/T21，规格见 docs/GRASSLAND.md）。
## 40×40 格、格边长 10 m，存在一张 Image 里（R = 草量，G = 退化），
## 这样同一份数据既能被牛查询，也能直接当纹理喂给草的 shader。
##
## 这个系统不指挥牛，只提供一个"场"：牛的吃草时长、漫步选点、头牛挑草场
## 各自读它，"牛群自己离开吃秃的地方"是这几条权重涌现出来的。
class_name Grassland
extends Node3D

## 地图边长（T20）。世界坐标范围 [-half, +half]。
@export var map_size: float = 400.0
@export var cell_size: float = 10.0
@export var map_seed: int = 7

@export_group("消耗 (GRASSLAND §2)")
## 吃草效率的拐点：草量低于此值效率开始下降。
@export var efficiency_knee: float = 0.3
## 效率地板。不留地板牛会在秃地里饿死锁（GRASSLAND §2.2）。
@export var efficiency_floor: float = 0.15

@export_group("恢复 (GRASSLAND §4)")
@export var regrow_rate: float = 0.35
## 无条件的种子项。逻辑斯蒂在 g=0 时增量恒为 0，没有它秃地永不恢复。
@export var seed_growth: float = 0.02
## 草量低于此值视为吃秃，当天累积退化。
@export var bare_threshold: float = 0.1
@export var degradation_gain: float = 0.15
@export var degradation_heal: float = 0.02

@export_group("初始分布 (GRASSLAND §5)")
@export var base_frequency: float = 0.012
@export var detail_frequency: float = 0.05
## 围栏周围的踩踏：半径内草量打折，鼓励把群带远。
@export var pen_bare_radius: float = 30.0
@export var pen_bare_factor: float = 0.6

var grid_size: int
var _img: Image
var _tex: ImageTexture
var _half: float

func _ready() -> void:
	add_to_group("grassland")
	grid_size = int(round(map_size / cell_size))
	_half = map_size * 0.5
	_generate()
	if not Clock.day_ended.is_connected(_on_day_ended):
		Clock.day_ended.connect(_on_day_ended)

func _on_day_ended(_day: int) -> void:
	daily_regrow()

## 世界坐标 → 格坐标，越界的钳到边缘。
func cell_at(world_pos: Vector3) -> Vector2i:
	var x := int(floor((world_pos.x + _half) / cell_size))
	var z := int(floor((world_pos.z + _half) / cell_size))
	return Vector2i(clampi(x, 0, grid_size - 1), clampi(z, 0, grid_size - 1))

func cell_center(cell: Vector2i) -> Vector3:
	return Vector3(
		(cell.x + 0.5) * cell_size - _half,
		0.0,
		(cell.y + 0.5) * cell_size - _half)

## 草量 0–1。
func sample(world_pos: Vector3) -> float:
	var c := cell_at(world_pos)
	return _img.get_pixel(c.x, c.y).r

func degradation_at(world_pos: Vector3) -> float:
	var c := cell_at(world_pos)
	return _img.get_pixel(c.x, c.y).g

## 吃草效率曲线（GRASSLAND §2.2）。草越少吃得越慢，但不归零。
func efficiency(world_pos: Vector3) -> float:
	return clampf(sample(world_pos) / efficiency_knee, efficiency_floor, 1.0)

## 从所在格吃掉一些草，返回实际吃到的量（格里不够就只给剩下的）。
func consume(world_pos: Vector3, amount: float) -> float:
	var c := cell_at(world_pos)
	var px := _img.get_pixel(c.x, c.y)
	var eaten := minf(amount, px.r)
	if eaten <= 0.0:
		return 0.0
	px.r -= eaten
	_img.set_pixel(c.x, c.y, px)
	return eaten

## 头牛挑草场（GRASSLAND §3）：环形采样，按草量 × 距离衰减 × 方向惯性 × 归栏偏置评分。
## bias_dir 为归栏方向（傍晚指向围栏），bias_weight 为归栏欲望 0–1。
## last_dir 是上次选中的方向，用来保持漂移的连贯，传 ZERO 表示没有惯性。
func best_cell_near(origin: Vector3, min_r: float, max_r: float, samples: int,
		last_dir: Vector3, bias_dir: Vector3, bias_weight: float) -> Vector3:
	var best := origin
	var best_score := -INF
	for i in samples:
		var angle := randf() * TAU
		var r := sqrt(randf()) * (max_r - min_r) + min_r
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var cand := origin + dir * r
		if absf(cand.x) > _half or absf(cand.z) > _half:
			continue
		var score := sample(cand)
		# 近处优先，避免每次都冲向地图边缘的最优格。
		score *= 1.0 - 0.5 * (r / max_r)
		# 方向惯性：群的漂移是一条连贯的弧线，不是布朗运动。
		if last_dir.length_squared() > 0.01:
			score *= 0.7 + 0.3 * (dir.dot(last_dir) * 0.5 + 0.5)
		# 归栏偏置：傍晚起，朝围栏的候选格分更高。
		if bias_weight > 0.0 and bias_dir.length_squared() > 0.01:
			var toward := dir.dot(bias_dir) * 0.5 + 0.5
			score *= lerpf(1.0, toward, clampf(bias_weight, 0.0, 1.0))
		if score > best_score:
			best_score = score
			best = cand
	return best

## 每日恢复（GRASSLAND §4）。由 Clock.day_ended 驱动，不自行计时（T17）。
func daily_regrow() -> void:
	for y in grid_size:
		for x in grid_size:
			var px := _img.get_pixel(x, y)
			var g := px.r
			var d := px.g
			g += regrow_rate * g * (1.0 - g) * (1.0 - d) + seed_growth * (1.0 - d)
			if px.r < bare_threshold:
				d = minf(1.0, d + degradation_gain)
			else:
				d = maxf(0.0, d - degradation_heal)
			_img.set_pixel(x, y, Color(clampf(g, 0.0, 1.0), d, 0.0, 1.0))
	_update_texture()

func texture() -> ImageTexture:
	return _tex

## 两层噪声：低频决定"好坡/差坡"，高频给格间差异。
## 均匀 1.0 会让头牛的挑草场退化成纯距离项，群就不漂移了（GRASSLAND §5）。
func _generate() -> void:
	_img = Image.create_empty(grid_size, grid_size, false, Image.FORMAT_RGF)
	var base := FastNoiseLite.new()
	base.seed = map_seed
	base.frequency = base_frequency
	var detail := FastNoiseLite.new()
	detail.seed = map_seed + 1
	detail.frequency = detail_frequency

	var pen := get_tree().get_first_node_in_group("pen") as Node3D
	for y in grid_size:
		for x in grid_size:
			var p := cell_center(Vector2i(x, y))
			var g := 0.55 + 0.35 * base.get_noise_2d(p.x, p.z) + 0.12 * detail.get_noise_2d(p.x, p.z)
			if pen != null:
				var d := Vector2(p.x - pen.global_position.x, p.z - pen.global_position.z).length()
				if d < pen_bare_radius:
					g *= lerpf(pen_bare_factor, 1.0, d / pen_bare_radius)
			_img.set_pixel(x, y, Color(clampf(g, 0.05, 1.0), 0.0, 0.0, 1.0))
	_update_texture()

func _update_texture() -> void:
	if _tex == null:
		_tex = ImageTexture.create_from_image(_img)
	else:
		_tex.update(_img)

## 存档（ARCHITECTURE §4.1）。按行展开成两个数组，保留 3 位小数。
func to_save() -> Dictionary:
	var grass := PackedFloat32Array()
	var degr := PackedFloat32Array()
	for y in grid_size:
		for x in grid_size:
			var px := _img.get_pixel(x, y)
			grass.append(snappedf(px.r, 0.001))
			degr.append(snappedf(px.g, 0.001))
	return {"size": grid_size, "grass": grass, "degradation": degr}

func from_save(d: Dictionary) -> void:
	var n: int = d.get("size", grid_size)
	if n != grid_size:
		push_warning("Grassland size mismatch: save %d vs current %d" % [n, grid_size])
		return
	var grass: Array = d.get("grass", [])
	var degr: Array = d.get("degradation", [])
	if grass.size() < grid_size * grid_size:
		push_warning("Grassland save data incomplete.")
		return
	for y in grid_size:
		for x in grid_size:
			var i := y * grid_size + x
			_img.set_pixel(x, y, Color(grass[i], degr[i] if i < degr.size() else 0.0, 0.0, 1.0))
	_update_texture()
