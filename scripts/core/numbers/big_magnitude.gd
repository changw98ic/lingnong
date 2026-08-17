class_name BigMagnitude
extends RefCounted

## 非负规范化十进制数量。
##
## mantissa/exponent 用于连续计算和显示；exact_digits 保存同一个规范化
## 十进制值的全部已知有效位。凡是要进入整数边界的操作，都只读取
## exact_digits 和 exponent，不使用 float 比较或截断有效位。

const FLOAT_DECIMAL_PLACES := 17
const FLOAT_EXACT_DECIMAL_PLACES := 15
const MAX_EXACT_ALIGNMENT_DIGITS := 1000000
const MAX_FLOAT_EXPONENT := 308

var mantissa: float = 0.0
var exponent: int = 0
## D * 10^(exponent - (D.length() - 1)) is the represented value.
var exact_digits: String = ""


func _init(value: Variant = 0.0, value_exponent: int = 0) -> void:
	if value is BigMagnitude:
		mantissa = value.mantissa
		exponent = value.exponent
		exact_digits = value.exact_digits
		return
	if value is Dictionary:
		if value.has("d"):
			_set_exact(String(value.get("d", "")), int(value.get("e", value.get("exponent", 0))))
		else:
			mantissa = float(value.get("m", value.get("mantissa", 0.0)))
			exponent = int(value.get("e", value.get("exponent", 0)))
			normalize()
		return
	if value is String:
		var parsed := BigMagnitude.from_string(value)
		mantissa = parsed.mantissa
		exponent = parsed.exponent
		exact_digits = parsed.exact_digits
		return
	mantissa = float(value)
	exponent = value_exponent
	normalize()


static func zero() -> BigMagnitude:
	return BigMagnitude.new(0.0)


static func one() -> BigMagnitude:
	return BigMagnitude.new(1.0)


static func from_float(value: float) -> BigMagnitude:
	return BigMagnitude.new(value)


static func from_parts(value_mantissa: float, value_exponent: int) -> BigMagnitude:
	return BigMagnitude.new(value_mantissa, value_exponent)


static func from_exact_integer(digits: String) -> BigMagnitude:
	return BigMagnitude.from_string(digits)


static func pow10(value_exponent: int) -> BigMagnitude:
	return BigMagnitude.new(1.0, value_exponent)


static func from_string(text: String) -> BigMagnitude:
	var parsed := _parse_decimal(text)
	if not bool(parsed.get("valid", false)):
		return BigMagnitude.zero()
	var value := BigMagnitude.new(0.0)
	value._set_exact(String(parsed.get("digits", "")), int(parsed.get("exponent", 0)))
	return value


static func from_dict(data: Variant) -> BigMagnitude:
	if data is BigMagnitude:
		return BigMagnitude.new(data)
	if data is Dictionary:
		return BigMagnitude.new(data)
	if data is String:
		return BigMagnitude.from_string(data)
	return BigMagnitude.new(float(data))


func duplicate_value() -> BigMagnitude:
	return BigMagnitude.new(self)


func normalize() -> BigMagnitude:
	if not exact_digits.is_empty():
		_normalize_exact()
		return self
	if is_nan(mantissa) or is_inf(mantissa) or mantissa <= 0.0:
		mantissa = 0.0
		exponent = 0
		exact_digits = ""
		return self
	while mantissa >= 10.0:
		mantissa /= 10.0
		exponent += 1
	while mantissa < 1.0:
		mantissa *= 10.0
		exponent -= 1
	_sync_exact_from_float()
	return self


func is_zero() -> bool:
	return exact_digits.is_empty() and mantissa == 0.0


func is_positive() -> bool:
	return not is_zero()


func compare(other: BigMagnitude) -> int:
	_ensure_exact()
	other._ensure_exact()
	if is_zero() and other.is_zero():
		return 0
	if is_zero():
		return -1
	if other.is_zero():
		return 1
	# exponent is the position of the most significant decimal digit, so it
	# decides the order before any mantissa comparison is needed.
	if exponent != other.exponent:
		return 1 if exponent > other.exponent else -1
	var width := maxi(exact_digits.length(), other.exact_digits.length())
	var left := exact_digits + "0".repeat(width - exact_digits.length())
	var right := other.exact_digits + "0".repeat(width - other.exact_digits.length())
	if left == right:
		return 0
	return 1 if left > right else -1


func equals(other: BigMagnitude) -> bool:
	return compare(other) == 0


func add(other: BigMagnitude) -> BigMagnitude:
	_ensure_exact()
	other._ensure_exact()
	if is_zero():
		return other.duplicate_value()
	if other.is_zero():
		return duplicate_value()
	var left_power := _decimal_power()
	var right_power := other._decimal_power()
	var base_power := mini(left_power, right_power)
	var left_shift := left_power - base_power
	var right_shift := right_power - base_power
	if maxi(left_shift, right_shift) > MAX_EXACT_ALIGNMENT_DIGITS:
		# The smaller term is below the least significant known decimal place of
		# the larger term. It cannot change that term's integer floor.
		return duplicate_value() if compare(other) >= 0 else other.duplicate_value()
	var left_digits := exact_digits + "0".repeat(left_shift)
	var right_digits := other.exact_digits + "0".repeat(right_shift)
	return _from_scaled_digits(_add_digit_strings(left_digits, right_digits), base_power)


func subtract(other: BigMagnitude) -> BigMagnitude:
	_ensure_exact()
	other._ensure_exact()
	if other.is_zero():
		return duplicate_value()
	if compare(other) <= 0:
		return BigMagnitude.zero()
	var left_power := _decimal_power()
	var right_power := other._decimal_power()
	var base_power := mini(left_power, right_power)
	var left_shift := left_power - base_power
	var right_shift := right_power - base_power
	if maxi(left_shift, right_shift) > MAX_EXACT_ALIGNMENT_DIGITS:
		# As in add(), the discarded term is far below the represented boundary
		# and cannot change floor_to_big_counter().
		return duplicate_value()
	var left_digits := exact_digits + "0".repeat(left_shift)
	var right_digits := other.exact_digits + "0".repeat(right_shift)
	return _from_scaled_digits(_subtract_digit_strings(left_digits, right_digits), base_power)


func multiply(other: BigMagnitude) -> BigMagnitude:
	_ensure_exact()
	other._ensure_exact()
	if is_zero() or other.is_zero():
		return BigMagnitude.zero()
	if exact_digits.length() + other.exact_digits.length() > MAX_EXACT_ALIGNMENT_DIGITS:
		return BigMagnitude.new(mantissa * other.mantissa, exponent + other.exponent)
	var product := _multiply_digit_strings(exact_digits, other.exact_digits)
	return _from_scaled_digits(product, _decimal_power() + other._decimal_power())


func multiply_scalar(value: float) -> BigMagnitude:
	if is_nan(value) or is_inf(value) or value <= 0.0 or is_zero():
		return BigMagnitude.zero()
	return multiply(BigMagnitude.from_float(value))


func divide(other: BigMagnitude) -> BigMagnitude:
	if other.is_zero() or is_zero():
		return BigMagnitude.zero()
	_ensure_exact()
	other._ensure_exact()
	# Power-of-ten divisors are common in chest settlement. Adjusting the
	# decimal power keeps the quotient exact instead of routing it through a
	# rounded float.
	if other.exact_digits == "1":
		return _from_scaled_digits(exact_digits, _decimal_power() - other.exponent)
	return BigMagnitude.new(mantissa / other.mantissa, exponent - other.exponent)


func divide_scalar(value: float) -> BigMagnitude:
	if is_nan(value) or is_inf(value) or value <= 0.0 or is_zero():
		return BigMagnitude.zero()
	var scalar := BigMagnitude.from_float(value)
	if scalar.exact_digits == "1":
		return divide(scalar)
	return BigMagnitude.new(mantissa / value, exponent)


func pow_value(value: float) -> BigMagnitude:
	if is_zero():
		return BigMagnitude.zero()
	if is_nan(value) or is_inf(value):
		return BigMagnitude.zero()
	if value >= 0.0 and value == floor(value) and value <= 64.0:
		var result := BigMagnitude.one()
		var factor := duplicate_value()
		var remaining := int(value)
		while remaining > 0:
			if remaining % 2 == 1:
				result = result.multiply(factor)
			remaining = int(remaining / 2)
			if remaining > 0:
				factor = factor.multiply(factor)
		return result
	var result_log10 := log10() * value
	var result_exponent := int(floor(result_log10))
	var result_mantissa := pow(10.0, result_log10 - float(result_exponent))
	return BigMagnitude.new(result_mantissa, result_exponent)


func pow(value: float) -> BigMagnitude:
	return pow_value(value)


func sqrt_value() -> BigMagnitude:
	return pow_value(0.5)


func sqrt() -> BigMagnitude:
	return sqrt_value()


func log10() -> float:
	if is_zero():
		return 0.0
	return float(exponent) + log(mantissa) / log(10.0)


func to_float() -> float:
	if is_zero():
		return 0.0
	if exponent > MAX_FLOAT_EXPONENT:
		return INF
	if exponent < -MAX_FLOAT_EXPONENT:
		return 0.0
	return mantissa * pow(10.0, float(exponent))


func to_int64_checked() -> int:
	if is_zero() or exponent < 0 or exponent > 18:
		return -1
	var whole := floor_to_big_counter()
	if whole.digits.length() > 18:
		return -1
	return int(whole.digits)


func floor_to_big_counter() -> BigCounter:
	var counter_script = preload("res://scripts/core/numbers/big_counter.gd")
	_ensure_exact()
	if is_zero() or exponent < 0:
		return counter_script.from_int(0)
	var keep := exponent + 1
	if keep <= 0:
		return counter_script.from_int(0)
	if keep >= exact_digits.length():
		return counter_script.from_string(exact_digits + "0".repeat(keep - exact_digits.length()))
	return counter_script.from_string(exact_digits.substr(0, keep))


func ceil_to_big_counter() -> BigCounter:
	var floor_value := floor_to_big_counter()
	if is_zero():
		return floor_value
	if exponent < 0:
		return floor_value.add(BigCounter.one())
	var keep := exponent + 1
	if keep >= exact_digits.length():
		return floor_value
	for index in range(keep, exact_digits.length()):
		if exact_digits[index] != "0":
			return floor_value.add(BigCounter.one())
	return floor_value


static func pow10_magnitude(value: BigMagnitude) -> BigMagnitude:
	if value.is_zero():
		return BigMagnitude.one()
	var exponent_value := value.to_float()
	if is_inf(exponent_value) or exponent_value >= 2147483000.0:
		return BigMagnitude.from_parts(1.0, 2147483000)
	var whole := int(floor(exponent_value))
	var fraction := exponent_value - float(whole)
	return BigMagnitude.pow10(whole).multiply_scalar(pow(10.0, fraction))


func to_dict() -> Dictionary:
	_ensure_exact()
	return {
		"m": String.num(mantissa, FLOAT_EXACT_DECIMAL_PLACES),
		"e": exponent,
		"d": exact_digits,
	}


func to_scientific_string(precision: int = 3) -> String:
	if is_zero():
		return "0"
	return "%se%s" % [String.num(mantissa, precision), str(exponent)]


func _to_string() -> String:
	return to_scientific_string(4)


func _set_exact(digits: String, value_exponent: int) -> void:
	exact_digits = digits
	exponent = value_exponent
	_normalize_exact()


func _normalize_exact() -> void:
	var cleaned := exact_digits.strip_edges()
	if cleaned.is_empty():
		mantissa = 0.0
		exponent = 0
		exact_digits = ""
		return
	for index in range(cleaned.length()):
		if not _is_digit(cleaned[index]):
			mantissa = 0.0
			exponent = 0
			exact_digits = ""
			return
	var first := 0
	while first < cleaned.length() and cleaned[first] == "0":
		first += 1
	if first >= cleaned.length():
		mantissa = 0.0
		exponent = 0
		exact_digits = ""
		return
	cleaned = cleaned.substr(first)
	# Removing leading zeroes does not change value_exponent: callers pass the
	# exponent of the first significant digit. Trailing zeroes are removed for
	# canonical form, while that same exponent is deliberately preserved.
	while cleaned.length() > 1 and cleaned.ends_with("0"):
		cleaned = cleaned.substr(0, cleaned.length() - 1)
	exact_digits = cleaned
	var take := mini(FLOAT_DECIMAL_PLACES, cleaned.length())
	var head := float(cleaned.substr(0, take))
	mantissa = head / pow(10.0, float(take - 1))


func _sync_exact_from_float() -> void:
	if mantissa <= 0.0 or is_nan(mantissa) or is_inf(mantissa):
		exact_digits = ""
		return
	# A binary float such as 0.015 or 1.18 is an input approximation, not a
	# gameplay decimal. Round it to a stable decimal before making it exact so
	# material-credit and purchase boundaries do not inherit binary noise.
	var parsed := _parse_decimal(String.num(mantissa, FLOAT_EXACT_DECIMAL_PLACES))
	if not bool(parsed.get("valid", false)):
		exact_digits = ""
		return
	_set_exact(String(parsed.get("digits", "")), exponent + int(parsed.get("exponent", 0)))


func _ensure_exact() -> void:
	if exact_digits.is_empty() and mantissa > 0.0:
		_sync_exact_from_float()


func _decimal_power() -> int:
	return exponent - (exact_digits.length() - 1)


static func _from_scaled_digits(digits: String, power: int) -> BigMagnitude:
	var value := BigMagnitude.new(0.0)
	if digits.is_empty():
		return value
	var first := 0
	while first < digits.length() and digits[first] == "0":
		first += 1
	if first >= digits.length():
		return value
	var significant := digits.substr(first)
	value._set_exact(significant, power + significant.length() - 1)
	return value


static func _add_digit_strings(left: String, right: String) -> String:
	var i := left.length() - 1
	var j := right.length() - 1
	var carry := 0
	var output := ""
	while i >= 0 or j >= 0 or carry > 0:
		var a := int(left[i]) if i >= 0 else 0
		var b := int(right[j]) if j >= 0 else 0
		var total := a + b + carry
		output = str(total % 10) + output
		carry = int(total / 10)
		i -= 1
		j -= 1
	return output


static func _subtract_digit_strings(left: String, right: String) -> String:
	var i := left.length() - 1
	var j := right.length() - 1
	var borrow := 0
	var output := ""
	while i >= 0:
		var a := int(left[i]) - borrow
		var b := int(right[j]) if j >= 0 else 0
		if a < b:
			a += 10
			borrow = 1
		else:
			borrow = 0
		output = str(a - b) + output
		i -= 1
		j -= 1
	var first := 0
	while first < output.length() - 1 and output[first] == "0":
		first += 1
	return output.substr(first)


static func _multiply_digit_strings(left: String, right: String) -> String:
	var output := PackedInt32Array()
	output.resize(left.length() + right.length())
	for index in range(output.size()):
		output[index] = 0
	for i in range(left.length() - 1, -1, -1):
		for j in range(right.length() - 1, -1, -1):
			output[i + j + 1] += int(left[i]) * int(right[j])
	for index in range(output.size() - 1, 0, -1):
		var carry := int(output[index] / 10)
		output[index] %= 10
		output[index - 1] += carry
	var text := ""
	for value in output:
		text += str(value)
	return text


static func _parse_decimal(text: String) -> Dictionary:
	var source := text.strip_edges().to_lower()
	if source.is_empty():
		return {"valid": false}
	if source.begins_with("+"):
		source = source.substr(1)
	if source.begins_with("-"):
		return {"valid": false}
	var exponent_adjust := 0
	var e_pos := source.find("e")
	if e_pos >= 0:
		var exponent_text := source.substr(e_pos + 1)
		if exponent_text.is_empty() or not exponent_text.is_valid_int():
			return {"valid": false}
		exponent_adjust = int(exponent_text)
		source = source.substr(0, e_pos)
	var dot_pos := source.find(".")
	if dot_pos >= 0 and source.find(".", dot_pos + 1) >= 0:
		return {"valid": false}
	var integer_part := source if dot_pos < 0 else source.substr(0, dot_pos)
	var fractional_part := "" if dot_pos < 0 else source.substr(dot_pos + 1)
	if integer_part.is_empty():
		integer_part = "0"
	var raw_digits := integer_part + fractional_part
	if raw_digits.is_empty():
		return {"valid": false}
	for index in range(raw_digits.length()):
		if not _is_digit(raw_digits[index]):
			return {"valid": false}
	var first_non_zero := 0
	while first_non_zero < raw_digits.length() and raw_digits[first_non_zero] == "0":
		first_non_zero += 1
	if first_non_zero >= raw_digits.length():
		return {"valid": true, "digits": "", "exponent": 0}
	var digits := raw_digits.substr(first_non_zero)
	var value_exponent := integer_part.length() - first_non_zero - 1 + exponent_adjust
	return {"valid": true, "digits": digits, "exponent": value_exponent}


static func _is_digit(value: String) -> bool:
	return value.length() == 1 and "0123456789".find(value) >= 0
