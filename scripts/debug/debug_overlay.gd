## 灰盒调试信息。F12 开关，T 键加速时钟。不是 UI，M3 前不打磨。
extends CanvasLayer

@onready var _label: Label = $Label
var _shot_path: String = ""
var _shot_timer: float = 2.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time="):
			Clock.time_of_day = float(a.trim_prefix("--time="))
		if a.begins_with("--screenshot="):
			_shot_path = a.trim_prefix("--screenshot=")

func _process(delta: float) -> void:
	if _shot_path != "":
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			_shot_path = ""
			get_tree().quit()
	if Input.is_action_just_pressed("debug_toggle"):
		visible = not visible
	Clock.time_scale = 20.0 if Input.is_action_pressed("debug_time_fast") else 1.0
	for cow in get_tree().get_nodes_in_group("cows"):
		cow.get_node("StateMarker").visible = visible
	if not visible:
		return
	var lines: PackedStringArray = []
	lines.append("day %d  t=%.2f  %s  homing=%.2f" % [Clock.day, Clock.time_of_day, Clock.Phase.keys()[Clock.phase], Clock.homing_urge()])
	for cow in get_tree().get_nodes_in_group("cows"):
		var p: Node3D = get_tree().get_first_node_in_group("player")
		var d: float = cow.global_position.distance_to(p.global_position) if p else 0.0
		lines.append("%s  %s  fear=%.2f  dist=%.1f" % [cow.name, cow.state_name(), cow.fear, d])
	lines.append("WASD 移动  Shift 跑  Q/E 或右键拖拽转视角  左键甩石  Tab 远/近  T 快进  F12 隐藏")
	_label.text = "\n".join(lines)
