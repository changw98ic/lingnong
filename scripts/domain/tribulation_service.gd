class_name TribulationService
extends RefCounted

## 纯气血雷劫服务。它只接受锁定气血和固定伤害，不读取任何其他状态。

static func strike_damage(total_damage: BigCounter, strike_count: int) -> Array:
	var count := maxi(1, strike_count)
	var result: Array = []
	var quotient := total_damage.divide_int(count)
	var base: BigCounter = quotient["quotient"]
	var remainder := int(quotient["remainder"])
	var accumulated := BigCounter.zero()
	for index in range(count):
		var value := base
		if index < remainder:
			value = value.add(BigCounter.one())
		result.append(value)
		accumulated = accumulated.add(value)
	# 最后一击吸收任何整除残差，保证逐击总和精确。
	if not result.is_empty() and accumulated.compare(total_damage) != 0:
		var difference := total_damage.subtract(accumulated)
		result[result.size() - 1] = (result[result.size() - 1] as BigCounter).add(difference)
	return result


static func evaluate(locked_hp: BigCounter, total_damage: BigCounter) -> Dictionary:
	var comparison := locked_hp.compare(total_damage)
	return {
		"success": comparison > 0,
		"locked_hp": locked_hp,
		"total_damage": total_damage,
		"remaining_hp": locked_hp.subtract(total_damage) if comparison > 0 else BigCounter.zero(),
		"failure_reason": "HP_EQUALS_DAMAGE" if comparison == 0 else ("HP_BELOW_DAMAGE" if comparison < 0 else ""),
	}
