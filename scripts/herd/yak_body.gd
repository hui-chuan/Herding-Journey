## 牦牛的低多边形外观，用原生几何体拼。花色由种子决定，同一头牛每次一样。
extends Node3D

@export var seed: int = 0

const DARK := Color(0.12, 0.09, 0.07)
const BROWN := Color(0.28, 0.18, 0.12)
const WHITE := Color(0.85, 0.82, 0.75)
const HORN := Color(0.75, 0.7, 0.6)

func _ready() -> void:
	rebuild()

func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else hash(get_parent().name)
	var coat: Color = DARK.lerp(BROWN, rng.randf() * 0.6)
	var white_face: bool = rng.randf() < 0.35
	var white_tail: bool = rng.randf() < 0.5
	var white_belly: bool = rng.randf() < 0.3
	var body_scale: float = rng.randf_range(0.92, 1.08)

	# 躯干（长毛裙摆更宽更低）
	_box(Vector3(0.9, 0.8, 1.9), Vector3(0, 1.0, 0.05), coat)
	_box(Vector3(1.05, 0.45, 1.7), Vector3(0, 0.6, 0.05), WHITE if white_belly else coat)
	# 肩峰
	_box(Vector3(0.7, 0.35, 0.6), Vector3(0, 1.5, -0.45), coat)
	# 头
	_box(Vector3(0.45, 0.45, 0.6), Vector3(0, 1.15, -1.25), WHITE if white_face else coat)
	_box(Vector3(0.3, 0.25, 0.25), Vector3(0, 0.98, -1.6), coat.lightened(0.15))
	# 角
	for sx in [-1.0, 1.0]:
		var horn := _cyl(0.05, 0.03, 0.45, Vector3(sx * 0.32, 1.4, -1.25), HORN)
		horn.rotation = Vector3(0, 0, sx * deg_to_rad(-60))
	# 腿
	for sx in [-1.0, 1.0]:
		for sz in [-0.65, 0.65]:
			_box(Vector3(0.22, 0.75, 0.22), Vector3(sx * 0.32, 0.37, sz), coat)
	# 尾巴
	_box(Vector3(0.12, 0.5, 0.12), Vector3(0, 0.95, 1.05), coat)
	_box(Vector3(0.2, 0.3, 0.2), Vector3(0, 0.6, 1.05), WHITE if white_tail else coat)

	scale = Vector3.ONE * body_scale

func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _add(m, pos, color)

func _cyl(top: float, bottom: float, h: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 6
	return _add(m, pos, color)

func _add(mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi
