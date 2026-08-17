class_name EconomyCodec
extends RefCounted

## 存档只允许使用明确的大数编码，不把领域对象直接交给 JSON。

static func encode_magnitude(value: BigMagnitude) -> Dictionary:
	return value.to_dict()


static func decode_magnitude(value: Variant) -> BigMagnitude:
	return BigMagnitude.from_dict(value)


static func encode_counter(value: BigCounter) -> String:
	return value.digits


static func decode_counter(value: Variant) -> BigCounter:
	return BigCounter.from_string(String(value if value != null else "0"))


static func encode_magnitude_map(values: Dictionary) -> Dictionary:
	var output := {}
	for key in values:
		var value = values[key]
		if value is BigMagnitude:
			output[String(key)] = encode_magnitude(value)
		elif value is BigCounter:
			output[String(key)] = encode_counter(value)
		else:
			output[String(key)] = value
	return output


static func decode_magnitude_map(values: Variant) -> Dictionary:
	var output := {}
	if not values is Dictionary:
		return output
	for key in values:
		var value = values[key]
		if value is Dictionary and (value.has("m") or value.has("mantissa")):
			output[String(key)] = decode_magnitude(value)
		else:
			output[String(key)] = value
	return output
