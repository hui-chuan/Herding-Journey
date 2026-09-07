## 灰盒参照物：散落石块，带碰撞。固定随机种子，每次打开位置一致。
extends Node3D

@export var rock_count: int = 60
@export var scatter_radius: float = 120.0
@export var keep_clear_center := Vector3(-30, 0, 30)
@export var keep_clear_radius: float = 22.0
@export var seed: int = 7

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.52, 0.48, 0.42)
	rock_mat.roughness = 1.0
	var placed := 0
	while placed < rock_count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * scatter_radius
		var pos := Vector3(cos(a) * r, 0.0, sin(a) * r)
		# 不在畜栏附近和出生点附近放石头。
		if pos.distance_to(keep_clear_center) < keep_clear_radius or pos.length() < 6.0:
			continue
		var s := rng.randf_range(0.6, 2.5)
		var size := Vector3(s * rng.randf_range(0.8, 1.6), s * 0.7, s)
		_add_rock(size, rock_mat, pos + Vector3(0, size.y * 0.4, 0), rng.randf() * TAU)
		placed += 1

func _add_rock(size: Vector3, mat: Material, pos: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = yaw
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
