class_name MaterialLedger
extends RefCounted

var on_hand: Dictionary = {}
var reserved: Dictionary = {}
var escrow: Dictionary = {}
var lifetime_earned: Dictionary = {}
var lifetime_spent: Dictionary = {}
var target_credits: Dictionary = {}
var auto_essence_conversion := true


func _init() -> void:
	ensure_keys()


func ensure_keys() -> void:
	for material_id in BalanceConfig.MATERIALS:
		var id := String(material_id)
		if bool(BalanceConfig.MATERIALS[id].get("dormant", false)):
			# Dormant migration-only items are added only when a legacy save
			# actually contains them; they must not appear in new inventories.
			continue
		if not on_hand.has(id):
			on_hand[id] = BigCounter.zero()
		if not reserved.has(id):
			reserved[id] = BigCounter.zero()
		if not escrow.has(id):
			escrow[id] = BigCounter.zero()
		if not lifetime_earned.has(id):
			lifetime_earned[id] = BigCounter.zero()
		if not lifetime_spent.has(id):
			lifetime_spent[id] = BigCounter.zero()


func amount(material_id: String) -> BigCounter:
	ensure_keys()
	return on_hand.get(material_id, BigCounter.zero())


func available(material_id: String) -> BigCounter:
	var current: BigCounter = amount(material_id)
	var reserved_value: BigCounter = reserved.get(material_id, BigCounter.zero())
	return current.subtract(reserved_value)


func can_afford(requirements: Dictionary) -> bool:
	for material_id in requirements:
		var required: BigCounter = requirements[material_id]
		if available(String(material_id)).compare(required) < 0:
			return false
	return true


func add(material_id: String, value: BigCounter) -> void:
	ensure_keys()
	var id := String(material_id)
	on_hand[id] = amount(id).add(value)
	lifetime_earned[id] = (lifetime_earned.get(id, BigCounter.zero()) as BigCounter).add(value)


func subtract(material_id: String, value: BigCounter) -> bool:
	ensure_keys()
	var id := String(material_id)
	if amount(id).compare(value) < 0:
		return false
	on_hand[id] = amount(id).subtract(value)
	lifetime_spent[id] = (lifetime_spent.get(id, BigCounter.zero()) as BigCounter).add(value)
	return true


func reserve_for(node_id: String, requirements: Dictionary) -> bool:
	if not can_afford(requirements):
		return false
	for material_id in requirements:
		var id := String(material_id)
		reserved[id] = (reserved.get(id, BigCounter.zero()) as BigCounter).add(requirements[material_id])
	target_credits[node_id] = target_credits.get(node_id, {})
	return true


func release_reservation(node_id: String, requirements: Dictionary) -> void:
	for material_id in requirements:
		var id := String(material_id)
		reserved[id] = (reserved.get(id, BigCounter.zero()) as BigCounter).subtract(requirements[material_id])


func refresh_hard_pity_reservation(requirements: Dictionary, hard_pity: int, failure_count: int) -> void:
	# Reserve only the additional main-material loss that can still happen
	# after the next attempt. The current full set remains available, so a
	# reservation never blocks an otherwise affordable attempt.
	for material_id in requirements:
		var id := String(material_id)
		reserved[id] = BigCounter.zero()
	if requirements.is_empty():
		return
	var main_id := String(requirements.keys()[0])
	var main_requirement: BigCounter = requirements[main_id]
	var failure_loss := main_requirement.ceil_div_int(20)
	var remaining_failures := maxi(0, hard_pity - failure_count - 1)
	var desired := failure_loss.multiply_int(remaining_failures)
	var surplus := amount(main_id).subtract(main_requirement)
	reserved[main_id] = desired if desired.compare(surplus) <= 0 else surplus


func clear_hard_pity_reservation(requirements: Dictionary) -> void:
	for material_id in requirements:
		reserved[String(material_id)] = BigCounter.zero()


func begin_escrow(requirements: Dictionary) -> bool:
	if not can_afford(requirements):
		return false
	for material_id in requirements:
		var id := String(material_id)
		var value: BigCounter = requirements[material_id]
		on_hand[id] = amount(id).subtract(value)
		escrow[id] = (escrow.get(id, BigCounter.zero()) as BigCounter).add(value)
	return true


func settle_escrow_success(requirements: Dictionary) -> void:
	for material_id in requirements:
		var id := String(material_id)
		var value: BigCounter = requirements[material_id]
		escrow[id] = (escrow.get(id, BigCounter.zero()) as BigCounter).subtract(value)
		lifetime_spent[id] = (lifetime_spent.get(id, BigCounter.zero()) as BigCounter).add(value)


func settle_escrow_failure(requirements: Dictionary, main_material_id: String) -> void:
	for material_id in requirements:
		var id := String(material_id)
		var value: BigCounter = requirements[material_id]
		var consumed := BigCounter.zero()
		if id == main_material_id:
			consumed = value.ceil_div_int(20)
		var refund := value.subtract(consumed)
		escrow[id] = (escrow.get(id, BigCounter.zero()) as BigCounter).subtract(value)
		on_hand[id] = amount(id).add(refund)
		lifetime_spent[id] = (lifetime_spent.get(id, BigCounter.zero()) as BigCounter).add(consumed)


func add_target_credit(node_id: String, material_id: String, value: BigMagnitude) -> void:
	if value.is_zero():
		return
	if not target_credits.has(node_id):
		target_credits[node_id] = {}
	var credits: Dictionary = target_credits[node_id]
	var current: BigMagnitude = credits.get(material_id, BigMagnitude.zero())
	credits[material_id] = current.add(value)


func target_credit(node_id: String, material_id: String) -> BigMagnitude:
	var credits: Dictionary = target_credits.get(node_id, {})
	return credits.get(material_id, BigMagnitude.zero())


func release_target_credit(node_id: String, source_tier: String, limit: BigCounter = null) -> Dictionary:
	var released := {}
	var credits: Dictionary = target_credits.get(node_id, {})
	for material_id in credits:
		if BalanceConfig.material_tier(String(material_id)) != source_tier:
			continue
		var credit: BigMagnitude = credits[material_id]
		var whole := credit.floor_to_big_counter()
		if limit != null and whole.compare(limit) > 0:
			whole = limit.duplicate_value()
		if whole.is_zero():
			continue
		add(String(material_id), whole)
		credits[material_id] = credit.subtract(whole.to_magnitude())
		released[String(material_id)] = whole
	return released


func to_dict() -> Dictionary:
	return {
		"on_hand": _encode_counter_map(on_hand),
		"reserved": _encode_counter_map(reserved),
		"escrow": _encode_counter_map(escrow),
		"lifetime_earned": _encode_counter_map(lifetime_earned),
		"lifetime_spent": _encode_counter_map(lifetime_spent),
		"target_credits": _encode_credit_map(),
		"auto_essence_conversion": auto_essence_conversion,
	}


func load_dict(data: Variant) -> void:
	on_hand = _decode_counter_map(data.get("on_hand", {}) if data is Dictionary else {})
	reserved = _decode_counter_map(data.get("reserved", {}) if data is Dictionary else {})
	escrow = _decode_counter_map(data.get("escrow", {}) if data is Dictionary else {})
	lifetime_earned = _decode_counter_map(data.get("lifetime_earned", {}) if data is Dictionary else {})
	lifetime_spent = _decode_counter_map(data.get("lifetime_spent", {}) if data is Dictionary else {})
	target_credits = _decode_credit_map(data.get("target_credits", {}) if data is Dictionary else {})
	auto_essence_conversion = bool(data.get("auto_essence_conversion", true)) if data is Dictionary else true
	ensure_keys()


func _encode_counter_map(values: Dictionary) -> Dictionary:
	var output := {}
	for key in values:
		var value: BigCounter = values[key]
		output[String(key)] = value.digits
	return output


func _decode_counter_map(values: Variant) -> Dictionary:
	var output := {}
	if values is Dictionary:
		for key in values:
			output[String(key)] = BigCounter.from_string(String(values[key]))
	return output


func _encode_credit_map() -> Dictionary:
	var output := {}
	for node_id in target_credits:
		var node_output := {}
		var credits: Dictionary = target_credits[node_id]
		for material_id in credits:
			var value: BigMagnitude = credits[material_id]
			node_output[String(material_id)] = value.to_dict()
		output[String(node_id)] = node_output
	return output


func _decode_credit_map(value: Variant) -> Dictionary:
	var output := {}
	if not value is Dictionary:
		return output
	for node_id in value:
		var credits := {}
		var source = value[node_id]
		if source is Dictionary:
			for material_id in source:
				credits[String(material_id)] = BigMagnitude.from_dict(source[material_id])
		output[String(node_id)] = credits
	return output
