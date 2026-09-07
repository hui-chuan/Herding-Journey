## 草地：MultiMesh 铺草丛。草量可视化（P1）以后从这里接草场网格。
extends MultiMeshInstance3D

@export var count: int = 120000
@export var radius: float = 160.0
@export var seed: int = 3
@export var grass_shader: Shader

func _ready() -> void:
	var mesh := _build_tuft()
	var mat := ShaderMaterial.new()
	mat.shader = grass_shader
	material_override = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var s := rng.randf_range(0.6, 1.3)
		var t := Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(s, s, s)), Vector3(cos(a) * r, 0, sin(a) * r))
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
