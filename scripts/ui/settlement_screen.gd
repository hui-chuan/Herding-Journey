## 结算界面（DAY_CYCLE §4）。全游戏第一个 UI，它定下后面所有 UI 的调性：
## 安静、居中、字少、不庆祝。商店（M5）照这个调子做。
##
## 刻意不做的事：不列清单、不算分、没有"+N"飘字、没有数字滚动动画、
## 没有音效奖励、没有"完成"字样。全员归栏时不写"全部归栏"——**没有消息就是好消息**。
extends Control

signal slept()

@export var fade_in_sec: float = 2.0
@export var text_delay_sec: float = 0.6

@onready var _dim: ColorRect = $Dim
@onready var _day_label: Label = $Center/Rows/Day
@onready var _stock: Label = $Center/Rows/Stock
@onready var _milk: Label = $Center/Rows/Milk
@onready var _wool: Label = $Center/Rows/Wool
@onready var _notices: VBoxContainer = $Center/Rows/Notices
@onready var _sleep: Button = $Center/Rows/Sleep

func _ready() -> void:
	add_to_group("settlement_screen")
	hide()
	_sleep.pressed.connect(_on_sleep)

## summary 由 GameState.settle() 给出；notices 是走失与死亡的文案（已含牛名）。
func show_settlement(summary: Dictionary, total: int, notices: PackedStringArray) -> void:
	_day_label.text = tr("settlement_day").format({"day": summary.get("day", 1)})
	_stock.text = "%s   %d / %d" % [tr("settlement_stock"), summary.get("penned", 0), total]
	_milk.text = "%s   %d" % [tr("settlement_milk"), summary.get("milk", 0)]
	_wool.text = "%s   %d" % [tr("settlement_wool"), summary.get("wool", 0)]

	for child in _notices.get_children():
		child.queue_free()
	for line in notices:
		var l := Label.new()
		l.text = line
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62))
		_notices.add_child(l)

	_sleep.text = tr("settlement_sleep")
	show()
	# 画面缓慢淡到深蓝，文字随后淡入。不要动画数字。
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, fade_in_sec)
	tween.tween_callback(func() -> void: _sleep.grab_focus())

## 供无头验证调用，等价于按下"睡觉"。
func sleep_now() -> void:
	_on_sleep()

func _on_sleep() -> void:
	hide()
	slept.emit()

## 结算界面开着时吞掉游戏内的输入，避免误甩石头。
func _unhandled_input(event: InputEvent) -> void:
	if visible and (event is InputEventMouseButton or event is InputEventKey):
		get_viewport().set_input_as_handled()
