## 牧人的低多边形外观。藏袍、帽子、脸朝 -Z。
extends Node3D

const SKIN := Color(0.75, 0.55, 0.42)
const ROBE := Color(0.45, 0.12, 0.1)
const ROBE_DARK := Color(0.3, 0.08, 0.07)
const HAT := Color(0.2, 0.15, 0.12)
const BOOT := Color(0.15, 0.1, 0.08)

func _ready() -> void:
	# 腿与靴
	for sx in [-0.12, 0.12]:
		_box(Vector3(0.18, 0.55, 0.18), Vector3(sx, 0.3, 0), ROBE_DARK)
		_box(Vector3(0.2, 0.12, 0.26), Vector3(sx, 0.06, -0.02), BOOT)
	# 袍子（上宽下窄）
	_box(Vector3(0.5, 0.6, 0.32), Vector3(0, 0.9, 0), ROBE)
	_box(Vector3(0.52, 0.06, 0.34), Vector3(0, 0.75, 0), Color(0.8, 0.65, 0.2))
	# 手臂
	for sx in [-0.32, 0.32]:
		_box(Vector3(0.14, 0.5, 0.16), Vector3(sx, 0.92, 0), ROBE)
		_box(Vector3(0.12, 0.1, 0.12), Vector3(sx, 0.62, 0), SKIN)
	# 头与帽
	_box(Vector3(0.28, 0.3, 0.28), Vector3(0, 1.4, 0), SKIN)
	_cyl(0.28, 0.28, 0.12, Vector3(0, 1.6, 0), HAT)
	_cyl(0.42, 0.42, 0.03, Vector3(0, 1.55, 0), HAT)
	# 鼻子（朝向标记）
	_box(Vector3(0.06, 0.06, 0.06), Vector3(0, 1.38, -0.16), SKIN.darkened(0.15))

func _box(size: Vector3, pos: Vector3, color: Color) -> void:
	var m := BoxMesh.new()
	m.size = size
	_add(m, pos, color)

func _cyl(top: float, bottom: float, h: float, pos: Vector3, color: Color) -> void:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 8
	_add(m, pos, color)

func _add(mesh: Mesh, pos: Vector3, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
