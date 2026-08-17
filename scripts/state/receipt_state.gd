class_name ReceiptState
extends RefCounted

const MAX_RECEIPTS := 100
var buffer: Array = []
var ack_cursor := 0
var next_id := 1


func append_receipt(receipt: Dictionary) -> void:
	var item := receipt.duplicate(true)
	item["receipt_id"] = next_id
	next_id += 1
	buffer.append(item)
	while buffer.size() > MAX_RECEIPTS:
		buffer.pop_front()
		ack_cursor += 1


func recent(limit: int = 20) -> Array:
	return buffer.slice(maxi(0, buffer.size() - limit), buffer.size())


func to_dict() -> Dictionary:
	return {"buffer": buffer.duplicate(true), "ack_cursor": ack_cursor, "next_id": next_id}


func load_dict(data: Dictionary) -> void:
	buffer = data.get("buffer", []) if data.get("buffer", []) is Array else []
	ack_cursor = maxi(0, int(data.get("ack_cursor", 0)))
	next_id = maxi(1, int(data.get("next_id", 1)))
	while buffer.size() > MAX_RECEIPTS:
		buffer.pop_front()
		ack_cursor += 1
