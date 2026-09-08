## 群体力（BEHAVIOR §5）：分离、聚合、质心、惊吓传染。
## 从 cow.gd 拆出来（ARCHITECTURE §5.1）。拆的理由不是行数，是**调群手感时只碰这一个文件**，
## 而且这里的函数都是"给定一群牛的位置，合力应该指向哪"，可以脱离状态机单独推演。
##
## 全部是静态函数，不持有状态。牛把自己和邻居传进来。
class_name CowForces

## 一次遍历取齐邻居，避免分离/传染/质心各扫一遍牛群（T13：50 头以内朴素实现即可，
## 但同一帧扫三遍仍然是白费）。
static func neighbours_of(cow: Cow) -> Array:
	var out: Array = []
	for node in cow.get_tree().get_nodes_in_group("cows"):
		var other := node as Cow
		if other != null and other != cow:
			out.append(other)
	return out

## 分离：邻居太近就推开。半径远大于牛身长——防重叠是碰撞体的事，
## 这个力的作用是把群铺开到足以覆盖多个草场格（BEHAVIOR §5 的实测定档）。
static func separation(cow: Cow, neighbours: Array, radius: float, push: float) -> Vector3:
	var force := Vector3.ZERO
	for other in neighbours:
		var away: Vector3 = cow.global_position - (other as Cow).global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.01 and d < radius:
			force += away.normalized() * (1.0 - d / radius) * push
	return force

## 聚合：普通牛指向头牛。近处几乎为零，所以牛群是松散的。
static func cohesion_to_leader(cow: Cow, leader: Cow, start: float, strength: float, full_at: float) -> Vector3:
	if leader == null or not is_instance_valid(leader):
		return Vector3.ZERO
	var to_leader := leader.global_position - cow.global_position
	to_leader.y = 0.0
	var d := to_leader.length()
	if d <= start:
		return Vector3.ZERO
	var t := clampf((d - start) / maxf(0.1, full_at - start), 0.0, 1.0)
	return to_leader.normalized() * t * strength * cow.sociability

## 头牛受群体质心的轻微牵引，不会自己走丢。
static func leader_to_centroid(cow: Cow, neighbours: Array, start: float, push: float) -> Vector3:
	var c := centroid(neighbours)
	if c == Vector3.INF:
		return Vector3.ZERO
	var to_c := c - cow.global_position
	to_c.y = 0.0
	if to_c.length() <= start:
		return Vector3.ZERO
	return to_c.normalized() * push

static func centroid(neighbours: Array) -> Vector3:
	if neighbours.is_empty():
		return Vector3.INF
	var sum := Vector3.ZERO
	for other in neighbours:
		sum += (other as Cow).global_position
	return sum / neighbours.size()

## 半径内的邻居，附带其中正在惊跑的头数——传染分级要用（BEHAVIOR §5.2）。
static func neighbours_within(cow: Cow, neighbours: Array, radius: float) -> Dictionary:
	var near: Array = []
	var fleeing := 0
	for other in neighbours:
		var o := other as Cow
		var d := o.global_position - cow.global_position
		d.y = 0.0
		if d.length() <= radius:
			near.append(o)
			if o.state == Cow.State.FLEE:
				fleeing += 1
	return {"near": near, "fleeing": fleeing}
