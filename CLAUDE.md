# 灵农修仙开发说明

这是 Godot 4.7.1 项目，使用 GDScript。实现基线是仓库外提供的
`REFACTOR-DESIGN-v1.2.md`。

## 常用命令

```bash
/opt/homebrew/bin/godot --editor --path .
/opt/homebrew/bin/godot --path .
/opt/homebrew/bin/godot --headless --path . --editor --quit
/opt/homebrew/bin/godot --headless --path . res://scenes/probes/field_balance_probe.tscn
```

修改数值或领域服务后必须运行编辑器解析检查和 headless 探针。探针成功标记为
`BALANCE_PROBE_PASS`。

## 代码边界

- `scripts/core/numbers/`：连续大数、精确整数和编码。
- `scripts/systems/balance_config.gd`：所有可调内容与数值目录。
- `scripts/state/`：Run、Lineage、Legacy、灵田、材料、宝箱、策略和收据状态。
- `scripts/domain/`：速率、农场经济、宝箱批处理、路线、突破、雷劫、轮回和世界模拟。
- `scripts/autoload/game_state.gd`：唯一应用门面；只协调命令、状态、领域服务和信号。
- `scripts/autoload/save_manager.gd`、`scripts/persistence/save_migrator.gd`：Save v20 与旧存档一次性迁移。
- `scripts/ui/main.gd`：主界面，不在 UI 中复制数值公式。

## 不变规则

- 修为本世只增不减；突破不清零；轮回才清空本世资源。
- 只有出生时的历史快照能满足后置路线前置；本世新发现轮回后才进入下一世历史。
- 普通、精良、稀有灵植分别只产生对应箱级；箱子生成时立即结算。
- 材料是批量吞吐量，不设背包上限，不出售、不炼制、不逐颗服用。
- 突破概率与箱子掉落分离；突破失败只消耗主材本套需求的 5%，节点保留硬保底。
- 金丹雷劫只读取锁定气血和固定伤害：HP 等于伤害失败，HP 大 1 成功。
- 寿元固定 900 有效秒，720 秒后平滑衰减，不存在延寿、复活或等待奖励。
- 在线和离线都调用 `RateEngine` 与 `WorldSimulator`，不得在 UI 另写一套模拟。
