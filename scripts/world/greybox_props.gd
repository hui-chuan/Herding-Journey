## 灰盒参照物：散落石块 + 一圈围栏。固定随机种子，每次打开位置一致。
extends Node3D

@export var rock_count: int = 60
@export var scatter_radius: float = 120.0
@export var pen_center := Vector3(-30, 0, 30)
@export var pen_size: float = 20.0
@export var seed: int = 7

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.52, 0.48, 0.42)
	for i in rock_count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * scatter_radius
		var s := rng.randf_range(0.6, 2.5)
		var box := BoxMesh.new()
		box.size = Vector3(s * rng.randf_range(0.8, 1.6), s * 0.7, s)
		_add_mesh(box, rock_mat, Vector3(cos(a) * r, box.size.y * 0.4, sin(a) * r), rng.randf() * TAU)

	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.5, 0.35, 0.2)
	var post := BoxMesh.new()
	post.size = Vector3(0.2, 1.2, 0.2)
	var half := pen_size * 0.5
	var step := 2.0
	var n := int(pen_size / step)
	for i in n + 1:
		var t := -half + i * step
		_add_mesh(post, post_mat, pen_center + Vector3(t, 0.6, -half), 0.0)
		_add_mesh(post, post_mat, pen_center + Vector3(t, 0.6, half), 0.0)
		_add_mesh(post, post_mat, pen_center + Vector3(-half, 0.6, t), 0.0)
		_add_mesh(post, post_mat, pen_center + Vector3(half, 0.6, t), 0.0)

func _add_mesh(mesh: Mesh, mat: Material, pos: Vector3, yaw: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	add_child(mi)
