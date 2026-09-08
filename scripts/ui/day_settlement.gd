## 一天的结算流程（DAY_CYCLE §4–§5）：统计存栏、算产出、判走失与死亡、存档、开界面。
## 逻辑从调试层搬到这里——调试层只该显示，不该是游戏流程的载体。
extends Node

## 走失的牛连续第二晚起有概率遭狼（DECISIONS D5）。第一晚绝不死：
## 死亡必须是玩家的不作为造成的，而不是运气，所以要给一整天的挽回窗口。
@export var wolf_chance: float = 0.25
@export var screen_path: NodePath

var _screen: Node

func _ready() -> void:
	add_to_group("day_settlement")
	_screen = get_node_or_null(screen_path)
	if _screen != null and _screen.has_signal("slept"):
		_screen.slept.connect(_on_slept)
	Clock.day_ended.connect(_on_day_ended)

func _on_day_ended(day: int) -> void:
	var hm := get_tree().get_first_node_in_group("herd_manager")
	if hm == null:
		return
	var gl := get_tree().get_first_node_in_group("grassland") as Grassland
	var player := get_tree().get_first_node_in_group("player") as Node3D
	hm.write_back_all()

	var penned: Array = []
	var lost: Array = []
	for node in get_tree().get_nodes_in_group("cows"):
		var cow := node as Cow
		if cow.is_in_pen():
			cow.data.lost_nights = 0
			penned.append(cow.data)
		else:
			cow.data.lost_nights += 1
			lost.append(cow.data)

	var summary := GameState.settle(penned)
	var died: Array = []
	for d in lost:
		var c := d as CowData
		if c.lost_nights >= 2 and randf() < wolf_chance:
			c.alive = false
			GameState.death_marks.append(c.position)
			died.append(c)

	SaveIO.save(GameState.collect(hm.herd, gl, player))

	# 走失与死亡按名字点出来，不写"1 头牲畜走失"——名字是玩家产生情感的唯一抓手。
	var notices := PackedStringArray()
	for c in lost:
		if (c as CowData).alive:
			notices.append(tr("settlement_lost").format({"name": cow_label(c)}))
	for c in died:
		notices.append(tr("settlement_died").format({"name": cow_label(c)}))

	print("SETTLE day %d  penned %d/%d  milk %d  wool %d%s" % [
		day, penned.size(), penned.size() + lost.size(),
		summary["milk"], summary["wool"],
		("  " + " ".join(notices)) if notices.size() > 0 else ""])

	if _screen != null and _screen.has_method("show_settlement"):
		_screen.show_settlement(summary, penned.size() + lost.size(), notices)
	else:
		_on_slept()

## 按下"睡觉"：进入次日。草场恢复由 Clock.day_ended 已经驱动过了（T17）。
func _on_slept() -> void:
	var hm := get_tree().get_first_node_in_group("herd_manager")
	if hm != null and hm.has_method("begin_new_day"):
		hm.begin_new_day()
	Clock.start_next_day()

static func cow_label(d: CowData) -> String:
	return d.display_name if d.display_name != "" else "Cow%d" % d.id
