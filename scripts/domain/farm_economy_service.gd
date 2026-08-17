class_name FarmEconomyService
extends RefCounted

## 灵田经济的唯一批量购买入口。
##
## 资源存量始终由 BigMagnitude 承载；buy_max 只使用对数估计定位区间，
## 最终通过 BigMagnitude 比较做单调二分，因此不会把大数转成 float 后少买。

const MAX_UPGRADE_COUNT := 1 << 60


static func next_cost(farm: FarmPortfolio, upgrade_id: String) -> BigMagnitude:
	var rule: Dictionary = BalanceConfig.FIELD_UPGRADES.get(upgrade_id, {})
	if rule.is_empty():
		return BigMagnitude.zero()
	match upgrade_id:
		"field_level":
			var base := _config_magnitude(rule.get("base", "10"), "10")
			var ratio := _config_magnitude(rule.get("ratio", "1.18"), "1.18")
			return base.multiply(ratio.pow_value(float(maxi(0, farm.field_level - 1))))
		"soil_tier":
			return BigMagnitude.pow10(int(rule.get("base_exponent", 3)) + int(rule.get("exponent_step", 2)) * farm.soil_tier)
		"array_level":
			var array_base := _config_magnitude(rule.get("base", "100"), "100")
			var array_ratio := _config_magnitude(rule.get("ratio", "2.2"), "2.2")
			return array_base.multiply(array_ratio.pow_value(float(farm.array_level)))
	return BigMagnitude.zero()


static func buy_one(farm: FarmPortfolio, stones: BigMagnitude, upgrade_id: String) -> Dictionary:
	var cost := next_cost(farm, upgrade_id)
	if cost.is_zero() or stones.compare(cost) < 0:
		return {"bought": false, "cost": cost, "reason": "INSUFFICIENT_STONES"}
	_apply_one(farm, upgrade_id)
	return {"bought": true, "cost": cost, "reason": ""}


static func buy_max(farm: FarmPortfolio, stones: BigMagnitude, upgrade_id: String) -> Dictionary:
	var count := _closed_form_count(farm, stones, upgrade_id)
	if count <= 0:
		return {"bought": 0, "spent": BigMagnitude.zero(), "reason": "INSUFFICIENT_STONES"}
	var spent := _geometric_sum(farm, upgrade_id, count)
	if spent.compare(stones) > 0:
		# This correction is normally reached only at a floating logarithm boundary.
		count = _correct_downward(farm, stones, upgrade_id, count)
		spent = _geometric_sum(farm, upgrade_id, count)
	else:
		# Close the other side of the boundary without iterating over levels.
		var next_spent := _geometric_sum(farm, upgrade_id, count + 1)
		if next_spent.compare(stones) <= 0:
			count = _correct_upward(farm, stones, upgrade_id, count)
			spent = _geometric_sum(farm, upgrade_id, count)
	if count <= 0:
		return {"bought": 0, "spent": BigMagnitude.zero(), "reason": "INSUFFICIENT_STONES"}
	_apply_count(farm, upgrade_id, count)
	return {"bought": count, "spent": spent, "reason": ""}


static func auto_purchase(farm: FarmPortfolio, stones: BigMagnitude, policy: AutomationPolicyState, snapshot: Dictionary) -> Dictionary:
	var budget := stones.multiply_scalar(clampf(policy.purchase_budget_ratio, 0.0, 1.0))
	var best_id := ""
	var best_payback := INF
	for upgrade_id in policy.purchase_priority:
		var id := String(upgrade_id)
		var cost := next_cost(farm, id)
		if cost.is_zero() or budget.compare(cost) < 0:
			continue
		var increase := _rate_increase(farm, snapshot, id)
		if increase.is_zero():
			continue
		var payback := cost.log10() - increase.log10()
		if payback < best_payback:
			best_payback = payback
			best_id = id
	if best_id.is_empty():
		return {"changed": false, "spent": BigMagnitude.zero(), "upgrade_id": ""}
	var result := buy_max(farm, budget, best_id)
	return {"changed": int(result.get("bought", 0)) > 0, "spent": result.get("spent", BigMagnitude.zero()), "upgrade_id": best_id}


static func _closed_form_count(farm: FarmPortfolio, available: BigMagnitude, upgrade_id: String) -> int:
	var base := next_cost(farm, upgrade_id)
	if base.is_zero() or available.compare(base) < 0:
		return 0
	var ratio := _upgrade_ratio(upgrade_id)
	if ratio.compare(BigMagnitude.one()) <= 0:
		return _counter_to_safe_int(available.divide(base).floor_to_big_counter())
	var ratio_minus_one := ratio.subtract(BigMagnitude.one())
	var term := available.divide(base).multiply(ratio_minus_one)
	var ratio_log := ratio.log10()
	if ratio_log <= 0.0:
		return 0
	var estimate_value: float = floor(_log10_one_plus(term) / ratio_log)
	var estimate := _safe_nonnegative_int(estimate_value)
	return _correct_count(farm, available, upgrade_id, estimate)


static func _correct_count(farm: FarmPortfolio, available: BigMagnitude, upgrade_id: String, estimate: int) -> int:
	var low := 0
	var high := maxi(1, estimate + 2)
	if high > MAX_UPGRADE_COUNT:
		high = MAX_UPGRADE_COUNT
	while _geometric_sum(farm, upgrade_id, high).compare(available) <= 0 and high < MAX_UPGRADE_COUNT:
		low = high
		high = mini(MAX_UPGRADE_COUNT, high * 2)
		if high == low:
			break
	while low + 1 < high:
		var middle := low + int((high - low) / 2)
		if _geometric_sum(farm, upgrade_id, middle).compare(available) <= 0:
			low = middle
		else:
			high = middle
	return low if _geometric_sum(farm, upgrade_id, high).compare(available) > 0 else high


static func _correct_downward(farm: FarmPortfolio, available: BigMagnitude, upgrade_id: String, count: int) -> int:
	var high := maxi(0, count)
	var low := 0
	while low < high:
		var middle := low + int((high - low + 1) / 2)
		if _geometric_sum(farm, upgrade_id, middle).compare(available) <= 0:
			low = middle
		else:
			high = middle - 1
	return low


static func _correct_upward(farm: FarmPortfolio, available: BigMagnitude, upgrade_id: String, count: int) -> int:
	var low := maxi(0, count)
	var high := mini(MAX_UPGRADE_COUNT, maxi(1, count * 2))
	while high < MAX_UPGRADE_COUNT and _geometric_sum(farm, upgrade_id, high).compare(available) <= 0:
		low = high
		high = mini(MAX_UPGRADE_COUNT, high * 2)
		if high == low:
			break
	while low + 1 < high:
		var middle := low + int((high - low) / 2)
		if _geometric_sum(farm, upgrade_id, middle).compare(available) <= 0:
			low = middle
		else:
			high = middle
	return low


static func _geometric_sum(farm: FarmPortfolio, upgrade_id: String, count: int) -> BigMagnitude:
	if count <= 0:
		return BigMagnitude.zero()
	var base := next_cost(farm, upgrade_id)
	var ratio := _upgrade_ratio(upgrade_id)
	if ratio.compare(BigMagnitude.one()) == 0:
		return base.multiply(BigMagnitude.from_exact_integer(str(count)))
	# Compute 1 + r + ... + r^(count - 1) by binary block composition.
	# This is O(log count) and stays exact, unlike a float division of the
	# closed form at a purchase boundary.
	var remaining := count
	var block_power := ratio.duplicate_value() # r^1
	var block_sum := BigMagnitude.one() # 1 + ... + r^0
	var accumulated_power := BigMagnitude.one() # r^0
	var accumulated_sum := BigMagnitude.zero()
	while remaining > 0:
		if remaining % 2 == 1:
			accumulated_sum = accumulated_sum.add(accumulated_power.multiply(block_sum))
			accumulated_power = accumulated_power.multiply(block_power)
		remaining = int(remaining / 2)
		if remaining > 0:
			block_sum = block_sum.add(block_power.multiply(block_sum))
			block_power = block_power.multiply(block_power)
	return base.multiply(accumulated_sum)


static func _upgrade_ratio(upgrade_id: String) -> BigMagnitude:
	var rule: Dictionary = BalanceConfig.FIELD_UPGRADES.get(upgrade_id, {})
	match upgrade_id:
		"field_level", "array_level":
			return _config_magnitude(rule.get("ratio", "1"), "1")
		"soil_tier":
			return BigMagnitude.pow10(int(rule.get("exponent_step", 0)))
	return BigMagnitude.one()


static func _log10_one_plus(value: BigMagnitude) -> float:
	if value.is_zero():
		return 0.0
	var value_log := value.log10()
	if value_log > 12.0:
		return value_log
	return log(1.0 + value.to_float()) / log(10.0)


static func _config_magnitude(value: Variant, fallback: String) -> BigMagnitude:
	var text := fallback if value == null else String(value)
	return BigMagnitude.from_string(text)


static func _safe_nonnegative_int(value: float) -> int:
	if is_nan(value) or value <= 0.0:
		return 0
	if is_inf(value) or value >= float(MAX_UPGRADE_COUNT):
		return MAX_UPGRADE_COUNT
	return int(value)


static func _counter_to_safe_int(value: BigCounter) -> int:
	if value.digits.length() >= 19:
		return MAX_UPGRADE_COUNT
	return maxi(0, int(value.digits))


static func _apply_one(farm: FarmPortfolio, upgrade_id: String) -> void:
	match upgrade_id:
		"field_level": farm.field_level += 1
		"soil_tier":
			farm.soil_tier += 1
			for cohort in farm.cohorts:
				cohort["upgrade_tier"] = farm.soil_tier
		"array_level": farm.array_level += 1


static func _apply_count(farm: FarmPortfolio, upgrade_id: String, count: int) -> void:
	if count <= 0:
		return
	match upgrade_id:
		"field_level": farm.field_level += count
		"soil_tier":
			farm.soil_tier += count
			for cohort in farm.cohorts:
				cohort["upgrade_tier"] = farm.soil_tier
		"array_level": farm.array_level += count


static func _rate_increase(farm: FarmPortfolio, snapshot: Dictionary, upgrade_id: String) -> BigMagnitude:
	var current: BigMagnitude = snapshot.get("cultivation_per_second", BigMagnitude.zero())
	var rule: Dictionary = BalanceConfig.FIELD_UPGRADES.get(upgrade_id, {})
	match upgrade_id:
		"field_level":
			return current.divide_scalar(float(maxi(1, farm.field_level)))
		"soil_tier", "array_level":
			var multiplier := _upgrade_ratio(upgrade_id)
			return current.multiply(multiplier.subtract(BigMagnitude.one()))
	return BigMagnitude.zero()
