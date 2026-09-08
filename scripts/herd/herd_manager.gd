## 牛群：按 CowData 生成，而不是复制场景里的模板牛（ARCHITECTURE §3）。
## 走失、买牛、读档重建都走同一条路——有数据就能造出牛。
extends Node

const COW_SCENE := preload("res://scenes/cow.tscn")
## 起始 1 头头牛 + 4 头普通牛（DECISIONS D16）。
@export var herd_size: int = 5
## 起始群生成在围栏里：一天从出栏开始（DAY_CYCLE §3.1）。
## 留空则回落到 spawn_center。
@export var spawn_in_pen: bool = true
@export var spawn_center := Vector3(8.0, 1.0, -8.0)
@export var spawn_radius: float = 7.0
@export var seed: int = 21
## 全群共用的种类参数（T16）。
@export var species: SpeciesData

## 场上所有牛的数据，结算与存档从这里取。
var herd: Array[CowData] = []
var _next_id: int = 1

func _ready() -> void:
	add_to_group("herd_manager")
	call_deferred("_start")

func _start() -> void:
	if species == null:
		species = load(Cow.DEFAULT_SPECIES) as SpeciesData
	if herd.is_empty():
		_roll_starting_herd()
	spawn_all()

## 从存档装回牛群（ARCHITECTURE §4）。清掉场上的牛，按数据重建。
func load_from_save(cow_rows: Array) -> void:
	for node in get_tree().get_nodes_in_group("cows"):
		node.queue_free()
	herd.clear()
	for row in cow_rows:
		var d := CowData.from_save(row, species)
		herd.append(d)
		_next_id = maxi(_next_id, d.id + 1)
	# queue_free 要等到帧末才真的移除，先等一帧再生成，否则新旧牛会同时在组里。
	await get_tree().process_frame
	spawn_all()

## 起始群：一头头牛，其余普通牛，散在出栏点周围。
func _roll_starting_herd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var centre := spawn_center
	var radius := spawn_radius
	var pen := get_tree().get_first_node_in_group("pen") as Pen
	if spawn_in_pen and pen != null:
		centre = pen.global_position
		# 留出边距，别把牛塞进栅栏里。
		radius = maxf(2.0, pen.size * 0.5 - 2.0)
	for i in herd_size:
		var d := CowData.roll(rng, _next_id, species, i == 0)
		_next_id += 1
		var angle := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * radius
		d.position = centre + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		d.position.y = 1.0
		herd.append(d)

## 按数据把整群造出来。读档与次日重建走的是同一个入口。
func spawn_all() -> void:
	var leader: Cow = null
	var spawned: Array[Cow] = []
	for d in herd:
		if not d.alive:
			continue
		var cow := spawn(d)
		spawned.append(cow)
		if d.is_leader:
			leader = cow
	# 头牛可能在生成顺序的后面，统一在这里把跟随目标接上。
	if leader != null:
		for cow in spawned:
			if cow != leader:
				cow.leader_path = cow.get_path_to(leader)

func spawn(d: CowData) -> Cow:
	var cow := COW_SCENE.instantiate() as Cow
	# 入树前设好，_ready 才能按这份数据初始化（模板 duplicate 时代踩过的坑）。
	cow.data = d
	cow.species = d.species if d.species != null else species
	cow.name = "Cow%d" % d.id
	add_child(cow)
	cow.global_position = d.position
	cow.rotation.y = randf() * TAU
	return cow

## 结算前把场上每头牛的状态写回数据（ARCHITECTURE §4.2）。
func write_back_all() -> void:
	for node in get_tree().get_nodes_in_group("cows"):
		(node as Cow).write_back()

func living() -> Array[CowData]:
	return herd.filter(func(d: CowData) -> bool: return d.alive)
