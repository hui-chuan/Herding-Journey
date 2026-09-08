## 草地：MultiMesh 铺草丛，草量可视化接草场网格（GRASSLAND §6）。
extends MultiMeshInstance3D

@export var count: int = 200000
## 覆盖整张地图（400 m 见方，T20）。原来的 160 m 半径在远视角下露出四角的空地。
@export var half_extent: float = 200.0
@export var seed: int = 3
@export var grass_shader: Shader

var _shader_mat: ShaderMaterial

func _ready() -> void:
	var mesh := _build_tuft()
	var mat := ShaderMaterial.new()
	mat.shader = grass_shader
	mat.set_shader_parameter("map_size", half_extent * 2.0)
	material_override = mat
	_shader_mat = mat
	call_deferred("_bind_grassland")

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in count:
		# 均匀铺满整个正方形地图，不用圆盘——圆盘会在四角留下没有草的空地。
		var px := rng.randf_range(-half_extent, half_extent)
		var pz := rng.randf_range(-half_extent, half_extent)
		var s := rng.randf_range(0.6, 1.3)
		var t := Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(s, s, s)), Vector3(px, 0, pz))
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, Color(rng.randf(), 0, 0))
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## 三片交叉的三角形叶片。
func _build_tuft() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var blade_w := 0.16
	var blade_h := 0.3
	for k in 3:
		var ang := k * PI / 3.0
		var dir := Vector3(cos(ang), 0, sin(ang)) * blade_w * 0.5
		verts.append(-dir); uvs.append(Vector2(0, 0))
		verts.append(dir); uvs.append(Vector2(1, 0))
		verts.append(Vector3(0, blade_h, 0)); uvs.append(Vector2(0.5, 1))
		for j in 3:
			normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 把草场网格的纹理接给 shader。草场每日恢复后会 update 同一张 Image，
## 纹理对象不变，所以只需绑一次。
func _bind_grassland() -> void:
	var gl := get_tree().get_first_node_in_group("grassland") as Grassland
	if gl == null or _shader_mat == null:
		return
	_shader_mat.set_shader_parameter("grassland_tex", gl.texture())
	_shader_mat.set_shader_parameter("map_size", gl.map_size)
