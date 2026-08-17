class_name BigCounter
extends RefCounted

## 精确的非负十进制整数。
##
## digits 是唯一的数值来源，并且始终是没有前导零的 ASCII 十进制字符串。
## 所有会进入领域边界的整数比较都在字符串上完成，不经过 float。

var digits: String = "0"


func _init(value: Variant = 0) -> void:
	if value is BigCounter:
		digits = value.digits
		return
	if value is Dictionary:
		digits = String(value.get("value", value.get("digits", "0")))
		normalize()
		return
	if value is int:
		digits = str(maxi(0, value))
		normalize()
		return
	digits = String(value)
	normalize()


static func zero() -> BigCounter:
	return BigCounter.new("0")


static func one() -> BigCounter:
	return BigCounter.new("1")


static func from_int(value: int) -> BigCounter:
	return BigCounter.new(maxi(0, value))


static func from_string(value: String) -> BigCounter:
	return BigCounter.new(value)


static func from_magnitude(value: BigMagnitude) -> BigCounter:
	return value.floor_to_big_counter()


func duplicate_value() -> BigCounter:
	return BigCounter.new(digits)


func normalize() -> BigCounter:
	var cleaned := digits.strip_edges()
	if cleaned.is_empty():
		digits = "0"
		return self
	var start := 0
	while start < cleaned.length() and cleaned[start] == "0":
		start += 1
	if start >= cleaned.length():
		digits = "0"
		return self
	cleaned = cleaned.substr(start)
	for index in range(cleaned.length()):
		if not _is_digit(cleaned[index]):
			digits = "0"
			return self
	digits = cleaned
	return self


func is_zero() -> bool:
	return digits == "0"


func compare(other: BigCounter) -> int:
	if digits.length() != other.digits.length():
		return 1 if digits.length() > other.digits.length() else -1
	if digits == other.digits:
		return 0
	return 1 if digits > other.digits else -1


func equals(other: BigCounter) -> bool:
	return compare(other) == 0


func add(other: BigCounter) -> BigCounter:
	var i := digits.length() - 1
	var j := other.digits.length() - 1
	var carry := 0
	var output := ""
	while i >= 0 or j >= 0 or carry > 0:
		var left_digit := int(digits[i]) if i >= 0 else 0
		var right_digit := int(other.digits[j]) if j >= 0 else 0
		var total := left_digit + right_digit + carry
		output = str(total % 10) + output
		carry = int(total / 10)
		i -= 1
		j -= 1
	return BigCounter.new(output)


func subtract(other: BigCounter) -> BigCounter:
	if compare(other) <= 0:
		return BigCounter.zero()
	var i := digits.length() - 1
	var j := other.digits.length() - 1
	var borrow := 0
	var output := ""
	while i >= 0:
		var left_digit := int(digits[i]) - borrow
		var right_digit := int(other.digits[j]) if j >= 0 else 0
		if left_digit < right_digit:
			left_digit += 10
			borrow = 1
		else:
			borrow = 0
		output = str(left_digit - right_digit) + output
		i -= 1
		j -= 1
	return BigCounter.new(output)


func multiply_int(factor: int) -> BigCounter:
	if factor <= 0 or is_zero():
		return BigCounter.zero()
	if factor == 1:
		return duplicate_value()
	# Convert the factor to a counter first so a large int never overflows
	# during the per-digit product.
	return multiply_counter(BigCounter.from_int(factor))


func multiply(factor: int) -> BigCounter:
	return multiply_int(factor)


func divide_int(divisor: int) -> Dictionary:
	if divisor <= 0:
		return {"quotient": BigCounter.zero(), "remainder": 0}
	var quotient := ""
	var remainder := 0
	for index in range(digits.length()):
		remainder = remainder * 10 + int(digits[index])
		var quotient_digit := int(remainder / divisor)
		quotient += str(quotient_digit)
		remainder %= divisor
	return {"quotient": BigCounter.new(quotient), "remainder": remainder}


func divide(divisor: int) -> BigCounter:
	return divide_int(divisor)["quotient"]


func ceil_div_int(divisor: int) -> BigCounter:
	var result := divide_int(divisor)
	var quotient: BigCounter = result["quotient"]
	if int(result["remainder"]) > 0:
		quotient = quotient.add(BigCounter.one())
	return quotient


func to_int64_checked() -> int:
	# 18 decimal digits are always below 2^63. A 19-digit value is
	# conservatively rejected instead of risking a platform conversion.
	if digits.length() > 18:
		return -1
	return int(digits)


func to_float() -> float:
	if is_zero():
		return 0.0
	if digits.length() > 308:
		return INF
	return float(digits)


func to_magnitude() -> BigMagnitude:
	if is_zero():
		return BigMagnitude.zero()
	return BigMagnitude.from_exact_integer(digits)


func to_big_magnitude() -> BigMagnitude:
	return to_magnitude()


func multiply_counter(other: BigCounter) -> BigCounter:
	if is_zero() or other.is_zero():
		return BigCounter.zero()
	var output := PackedInt32Array()
	output.resize(digits.length() + other.digits.length())
	for index in range(output.size()):
		output[index] = 0
	for i in range(digits.length() - 1, -1, -1):
		for j in range(other.digits.length() - 1, -1, -1):
			output[i + j + 1] += int(digits[i]) * int(other.digits[j])
	for index in range(output.size() - 1, 0, -1):
		var carry := int(output[index] / 10)
		output[index] %= 10
		output[index - 1] += carry
	var text := ""
	for value in output:
		text += str(value)
	return BigCounter.from_string(text)


static func pow_int(base: int, exponent: int) -> BigCounter:
	if base <= 0 or exponent < 0:
		return BigCounter.zero()
	var result := BigCounter.one()
	var factor := BigCounter.from_int(base)
	var remaining := exponent
	while remaining > 0:
		if remaining % 2 == 1:
			result = result.multiply_counter(factor)
		remaining = int(remaining / 2)
		if remaining > 0:
			factor = factor.multiply_counter(factor)
	return result


func log10() -> float:
	if is_zero():
		return -INF
	var take := mini(15, digits.length())
	return float(digits.length() - 1) + log(float(digits.substr(0, take))) / log(10.0) - float(take - 1)


func to_dict() -> Dictionary:
	return {"value": digits}


func _to_string() -> String:
	return digits


static func _is_digit(value: String) -> bool:
	return value.length() == 1 and "0123456789".find(value) >= 0
