class_name NumberFormatService
extends RefCounted

static func magnitude(value: BigMagnitude, precision: int = 3) -> String:
	if value == null or value.is_zero():
		return "0"
	if value.exponent < 6:
		var number := value.to_float()
		if number < 1000.0:
			return "%.2f" % number
		return "%.0f" % number
	return "%se%s" % [String.num(value.mantissa, precision), str(value.exponent)]


static func counter(value: BigCounter) -> String:
	if value == null:
		return "0"
	if value.digits.length() < 7:
		return value.digits
	var take := mini(4, value.digits.length())
	var head := float(value.digits.substr(0, take)) / pow(10.0, float(take - 1))
	return "%se%s" % [String.num(head, 3), str(value.digits.length() - 1)]


static func ratio(value: float) -> String:
	return "%.3f" % value


static func seconds(value: float) -> String:
	if is_inf(value) or value >= 1.0e30:
		return "∞"
	if value <= 0.0:
		return "现在"
	if value < 60.0:
		return "%.1f 秒" % value
	if value < 3600.0:
		return "%.1f 分钟" % (value / 60.0)
	return "%.1f 小时" % (value / 3600.0)
