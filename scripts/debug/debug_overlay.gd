## 灰盒调试信息。F12 开关，T 键加速时钟。不是 UI，M3 前不打磨。
extends CanvasLayer

@onready var _label: Label = $Label

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_toggle"):
		visible = not visible
	Clock.time_scale = 20.0 if Input.is_action_pressed("debug_time_fast") else 1.0
	if not visible:
		return
	var lines: PackedStringArray = []
	lines.append("day %d  t=%.2f  %s  homing=%.2f" % [Clock.day, Clock.time_of_day, Clock.Phase.keys()[Clock.phase], Clock.homing_urge()])
	for cow in get_tree().get_nodes_in_group("cows"):
		var p: Node3D = get_tree().get_first_node_in_group("player")
		var d: float = cow.global_position.distance_to(p.global_position) if p else 0.0
		lines.append("%s  %s  fear=%.2f  dist=%.1f" % [cow.name, cow.state_name(), cow.fear, d])
	lines.append("WASD 移动  Shift 跑  Q/E 或右键拖拽转视角  左键甩石  T 快进  F12 隐藏")
	_label.text = "\n".join(lines)
