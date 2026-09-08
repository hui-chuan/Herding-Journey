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
@export var wander_max_distance: float = 15.0
## 一次惊跑最多跑这么远，跑到就停下张望。
@export var flee_max_distance: float = 9.0
## 被区域压力"挪开"：小跑背离源点，距离随远近在 [min,max] 之间。
@export var nudge_speed: float = 2.5
@export var nudge_min_distance: float = 1.5
@export var nudge_max_distance: float = 5.0

@export_group("牛群 (BEHAVIOR §5)")
@export var leader_search_radius: float = 40.0
## 跟随触发：离头牛超过此距离无条件跟；头牛在移动时超过 follow_stop_distance 就跟。
@export var follow_start_distance: float = 22.0
@export var follow_stop_distance: float = 9.0
## 群有两档（BEHAVIOR §5.1）：吃草时散开以摊薄草场压力，移动时收拢成一团跟着走。
## 分离半径远大于牛身长 2.2 m，防重叠由物理碰撞体负责；这个力只负责铺开。
@export var separation_radius: float = 8.0
@export var separation_radius_moving: float = 4.0
@export var separation_push: float = 2.0
## 聚合：离头牛超过 cohesion_start 起有拉力，到 follow_start_distance 时达到 cohesion_push。
@export var cohesion_start: float = 10.0
@export var cohesion_push: float = 0.8
## 移动档的聚合力倍率。
@export var cohesion_moving_scale: float = 2.0
## 头牛受群体质心的轻微牵引，不会自己走丢。
@export var leader_cohesion_push: float = 0.35
## 漫步选点：候选数与"靠近头牛"权重（乘以合群参数）。
@export var wander_samples: int = 6
@export var wander_cohesion_weight: float = 1.0
@export var contagion_radius: float = 8.0
## 连锁：半径内两头以上同时惊跑时邻居获得的惊吓（BEHAVIOR §5.2）。
@export var contagion_fear: float = 0.3
## 单头惊跑只让邻居抬头警觉，给这么点惊吓，通常不过阈值。
@export var contagion_fear_single: float = 0.12

@export_group("惊吓 (BEHAVIOR §1.1)")
## 牦牛比家牛敏感，阈值整体偏低（BEHAVIOR §9）。
@export var fear_threshold: float = 0.45
@export var fear_half_life: float = 6.0
## 撤压奖励（BEHAVIOR §6.5）：这一帧没有任何压力源作用时，半衰期乘以这个倍率。
@export var release_decay_scale: float = 0.5

@export_group("施压响应 (BEHAVIOR §6)")
## 平衡点（BEHAVIOR §6.0）：压力源在肩后时牛向前走，向前方向里掺入这么多"背离源点"的侧向分量。
@export var balance_side_bias: float = 0.35
## 逃离区随情绪变大：有效半径 = 半径 × (1 + fear × 此系数)。
@export var flight_zone_fear_scale: float = 1.0
## 不吆喝：人走近只是轻微让开，不加惊吓；跑动才有惊吓。
@export var pressure_radius: float = 4.0
@export var pressure_push_walk: float = 0.5
@export var pressure_push_run: float = 2.0
@export var pressure_fear_run: float = 0.25
## 吆喝：以玩家为源点的区域压力，半径内的牛背离玩家挪开，惊吓缓慢累积。
@export var drive_radius: float = 8.0
@export var drive_fear_per_sec: float = 0.08

@export_group("草场 (GRASSLAND §2)")
## 吃草漂移（BEHAVIOR §1.3）：吃草时全群沿头牛的漂移方向缓慢前移，像一片慢慢漂的云。
## 0.12 m/s × 一天约 1000 s 吃草 ≈ 100 m，加上 15 m 宽的锋面，一天扫过 20–30 格，
## 这是 GRASSLAND §2.1 "5 头牛一天吃 25 格"定标的来源。收拢的群不漂移就会把脚下几格吃秃饿到 0。
@export var graze_drift_speed: float = 0.12
## 与 Grassland.efficiency_floor 对应：吃到这个效率就认为不划算，该挪窝了。
@export var graze_efficiency_floor: float = 0.15
## 每秒从所在格吃掉的草量。整个多日节奏的调速旋钮，定标见 GRASSLAND §2.1。
@export var graze_rate: float = 0.0015
## 吃掉一单位草量转化的饱腹度。
@export var satiety_per_grass: float = 0.12
