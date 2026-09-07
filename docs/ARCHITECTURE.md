# 工程结构 ARCHITECTURE.md

场景层级、数据流、Resource 与存档的组织方式。
对应 DECISIONS T15、T16、T17。

更新：2026-09-07 · 状态：设计定稿，M1/M2 现状与目标结构的差异见 §6

---

## 0. 一条原则

**状态在数据里，表现在场景里。**

存档只存状态（T15），场景可以随时被扔掉重建。一头牛的性格、饱腹度、位置是数据；它的网格、材质、状态标记是表现。这条线划清楚了，走失、买牛、读档、次日重开这四件事就都是同一件事：**按数据造节点**。

M1/M2 的灰盒违反了这条（牛是场景里手搭的节点，`herd_manager` 靠 `duplicate()` 复制模板）。M3 的第一件结构性工作就是把它掰回来。

---

## 1. 场景层级

```
Main (main.tscn)                    ← 启动场景，常驻
├── World (world.tscn)              ← 可整个卸载重建
│   ├── Terrain                     ← 地形 mesh + 碰撞
│   ├── Grassland                   ← 草场网格数据 (GRASSLAND §7)
│   ├── GrassField                  ← MultiMesh 草丛，读 Grassland 的纹理
│   ├── Mountains / Props           ← 远山、玛尼堆等
│   ├── Pen                         ← 围栏 + 自动门，已实现 (DAY_CYCLE §2.2)
│   ├── Herd                        ← 牛的父节点，运行时填充
│   │   └── Cow × N   (cow.tscn)
│   ├── Player (player.tscn)
│   │   └── CameraRig
│   └── DayLight                    ← 太阳 + 环境，读 Clock
└── UI (ui.tscn)                    ← CanvasLayer，常驻
    ├── SettlementScreen            ← 结算 (DAY_CYCLE §4)
    ├── PauseScreen
    └── DebugOverlay                ← 仅 debug 构建
```

Autoload（`project.godot`）：

| Autoload | 职责 | 状态 |
| --- | --- | --- |
| `Clock` | 唯一计时源（T17）。昼夜、结算、草场恢复 | 已有 |
| `GameState` | 当前存档的内存镜像：日期、现金、库存、牛的数据数组 | 新增 |
| `SaveIO` | JSON 读写、`save_version` 迁移 | 新增 |

**Autoload 只放这三个。** 草场、围栏、牛群都属于 world，不是全局的——把它们做成 autoload 会让"卸载 world 重建"变得不可能。需要跨节点找它们时用 group（`"grassland"`、`"pen"`、`"player"`、`"lead_cow"`）。

### 1.1 为什么要拆 World

M4 的"睡觉 → 次日"需要一次干净的重置：草场恢复、牛按数据重新摆位、走失的牛投放到新位置、时钟归零。

两种做法：逐个节点写 `reset()`，或者整个卸载重建。**选后者**——`reset()` 会随着系统增多而不断漏掉某个字段，重建则天然正确。代价是加载一次的时间，400 m 的灰盒场景可以忽略。

---

## 2. Resource 驱动（T16）

### 2.1 CowData

一头牛的**全部持久状态**。既是配置也是存档单元。

```gdscript
class_name CowData extends Resource

@export var id: int                    # 唯一，永不复用
@export var display_name: String       # "灰额头"。玩家的情感抓手
@export var species: SpeciesData       # 指向种类定义，见 §2.2

@export_group("性格 (BEHAVIOR §2)")    # 出生时抽定，终身不变
@export var boldness: float
@export var greed: float
@export var restlessness: float
@export var sociability: float

@export_group("外观")
@export var body_seed: int             # 驱动花色与体型微差
@export var patch_color: Color

@export_group("运行时状态")            # 每日结算时写回
@export var is_leader: bool
@export var satiety: float
@export var position: Vector3
@export var lost_nights: int           # 连续未归栏的夜数 (DAY_CYCLE §5.2)
@export var alive: bool
```

一处分歧要注意：**性格是配置，状态是存档**，但两者放在同一个 Resource 里。理由是它们的生命周期一致（一头牛从出生到死亡），拆成两个类只会带来同步负担。`@export_group` 做视觉区分足够。

### 2.2 SpeciesData

D3：当前只有牦牛，但群体行为参数按种类独立配置，为后续加羊留口。

```gdscript
class_name SpeciesData extends Resource
# 移动
@export var wander_speed: float
@export var follow_speed: float
@export var flee_speed: float
@export var calm_speed_cap: float
@export var accel_calm / accel_flee / decel: float
# 群体力 (BEHAVIOR §5)
@export var separation_radius / separation_push: float
@export var cohesion_start / cohesion_push: float
@export var follow_start_distance / follow_stop_distance: float
@export var contagion_radius / contagion_fear: float
# 惊吓
@export var fear_threshold / fear_half_life: float
# 施压响应 (BEHAVIOR §6.1)
@export var pressure_radius / drive_radius / ...: float
# 草场 (GRASSLAND §2)
@export var graze_rate / satiety_per_grass: float
```

`cow.gd` 现在的 40 多个 `@export` 全部搬到这里，`res://data/species/yak.tres` 一份。

**这是 M3 最有价值的一次重构**：调参从"改脚本、改场景里每头牛的属性"变成"改一个 .tres，全群立刻生效"。BEHAVIOR §7 那张待调参数清单有二十来项，没有这一步，M3 的调参会非常痛苦。

### 2.3 其他 Resource

后续按需加，都放 `res://data/`：`ProductData`（奶、毛）、`VehicleData`（马、摩托）、`HouseLevelData`。M5 之前不用建。

---

## 3. 牛的实例化

`cow.tscn` 预制体，`HerdManager` 按 `CowData` 造：

```gdscript
func spawn(data: CowData) -> Cow:
    var cow := COW_SCENE.instantiate() as Cow
    cow.data = data                    # 入树前设好，避免 _ready 用错值
    cow.species = data.species
    herd_root.add_child(cow)
    cow.global_position = data.position
    return cow
```

M2 现有的 `duplicate()` 模板做法要去掉。它的问题：模板牛本身是头牛，复制出来的牛需要事后"改回普通牛"（`herd_manager.gd` 里 `_configure_cow` 就在做这件事），属性来源混乱，而且没法从存档重建。

### 3.1 头牛的确定

不在 `CowData` 里硬写，而是每天开始时由 `HerdManager` 选出：

```
存活的牛中 is_leader 者 → 保持
若无（头牛死了/走失了一夜）→ sociability 最高者接任，
    其 leader_skill = 0.5，每日 +0.15 直到 1.0
```

`leader_skill` 乘在 GRASSLAND §3 的挑草场评分与 DAY_CYCLE §3.2 的归栏偏置上。新头牛初期挑草场眼光差、回家路线绕，逐日恢复——这正是 BEHAVIOR §3"失去头牛"想要的（能力减半，逐日恢复）。

---

## 4. 存档（T15）

### 4.1 格式

`user://save_1.json`，UTF-8，非压缩（可读便于调试）。

```json
{
  "save_version": 1,
  "day": 4,
  "time_of_day": 0.0,
  "cash": 0,
  "inventory": { "milk": 3, "wool": 1 },
  "player": { "position": [12.0, 0.0, -8.0] },
  "cows": [ { "id": 1, "name": "灰额头", "boldness": 1.31, ... } ],
  "grassland": { "size": 40, "grass": [...], "degradation": [...] },
  "landmarks": { "death_marks": [[120.0, 0.0, -35.0]] }
}
```

`time_of_day` 存在存档里，是 DAY_CYCLE §1.3 可中断性的实现基础：**任何时候退出都能接着玩。**

### 4.2 时机

| 时机 | 说明 |
| --- | --- |
| 结算后（按下"睡觉"） | 主存档点。一天的正式落点 |
| 退出游戏时 | 中途存档，含 `time_of_day` |
| 玛尼石堆（P1） | 手动存档点 |

**不做自动定期存档。** 它会和"真实的失去"（D5/D10）打架——玩家如果知道每分钟都在存，就不会有"牛没了"的分量。

### 4.3 版本迁移

`save_version` 从 1 开始。读档时若版本低于当前，走一串 `_migrate_v1_to_v2()` 之类的函数逐级升。M4 之前不会真的用到，但字段和分支现在就留好，**因为存档格式一旦发出去就改不动了**。

版本不匹配且无迁移路径时：明确报错，不静默丢弃玩家的存档。

---

## 5. 代码组织

### 5.1 cow.gd 要拆

现在 489 行，接入草场和归栏之后会到 700+。按职责拆三块：

| 文件 | 职责 | 约 |
| --- | --- | --- |
| `cow.gd` | 状态机、状态时长、饱腹度、对外接口 | 200 |
| `cow_forces.gd` | 分离 / 聚合 / 对齐 / 区域压力（吆喝与乌尔朵同一机制，D11），返回一个合力向量 | 150 |
| `cow_body.gd` | 外观（已有 `yak_body.gd`） | 70 |

`cow_forces.gd` 做成无状态的静态函数集或一个轻 helper 对象，输入是（自己、邻居数组、玩家、场），输出是 `Vector3` 合力。**把力的计算和状态机分开的好处**：调群体手感时只碰一个文件，而且这个文件可以单独写测试（给定几头牛的位置，合力方向应当是什么）。

### 5.2 目录

```
scripts/
  autoload/    clock.gd  game_state.gd  save_io.gd
  herd/        cow.gd  cow_forces.gd  yak_body.gd  herd_manager.gd
  world/       grassland.gd  grass_field.gd  pen.gd  terrain.gd  day_light.gd  mountains.gd
  player/      player.gd  player_body.gd  camera_rig.gd  sling.gd
  ui/          settlement_screen.gd  pause_screen.gd
  debug/       debug_overlay.gd
data/
  species/     yak.tres
  cows/        （运行时生成，不入库）
scenes/
  main.tscn  world.tscn  ui.tscn
  cow.tscn  player.tscn
```

`m1_sandbox.tscn` 在 world.tscn 建好后删除，不保留。

---

## 6. 从现状到目标

M1/M2 的现状与上面的差异，按依赖顺序：

| # | 工作 | 阻塞了什么 |
| --- | --- | --- |
| 1 | `Grassland` 数据层 + 接 `Clock.day_ended` | 头牛挑草场、走失投放、产奶 |
| 2 | 牛接草场（消耗、效率、选点、挑草场） | 多日节奏 |
| 3 | ~~`SpeciesData` 抽出 `cow.gd` 的 @export~~ **已完成** | M3 全部调参 |
| 4 | `cow.tscn` 预制体 + `CowData` + `HerdManager` 重写 | 存档、走失、买牛 |
| 5 | `cow.gd` 拆分 | 后续可维护性（可与 3/4 合并做） |
| 6 | 出栏/归栏判定收进 `Pen` + 60 s 宽限（围栏本体已有） | 结算 |
| 7 | `main/world/ui` 三场景拆分 | 次日重建 |
| 8 | 结算 UI + `tr()` + 藏文 TextServer 验证（T18） | M4 |
| 9 | `SaveIO` + `GameState` | M4 出口 |

1–2 是 GRASSLAND 的实现，3–5 是本文的重构，6–7 是 DAY_CYCLE 的实现，8–9 是 M4。

**建议顺序上把 3 提前到 1 之前**：先有 `SpeciesData`，后面所有调参都受益，而它是纯机械的搬运，不会引入 bug。
