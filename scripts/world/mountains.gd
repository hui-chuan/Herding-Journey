## 远山：一圈低多边形锥体，给尺度感和方向感。
extends Node3D

@export var count: int = 18
@export var ring_radius: float = 420.0
@export var seed: int = 11

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in count:
		var a := (float(i) + rng.randf_range(-0.3, 0.3)) / count * TAU
		var r := ring_radius + rng.randf_range(-60, 60)
		var h := rng.randf_range(90, 220)
		var w := rng.randf_range(120, 260)
		var m := CylinderMesh.new()
		m.top_radius = 0.0
		m.bottom_radius = w
		m.height = h
		m.radial_segments = rng.randi_range(4, 6)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.55, 0.65).lerp(Color(0.85, 0.87, 0.9), clampf((h - 150.0) / 80.0, 0.0, 1.0))
		mat.roughness = 1.0
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mat
		mi.position = Vector3(cos(a) * r, h * 0.5 - 5.0, sin(a) * r)
		mi.rotation.y = rng.randf() * TAU
		add_child(mi)
