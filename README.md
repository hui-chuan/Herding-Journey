# 牧野旅人 / Herding Traveler

当代藏区背景的 3D 低多边形放牧游戏。玩家是牧人，白天远远看着牛群吃草，偶尔甩一颗石头纠偏，傍晚陪头牛把群带回围栏。

- 引擎：Godot 4.7.2 stable（锁定，不追 dev 版）· GDScript · Forward+ · Jolt
- 文档：[PRD](docs/PRD.md) · [决策记录](docs/DECISIONS.md) · [牛群与草场行为](docs/Herd_BEHAVIOR.md)

二进制资源（.glb / .png / .wav / .ogg）由 Git LFS 管理，克隆前请先安装 `git lfs`。

## 运行

用 Godot 4.7.2 打开 `project.godot`，主场景是 `scenes/m1_sandbox.tscn`（M1 灰盒）。

| 操作 | 键鼠 | 手柄 |
| --- | --- | --- |
| 移动 / 奔跑 | WASD / Shift | 左摇杆 / L1 |
| 转视角 | Q/E 或右键拖拽 | 右摇杆 |
| 远/近视角 | Tab | R3 |
| 甩乌尔朵 | 左键（鼠标瞄准落点） | R1（朝向前方 25 m） |
| 吆喝开关 | F | X |
| 调试 | F12 显示隐藏，T 快进时钟 | — |
