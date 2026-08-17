extends Node

func _ready() -> void:
	var failures: Array = []
	_check(BigCounter.from_string("999").add(BigCounter.one()).digits == "1000", "BigCounter 加法", failures)
	_check(BigCounter.from_string("1000").subtract(BigCounter.one()).digits == "999", "BigCounter 减法", failures)
	_check(BigCounter.from_string("123456789").multiply_int(9).digits == "1111111101", "BigCounter 乘法", failures)
	_check(BigCounter.from_string("123456789").multiply_counter(BigCounter.from_string("99")).digits == "12222222111", "BigCounter 大数乘法", failures)
	_check(BigCounter.pow_int(10, 18).digits == "1000000000000000000", "BigCounter 整数幂", failures)
	var magnitude := BigMagnitude.from_string("1e82")
	_check(magnitude.to_dict()["e"] == 82, "BigMagnitude 指数编码", failures)
	_check(BigMagnitude.from_dict(magnitude.to_dict()).compare(magnitude) == 0, "BigMagnitude JSON 往返", failures)
	var exact_fraction := BigMagnitude.from_string("999999999999999999999.001")
	_check(exact_fraction.floor_to_big_counter().digits == "999999999999999999999", "BigMagnitude 精确 floor 边界", failures)
	_check(exact_fraction.ceil_to_big_counter().digits == "1000000000000000000000", "BigMagnitude 精确 ceil 边界", failures)
	var exact_carry := BigMagnitude.from_string("999999999999999999999").add(BigMagnitude.one())
	_check(exact_carry.compare(BigMagnitude.from_string("1000000000000000000000")) == 0, "BigMagnitude 精确进位", failures)
	_check(BigMagnitude.from_string("1000000000000000000000").compare(BigMagnitude.from_string("999999999999999999999.999")) > 0, "BigMagnitude 精确比较边界", failures)
	_check(not SaveValidator._valid_magnitude({"m": "1", "e": 0, "d": "2"}), "Save 拒绝不一致的大数编码", failures)
	var reserve_ledger := MaterialLedger.new()
	var reserve_requirements := BalanceConfig.material_requirements("qi_common")
	var reserve_requirement: BigCounter = reserve_requirements["fu_qi_dan"]
	var reserve_loss := reserve_requirement.ceil_div_int(20)
	reserve_ledger.add("fu_qi_dan", reserve_requirement.add(reserve_loss.multiply_int(2)))
	reserve_ledger.refresh_hard_pity_reservation(reserve_requirements, 3, 0)
	_check(reserve_ledger.available("fu_qi_dan").compare(reserve_requirement) == 0, "硬保底预留不吞掉当前尝试材料", failures)

	for definition in BalanceConfig.REALM_NODES:
		var node_id := String(definition["id"])
		var requirements := BalanceConfig.material_requirements(node_id)
		var total := BigCounter.zero()
		for material_id in requirements:
			total = total.add(requirements[material_id])
		_check(total.equals(BalanceConfig.material_set_total(node_id)), "材料权重守恒 %s" % node_id, failures)

	var equal := TribulationService.evaluate(BigCounter.from_string("100"), BigCounter.from_string("100"))
	var above := TribulationService.evaluate(BigCounter.from_string("101"), BigCounter.from_string("100"))
	_check(not bool(equal["success"]), "气血等于伤害必须失败", failures)
	_check(bool(above["success"]), "气血大 1 必须成功", failures)
	_check(is_equal_approx(BalanceConfig.soft_wall_efficiency(720.0), 1.0), "软墙起点效率为 1", failures)
	_check(is_equal_approx(BalanceConfig.soft_wall_efficiency(900.0), 0.0), "软墙终点效率为 0", failures)
	_check(BalanceConfig.soft_wall_efficiency(810.0) < 1.0 and BalanceConfig.soft_wall_efficiency(810.0) > 0.0, "软墙中段连续衰减", failures)
	_check(BalanceConfig.law_multiplier(BigCounter.from_string("100")).compare(BigMagnitude.from_string("1e10")) == 0, "法则乘区平方根指数", failures)
	var strikes := TribulationService.strike_damage(BigCounter.from_string("100"), 3)
	var strike_sum := BigCounter.zero()
	for value in strikes:
		strike_sum = strike_sum.add(value)
	_check(strike_sum.equals(BigCounter.from_string("100")), "逐雷伤害守恒", failures)
	var max_farm := FarmPortfolio.new()
	var max_buy := FarmEconomyService.buy_max(max_farm, BigMagnitude.from_float(1000.0), "field_level")
	var manual_farm := FarmPortfolio.new()
	var manual_budget := BigMagnitude.from_float(1000.0)
	var manual_spent := BigMagnitude.zero()
	while true:
		var one := FarmEconomyService.buy_one(manual_farm, manual_budget, "field_level")
		if not bool(one.get("bought", false)):
			break
		manual_budget = manual_budget.subtract(one["cost"])
		manual_spent = manual_spent.add(one["cost"])
	_check(max_farm.field_level == manual_farm.field_level, "购买最大与逐级购买等级一致", failures)
	_check((max_buy["spent"] as BigMagnitude).compare(manual_spent) == 0, "购买最大与逐级购买花费一致", failures)

	GameState.initialize_new_game()
	var rates := GameState.get_rate_snapshot()
	_check((rates["cultivation_per_second"] as BigMagnitude).compare(BigMagnitude.zero()) > 0, "新档修为速率为正", failures)
	var before := GameState.run.total_cultivation
	GameState.advance_offline(30.0)
	_check(GameState.run.total_cultivation.compare(before) > 0, "连续推进增加修为", failures)
	_check(GameState.run.total_cultivation.compare(BigMagnitude.from_float(30.0)) >= 0, "30 秒累计修为可见", failures)
	GameState.run.status = "AWAITING_RESET"
	var blocked_offline := GameState.advance_offline(5.0)
	_check(String(blocked_offline.get("stopped_reason", "")) == "AWAITING_RESET" and GameState.offline_time_bank > 4.9, "离线阻塞保留时间银行", failures)
	GameState.run.status = "RUNNING"
	GameState.advance_offline(1.0)
	_check(GameState.offline_time_bank < 0.000001 and GameState.run.total_cultivation.compare(before) > 0, "时间银行只继续结算一次", failures)
	GameState.initialize_new_game()
	GameState.advance_offline(600.0)
	var first_breakthrough := GameState.attempt_breakthrough(9)
	_check(bool(first_breakthrough.get("success", false)), "普通练气可完成概率突破", failures)
	_check(GameState.run.completed_nodes.has("qi_common"), "本世写入新发现", failures)
	_check(GameState.run.active_target_id != "qi_common", "完成节点不会重新成为当前目标", failures)
	_check(not bool(GameState.choose_target("foundation_dan").get("ok", false)), "本世新发现不能满足后置前置", failures)
	var first_reset := GameState.reincarnate_now()
	_check(bool(first_reset.get("can_reset", false)), "首世可轮回", failures)
	_check(GameState.lineage.historical_realm_unlocks.has("qi_common"), "轮回提交历史节点", failures)
	_check(GameState.run.inherited_history.has("qi_common"), "下一世出生历史快照", failures)
	_check(GameState.get_available_crops().size() >= 2, "历史普通练气开放养元参", failures)
	var original_save_path := SaveManager.save_path
	var original_backup_path := SaveManager.backup_path
	var original_temp_path := SaveManager.temp_path
	SaveManager.save_path = "user://lingnong_probe_save.json"
	SaveManager.backup_path = "user://lingnong_probe_save.json.bak"
	SaveManager.temp_path = "user://lingnong_probe_save.json.tmp"
	_check(SaveManager.save_game(), "Save v20 原子写入", failures)
	var saved_file := FileAccess.open(SaveManager.save_path, FileAccess.READ)
	var parsed_save: Variant = null
	if saved_file != null:
		parsed_save = JSON.parse_string(saved_file.get_as_text())
		saved_file.close()
	_check(parsed_save is Dictionary, "Save checksum JSON 可解析", failures)
	if parsed_save is Dictionary:
		var saved_data: Dictionary = parsed_save
		_check(not String(saved_data.get("checksum", "")).is_empty(), "Save checksum 已写入", failures)
		_check(bool(SaveValidator.validate(saved_data, true).get("ok", false)), "Save checksum 校验通过", failures)
		var tampered: Dictionary = saved_data.duplicate(true)
		tampered["revision"] = str(int(tampered.get("revision", 0)) + 1)
		_check(not bool(SaveValidator.validate(tampered, true).get("ok", false)), "Save checksum 能拒绝篡改", failures)
	GameState.initialize_new_game()
	_check(SaveManager.load_game(), "Save v20 读取", failures)
	_check(GameState.run.inherited_history.has("qi_common"), "Save v20 保留历史快照", failures)
	GameState.run.action_seq += 1
	_check(SaveManager.save_game(), "Save v20 生成备份", failures)
	var corrupt_file := FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	if corrupt_file != null:
		corrupt_file.store_string("{\"broken\":true}")
		corrupt_file.close()
	GameState.initialize_new_game()
	_check(SaveManager.load_game(), "主档损坏时回退备份", failures)
	_check(GameState.run.inherited_history.has("qi_common"), "备份回退保留历史", failures)
	DirAccess.remove_absolute(SaveManager.save_path)
	DirAccess.remove_absolute(SaveManager.backup_path)
	DirAccess.remove_absolute(SaveManager.temp_path)
	SaveManager.save_path = original_save_path
	SaveManager.backup_path = original_backup_path
	SaveManager.temp_path = original_temp_path

	GameState.initialize_new_game()
	GameState.run.spirit_stones = BigMagnitude.from_string("1000")
	var command_revision := GameState.revision
	var first_command := GameState.buy_upgrade("field_level", false, "probe-command", command_revision)
	var revision_after_command := GameState.revision
	var retry_command := GameState.buy_upgrade("field_level", false, "probe-command", command_revision)
	_check(bool(first_command.get("bought", false)), "命令首次执行成功", failures)
	_check(bool(retry_command.get("bought", false)), "命令重试返回原结果", failures)
	var first_cost: BigMagnitude = first_command["cost"]
	var retry_cost: BigMagnitude = retry_command["cost"]
	_check(retry_cost.compare(first_cost) == 0, "命令重试不重算结果", failures)
	_check(GameState.revision == revision_after_command, "命令重试不重复推进 revision", failures)
	var conflict_command := GameState.buy_upgrade("field_level", false, "probe-stale", command_revision)
	_check(String(conflict_command.get("reason", "")) == "REVISION_CONFLICT", "过期 revision 被拒绝", failures)
	_check(GameState.revision == revision_after_command, "revision 冲突不改变状态", failures)

	GameState.initialize_new_game()
	GameState.lineage.historical_realm_unlocks = ["qi_common", "foundation_dan"]
	GameState.run.inherited_history = GameState.lineage.historical_realm_unlocks.duplicate()
	GameState.lineage.breakthrough_failures["golden_one"] = 3
	_check(bool(GameState.choose_target("golden_one").get("ok", false)), "出生历史允许合法金丹目标", failures)
	var golden_requirements := BalanceConfig.material_requirements("golden_one")
	for material_id in golden_requirements:
		GameState.lineage.materials.add(String(material_id), golden_requirements[material_id])
	GameState.run.total_cultivation = BalanceConfig.node_requirement("golden_one")
	GameState.run.body_power = BigMagnitude.from_string("4e24")
	GameState.advance_offline(0.1)
	var golden_breakthrough := GameState.attempt_breakthrough(1)
	_check(bool(golden_breakthrough.get("success", false)), "金丹概率成功进入 pending", failures)
	var tribulation := GameState.begin_tribulation()
	_check(bool(tribulation.get("success", false)), "气血大 1 通过纯 HP 雷劫", failures)
	_check(GameState.run.completed_nodes.has("golden_one"), "雷劫后才写入金丹发现", failures)
	GameState.initialize_new_game()
	GameState.lineage.historical_realm_unlocks = ["qi_common", "foundation_dan"]
	GameState.run.inherited_history = GameState.lineage.historical_realm_unlocks.duplicate()
	GameState.lineage.breakthrough_failures["golden_one"] = 3
	GameState.choose_target("golden_one")
	for material_id in BalanceConfig.material_requirements("golden_one"):
		GameState.lineage.materials.add(String(material_id), BalanceConfig.material_requirements("golden_one")[material_id])
	GameState.run.total_cultivation = BalanceConfig.node_requirement("golden_one")
	var pending_breakthrough := GameState.attempt_breakthrough(1)
	var pending_retry := GameState.attempt_breakthrough(1)
	var pending_report := GameState.advance_offline(1.0)
	_check(bool(pending_breakthrough.get("success", false)) and not GameState.run.pending_tribulation.is_empty(), "气血不足时保留待渡雷劫", failures)
	_check(String(pending_retry.get("reason", "")) == "BREAKTHROUGH_IN_PROGRESS" and pending_retry.get("attempts", []).is_empty(), "待渡雷劫禁止重复突破", failures)
	_check(GameState.run.elapsed_seconds > 0.0 and GameState.run.body_power.is_positive(), "待渡雷劫继续积累体魄", failures)
	_check(String(pending_report.get("stopped_reason", "")) != "AUTOMATION_LOOP", "待渡雷劫不会误判自动化死循环", failures)

	var batch_rates := {"treasure_work_per_second_by_tier": {"common": BigMagnitude.from_float(100.0), "elite": BigMagnitude.zero(), "rare": BigMagnitude.zero()}, "source_stones_by_tier": {"common": BigMagnitude.from_float(10.0), "elite": BigMagnitude.zero(), "rare": BigMagnitude.zero()}}
	var state_a := TreasureState.new()
	var state_b := TreasureState.new()
	var ledger_a := MaterialLedger.new()
	var ledger_b := MaterialLedger.new()
	var run_a := RunState.new()
	var run_b := RunState.new()
	var first := TreasureBatchService.settle(state_a, ledger_a, run_a, batch_rates, 10.0)
	var second := TreasureBatchService.settle(state_a, ledger_a, run_a, batch_rates, 20.0)
	var combined := TreasureBatchService.settle(state_b, ledger_b, run_b, batch_rates, 30.0)
	_check(state_a.chests["common"].equals(combined["chests"]["common"]), "批量宝箱可拆分", failures)
	_check(state_a.entropy_credit["common:fu_qi_dan"].equals(state_b.entropy_credit["common:fu_qi_dan"]), "概率信用可拆分", failures)
	_check((first["stone_gain"] as BigMagnitude).add(second["stone_gain"]).compare(combined["stone_gain"]) == 0, "宝箱灵石可拆分", failures)

	var credit_state := TreasureState.new()
	var credit_ledger := MaterialLedger.new()
	var credit_run := RunState.new()
	credit_run.active_target_id = "qi_common"
	var target_requirement: BigCounter = BalanceConfig.material_requirements("qi_common")["fu_qi_dan"]
	credit_ledger.add_target_credit("qi_common", "fu_qi_dan", target_requirement.to_magnitude())
	var no_chest := TreasureBatchService.settle(credit_state, credit_ledger, credit_run, batch_rates, 0.5)
	_check((no_chest["chests"]["common"] as BigCounter).is_zero(), "目标信用无宝箱时不释放", failures)
	_check(credit_ledger.amount("fu_qi_dan").is_zero(), "目标信用无命中时不入库", failures)
	_check(credit_ledger.target_credit("qi_common", "fu_qi_dan").compare(target_requirement.to_magnitude()) == 0, "目标信用无命中时保留", failures)
	var credit_hit := TreasureBatchService.settle(credit_state, credit_ledger, credit_run, batch_rates, 0.5)
	_check((credit_hit["chests"]["common"] as BigCounter).equals(BigCounter.one()), "目标信用命中一个宝箱", failures)
	_check(credit_ledger.amount("fu_qi_dan").compare(target_requirement) >= 0, "目标信用命中后释放", failures)
	_check(credit_ledger.target_credit("qi_common", "fu_qi_dan").is_zero(), "目标信用命中后清零", failures)

	var generic_rates := {"treasure_work_per_second_by_tier": {"common": BigMagnitude.zero(), "elite": BigMagnitude.from_float(1.0e10), "rare": BigMagnitude.zero()}, "source_stones_by_tier": {"common": BigMagnitude.zero(), "elite": BigMagnitude.zero(), "rare": BigMagnitude.zero()}}
	var generic_state := TreasureState.new()
	var generic_ledger := MaterialLedger.new()
	var generic_run := RunState.new()
	generic_run.inherited_history = ["qi_common"]
	generic_run.active_target_id = "foundation_dan"
	var generic_result := TreasureBatchService.settle(generic_state, generic_ledger, generic_run, generic_rates, 1.0)
	_check(not generic_ledger.amount("jin_yang_hua").is_zero(), "精良箱通用材料实际入账", failures)
	_check(not (generic_result["receipt"] as Dictionary).get("materials", {}).is_empty(), "通用材料进入聚合收据", failures)
	var massive_rates := {"treasure_work_per_second_by_tier": {"common": BigMagnitude.zero(), "elite": BigMagnitude.zero(), "rare": BigMagnitude.from_string("1e100")}, "source_stones_by_tier": {"common": BigMagnitude.zero(), "elite": BigMagnitude.zero(), "rare": BigMagnitude.zero()}}
	var massive_result := TreasureBatchService.settle(TreasureState.new(), MaterialLedger.new(), RunState.new(), massive_rates, 1.0)
	_check((massive_result["chests"]["rare"] as BigCounter).digits.length() > 80, "超大稀有箱批量不按箱循环", failures)

	var save_data := GameState.to_save_dict()
	var saved_revision := GameState.revision
	var pending_tampered := save_data.duplicate(true)
	if pending_tampered.get("run", {}).get("pending_tribulation", {}) is Dictionary and not pending_tampered["run"]["pending_tribulation"].is_empty():
		pending_tampered["run"]["pending_tribulation"]["total_damage"] = "1"
		_check(not bool(SaveValidator.validate(pending_tampered, false).get("ok", false)), "Save 拒绝伪造雷劫伤害", failures)
	_check(GameState.load_save_dict(save_data), "v20 存档往返", failures)
	_check(GameState.revision == saved_revision, "存档 revision 保留", failures)

	var legacy_fixture := {"version": 18, "realm_index": 1, "cultivation": "12345678901234567890", "spirit_stones": "1e25", "qi": "1e12", "total_cultivation_earned": "1e30", "breakthrough_materials": {"recovery_pill": "10"}, "fields": []}
	var migrated_fixture := SaveMigrator.migrate_legacy(legacy_fixture)
	_check(bool(SaveValidator.validate(migrated_fixture, false).get("ok", false)), "v18 迁移候选通过 v20 校验", failures)
	_check(migrated_fixture["lineage"]["historical_realm_unlocks"].has("qi_common"), "v18 迁移保留历史境界", failures)
	_check(String(migrated_fixture["run"]["total_cultivation"].get("d", "")) == "1234567890123456789", "v18 迁移保留大数有效位", failures)

	if failures.is_empty():
		print("BALANCE_PROBE_PASS")
	else:
		for failure in failures:
			push_error(String(failure))
		print("BALANCE_PROBE_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String, failures: Array) -> void:
	if not condition:
		failures.append(message)
