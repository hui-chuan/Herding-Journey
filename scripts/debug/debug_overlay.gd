## 灰盒调试信息。F12 开关，T 键加速时钟。不是 UI，M3 前不打磨。
extends CanvasLayer

@onready var _label: Label = $Label
var _shot_path: String = ""
var _shot_timer: float = 2.0
var _settlement_timer: float = 0.0
var _log_positions: bool = false
var _log_timer: float = 0.0
var _test_sling: bool = false
var _test_sling_timer: float = 3.0
var _settlement_text: String = ""

func _ready() -> void:
	Clock.day_ended.connect(_on_day_ended)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time="):
			Clock.time_of_day = float(a.trim_prefix("--time="))
		if a == "--test-sling":
			_test_sling = true
		if a == "--log-positions":
			_log_positions = true
		if a.begins_with("--shot-delay="):
			_shot_timer = float(a.trim_prefix("--shot-delay="))
		if a.begins_with("--screenshot="):
			_shot_path = a.trim_prefix("--screenshot=")

func _process(delta: float) -> void:
	if _test_sling:
		_test_sling_timer -= delta
		if _test_sling_timer <= 0.0:
			_test_sling = false
			var leader: Node3D = null
			for c in get_tree().get_nodes_in_group("cows"):
				if not c.is_leader:
					leader = c
					break
			if leader:
				var point: Vector3 = leader.global_position + Vector3(0.8, 0, 0)
				print("TEST sling lands at %s" % point)
				for cow in get_tree().get_nodes_in_group("cows"):
					cow.apply_sling_impact(point, 4.0, 4.0, 0.7)
	if _log_positions:
		_log_timer -= delta
		if _log_timer <= 0.0:
			_log_timer = 1.0
			var parts: PackedStringArray = []
			for cow in get_tree().get_nodes_in_group("cows"):
				var gp: Vector3 = cow.global_position
				parts.append("%s(%s %.1f,%.1f,%.1f v=%.2f floor=%s)" % [cow.name, cow.state_name(), gp.x, gp.y, gp.z, cow.velocity.length(), cow.is_on_floor()])
			print("POS t=%.2f  %s" % [Clock.time_of_day, " ".join(parts)])
	if _shot_path != "":
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			_shot_path = ""
			get_tree().quit()
	if Input.is_action_just_pressed("debug_toggle"):
		visible = not visible
	Clock.time_scale = 20.0 if Input.is_action_pressed("debug_time_fast") else 1.0
	if _settlement_timer > 0.0:
		_settlement_timer -= delta
		if _settlement_timer <= 0.0:
			Clock.start_next_day()
			_settlement_text = ""
	for cow in get_tree().get_nodes_in_group("cows"):
		cow.get_node("StateMarker").visible = visible
	if not visible:
		return
	var lines: PackedStringArray = []
	lines.append("day %d  t=%.2f  %s  homing=%.2f" % [Clock.day, Clock.time_of_day, Clock.Phase.keys()[Clock.phase], Clock.homing_urge()])
	if _settlement_text != "":
		lines.append(_settlement_text)
	for cow in get_tree().get_nodes_in_group("cows"):
		var p: Node3D = get_tree().get_first_node_in_group("player")
		var d: float = cow.global_position.distance_to(p.global_position) if p else 0.0
		var pen := " pen" if cow.has_method("is_in_pen") and cow.is_in_pen() else ""
		lines.append("%s  %s%s  fear=%.2f  dist=%.1f" % [cow.name, cow.state_name(), pen, cow.fear, d])
	lines.append("WASD 移动  Shift 跑  Q/E 或右键拖拽转视角  左键甩石  Tab 远/近  T 快进  F12 隐藏")
	_label.text = "\n".join(lines)

func _on_day_ended(day: int) -> void:
	var total := 0
	var penned := 0
	for cow in get_tree().get_nodes_in_group("cows"):
		total += 1
		if cow.has_method("is_in_pen") and cow.is_in_pen():
			penned += 1
	var milk := penned * 2
	var wool := penned
	_settlement_text = "nightfall day %d  returned %d/%d  milk +%d  wool +%d  next dawn soon" % [day, penned, total, milk, wool]
	_settlement_timer = 6.0
