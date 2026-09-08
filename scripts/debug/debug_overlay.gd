## 灰盒调试信息。F12 开关，T 键加速时钟。不是 UI，M3 前不打磨。
extends CanvasLayer

@onready var _label: Label = $Label
var _shot_path: String = ""
var _shot_timer: float = 2.0
var _settlement_timer: float = 0.0
var _log_positions: bool = false
var _log_grass: bool = false
var _forced_scale: float = 0.0
var _pin_herd: bool = false
var _test_save: bool = false
var _test_load: bool = false
var _save_timer: float = 3.0
var _grass_timer: float = 0.0
var _log_timer: float = 0.0
var _test_sling: bool = false
var _test_drive: bool = false
var _test_sling_timer: float = 3.0
var _settlement_text: String = ""

func _ready() -> void:
	Clock.day_ended.connect(_on_day_ended)
	Clock.grace_started.connect(_on_grace_started)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time="):
			Clock.time_of_day = float(a.trim_prefix("--time="))
		if a == "--test-drive":
			_test_drive = true
		if a == "--test-sling":
			_test_sling = true
		if a == "--log-positions":
			_log_positions = true
		if a == "--log-grass":
			_log_grass = true
		if a == "--pin-herd":
			_pin_herd = true
		if a == "--test-save":
			_test_save = true
		if a == "--test-load":
			_test_load = true
		if a == "--test-bare":
			call_deferred("_bare_patch")
		if a.begins_with("--zoom="):
			var rig := get_tree().get_first_node_in_group("camera_rig")
			if rig != null:
				rig.set("zoom_level", int(a.trim_prefix("--zoom=")))
				rig.call("_ready")
		if a.begins_with("--player-at="):
			var xz := a.trim_prefix("--player-at=").split(",")
			var p := get_tree().get_first_node_in_group("player") as Node3D
			if p and xz.size() == 2:
				p.global_position = Vector3(float(xz[0]), 1.0, float(xz[1]))
		if a.begins_with("--time-scale="):
			_forced_scale = float(a.trim_prefix("--time-scale="))
		if a.begins_with("--shot-delay="):
			_shot_timer = float(a.trim_prefix("--shot-delay="))
		if a.begins_with("--screenshot="):
			_shot_path = a.trim_prefix("--screenshot=")

func _process(delta: float) -> void:
	if _test_drive:
		# 玩家站在群的南侧 6 m 处持续吆喝并跟着走。
		var p := get_tree().get_first_node_in_group("player") as CharacterBody3D
		var sum := Vector3.ZERO
		var n := 0
		for cow in get_tree().get_nodes_in_group("cows"):
			sum += cow.global_position
			n += 1
		if p and n > 0:
			p.set("driving", true)
			var c := sum / n
			var want := c + Vector3(0, 0, 6.0)
			want.y = p.global_position.y
			p.global_position = p.global_position.lerp(want, 1.5 * delta)
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
				var point: Vector3 = leader.global_position + Vector3(1.0, 0, 0)
				print("TEST sling lands at %s" % point)
				for cow in get_tree().get_nodes_in_group("cows"):
					cow.apply_sling_impact(point, 6.0, 0.7)
	if _pin_herd:
		# 把群按住在出生点附近，单独验证"一片草场被连吃"的局部消耗。
		for cow in get_tree().get_nodes_in_group("cows"):
			var off: Vector3 = cow.global_position - Vector3(8.0, 0.0, -8.0)
			off.y = 0.0
			if off.length() > 20.0:
				cow.global_position = Vector3(8.0, cow.global_position.y, -8.0) + off.normalized() * 20.0
	if _test_save:
		_save_timer -= delta
		if _save_timer <= 0.0:
			_test_save = false
			_run_save_roundtrip()
	if _test_load:
		_save_timer -= delta
		if _save_timer <= 0.0:
			_test_load = false
			var d := SaveIO.load_save()
			print("LOAD result empty=%s (空 = 正确地拒绝了读取)" % d.is_empty())
	if _log_grass:
		_grass_timer -= delta
		if _grass_timer <= 0.0:
			_grass_timer = 5.0
			var gl := get_tree().get_first_node_in_group("grassland") as Grassland
			if gl != null:
				var total := 0.0
				var bare := 0
				var degr := 0.0
				for y in gl.grid_size:
					for x in gl.grid_size:
						var c: Vector3 = gl.cell_center(Vector2i(x, y))
						total += gl.sample(c)
						degr += gl.degradation_at(c)
						if gl.sample(c) < 0.1:
							bare += 1
				var n := gl.grid_size * gl.grid_size
				var sat := 0.0
				var cows := get_tree().get_nodes_in_group("cows")
				for cow in cows:
					sat += cow.satiety
				# 群脚下的局部草量：地图均值看不出消耗，局部才看得出。
				var local := 0.0
				var lmin := 1.0
				var centroid := Vector3.ZERO
				for cow in cows:
					centroid += cow.global_position
				if cows.size() > 0:
					centroid /= cows.size()
				var lc := gl.cell_at(centroid)
				var cnt := 0
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var cc := Vector2i(clampi(lc.x + dx, 0, gl.grid_size - 1), clampi(lc.y + dy, 0, gl.grid_size - 1))
						var v: float = gl.sample(gl.cell_center(cc))
						local += v
						lmin = minf(lmin, v)
						cnt += 1
				var occupied := {}
				for cow in cows:
					occupied[gl.cell_at(cow.global_position)] = true
				var spread := 0.0
				for cow in cows:
					spread = maxf(spread, cow.global_position.distance_to(centroid))
				var lead := get_tree().get_first_node_in_group("lead_cow")
				print("SPREAD cells=%d  max_radius=%.1fm  centroid=(%.0f,%.0f)  leader=%s eff=%.2f" % [occupied.size(), spread, centroid.x, centroid.z, lead.state_name() if lead else "-", lead.graze_efficiency() if lead else 0.0])
				var effsum := 0.0
				for cow in cows:
					effsum += cow.graze_efficiency()
				print("EFF avg_under_cows=%.3f" % (effsum / maxf(1.0, float(cows.size()))))
				print("GRASS day=%d t=%.2f  avg=%.4f  degr=%.4f  bare=%d  局部5x5=%.3f 最低=%.3f  avg_satiety=%.3f" % [
					Clock.day, Clock.time_of_day, total / n, degr / n, bare,
					local / cnt, lmin, sat / maxf(1.0, float(cows.size()))])

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
	# --time-scale 走引擎整体缩放：物理、状态机、时钟、吃草一起加速，牛相对一天的移动才是真的。
	# 只加速 Clock 会让牛"相对一天"几乎不动而草照常被吃，饱腹度必崩（STATUS 踩过的坑）。
	# T 键的 20 倍仍只加速时钟，那是看光色用的，不用来验证平衡。
	if _forced_scale > 0.0:
		Engine.time_scale = _forced_scale
		Clock.time_scale = 1.0
		# 默认每帧最多补 8 个物理步，缩放超过 8 倍时物理就跟不上时钟，牛又"相对一天"变慢了。
		# 放开上限，宁可帧率掉也要物理与时钟同步。
		Engine.max_physics_steps_per_frame = maxi(8, int(ceil(_forced_scale)) * 2)
	else:
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
	var player := get_tree().get_first_node_in_group("player")
	var drive_txt := "  [吆喝]" if player and player.get("driving") == true else ""
	var rig := get_tree().get_first_node_in_group("camera_rig")
	var zoom_txt := "  视角 %s" % rig.call("zoom_name") if rig != null else ""
	var grace_txt := "  宽限 %.0fs" % Clock.grace_left if Clock.in_grace else ""
	lines.append("day %d  t=%.2f  %s  homing=%.2f%s%s" % [Clock.day, Clock.time_of_day, Clock.Phase.keys()[Clock.phase], Clock.homing_urge(), drive_txt, grace_txt + zoom_txt])
	if _settlement_text != "":
		lines.append(_settlement_text)
	for cow in get_tree().get_nodes_in_group("cows"):
		var p: Node3D = get_tree().get_first_node_in_group("player")
		var d: float = cow.global_position.distance_to(p.global_position) if p else 0.0
		var pen := " pen" if cow.has_method("is_in_pen") and cow.is_in_pen() else ""
		lines.append("%s  %s%s  fear=%.2f  饱=%.2f  草=%.2f  dist=%.1f" % [
			cow.name, cow.state_name(), pen, cow.fear, cow.satiety, cow.graze_efficiency(), d])
	lines.append("WASD 移动  Shift 跑  Q/E 或右键拖拽转视角  左键甩石  F 吆喝  Tab 远/近  T 快进  F12 隐藏")
	_label.text = "\n".join(lines)

func _on_grace_started() -> void:
	_settlement_text = "天黑了，还有 %d 秒宽限" % int(Clock.grace_sec)

## 天黑结算：统计存栏、产出、写回数据、存盘（DAY_CYCLE §4，ARCHITECTURE §4.2）。
func _on_day_ended(day: int) -> void:
	var hm := get_tree().get_first_node_in_group("herd_manager")
	var gl := get_tree().get_first_node_in_group("grassland") as Grassland
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if hm == null:
		return
	hm.write_back_all()

	var penned: Array = []
	var lost: Array = []
	for node in get_tree().get_nodes_in_group("cows"):
		var cow := node as Cow
		if cow.is_in_pen():
			cow.data.lost_nights = 0
			penned.append(cow.data)
		else:
			# 连续两晚未归栏，第二晚起有概率遭狼（D5）。第一晚绝不死。
			cow.data.lost_nights += 1
			lost.append(cow.data)

	var summary := GameState.settle(penned)
	var died: Array = []
	for d in lost:
		var c := d as CowData
		if c.lost_nights >= 2 and randf() < 0.25:
			c.alive = false
			GameState.death_marks.append(c.position)
			died.append(c)

	SaveIO.save(GameState.collect(hm.herd, gl, player))

	var parts: PackedStringArray = ["day %d  存栏 %d/%d  奶 +%d  毛 +%d" % [
		day, penned.size(), penned.size() + lost.size(), summary["milk"], summary["wool"]]]
	for c in lost:
		if (c as CowData).alive:
			parts.append("%s 没有回来" % _cow_label(c))
	for c in died:
		parts.append("%s 死了" % _cow_label(c))
	_settlement_text = "  ·  ".join(parts)
	print("SETTLE %s" % _settlement_text)
	_settlement_timer = 6.0

func _cow_label(d: CowData) -> String:
	return d.display_name if d.display_name != "" else "Cow%d" % d.id

## 验证真正的落盘往返（ARCHITECTURE §4）：写盘 → 改状态 → 读盘 → 比对。
func _run_save_roundtrip() -> void:
	var hm := get_tree().get_first_node_in_group("herd_manager")
	var gl := get_tree().get_first_node_in_group("grassland") as Grassland
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if hm == null or gl == null:
		print("SAVE test: herd_manager or grassland missing")
		return

	hm.write_back_all()
	GameState.cash = 42
	GameState.inventory["milk"] = 7
	var payload := GameState.collect(hm.herd, gl, player)
	if not SaveIO.save(payload):
		print("SAVE test: write failed")
		return

	# 破坏当前状态，确认读回来的是盘上的那份而不是内存里的残留。
	var before_first: Dictionary = hm.herd[0].to_save()
	var before_grass: float = gl.sample(Vector3.ZERO)
	GameState.cash = 0
	GameState.inventory["milk"] = 0
	gl.consume(Vector3.ZERO, 1.0)

	var back := SaveIO.load_save()
	if back.is_empty():
		print("SAVE test: load failed")
		return
	GameState.apply(back)
	gl.from_save(back["grassland"])
	hm.load_from_save(back["cows"])
	await get_tree().process_frame

	var after_first: Dictionary = hm.herd[0].to_save()
	var cows_ok: bool = after_first == before_first and hm.herd.size() == back["cows"].size()
	var grass_ok: bool = absf(gl.sample(Vector3.ZERO) - before_grass) < 0.002
	var state_ok: bool = GameState.cash == 42 and GameState.inventory["milk"] == 7
	var spawned := get_tree().get_nodes_in_group("cows").size()
	print("SAVE roundtrip cows=%s grass=%s state=%s spawned=%d day=%d" % [
		cows_ok, grass_ok, state_ok, spawned, Clock.day])
