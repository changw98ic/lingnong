class_name TreasureState
extends RefCounted

const TIERS := ["common", "elite", "rare"]
const CHANNELS := ["fu_qi_dan", "breakthrough_material", "body_pill", "spirit_pill", "dragon_tiger_pill", "nourishing_spirit_pill", "golden_material", "dao_mark"]

var work_credit: Dictionary = {"common": BigMagnitude.zero(), "elite": BigMagnitude.zero(), "rare": BigMagnitude.zero()}
var chests: Dictionary = {"common": BigCounter.zero(), "elite": BigCounter.zero(), "rare": BigCounter.zero()}
var entropy_credit: Dictionary = {}
var total_granted: Dictionary = {}
var rare_chest_credit: BigCounter = BigCounter.zero()
var dao_mark_count: BigCounter = BigCounter.zero()
var next_dao_mark_requirement: BigCounter = BigCounter.from_string(BalanceConfig.DAO_MARK_INITIAL_REQUIREMENT)


func _init() -> void:
	for tier in TIERS:
		if not work_credit.has(tier):
			work_credit[tier] = BigMagnitude.zero()
		if not chests.has(tier):
			chests[tier] = BigCounter.zero()
		for channel in CHANNELS:
			var key := "%s:%s" % [tier, channel]
			if not entropy_credit.has(key):
				entropy_credit[key] = BigCounter.zero()


func initialize_entropy(rng: RandomNumberGenerator) -> void:
	# Each channel receives a deterministic, persisted fixed-point offset once
	# per lineage. This keeps the low-variance stream reproducible without
	# making every new save begin at the same visible chest outcome.
	for tier in TIERS:
		for channel in CHANNELS:
			var key := "%s:%s" % [tier, channel]
			entropy_credit[key] = BigCounter.from_int(rng.randi_range(0, BalanceConfig.ENTROPY_SCALE - 1))


func add_granted(item_id: String, amount: BigCounter) -> void:
	var current: BigCounter = total_granted.get(item_id, BigCounter.zero())
	total_granted[item_id] = current.add(amount)


func to_dict() -> Dictionary:
	var encoded_work := {}
	for tier in work_credit:
		var value: BigMagnitude = work_credit[tier]
		encoded_work[String(tier)] = value.to_dict()
	var encoded_chests := {}
	for tier in chests:
		var value: BigCounter = chests[tier]
		encoded_chests[String(tier)] = value.digits
	var encoded_entropy := {}
	for key in entropy_credit:
		var value: BigCounter = entropy_credit[key]
		encoded_entropy[String(key)] = value.digits
	var encoded_total := {}
	for key in total_granted:
		var value: BigCounter = total_granted[key]
		encoded_total[String(key)] = value.digits
	return {
		"work_credit": encoded_work,
		"chests": encoded_chests,
		"entropy_credit": encoded_entropy,
		"total_granted": encoded_total,
		"rare_chest_credit": rare_chest_credit.digits,
		"dao_mark_count": dao_mark_count.digits,
		"next_dao_mark_requirement": next_dao_mark_requirement.digits,
	}


func load_dict(data: Dictionary) -> void:
	var encoded_work: Dictionary = data.get("work_credit", {}) if data.get("work_credit", {}) is Dictionary else {}
	var encoded_chests: Dictionary = data.get("chests", {}) if data.get("chests", {}) is Dictionary else {}
	work_credit = {}
	chests = {}
	for tier in TIERS:
		work_credit[tier] = BigMagnitude.from_dict(encoded_work.get(tier, 0.0))
		chests[tier] = BigCounter.from_string(String(encoded_chests.get(tier, "0")))
	entropy_credit = {}
	var encoded_entropy: Dictionary = data.get("entropy_credit", {}) if data.get("entropy_credit", {}) is Dictionary else {}
	for key in encoded_entropy:
		var credit := BigCounter.from_string(String(encoded_entropy[key]))
		var normalized := credit.divide_int(BalanceConfig.ENTROPY_SCALE)
		entropy_credit[String(key)] = BigCounter.from_int(int(normalized["remainder"]))
	total_granted = {}
	var encoded_total: Dictionary = data.get("total_granted", {}) if data.get("total_granted", {}) is Dictionary else {}
	for key in encoded_total:
		total_granted[String(key)] = BigCounter.from_string(String(encoded_total[key]))
	rare_chest_credit = BigCounter.from_string(String(data.get("rare_chest_credit", "0")))
	dao_mark_count = BigCounter.from_string(String(data.get("dao_mark_count", "0")))
	next_dao_mark_requirement = BigCounter.from_string(String(data.get("next_dao_mark_requirement", BalanceConfig.DAO_MARK_INITIAL_REQUIREMENT)))
	if next_dao_mark_requirement.is_zero():
		next_dao_mark_requirement = BigCounter.from_string(BalanceConfig.DAO_MARK_INITIAL_REQUIREMENT)
	_init()
