## 一头牛的全部持久状态（ARCHITECTURE §2.1）。
## 既是"生成一头牛需要的东西"，也是"存档里要写的东西"——两者本来就是同一份数据。
## 性格终身不变，运行时状态每日结算写回。行为参数不在这里，在 SpeciesData 里。
class_name CowData
extends Resource

@export var id: int = 0
## 玩家认得出的名字（"灰额头"）。情感抓手，走失与死亡的文案都用它。
@export var display_name: String = ""
@export var species: SpeciesData

@export_group("性格 (BEHAVIOR §2)")
## 出生时抽定，终身不变，随存档保存。
@export var boldness: float = 1.0
@export var greed: float = 1.0
@export var restlessness: float = 1.0
@export var sociability: float = 1.0
## 跟随触发距离的个体倍率，与合群一起决定"爱不爱走远"。
@export var follow_distance_scale: float = 1.0

@export_group("外观")
@export var body_seed: int = 0

@export_group("运行时状态")
@export var is_leader: bool = false
@export var satiety: float = 0.5
@export var position: Vector3 = Vector3.ZERO
## 连续未归栏的夜数。第二晚起有概率遭狼（DAY_CYCLE §5.2）。
@export var lost_nights: int = 0
@export var alive: bool = true
## 新头牛的能力恢复：挑草场与认路的倍率，接任时 0.5，逐日 +0.15 到 1.0（ARCHITECTURE §3.1）。
@export var leader_skill: float = 1.0

## 按种类与随机种子抽一头新牛的性格与外观（BEHAVIOR §2：截断正态，中心 1.0）。
static func roll(rng: RandomNumberGenerator, new_id: int, sp: SpeciesData, leader: bool) -> CowData:
	var d := CowData.new()
	d.id = new_id
	d.species = sp
	d.is_leader = leader
	# 头牛胆量取上区间：她是稳定器，也是最大风险点（BEHAVIOR §3）。
	d.boldness = rng.randf_range(1.2, 1.5) if leader else rng.randf_range(0.65, 1.35)
	d.greed = rng.randf_range(0.75, 1.25)
	d.restlessness = rng.randf_range(0.75, 1.25)
	d.sociability = rng.randf_range(0.75, 1.25)
	d.follow_distance_scale = 1.15 if leader else rng.randf_range(0.77, 1.15)
	d.body_seed = rng.randi_range(1, 1 << 30)
	d.leader_skill = 1.0
	return d

func to_save() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"boldness": snappedf(boldness, 0.001),
		"greed": snappedf(greed, 0.001),
		"restlessness": snappedf(restlessness, 0.001),
		"sociability": snappedf(sociability, 0.001),
		"follow_distance_scale": snappedf(follow_distance_scale, 0.001),
		"body_seed": body_seed,
		"is_leader": is_leader,
		"satiety": snappedf(satiety, 0.001),
		"position": [snappedf(position.x, 0.01), snappedf(position.y, 0.01), snappedf(position.z, 0.01)],
		"lost_nights": lost_nights,
		"alive": alive,
		"leader_skill": snappedf(leader_skill, 0.001),
	}

static func from_save(d: Dictionary, sp: SpeciesData) -> CowData:
	var c := CowData.new()
	c.species = sp
	c.id = int(d.get("id", 0))
	c.display_name = String(d.get("name", ""))
	c.boldness = float(d.get("boldness", 1.0))
	c.greed = float(d.get("greed", 1.0))
	c.restlessness = float(d.get("restlessness", 1.0))
	c.sociability = float(d.get("sociability", 1.0))
	c.follow_distance_scale = float(d.get("follow_distance_scale", 1.0))
	c.body_seed = int(d.get("body_seed", 0))
	c.is_leader = bool(d.get("is_leader", false))
	c.satiety = float(d.get("satiety", 0.5))
	var p: Array = d.get("position", [0.0, 0.0, 0.0])
	c.position = Vector3(p[0], p[1], p[2]) if p.size() == 3 else Vector3.ZERO
	c.lost_nights = int(d.get("lost_nights", 0))
	c.alive = bool(d.get("alive", true))
	c.leader_skill = float(d.get("leader_skill", 1.0))
	return c
