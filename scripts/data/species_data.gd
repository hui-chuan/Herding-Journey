## 一个牲口种类的全部行为参数（DECISIONS T16、D3）。
## 同种的牛共享一份 .tres：调参改一个文件，全群立刻生效。
## 个体差异不在这里，在 CowData 的性格参数里（BEHAVIOR §2）。
class_name SpeciesData
extends Resource

@export var display_name: String = "牦牛"

@export_group("运动")
@export var wander_speed: float = 1.3
@export var follow_speed: float = 1.7
@export var flee_speed: float = 3.5
@export var turn_speed: float = 4.0
## 平静态下（含被推）的速度上限；惊跑时上限为 flee_speed。
@export var calm_speed_cap: float = 3.0
## 目标速度低于此值视为停下，避免蠕动。
@export var min_move_speed: float = 0.25
@export var accel_calm: float = 3.0
@export var accel_flee: float = 8.0
@export var decel: float = 3.5
@export var wander_min_distance: float = 4.0
@export var wander_max_distance: float = 12.0
## 一次惊跑最多跑这么远，跑到就停下张望。
@export var flee_max_distance: float = 9.0
## 被区域压力"挪开"：小跑背离源点，距离随远近在 [min,max] 之间。
@export var nudge_speed: float = 2.5
@export var nudge_min_distance: float = 1.5
@export var nudge_max_distance: float = 5.0

@export_group("牛群 (BEHAVIOR §5)")
@export var leader_search_radius: float = 40.0
@export var follow_start_distance: float = 13.0
@export var follow_stop_distance: float = 7.0
@export var separation_radius: float = 3.5
@export var separation_push: float = 2.0
## 聚合：离头牛超过 cohesion_start 起有拉力，到 follow_start_distance 时达到 cohesion_push。
@export var cohesion_start: float = 4.0
@export var cohesion_push: float = 0.9
## 头牛受群体质心的轻微牵引，不会自己走丢。
@export var leader_cohesion_push: float = 0.35
## 漫步选点：候选数与"靠近头牛"权重（乘以合群参数）。
@export var wander_samples: int = 6
@export var wander_cohesion_weight: float = 1.0
@export var contagion_radius: float = 8.0
@export var contagion_fear: float = 0.3

@export_group("惊吓 (BEHAVIOR §1.1)")
@export var fear_threshold: float = 0.5
@export var fear_half_life: float = 6.0

@export_group("施压响应 (BEHAVIOR §6)")
## 不吆喝：人走近只是轻微让开，不加惊吓；跑动才有惊吓。
@export var pressure_radius: float = 4.0
@export var pressure_push_walk: float = 0.5
@export var pressure_push_run: float = 2.0
@export var pressure_fear_run: float = 0.25
## 吆喝：以玩家为源点的区域压力，半径内的牛背离玩家挪开，惊吓缓慢累积。
@export var drive_radius: float = 8.0
@export var drive_fear_per_sec: float = 0.08

@export_group("草场 (GRASSLAND §2)")
## 每秒从所在格吃掉的草量。整个多日节奏的调速旋钮，定标见 GRASSLAND §2.1。
@export var graze_rate: float = 0.0025
## 吃掉一单位草量转化的饱腹度。
@export var satiety_per_grass: float = 0.12
