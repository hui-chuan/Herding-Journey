## 常驻根节点（ARCHITECTURE §1）。只做一件事：持有 World 与 UI，并且能把 World 整个换掉。
##
## 次日重开、读档、将来的转场都是同一件事——**卸载 world，按数据重建**。
## 逐个节点写 reset() 会随着系统变多不断漏字段；重建则天然正确（§1.1）。
class_name Main
extends Node

const WORLD_SCENE := preload("res://scenes/world.tscn")

@onready var _slot: Node = $WorldSlot

func _ready() -> void:
	add_to_group("main")
	if _slot.get_child_count() == 0:
		build_world()

## 造一个新的 world。herd 非空时按它重建牛群（读档、次日），否则用起始群。
func build_world(herd: Array = []) -> Node:
	var world := WORLD_SCENE.instantiate()
	_slot.add_child(world)
	if not herd.is_empty():
		var hm := world.get_tree().get_first_node_in_group("herd_manager")
		if hm != null:
			hm.herd.assign(herd)
	return world

## 扔掉当前 world。free 是立即的，queue_free 要等帧末——重建时必须先腾空，
## 否则新旧两份牛会同时在 "cows" 组里（HerdManager.load_from_save 踩过这个坑）。
func clear_world() -> void:
	for child in _slot.get_children():
		_slot.remove_child(child)
		child.queue_free()

## 换一个 world：常用于读档。调用方负责先把 GameState / 草场装好。
func reload_world(herd: Array = []) -> Node:
	clear_world()
	await get_tree().process_frame
	return build_world(herd)
