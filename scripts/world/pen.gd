## 畜栏：四边围栏（带碰撞），东侧一道门。门前有牛或人时自动打开，走空后关上。
## 归栏判定也在这里（DAY_CYCLE §2.2）：只有一处知道"什么算在栏里"。
class_name Pen
extends Node3D

@export var size: float = 20.0
@export var gate_width: float = 5.0
@export var post_spacing: float = 2.5
@export var rail_height: float = 1.1
@export var open_radius: float = 10.0
@export var close_delay: float = 2.0
## 门扇向外贴着栅栏放平（175°）。开 110° 时门扇与栅栏夹出一个 V 形口袋，从后面赶来的牛正好被楔进去。
@export var open_angle_deg: float = 175.0
## 门外的集结点离门多远：牛先走到这里，再直线穿门，不会斜着撞栅栏。
@export var approach_distance: float = 7.0
@export var swing_speed: float = 2.0

const WOOD := Color(0.5, 0.35, 0.2)
const WOOD_DARK := Color(0.38, 0.26, 0.15)

var _gate_pivot: Node3D
var _gate_open: bool = false
var _gate_t: float = 0.0
var _close_timer: float = 0.0
var _gate_center: Vector3
var _mat_post: StandardMaterial3D
var _mat_rail: StandardMaterial3D

func _ready() -> void:
	add_to_group("pen")
	_mat_post = StandardMaterial3D.new()
	_mat_post.albedo_color = WOOD_DARK
	_mat_post.roughness = 1.0
	_mat_rail = StandardMaterial3D.new()
	_mat_rail.albedo_color = WOOD
	_mat_rail.roughness = 1.0
	var h := size * 0.5
	# 北、南、西三边整段；东边留门。
	_build_side(Vector3(-h, 0, -h), Vector3(h, 0, -h))
	_build_side(Vector3(-h, 0, h), Vector3(h, 0, h))
	_build_side(Vector3(-h, 0, -h), Vector3(-h, 0, h))
	var g := gate_width * 0.5
	_build_side(Vector3(h, 0, -h), Vector3(h, 0, -g))
	_build_side(Vector3(h, 0, g), Vector3(h, 0, h))
	_build_gate(Vector3(h, 0, -g), Vector3(h, 0, g))
	_gate_center = global_position + Vector3(h, 0, 0)

func _process(delta: float) -> void:
	var someone_near := false
	for node in get_tree().get_nodes_in_group("cows"):
		if _flat_dist((node as Node3D).global_position, _gate_center) <= open_radius:
			someone_near = true
			break
	if not someone_near:
		var p := get_tree().get_first_node_in_group("player") as Node3D
		if p and _flat_dist(p.global_position, _gate_center) <= open_radius:
			someone_near = true
	if someone_near:
		_gate_open = true
		_close_timer = close_delay
	else:
		_close_timer -= delta
		if _close_timer <= 0.0:
			_gate_open = false
	_gate_t = move_toward(_gate_t, 1.0 if _gate_open else 0.0, swing_speed * delta)
	_gate_pivot.rotation.y = deg_to_rad(open_angle_deg) * ease(_gate_t, 0.6)

func is_gate_open() -> bool:
	return _gate_t > 0.5

func gate_center() -> Vector3:
	return _gate_center

## 门外的集结点（门正对面 approach_distance 处）。
func approach_point() -> Vector3:
	return _gate_center + Vector3(approach_distance, 0.0, 0.0)

## 从 from 出发要回栏，此刻该朝哪走（DAY_CYCLE §3）：
## 栏内 → 栏中心；栏外且不在门前走廊里 → 集结点；在走廊里 → 直穿门到栏中心。
## 直接瞄准栏中心会斜着撞在栅栏上卡住。
func home_target(from: Vector3) -> Vector3:
	if contains(from):
		return global_position
	var rel := from - _gate_center
	var g := gate_width * 0.5
	var in_corridor := rel.x >= -0.5 and rel.x <= approach_distance + 3.0 and absf(rel.z) <= g * 0.6
	if in_corridor:
		return global_position
	return approach_point()

## 归栏判定（DAY_CYCLE §3.4）。半边长按围栏尺寸算，围栏挪位置或改大小都不用改别处。
func contains(world_pos: Vector3) -> bool:
	var flat := world_pos - global_position
	flat.y = 0.0
	var h := size * 0.5
	return absf(flat.x) <= h and absf(flat.z) <= h

func cows_inside() -> Array:
	return get_tree().get_nodes_in_group("cows").filter(
		func(c: Node3D) -> bool: return contains(c.global_position))

## 一段直线围栏：等距立柱 + 两根横杆 + 一块整体碰撞板。
func _build_side(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var n := maxi(1, int(round(length / post_spacing)))
	for i in n + 1:
		_add_box(self, Vector3(0.18, rail_height + 0.2, 0.18), a.lerp(b, float(i) / n) + Vector3(0, (rail_height + 0.2) * 0.5, 0), 0.0, _mat_post)
	var mid := (a + b) * 0.5
	var yaw := atan2(-(b - a).x, -(b - a).z) + PI * 0.5
	for y in [rail_height * 0.45, rail_height * 0.95]:
		_add_box(self, Vector3(length, 0.1, 0.08), mid + Vector3(0, y, 0), yaw, _mat_rail)
	_add_collider(self, Vector3(length, rail_height + 0.2, 0.25), mid + Vector3(0, (rail_height + 0.2) * 0.5, 0), yaw)

## 门：绕 a 端立柱旋转的一段围栏，带碰撞，随枢轴一起转。
func _build_gate(a: Vector3, b: Vector3) -> void:
	_gate_pivot = Node3D.new()
	_gate_pivot.position = a
	add_child(_gate_pivot)
	var length := a.distance_to(b)
	var local_b := b - a
	var yaw := atan2(-local_b.x, -local_b.z) + PI * 0.5
	var mid := local_b * 0.5
	_add_box(_gate_pivot, Vector3(0.18, rail_height + 0.2, 0.18), Vector3(0, (rail_height + 0.2) * 0.5, 0), 0.0, _mat_post)
	for y in [rail_height * 0.3, rail_height * 0.65, rail_height * 1.0]:
		_add_box(_gate_pivot, Vector3(length, 0.1, 0.08), mid + Vector3(0, y, 0), yaw, _mat_rail)
	_add_box(_gate_pivot, Vector3(0.12, rail_height * 0.9, 0.1), local_b * 0.85 + Vector3(0, rail_height * 0.62, 0), yaw, _mat_rail)
	_add_collider(_gate_pivot, Vector3(length, rail_height + 0.2, 0.2), mid + Vector3(0, (rail_height + 0.2) * 0.5, 0), yaw)

func _add_box(parent: Node3D, box: Vector3, pos: Vector3, yaw: float, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	parent.add_child(mi)

func _add_collider(parent: Node3D, box: Vector3, pos: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = yaw
	var shape := BoxShape3D.new()
	shape.size = box
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)

func _flat_dist(a: Vector3, b: Vector3) -> float:
	var d := a - b
	d.y = 0.0
	return d.length()
