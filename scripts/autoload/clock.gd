## 全局时钟（DECISIONS T17）。唯一的计时来源：昼夜、结算、草场恢复都由它驱动。
## 禁止其他节点自行计时。
extends Node

signal phase_changed(phase: Phase)
## time_of_day 到 1.0，进入宽限期。天继续黑，但还能把最后一头牛推进围栏。
signal grace_started()
## 宽限期结束，可以结算了。
signal day_ended(day: int)

enum Phase { DAWN, MORNING, NOON, AFTERNOON, EVENING, NIGHT }

## 一天的实时长度（秒）。D4 已定 30 分钟。
@export var day_length_sec: float = 1800.0
## 天黑宽限（DECISIONS D17）。硬截止会让傍晚变成抢时间，与调性冲突。
@export var grace_sec: float = 60.0

## 0.0 = 出栏（清晨），1.0 = 天黑。
var time_of_day: float = 0.0
var day: int = 1
var phase: Phase = Phase.DAWN
var running: bool = true
var time_scale: float = 1.0
var in_grace: bool = false
var grace_left: float = 0.0

## 各时段的结束点（time_of_day）。傍晚段刻意留长一些，它是归栏的支点。
## 时段边界（DAY_CYCLE §1.1）。傍晚占全天 28%：它是唯一有明确目标、
## 也唯一会真的失败的一段，必须长到足够找回两三头掉队的牛。
## 正午的 4.2 分钟空白是故意的，不要填。
const PHASE_ENDS := {
	Phase.DAWN: 0.08,
	Phase.MORNING: 0.33,
	Phase.NOON: 0.47,
	Phase.AFTERNOON: 0.72,
	Phase.EVENING: 1.0,
}

func _process(delta: float) -> void:
	if in_grace:
		_tick_grace(delta)
		return
	if not running:
		return
	time_of_day += delta * time_scale / day_length_sec
	if time_of_day >= 1.0:
		time_of_day = 1.0
		_set_phase(Phase.NIGHT)
		in_grace = true
		grace_left = grace_sec
		grace_started.emit()
		return
	_set_phase(_phase_for(time_of_day))

## 宽限期：全部归栏就提前结束，不必等满 60 s。
func _tick_grace(delta: float) -> void:
	grace_left -= delta * time_scale
	if grace_left <= 0.0 or _all_cows_penned():
		in_grace = false
		running = false
		day_ended.emit(day)

func _all_cows_penned() -> bool:
	var cows := get_tree().get_nodes_in_group("cows")
	if cows.is_empty():
		return false
	for c in cows:
		if not c.has_method("is_in_pen") or not c.is_in_pen():
			return false
	return true

func _phase_for(t: float) -> Phase:
	for p in PHASE_ENDS:
		if t < PHASE_ENDS[p]:
			return p
	return Phase.EVENING

func _set_phase(p: Phase) -> void:
	if p != phase:
		phase = p
		phase_changed.emit(p)

## 结算后调用：进入下一天。
func start_next_day() -> void:
	day += 1
	time_of_day = 0.0
	running = true
	in_grace = false
	grace_left = 0.0
	_set_phase(Phase.DAWN)

## 傍晚归栏欲望 0–1，供牛群使用。下午起缓慢上升，傍晚陡增。
## 归栏欲望 0–1（DAY_CYCLE §3.2）。下午起离开 0，但 t² 让它前期几乎不可察觉；
## 0.95 之后满值。用线性会让整个下午都在往回走，玩家感觉一天下午都在收工。
func homing_urge() -> float:
	if time_of_day < PHASE_ENDS[Phase.NOON]:
		return 0.0
	var t := inverse_lerp(PHASE_ENDS[Phase.NOON], 0.95, time_of_day)
	return clampf(t * t, 0.0, 1.0)
