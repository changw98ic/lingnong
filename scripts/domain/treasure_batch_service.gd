class_name TreasureBatchService
extends RefCounted

## 箱子生成即结算。批次复杂度只随箱级、掉落通道和印记边界增长，
## 不随箱子数量线性增长。

static func settle(state: TreasureState, ledger: MaterialLedger, run: RunState, rates: Dictionary, seconds: float) -> Dictionary:
	var result := {
		"chests": {"common": BigCounter.zero(), "elite": BigCounter.zero(), "rare": BigCounter.zero()},
		"stone_gain": BigMagnitude.zero(),
		"body_essence": BigCounter.zero(),
		"spirit_essence": BigCounter.zero(),
		"released_materials": {},
		"dao_marks": BigCounter.zero(),
		"receipt": {},
	}
	if seconds <= 0.0:
		return result
	var rates_by_tier: Dictionary = rates.get("treasure_work_per_second_by_tier", {})
	var source_stones: Dictionary = rates.get("source_stones_by_tier", {})
	for tier in ["common", "elite", "rare"]:
		var rate: BigMagnitude = rates_by_tier.get(tier, BigMagnitude.zero())
		var credit: BigMagnitude = state.work_credit.get(tier, BigMagnitude.zero())
		credit = credit.add(rate.multiply_scalar(seconds))
		var divisor := BalanceConfig.treasure_divisor(tier)
		var chest_count := credit.divide(divisor).floor_to_big_counter()
		if not chest_count.is_zero():
			credit = credit.subtract(chest_count.to_magnitude().multiply(divisor))
			state.chests[tier] = (state.chests.get(tier, BigCounter.zero()) as BigCounter).add(chest_count)
			result["chests"][tier] = chest_count
		state.work_credit[tier] = credit
		var rule: Dictionary = BalanceConfig.TREASURE_RULES.get(tier, {})
		var stone_source: BigMagnitude = source_stones.get(tier, BigMagnitude.zero())
		result["stone_gain"] = (result["stone_gain"] as BigMagnitude).add(stone_source.multiply_scalar(float(rule.get("stone_ratio", 0.0)) * seconds))
		if chest_count.is_zero():
			continue
		var channels: Dictionary = rule.get("channels", {})
		for channel in channels:
			var channel_id := String(channel)
			var probability := float(channels[channel])
			var forced := _force_target_channel(ledger, run.active_target_id, tier, channel_id)
			var grants := _roll_channel(state, tier, channel_id, chest_count, probability, forced)
			if grants.is_zero():
				continue
			_apply_channel_result(result, ledger, run, tier, channel_id, grants)
			# 定向信用只在对应概率通道实际命中后释放；只有箱子而没有命中时保留信用。
			if _is_target_release_channel(channel_id):
				_record_released_materials(result, _release_channel_credit(ledger, run.active_target_id, tier, channel_id))

	# 稀有印记按几何阈值一次计算，复杂度不随箱子数量线性增长。
	var rare_chests: BigCounter = result["chests"]["rare"]
	if not rare_chests.is_zero():
		state.rare_chest_credit = state.rare_chest_credit.add(rare_chests)
		var mark_count := _mark_count(state.rare_chest_credit, state.next_dao_mark_requirement)
		if mark_count > 0:
			var marks := BigCounter.from_int(mark_count)
			var threshold_total := _mark_threshold(state.next_dao_mark_requirement, mark_count)
			state.rare_chest_credit = state.rare_chest_credit.subtract(threshold_total)
			state.dao_mark_count = state.dao_mark_count.add(marks)
			state.next_dao_mark_requirement = state.next_dao_mark_requirement.multiply_counter(BigCounter.pow_int(BalanceConfig.DAO_MARK_GROWTH, mark_count))
			result["dao_marks"] = marks
			ledger.add("dao_mark", marks)

	result["receipt"] = _receipt(result)
	return result


static func _roll_channel(state: TreasureState, tier: String, channel: String, chests: BigCounter, probability: float, force_one := false) -> BigCounter:
	if chests.is_zero():
		return BigCounter.zero()
	if force_one:
		var normal := _roll_channel(state, tier, channel, chests.subtract(BigCounter.one()), probability, false)
		return normal.add(BigCounter.one())
	var key := "%s:%s" % [tier, channel]
	var prior: BigCounter = state.entropy_credit.get(key, BigCounter.zero())
	var numerator := chests.multiply_int(BalanceConfig.probability_numerator(probability))
	var total := prior.add(numerator)
	var split := total.divide_int(BalanceConfig.ENTROPY_SCALE)
	state.entropy_credit[key] = BigCounter.from_int(int(split["remainder"]))
	return split["quotient"]


static func _apply_channel_result(result: Dictionary, ledger: MaterialLedger, run: RunState, tier: String, channel: String, grants: BigCounter) -> void:
	match channel:
		"fu_qi_dan":
			ledger.add("fu_qi_dan", grants)
		"body_pill", "dragon_tiger_pill":
			_grant_pill(result, ledger, run, channel, grants, true if channel == "dragon_tiger_pill" else false)
		"spirit_pill", "nourishing_spirit_pill":
			_grant_pill(result, ledger, run, channel, grants, false)
		"breakthrough_material", "golden_material":
			_grant_generic_material(result, ledger, run, tier, grants)


static func _grant_pill(result: Dictionary, ledger: MaterialLedger, run: RunState, material_id: String, grants: BigCounter, body_channel: bool) -> void:
	if not ledger.auto_essence_conversion:
		ledger.add(material_id, grants)
		return
	var required: BigCounter = BalanceConfig.material_requirements(run.active_target_id).get(material_id, BigCounter.zero())
	var missing := required.subtract(ledger.amount(material_id))
	var retained := grants if grants.compare(missing) <= 0 else missing
	if not retained.is_zero():
		ledger.add(material_id, retained)
	var excess := grants.subtract(retained)
	if excess.is_zero():
		return
	var multiplier := 100 if material_id == "dragon_tiger_pill" or material_id == "nourishing_spirit_pill" else 1
	if body_channel:
		result["body_essence"] = (result["body_essence"] as BigCounter).add(excess.multiply_int(multiplier))
	else:
		result["spirit_essence"] = (result["spirit_essence"] as BigCounter).add(excess.multiply_int(multiplier))


static func _is_target_release_channel(channel: String) -> bool:
	return channel == "fu_qi_dan" or channel == "body_pill" or channel == "spirit_pill" or channel == "dragon_tiger_pill" or channel == "nourishing_spirit_pill" or channel == "breakthrough_material" or channel == "golden_material"


static func _channel_material_ids(node_id: String, tier: String, channel: String) -> Array:
	var ids: Array = []
	if channel in ["fu_qi_dan", "body_pill", "spirit_pill", "dragon_tiger_pill", "nourishing_spirit_pill"]:
		if BalanceConfig.material_tier(channel) == tier:
			ids.append(channel)
		return ids
	if channel != "breakthrough_material" and channel != "golden_material":
		return ids
	for material_id in BalanceConfig.material_requirements(node_id):
		var id := String(material_id)
		# Pill channels have their own independent probability stream. The
		# generic breakthrough stream must not release the same target credit a
		# second time.
		var definition: Dictionary = BalanceConfig.MATERIALS.get(id, {})
		if BalanceConfig.material_tier(id) == tier and not bool(definition.get("is_essence", false)):
			ids.append(id)
	return ids


static func _grant_generic_material(result: Dictionary, ledger: MaterialLedger, run: RunState, tier: String, grants: BigCounter) -> void:
	if grants.is_zero():
		return
	var material_id := _generic_material_id(run, tier)
	if material_id.is_empty():
		return
	# The generic reward is an additional 20% material stream. Ceil keeps a
	# one-hit batch visible while the channel remains independent of target
	# credit release.
	var amount := grants.ceil_div_int(5)
	ledger.add(material_id, amount)
	_record_released_materials(result, {material_id: amount})


static func _generic_material_id(run: RunState, tier: String) -> String:
	var candidates: Array = []
	for definition in BalanceConfig.REALM_NODES:
		var node_id := String(definition.get("id", ""))
		if not run.inherited_history.has(node_id) and not run.completed_nodes.has(node_id) and node_id != run.active_target_id:
			continue
		for material_id in definition.get("materials", {}):
			var id := String(material_id)
			var item: Dictionary = BalanceConfig.MATERIALS.get(id, {})
			if BalanceConfig.material_tier(id) == tier and not bool(item.get("is_essence", false)) and not bool(item.get("dormant", false)) and not candidates.has(id):
				candidates.append(id)
	if candidates.is_empty():
		# Generic rewards never unlock a future route. If the current birth
		# snapshot has no material from this tier, the batch remains a pure
		# chest/stone result until the player reaches a legal target.
		return ""
	return String(candidates[0]) if not candidates.is_empty() else ""


static func _force_target_channel(ledger: MaterialLedger, node_id: String, tier: String, channel: String) -> bool:
	if node_id.is_empty():
		return false
	var requirements := BalanceConfig.material_requirements(node_id)
	for material_id in _channel_material_ids(node_id, tier, channel):
		var required: BigCounter = requirements.get(material_id, BigCounter.zero())
		var missing := required.subtract(ledger.available(material_id))
		if missing.is_zero():
			continue
		var credit := ledger.target_credit(node_id, material_id)
		if credit.floor_to_big_counter().compare(missing) >= 0:
			return true
	return false


static func _release_channel_credit(ledger: MaterialLedger, node_id: String, tier: String, channel: String) -> Dictionary:
	var released := {}
	if node_id.is_empty():
		return released
	var credits: Dictionary = ledger.target_credits.get(node_id, {})
	for material_id in _channel_material_ids(node_id, tier, channel):
		var id := String(material_id)
		var credit: BigMagnitude = credits.get(id, BigMagnitude.zero())
		var whole := credit.floor_to_big_counter()
		if whole.is_zero():
			continue
		ledger.add(id, whole)
		credits[id] = credit.subtract(whole.to_magnitude())
		released[id] = whole
	return released


static func _record_released_materials(result: Dictionary, released: Dictionary) -> void:
	for material_id in released:
		var current: BigCounter = result["released_materials"].get(material_id, BigCounter.zero())
		result["released_materials"][material_id] = current.add(released[material_id])


static func _mark_count(credit: BigCounter, requirement: BigCounter) -> int:
	if requirement.is_zero() or credit.compare(requirement) < 0:
		return 0
	var ratio_log := credit.log10() - requirement.log10()
	var growth_log := log(float(BalanceConfig.DAO_MARK_GROWTH)) / log(10.0)
	var estimate := maxi(1, int(ceil(ratio_log / growth_log)) + 1)
	var low := 0
	var high := estimate
	while _mark_threshold(requirement, high).compare(credit) <= 0:
		low = high
		high *= 2
	while low < high:
		var middle := low + int((high - low + 1) / 2)
		if _mark_threshold(requirement, middle).compare(credit) <= 0:
			low = middle
		else:
			high = middle - 1
	return low


static func _mark_threshold(requirement: BigCounter, mark_count: int) -> BigCounter:
	if mark_count <= 0:
		return BigCounter.zero()
	var power := BigCounter.pow_int(BalanceConfig.DAO_MARK_GROWTH, mark_count)
	return requirement.multiply_counter(power.subtract(BigCounter.one())).divide_int(BalanceConfig.DAO_MARK_GROWTH - 1)["quotient"]


static func _receipt(result: Dictionary) -> Dictionary:
	var chest_text := {}
	for tier in result["chests"]:
		var value: BigCounter = result["chests"][tier]
		if not value.is_zero():
			chest_text[tier] = value.digits
	var material_text := {}
	for material_id in result["released_materials"]:
		var value: BigCounter = result["released_materials"][material_id]
		material_text[String(material_id)] = value.digits
	return {
		"kind": "treasure_batch",
		"chests": chest_text,
		"materials": material_text,
		"body_essence": (result["body_essence"] as BigCounter).digits,
		"spirit_essence": (result["spirit_essence"] as BigCounter).digits,
		"dao_marks": (result["dao_marks"] as BigCounter).digits,
	}
