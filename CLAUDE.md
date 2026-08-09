# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概览

《灵农修仙》是 Godot 4.7.1 的单机国风增量游戏原型。当前主循环是种植、收获、突破材料准备、渡劫和天赋树加点；长期成长不再使用转世或转世知识点。

## 常用命令

在仓库根目录执行：

```bash
/opt/homebrew/bin/godot --editor --path .
/opt/homebrew/bin/godot --path .
/opt/homebrew/bin/godot --headless --path . --editor --quit
/opt/homebrew/bin/godot --headless --path . --quit
```

数值平衡探针（修改 `BalanceConfig` 后必须跑；全部通过时输出 `BALANCE_PROBE_PASS`）：

```bash
/opt/homebrew/bin/godot --headless --path . res://scenes/probes/field_balance_probe.tscn
```

项目没有包管理器、构建脚本或自动化测试套件。修改脚本或场景后，至少运行两条 headless 命令，并通过主场景检查相关交互。

## 代码结构

- `project.godot`：项目入口和两个自动加载单例。
- `scenes/main/main.tscn`：主场景骨架。
- `scripts/autoload/game_state.gd`：唯一的运行时游戏状态和增量结算入口。
- `scripts/autoload/save_manager.gd`：`user://lingnong_save.json` 的读写，当前存档版本为 17。
- `scripts/systems/`：境界、作物、成就、自动化、倍率、商店、天赋树的规则。
- `scripts/probes/field_balance_probe.gd`：headless 数值探针，配合 `scenes/probes/field_balance_probe.tscn` 使用。
- `scripts/ui/main.gd`：标签页控制器和每帧推进。
- `scripts/ui/panels/`：种植、突破、天赋树、成就、商店、法术/事件、数值模拟面板。

## 数值与规则边界

- **全部可调数值集中在 `scripts/systems/balance_config.gd` 的 `BalanceConfig`**：境界、作物、四季、灵田价格与倍率、天赋、成就、商店、事件、自动化和离线参数。改平衡只改这一个文件。
- `GameState` 只保存状态并执行结算；`AchievementSystem`、`RealmConfig`、`CropConfig`、`TalentTree`、`AutomationSystem`、`ShopSystem` 只做规则查询，面板只负责显示和调用方法，不复制数值。
- 真实结算与游戏内“数值模拟”标签页共同调用 `SimulationSystem`，不存在第二套数值表。修改 `BalanceConfig` 后跑探针即可确认两者同步。

## 当前规则

```text
种植 → 自动收获/补种或点击加速 → 灵石/修为直接入账
    → 切换作物与熟练度 → 修为门槛 + 商店突破材料 → 九九/六九/三九天劫 → 境界倍率/天赋树分支
```

- 默认自动收获并补种；点击只加速生长倒计时，成熟后仍由世界循环统一结算。
- 当前灵气每满 100 点使收获提高 10%，基础收获加成上限为 ×3；灵气还支付法术消耗。
- 寿元按真实运行时间每秒扣除，默认每秒 0.5 年；不按种植次数扣除。归零后进入大限，生产暂停；可用商店续命，或手动开启新局并保留长期成长。
- 突破材料只能从商店兑换；点击突破后先进入天劫，境界、寿元和突破天赋点在天劫成功后才生效。天劫期间暂停生产、事件和自动修炼。
- 商店商品：长生丹续命、聚气玉补灵气、治疗丹/抗性丹/强化丹渡劫、悟道残卷换天赋点、狂暴丹（生产 ×3 持续 5 秒，100 灵石起每次购买 ×1.5 递进、不设上限）换短时爆发；购买次数跨大限新局保留。
- 天劫默认 99 道；当前未用天赋点达到 10 点降为 69 道，达到 25 点降为 39 道。治疗丹恢复 30 劫体，抗性丹提供 10 道半伤抗性，强化丹让本次劫体上限 +50 且雷劫伤害 ×0.8。
- 天赋树是带前置和分支的图：农道、丹道、灵根、幸运四条路线（幸运系提供收获暴击 ×2/×5 与天降横财）；玩家在分支节点中选择路线，不是固定升级条。
- 种植熟练度（10/50/150/400 次）按灵植发放产量、成熟时间和天赋点奖励，跨新局保留。
- 成就由 `AchievementSystem` 统一检查，成就点独立于修为、灵石和天赋点，随存档和新局保留。
- 自动修炼只在在线循环中按秒结算；离线结算不读取离线时长，只按轮回、晋级和总收获计数发放一次性天赋点与灵石差额，大限未续命时不发放。

## 文档基线

- `docs/CURRENT-GAME-FLOW.md`：依据当前可执行代码整理的运行逻辑图，是唯一以代码为准的基线；UI 文案和旧设计说明不算运行逻辑。
- `docs/TARGET-GAME-FLOW.md`：下一版玩法设计基线，包含转世/飞升等**尚未实现**的方向；不要把目标版当作当前行为实现。
- `docs/GDD-v0.1.md` 与 `docs/IMPLEMENTATION-PLAN-v0.1.md`：较早的设计与实施说明，改动以 CURRENT-GAME-FLOW.md 为准。
- 数值或交互发生变化时，先更新 README，再更新 `docs/CURRENT-GAME-FLOW.md` 和本文件。

## 变更后的检查重点

1. 新游戏默认显示“自动收获并补种”。
2. 生长中的灵田点击后会减少成熟倒计时，成熟作物仍自动收获并补种。
3. 连续调用 `update_world(delta)` 时寿元按秒下降，种植本身不扣寿元；归零后生产暂停。
4. 天赋树面板显示连接线、节点状态、费用、前置条件和效果。
5. 商店面板能购买七种商品（狂暴丹价格随购买次数递进），并正确保存资源变化；渡劫面板能使用三类渡劫丹。
6. 成就面板显示完成度，收获、突破、熟练度、灵田、轮回和天赋目标能自动解锁且不重复发放成就点。
7. 存档加载后保留天赋节点、天赋点、成就、成就点、灵田购买结果、寿元、天劫进度、渡劫丹库存和商店产生的资源。
