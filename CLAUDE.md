# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目

《牧野旅人 / Herding Traveler》——当代藏区背景的 3D 低多边形放牧游戏。Godot 4.7.2 stable（版本锁定，不追 dev 版）· GDScript · Forward+ · Jolt。

**文档与注释一律用中文。** 现有代码的注释密度较高且解释"为什么这样定"而非"这行做什么"，新代码沿用这个风格。

## 设计文档先行

`docs/` 下的文档不是事后补的说明，而是**规格的唯一来源**，代码是它的实现。改动任何系统前先读对应文档；改了行为就同步更新文档。

| 文档 | 内容 |
| --- | --- |
| `docs/DECISIONS.md` | 已定的技术（T*）与设计（D*）决策，一条一行。**改任何一条前先看这里，改了就更新这里** |
| `docs/PRD.md` | 做什么、验收标准、里程碑 M1–M6 |
| `docs/Herd_BEHAVIOR.md` | 牛的状态机、性格、头牛、群体力、玩家施压 |
| `docs/GRASSLAND.md` | 草场网格数据结构、消耗与恢复、头牛挑草场 |
| `docs/DAY_CYCLE.md` | 一天的时间结构、围栏、归栏、结算、走失与死亡 |
| `docs/ARCHITECTURE.md` | 场景层级、Resource 驱动、存档格式、从现状到目标的重构路线（§6 是待办清单） |
| `docs/STATUS.md` | 代码现状、已知缺口、**踩过的坑** |

代码注释里的 `BEHAVIOR §5`、`GRASSLAND §2.4`、`D11`、`T16` 这类引用指向上面这些文档的章节与决策编号，遇到时去查。

## 运行与调试

灰盒期没有单元测试框架，也没有 lint。**所有验证走命令行参数**（D15），headless 跑数值、有窗口截图：

```bash
G=/Applications/Godot.app/Contents/MacOS/Godot

# 打开编辑器 / 直接跑（主场景 scenes/m1_sandbox.tscn）
$G --path .

# 指定时段截图（2 s 后）
$G --path . -- --time=0.85 --screenshot=out.png
$G --path . -- --shot-delay=10 --player-at=-16,30 --screenshot=out.png

# 每秒打印每头牛的状态与位置
$G --headless --path . --quit-after 1200 -- --log-positions

# 3 s 后在第一头普通牛旁落石，验证惊跑与传染
$G --headless --path . --quit-after 700 -- --log-positions --test-sling

# 玩家自动站在群后吆喝跟走，验证区域压力
$G --headless --path . --quit-after 1500 -- --log-positions --test-drive

# 每 5 游戏秒打印草场均值/退化/秃格/群的占格与饱腹。--time-scale 是引擎整体缩放（物理+时钟一起快），
# 20 倍下一天 90 s 实时；别用 60，物理 delta 太大牛会在目标点附近抖
$G --headless --path . --quit-after 27000 -- --log-grass --time-scale=20
# 把群按在原地，单独验证局部过牧
$G --headless --path . --quit-after 27000 -- --log-grass --pin-herd --time-scale=20

# 牛与草场的存档往返自检
$G --headless --path . --quit-after 900 -- --test-save
```

注意 `--` 之前是 Godot 自己的参数，之后是本项目的参数（`debug_overlay.gd` 用 `OS.get_cmdline_user_args()` 解析）。新增一种验证 = 在 `scripts/debug/debug_overlay.gd` 里加一个 `--xxx` 分支，不要引入测试框架。

游戏内：F12 调试层开关，T 键 20 倍快进时钟，F 吆喝，Tab 远近，左键甩乌尔朵。

## 架构要点

**一条原则：状态在数据里，表现在场景里。** 存档只存状态，场景随时可以扔掉重建。走失、买牛、读档、次日重开是同一件事——**按数据造节点**。

### 数据流

```
data/species/yak.tres (SpeciesData)   全群共用的行为参数，调参只改这一个文件
        ↓ 注入
CowData (每头牛的持久状态：性格/外观种子/饱腹/位置/走失夜数/存活)
        ↓ HerdManager.spawn(d) → 实例化 scenes/cow.tscn
Cow 节点（表现 + 状态机，参数一律读 species，不自带 @export 数值）
        ↓ write_back()
CowData（结算与存档从 herd_manager.herd 取）
```

调牛群手感 = 改 `data/species/yak.tres`，**不要**往 `cow.gd` 加 `@export` 数值。牛身上只保留性格四参数、`is_leader`、`follow_distance_scale`、`pen_center`。

### 计时

`Clock`（唯一 autoload）是唯一的计时来源（T17）。**禁止任何节点自行计时**——昼夜光照、牛的归栏欲望、草场每日恢复都从 `Clock` 读或接它的信号：

- `Clock.time_of_day` 0.0（清晨出栏）→ 1.0（天黑），一天 1800 s
- `Clock.homing_urge()` → 傍晚归栏欲望 0–1，牛读它
- `Clock.phase_changed` / `grace_started` / `day_ended(day)` 三个信号
- 到 1.0 后有 60 s 宽限（D17），全部归栏则提前结算

### 跨节点查找用 group，不用 autoload

`"grassland"` `"pen"` `"player"` `"cows"` `"herd_manager"`。草场、围栏、牛群都属于 world，做成 autoload 会让"卸载 world 重建"变得不可能（ARCHITECTURE §1.1）。Autoload 只允许有三个：`Clock`（已有）、`GameState`、`SaveIO`（未做）。

### 输入

代码里不出现具体按键（T11），一律走 InputMap 命名动作：`move_forward` `run` `camera_left` `camera_drag` `camera_zoom_toggle` `sling_throw` `drive_toggle` `debug_toggle` `debug_time_fast`。键鼠与手柄同时支持。

### 其他约定

- 1 unit = 1 米（T7）；模型前方 = -Z（T8）
- 物理层：1 = ground（地面/石块/围栏），2 = player，4 = livestock
- 灰盒美术全部用引擎原生几何体在代码里拼（D14）：`*_body.gd` `grass_field.gd` `mountains.gd` `pen.gd`。M3 前不引入外部模型，不做美术与 UI 打磨
- UI 文本一律 `tr()`，不写字面量（T18）
- 二进制资源（.glb/.png/.wav/.ogg/.blend/.ttf）走 Git LFS（T19）

## 当前状态与下一步

M1（手感）、M2（群体）灰盒完成；M3（可玩）部分完成。**待办清单在 `docs/ARCHITECTURE.md` §6 的表格**，`docs/STATUS.md` 的"已知缺口"是同一份的展开。当前主要缺口：`cow.gd` 拆分（546 行，规格见 ARCHITECTURE §5.1）、`main/world/ui` 三场景拆分、结算 UI、走失与死亡、`SaveIO`/`GameState`。

## 踩过的坑

`docs/STATUS.md` 文末有完整列表。最容易再犯的几条：

- **改场景前先看一眼 `git diff`。** 编辑器拖 gizmo 会误改节点变换，表现为人物和牛的朝向、位置异常
- 实例的属性要在 `add_child` **之前**配置好，否则 `_ready` 会按模板值初始化
- GDScript 对从 Variant 推断类型的 `:=` 报错，`get_node` / `lerp` 等返回 Variant 的地方要写显式类型或用 `lerpf`
- 无头模式不轮询鼠标手柄；有窗口时误点一下等于甩了一颗石头
