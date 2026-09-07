## 用 Clock 驱动太阳角度与颜色。M1 只求能看出时间在走，M3 后再专门调光色。
extends DirectionalLight3D

@export var dawn_color := Color(0.85, 0.9, 1.0)
@export var noon_color := Color(1.0, 0.98, 0.92)
@export var evening_color := Color(1.0, 0.7, 0.4)
@export var night_color := Color(0.25, 0.3, 0.5)

func _process(_delta: float) -> void:
	var t: float = Clock.time_of_day
	# 太阳从东边 10° 升起，正午 70°，傍晚落到西边 5°。
	var elevation: float = lerpf(10.0, 70.0, sin(t * PI))
	var azimuth: float = lerpf(-80.0, 80.0, t)
	rotation_degrees = Vector3(-elevation, azimuth, 0.0)
	if t < 0.15:
		light_color = dawn_color.lerp(noon_color, t / 0.15)
	elif t < 0.65:
		light_color = noon_color
	elif t < 0.9:
		light_color = noon_color.lerp(evening_color, (t - 0.65) / 0.25)
	else:
		light_color = evening_color.lerp(night_color, (t - 0.9) / 0.1)
	light_energy = lerpf(0.3, 1.2, sin(t * PI))
