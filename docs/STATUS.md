# STATUS.md — 代码现状

更新：2026-09-07（设计文档补齐，M3 待办见文末）。记录"代码里现在有什么"，供接手与复盘。设计意图看 PRD 与 DECISIONS，行为规格看 Herd_BEHAVIOR。

仓库：https://github.com/hui-chuan/Herding-Journey · 引擎：Godot 4.7.2 stable

## 进度

| 里程碑 | 状态 | 说明 |
| --- | --- | --- |
| M1 手感 | 灰盒完成 | 玩家、相机、乌尔朵、单牛躲避 |
| M2 群体 | 灰盒完成，调参中 | 状态机、性格、头牛、群体力（双档）、分级传染、吆喝、区域压力、平衡点、撤压奖励 |
| M3 可玩 | 部分 | 时钟与光照有；畜栏与门有；归栏判定与简易结算有（调试层内）；草场数据层已做，真实比例下零秃格、饱腹度上升（可能偏易，M3 重定标） |
| M4 循环 | 未开始 | 走失、存档 |

## 目录

```
project.godot                 Forward+ / Jolt / InputMap / 自动加载 Clock
scenes/m1_sandbox.tscn        唯一场景：地面、光、草、远山、石块、畜栏、草场、玩家、牛群生成器、调试层（牛不再在场景里）
shaders/grid_ground.gdshader  10 m 大格 + 1 m 小格的灰盒地面（大格 = 草场格尺寸）
shaders/grass.gdshader        草丛：随风摆动，高度与颜色读草场网格
shaders/grid_ground.gdshader  地面：网格线 + 草量底色（远视角下靠它读出被吃过的地方）
scripts/autoload/clock.gd     全局时钟：一天 1800 s，五时段（DAY_CYCLE §1.1），60 s 天黑宽限，homing_urge()
scripts/autoload/game_state.gd 现金、库存、死亡现场；collect/apply 汇总整局状态，settle 算产出
scripts/autoload/save_io.gd   JSON 读写 user://save_1.json，save_version 与迁移分支
scripts/world/day_light.gd    太阳角度与色温随时钟变化
scripts/world/grassland.gd    草场网格 40×40（Image RGF：R 草量 G 退化）：查询、消耗、挑草场、每日恢复、存档
scripts/world/grass_field.gd  MultiMesh 铺 20 万丛草，铺满整张 400 m 地图
scripts/world/mountains.gd    一圈低多边形远山
scripts/world/greybox_props.gd 散落石块（StaticBody3D，带碰撞）
scripts/world/pen.gd          畜栏：四边围栏带碰撞，东侧自动门；归栏判定 contains()/cows_inside()
scripts/player/player.gd      步行 2 / 奔跑 5 m/s；driving 吆喝开关
scripts/player/player_body.gd 牧人外观（原生几何体拼）
scripts/player/camera_rig.gd  固定 40° 俯角，水平可转，Tab 远近 + 静止 3 s 自动远观
scripts/player/sling.gd       乌尔朵：鼠标瞄准落点，4–40 m，抛物线 1 s，冷却 2 s
scripts/data/species_data.gd  种类行为参数 Resource（T16）：运动、群体力、惊吓、施压响应、草场
scripts/data/cow_data.gd      一头牛的持久数据（性格、外观种子、饱腹、位置、走失夜数、存活）+ 存档往返
data/species/yak.tres         牦牛的一份参数，全群共用；调参只改这个文件
scripts/herd/cow.gd           牛：状态机、性格、惊吓、区域压力、头牛意图（参数读 species）
scripts/herd/cow_forces.gd    群体力：分离、聚合、质心、传染邻居查询（静态函数，不持状态）
scripts/herd/yak_body.gd      牦牛外观，花色按种子
scripts/herd/herd_manager.gd  按 CowData 生成牛群（5 头，1 头头牛）；spawn/spawn_all/write_back_all
scenes/cow.tscn               牛的预制体：碰撞体 + 外观 + 状态小球
scripts/ui/settlement_screen.gd 结算界面：一屏，居中，字少，唯一按钮是"睡觉"
scripts/ui/day_settlement.gd  结算流程：统计存栏、算产出、判走失与死亡、存档、开界面
scenes/ui/settlement_screen.tscn 结算界面场景
locale/ui.csv                 UI 文案（zh_CN / en），Godot 生成 .translation
scripts/debug/debug_overlay.gd 调试层与命令行参数（不再承载游戏流程）
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
| 运动 | 漫步距离 / 惊跑最远 / 挪开距离 | 4–15 / 9 / 1.5–5 m |
| 牛群 | 分离半径（吃草 / 移动）/ 力 | 8 / 4 m / 2.0 |
| 牛群 | 聚合起点 / 力 / 移动档倍率 / 头牛受质心牵引 | 10 m / 0.8 / 2.0 / 0.35 |
| 牛群 | 跟随触发 / 停止距离 | 22（×个体倍率）/ 9 m |
| 草场 | 吃草速率 / 饱腹转化 / 饱腹自然下降 / 吃草漂移 | 0.0015 每秒 / 0.12 / 0.0001 每秒 / 0.12 m/s |
| 牛群 | 传染半径 / 连锁量 / 单头量 | 8 m / 0.3 / 0.12 |
| 惊吓 | 阈值 × 胆量 / 半衰期 / 撤压衰减倍率 | 0.45 / 6 s / 0.5 |
| 施压 | 不吆喝半径 / 吆喝半径 / 吆喝惊吓 | 4 m / 8 m / 0.08 每秒（半径 × (1 + fear)） |
| 施压 | 平衡点侧向分量 | 0.35 |
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
$G --path . -- --zoom=2 --test-bare --shot-delay=8 --screenshot=out.png     # 远档 + 吃秃一片，检验草量可视化
$G --headless --path . --quit-after 900 -- --test-load                      # 只读一次存档（用于验证迁移/拒绝路径）
# 无头跑多天：--auto-sleep 替玩家按"睡觉"，否则结算界面会一直等着，天数不推进
$G --headless --path . --quit-after 400000 -- --time=0.97 --time-scale=12 --auto-sleep --quit-after-days=3
```

游戏内：F12 调试层开关，T 键 20 倍快进时钟，F 吆喝，Tab 三档视角循环。

**`--time-scale` 上限 12。** 再快物理步长会被引擎钳到 0.5 s，牛一步下落一米多，
穿过地面碰撞体后无限坠落——那是快进的假象，不是游戏里的 bug。
快进用来验证草场与结算的数值，不要用它验证移动。

## 已知缺口

- ~~草场数据层~~ → **已实现**（`grassland.gd`）。消耗、效率曲线、每日逻辑斯蒂恢复、退化累积/自愈、初始双层噪声、存档接口均已验证。
- ~~草场压力未达设计目标~~ → 已解决。牛群放松到半径 14–18 m（占 4–5 格），
  并修正了按 480 s 的一天定的 `SATIETY_DECAY`（0.0002→0.0001，否则牛必饿死）。
  10 天实测饱腹度 0.50→0.32 后趋平，系统收敛。定标经过见 `GRASSLAND.md` §2.4、群体参数见 `Herd_BEHAVIOR.md` §5。
- ~~草量可视化未做~~ → **已完成**：草丛与地面两个 shader 都接了草场纹理。
  只接草丛不够——远视角下草丛只占很少像素，亮绿的地面会把它冲掉，必须两个都接。
- ~~一天仍是 480 s、时段边界与归栏曲线未按 DAY_CYCLE 重定~~ → **已完成**（1800 s，新五时段，t² 归栏曲线到 0.95 满值）。
- ~~天黑宽限未做~~ → **已完成**：到 1.0 进宽限，60 s 或全部归栏则结算，`grace_started` / `day_ended` 两个信号。
- 结算仍是调试层的一行文字，正式结算界面（DAY_CYCLE §4）未做。
- 走失、死亡、存档未做。规格已定：`DAY_CYCLE.md` §4–§5。
- ~~`cow.gd` 的 @export 抽成 `SpeciesData`~~ → 已完成。
- ~~牛还不是预制体、`CowData` 未做~~ → **已完成**。`scenes/cow.tscn` + `CowData`，
  `HerdManager` 按数据生成；存档往返已验证（5 头牛的性格/头牛/外观种子/位置与 1600 格草场全部一致，JSON 约 36 KB）。
- ~~`SaveIO` / `GameState` 与真正的读写盘未做~~ → **已完成**。落盘往返验证：写盘 → 故意破坏内存状态
  → 读盘，牛/草场/现金库存全部还原，5 头牛无重复。未来版本号的存档会被拒绝读取并报错，不静默丢档。
- ~~正式结算界面未做~~ → **已完成**（`scenes/ui/settlement_screen.tscn`）。结算流程从调试层搬进
  `day_settlement.gd`；文案全部走 `tr()`（T18）。次日投放已实现：走失的牛出现在它昨晚位置
  附近的高草量格，归栏的牛回到围栏里。
- 藏文渲染已验证（T18）：内置 ICU/HarfBuzz 整形正确，不需要额外字体资产。
- 出栏（DAY_CYCLE §3.1）已实现：群生成在栏内，清晨头牛朝栏外挑草场，其余跟出去。
- 牛有下落速度上限、掉出地面的捞回、以及地图边界兜底（一处收口，不在四条移动路径上各写一遍）。
- 场景仍是单一的 `m1_sandbox.tscn`，`main/world/ui` 三层未拆（ARCHITECTURE §1.1）。
- 地形是平的；起伏与草量可视化留到 M3 处理 T14 时一起做。
- 人和牛没有动画。
- 落石的"闷响让其他牛抬头"未做。
- 惊跑传染只传给半径内的牛，远端不受影响；"赶太猛整群炸"若要，可在区域压力里加传递。

## 踩过的坑

- **牛群的行为跑一次看不出结论。** 每头牛的漫步噪声用 `randi()` 播种，不随
  `HerdManager.seed` 固定，所以同一份代码连跑两次，群的质心、占格、脚下草量都会明显不同
  （实测同一 build 两次：centroid (-28,37) eff 0.27 / (-32,37) eff 0.15）。
  **比较改动前后的行为要各跑三次以上**，否则会把随机波动当成自己引入的 bug。

- **`project.godot` 的翻译列表键名要带 `locale/` 前缀**：section 是 `[internationalization]`，
  键必须写成 `locale/translations=`，写成 `translations=` 不报错但一条都不加载
  （`TranslationServer.get_loaded_locales()` 返回空，`tr()` 原样吐出 key）。
  另外列表要填 Godot 从 CSV 生成的 `.translation` 文件，不是 CSV 本身。

- 场景里的节点变换曾被编辑器误改（拖 gizmo 后保存），表现为人物和牛的朝向、位置异常。改场景前看一眼 git diff。
- 用 duplicate 复制节点时材质资源是共享的，每个实例要 `duplicate()` 一份材质；实例的属性要在 `add_child` 之前配置好，否则 `_ready` 按模板值初始化。
- 分离半径必须大于牛身长，否则中心距够远但模型仍重叠。
- 群的松紧不能用一套参数：散到草场压力够薄，赶起来就成一片云；收到能赶，草场就崩。要分吃草 / 移动两档（BEHAVIOR §5.1）。
- 跟随判断放在吃草计时结束处会慢 20 s，头牛的吸引"看起来"消失了。跟随、传染这类要及时响应的判断要有自己的节拍。
- **引擎缩放超过 8 倍时物理跟不上。** `max_physics_steps_per_frame` 默认 8，`Engine.time_scale=20` 实际物理只有 8 倍而时钟 20 倍，又失真。`--time-scale` 现在同时放开物理步数上限；代价是帧率下降，所以按帧数的 `--quit-after` 不可靠，用 `--quit-after-days=N`。
- **只加速时钟的模拟是失真的。** `Clock.time_scale=60` 时牛相对一天几乎不动、草照常被吃，得出的"必须放松群""graze_rate 无效"全是假象（GRASSLAND §2.4 更正）。验证平衡一律用 `Engine.time_scale`（`--time-scale`），且不超过 20。
- 漫步选点的打分里，乘在小随机数上的项永远输给加法项。草量和合群要放在同一量级上比较，合群只在出了舒适半径才扣分。
- 惊跑结束时惊吓值仍高于阈值会立刻再跑；要在退出惊跑时消耗掉。
- 门扇外开 110° 会和栅栏夹出 V 形口袋卡牛；门要贴栅栏放平。牛回栏要经门前集结点，不能直瞄栏中心。
- 无头模式不轮询鼠标手柄；有窗口时误点一下等于甩了一颗石头。
- GDScript 对从 Variant 推断类型的 `:=` 报错，`get_node` / `lerp` 等返回 Variant 的地方要写显式类型或用 `lerpf`。
