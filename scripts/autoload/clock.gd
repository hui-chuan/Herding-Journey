## 全局时钟（DECISIONS T17）。唯一的计时来源：昼夜、结算、草场恢复都由它驱动。
## 禁止其他节点自行计时。
extends Node

signal phase_changed(phase: Phase)
signal day_ended(day: int)

enum Phase { DAWN, MORNING, NOON, AFTERNOON, EVENING, NIGHT }

## 一天的实时长度（秒）。D4 暂定 6–10 分钟，先取 8 分钟。
@export var day_length_sec: float = 480.0

## 0.0 = 出栏（清晨），1.0 = 天黑。
var time_of_day: float = 0.0
var day: int = 1
var phase: Phase = Phase.DAWN
var running: bool = true
var time_scale: float = 1.0

## 各时段的结束点（time_of_day）。傍晚段刻意留长一些，它是归栏的支点。
const PHASE_ENDS := {
	Phase.DAWN: 0.10,
	Phase.MORNING: 0.35,
	Phase.NOON: 0.50,
	Phase.AFTERNOON: 0.70,
	Phase.EVENING: 1.0,
}

func _process(delta: float) -> void:
	if not running:
		return
	time_of_day += delta * time_scale / day_length_sec
	if time_of_day >= 1.0:
		time_of_day = 1.0
		running = false
		_set_phase(Phase.NIGHT)
		day_ended.emit(day)
		return
	_set_phase(_phase_for(time_of_day))

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
	_set_phase(Phase.DAWN)

## 傍晚归栏欲望 0–1，供牛群使用。下午起缓慢上升，傍晚陡增。
func homing_urge() -> float:
	if time_of_day < PHASE_ENDS[Phase.NOON]:
		return 0.0
	var t := inverse_lerp(PHASE_ENDS[Phase.NOON], 1.0, time_of_day)
	return t * t
