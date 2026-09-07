## M2 灰盒牛群生成器。
## 复用场景里手工搭好的 Cow 作为模板，运行时生成起始牛群。
extends Node

@export var cow_template_path: NodePath
@export var herd_size: int = 5
@export var spawn_center := Vector3(8.0, 1.0, -8.0)
@export var spawn_radius: float = 7.0
@export var pen_center := Vector3(-30.0, 0.0, 30.0)
@export var seed: int = 21
## 全群共用的种类参数（T16）。留空则各头牛自己回落到 yak.tres。
@export var species: SpeciesData

func _ready() -> void:
	call_deferred("_spawn_herd")

func _spawn_herd() -> void:
	var template := get_node_or_null(cow_template_path) as Cow
	if template == null:
		push_warning("HerdManager needs a Cow template.")
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_configure_cow(template, 0, rng, true)
	template.add_to_group("lead_cow")
	template.refresh_marker()
	var leader := template

	for i in range(1, herd_size):
		var cow := template.duplicate() as Cow
		cow.name = "Cow%d" % (i + 1)
		# 先配置再入树，否则 _ready 会按模板（头牛）的参数初始化。
		_configure_cow(cow, i, rng, false)
		get_parent().add_child(cow)
		cow.leader_path = cow.get_path_to(leader)

func _configure_cow(cow: Cow, index: int, rng: RandomNumberGenerator, leader: bool) -> void:
	var angle := rng.randf() * TAU
	var dist := sqrt(rng.randf()) * spawn_radius
	cow.position = spawn_center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	cow.position.y = 1.0
	cow.rotation.y = rng.randf() * TAU
	cow.is_leader = leader
	cow.pen_center = pen_center
	if species != null:
		cow.species = species
	cow.boldness = rng.randf_range(1.2, 1.5) if leader else rng.randf_range(0.65, 1.35)
	cow.greed = rng.randf_range(0.75, 1.25)
	cow.restlessness = rng.randf_range(0.75, 1.25)
	cow.sociability = rng.randf_range(0.75, 1.25)
	# 跟随触发距离改用倍率（种类基准 13 m）：头牛略宽松，普通牛 0.77–1.15 倍。
	cow.follow_distance_scale = 1.15 if leader else rng.randf_range(0.77, 1.15)
	var body := cow.get_node_or_null("Body")
	if body != null:
		body.seed = seed + index * 17
		if body.has_method("rebuild"):
			body.rebuild()
