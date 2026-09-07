# STATUS.md — 代码现状

更新：2026-09-07（设计文档补齐，M3 待办见文末）。记录"代码里现在有什么"，供接手与复盘。设计意图看 PRD 与 DECISIONS，行为规格看 Herd_BEHAVIOR。

仓库：https://github.com/hui-chuan/Herding-Journey · 引擎：Godot 4.7.2 stable

## 进度

| 里程碑 | 状态 | 说明 |
| --- | --- | --- |
| M1 手感 | 灰盒完成 | 玩家、相机、乌尔朵、单牛躲避 |
| M2 群体 | 灰盒完成，调参中 | 状态机、性格、头牛、群体力、传染、吆喝、区域压力 |
| M3 可玩 | 部分 | 时钟与光照有；畜栏与门有；归栏判定与简易结算有（调试层内）；草场数据层已做，压力定标待解（GRASSLAND §2.4） |
| M4 循环 | 未开始 | 走失、存档 |

## 目录

```
project.godot                 Forward+ / Jolt / InputMap / 自动加载 Clock
scenes/m1_sandbox.tscn        唯一场景：地面、光、草、远山、石块、畜栏、草场、玩家、牛群生成器、调试层（牛不再在场景里）
shaders/grid_ground.gdshader  10 m 大格 + 1 m 小格的灰盒地面（大格 = 草场格尺寸）
shaders/grass.gdshader        草丛：随风摆动，按实例变色，法线统一朝上
scripts/autoload/clock.gd     全局时钟：一天 480 s（**待改 1800 s**，D4），五时段（**待按 DAY_CYCLE §1.1 重划**），homing_urge()
scripts/world/day_light.gd    太阳角度与色温随时钟变化
scripts/world/grassland.gd    草场网格 40×40（Image RGF：R 草量 G 退化）：查询、消耗、挑草场、每日恢复、存档
scripts/world/grass_field.gd  MultiMesh 铺 12 万丛草
scripts/world/mountains.gd    一圈低多边形远山
scripts/world/greybox_props.gd 散落石块（StaticBody3D，带碰撞）
scripts/world/pen.gd          畜栏：四边围栏带碰撞，东侧自动门
scripts/player/player.gd      步行 2 / 奔跑 5 m/s；driving 吆喝开关
scripts/player/player_body.gd 牧人外观（原生几何体拼）
scripts/player/camera_rig.gd  固定 40° 俯角，水平可转，Tab 远近 + 静止 3 s 自动远观
scripts/player/sling.gd       乌尔朵：鼠标瞄准落点，4–40 m，抛物线 1 s，冷却 2 s
scripts/data/species_data.gd  种类行为参数 Resource（T16）：运动、群体力、惊吓、施压响应、草场
scripts/data/cow_data.gd      一头牛的持久数据（性格、外观种子、饱腹、位置、走失夜数、存活）+ 存档往返
data/species/yak.tres         牦牛的一份参数，全群共用；调参只改这个文件
scripts/herd/cow.gd           牛：状态机、性格、惊吓、群体力、区域压力、头牛意图（参数读 species）
scripts/herd/yak_body.gd      牦牛外观，花色按种子
scripts/herd/herd_manager.gd  按 CowData 生成牛群（5 头，1 头头牛）；spawn/spawn_all/write_back_all
scenes/cow.tscn               牛的预制体：碰撞体 + 外观 + 状态小球
scripts/debug/debug_overlay.gd 调试层与命令行参数
```

## 物理层

| 层 | 名称 | 用途 |
| --- | --- | --- |
| 1 | ground | 地面、石块、围栏 |
| 2 | player | 玩家（掩码 1+4） |
| 3 (值 4) | livestock | 牛（掩码 1+2+4） |

人、牛、石块、围栏互为实体，不穿模。

## 牛的状态机（cow.gd）

GRAZE / WANDER / REST / FOLLOW / FLEE / ALERT / NUDGE。调试层开着时每头牛头顶有状态小球：黄 = 头牛吃草，黑 = 吃草，蓝 = 跟随，红 = 惊跑，橙黄 = 警觉，橙 = 挪开。

关键参数**已全部移入 `data/species/yak.tres`**（`SpeciesData`，T16），改一处全群生效。
牛身上只留性格四参数、`is_leader`、`follow_distance_scale`（个体的跟随距离倍率）与 `pen_center`。

| 组 | 参数 | 值 |
| --- | --- | --- |
| 运动 | wander / follow / flee / nudge 速度 | 1.3 / 1.7 / 3.5 / 2.5 m/s |
| 运动 | 平静上限 / 最小意图速度 | 3.0 / 0.25 m/s |
| 运动 | 加速（平静 / 惊跑）/ 减速 | 3.0 / 8.0 / 3.5 |
| 运动 | 漫步距离 / 惊跑最远 / 挪开距离 | 4–20 / 9 / 1.5–5 m |
| 牛群 | 分离半径 / 力 | 14 m / 2.0 |
| 牛群 | 聚合起点 / 力 / 头牛受质心牵引 | 26 m / 0.5 / 0.35 |
| 牛群 | 跟随触发 / 停止距离 | 30（×个体倍率）/ 20 m |
| 草场 | 吃草速率 / 饱腹转化 / 饱腹自然下降 | 0.0015 每秒 / 0.12 / 0.0001 每秒 |
| 牛群 | 传染半径 / 量 | 8 m / 0.3 |
| 惊吓 | 阈值 × 胆量 / 半衰期 | 0.5 / 6 s |
| 施压 | 不吆喝半径 / 吆喝半径 / 吆喝惊吓 | 4 m / 8 m / 0.08 每秒 |
| 乌尔朵 | 半径 / 惊吓 | 6 m / 0.7 |

## 命令行调试参数

```
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --path . -- --time=0.85 --screenshot=out.png          # 指定时段截图（2 s 后）
$G --path . -- --shot-delay=10 --player-at=-16,30 ...    # 延时截图、放置玩家
$G --headless --path . --quit-after 1200 -- --log-positions   # 每秒打印每头牛的状态与位置
$G --headless --path . --quit-after 700 -- --log-positions --test-sling   # 3 s 后在第一头普通牛旁落石
$G --headless --path . --quit-after 1500 -- --log-positions --test-drive  # 玩家自动站在群后吆喝跟走
$G --headless --path . --quit-after 9000 -- --log-grass --time-scale=60     # 每 5 s 打印草场均值/退化/秃格/群的占格与饱腹
$G --headless --path . --quit-after 9000 -- --log-grass --pin-herd --time-scale=60  # 把群按在原地，单独验证局部过牧
$G --headless --path . --quit-after 900 -- --test-save                      # 牛与草场的存档往返自检
```

游戏内：F12 调试层开关，T 键 20 倍快进时钟，F 吆喝，Tab 远近。

## 已知缺口

- ~~草场数据层~~ → **已实现**（`grassland.gd`）。消耗、效率曲线、每日逻辑斯蒂恢复、退化累积/自愈、初始双层噪声、存档接口均已验证。
- ~~草场压力未达设计目标~~ → 已解决。牛群放松到半径 14–18 m（占 4–5 格），
  并修正了按 480 s 的一天定的 `SATIETY_DECAY`（0.0002→0.0001，否则牛必饿死）。
  10 天实测饱腹度 0.50→0.32 后趋平，系统收敛。定标经过见 `GRASSLAND.md` §2.4、群体参数见 `Herd_BEHAVIOR.md` §5。
- 草量可视化（P1）未做：`grassland.texture()` 已备好，`grass.gdshader` 尚未接。
- 一天仍是 480 s，D4 已改为 1800 s；时段边界与 `homing_urge()` 曲线待按 `DAY_CYCLE.md` §1.1/§3.2 重定。
- 天黑宽限（60 s，D17）未做。
- 走失、死亡、存档、正式结算未做；结算目前只是调试层的一行文字，6 s 后自动进入次日。规格已定：`DAY_CYCLE.md` §4–§5。
- ~~`cow.gd` 的 @export 抽成 `SpeciesData`~~ → 已完成。
- ~~牛还不是预制体、`CowData` 未做~~ → **已完成**。`scenes/cow.tscn` + `CowData`，
  `HerdManager` 按数据生成；存档往返已验证（5 头牛的性格/头牛/外观种子/位置与 1600 格草场全部一致，JSON 约 36 KB）。
- `SaveIO` / `GameState` 两个 autoload 与真正的读写盘未做（现在只验证了序列化往返）。
- 场景仍是单一的 `m1_sandbox.tscn`，`main/world/ui` 三层未拆（ARCHITECTURE §1.1）。
- 地形是平的；起伏与草量可视化留到 M3 处理 T14 时一起做。
- 人和牛没有动画。
- 落石的"闷响让其他牛抬头"未做。
- 惊跑传染只传给半径内的牛，远端不受影响；"赶太猛整群炸"若要，可在区域压力里加传递。

## 踩过的坑

- 场景里的节点变换曾被编辑器误改（拖 gizmo 后保存），表现为人物和牛的朝向、位置异常。改场景前看一眼 git diff。
- 用 duplicate 复制节点时材质资源是共享的，每个实例要 `duplicate()` 一份材质；实例的属性要在 `add_child` 之前配置好，否则 `_ready` 按模板值初始化。
- 分离半径必须大于牛身长，否则中心距够远但模型仍重叠。
- 惊跑结束时惊吓值仍高于阈值会立刻再跑；要在退出惊跑时消耗掉。
- 无头模式不轮询鼠标手柄；有窗口时误点一下等于甩了一颗石头。
- GDScript 对从 Variant 推断类型的 `:=` 报错，`get_node` / `lerp` 等返回 Variant 的地方要写显式类型或用 `lerpf`。
