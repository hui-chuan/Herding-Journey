## 牛群：按 CowData 生成，而不是复制场景里的模板牛（ARCHITECTURE §3）。
## 走失、买牛、读档重建都走同一条路——有数据就能造出牛。
extends Node

const COW_SCENE := preload("res://scenes/cow.tscn")
## 起始 1 头头牛 + 4 头普通牛（DECISIONS D16）。
@export var herd_size: int = 5
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

## 起始群：一头头牛，其余普通牛，散在出栏点周围。
func _roll_starting_herd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in herd_size:
		var d := CowData.roll(rng, _next_id, species, i == 0)
		_next_id += 1
		var angle := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * spawn_radius
		d.position = spawn_center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
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
