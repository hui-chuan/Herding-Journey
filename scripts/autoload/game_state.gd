## 当前存档的内存镜像（ARCHITECTURE §1）。
## 谁需要"这一局的状态"就问它，不要各自持有一份。
extends Node

signal day_settled(summary: Dictionary)

var cash: int = 0
var inventory := {"milk": 0, "wool": 0}
## 死亡现场的位置，永久留在地图上（DAY_CYCLE §5.2）。
var death_marks: Array[Vector3] = []

func reset() -> void:
	cash = 0
	inventory = {"milk": 0, "wool": 0}
	death_marks.clear()

## 收集整局状态。牛与草场的数据由各自的持有者提供，这里只做汇总。
func collect(herd: Array, grassland: Grassland, player: Node3D) -> Dictionary:
	var cows: Array = []
	for d in herd:
		cows.append((d as CowData).to_save())
	var data := {
		"day": Clock.day,
		"time_of_day": snappedf(Clock.time_of_day, 0.0001),
		"cash": cash,
		"inventory": inventory.duplicate(),
		"cows": cows,
		"death_marks": death_marks.map(func(v: Vector3) -> Array:
			return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]),
	}
	if grassland != null:
		data["grassland"] = grassland.to_save()
	if player != null:
		data["player"] = {"position": [
			snappedf(player.global_position.x, 0.01),
			snappedf(player.global_position.y, 0.01),
			snappedf(player.global_position.z, 0.01)]}
	return data

## 把存档里的全局部分装回来。牛与草场由各自的持有者自己读。
func apply(data: Dictionary) -> void:
	Clock.day = int(data.get("day", 1))
	Clock.time_of_day = float(data.get("time_of_day", 0.0))
	Clock.running = true
	Clock.in_grace = false
	cash = int(data.get("cash", 0))
	var inv: Dictionary = data.get("inventory", {})
	inventory = {"milk": int(inv.get("milk", 0)), "wool": int(inv.get("wool", 0))}
	death_marks.clear()
	for m in data.get("death_marks", []):
		if m is Array and m.size() == 3:
			death_marks.append(Vector3(m[0], m[1], m[2]))

## 结算产出（DAY_CYCLE §4.3）。饱腹度挂钩产奶：草不好 → 牛吃不饱 → 产奶少，
## 这是把草场系统接到经济上的那一根线。
func settle(penned: Array) -> Dictionary:
	var milk := 0
	for d in penned:
		if (d as CowData).satiety > 0.5:
			milk += 1
	milk = int(milk * 0.5)
	var wool := 0
	if Clock.day % 3 == 0:
		wool = int(penned.size() * 0.5)
	inventory["milk"] += milk
	inventory["wool"] += wool
	var summary := {"day": Clock.day, "penned": penned.size(), "milk": milk, "wool": wool}
	day_settled.emit(summary)
	return summary
