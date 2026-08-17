# 灵农修仙

《灵农修仙》是使用 Godot 4.7.1 开发的单机增量游戏原型。当前 v1.2
核心是连续生产、谱系轮回和批量结算，不再使用逐田收获、逐箱打开、出售或炼丹服用链。

## 当前循环

```text
配置作物比例
  → 灵田农力持续产生修为、灵石、体魄、神识和对应品阶宝箱
  → 宝箱立即批量结算，材料信用按目标路线释放
  → 累计修为、出生历史前置和材料齐备后进行概率突破
  → 金丹节点锁定气血，达到固定雷劫伤害 + 1 后一次结算
  → 主动或已授权自动轮回，提交本世新发现并获得道蕴
```

## 已实现的 v1.2 核心

- `BigMagnitude`：规范化尾数/指数，资源按 `{m, e}` 保存。
- `BigCounter`：十进制精确整数，用于材料、宝箱、气血和雷劫伤害。
- `RateEngine`：唯一连续速率来源，统一在线、离线、ETA 和 UI 展示。
- `FarmPortfolio`：作物 cohort 比例、灵田等级、灵土阶数、聚灵阵和购买最大。
- 三档宝箱：普通/精良/稀有作物只产对应箱级；掉落通道使用定点概率信用。
- `MaterialLedger`：持有、预留、escrow、终身获得/消耗和目标材料信用。
- `BreakthroughService`：不同路线的 E/H、材料权重、显示概率、失败损失和硬保底。
- `TribulationService`：只比较精确气血与固定总伤害，气血等于伤害时失败，大 1 时成功。
- `RunState / LineageState / LegacyState`：轮回清空、谱系保留、飞升保留三层状态。
- Save v20：嵌套状态、原子临时文件替换、v18/v19 平铺存档一次性迁移。
- `WorldSimulator`：按目标门槛、寿元软墙和自动动作分段积分，支持离线有效时间。
- 可运行主界面：生产预设、购买最大、路线选择、突破、雷劫、轮回和收据。

## 运行与验证

安装 Godot 4.7.1 后，在项目根目录运行：

```bash
godot --editor --path .
godot --path .
godot --headless --path . --editor --quit
godot --headless --path . res://scenes/probes/field_balance_probe.tscn
godot --headless --path . res://scenes/probes/art_catalog_probe.tscn
```

玩法探针通过时输出 `BALANCE_PROBE_PASS`，覆盖大数编码、材料权重守恒、批量拆分、雷劫边界、首世突破、轮回历史提交和 v20 存档往返。美术探针通过时输出 `ART_CATALOG_PROBE_PASS`，确认 86 张静态图和 26 组动画都能被 Godot 加载，且动画帧数、速度和加法混合设置正确。

存档路径为 `user://lingnong_save.json`，失败写入时保留 `user://lingnong_save.json.bak`。

## 开源协议

本项目使用 [Apache License 2.0](LICENSE)。
