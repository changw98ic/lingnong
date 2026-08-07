## 数字格式化工具模块。
## 把数值按灵农修仙的展示规则转成短字符串：
##   value < 10000  → 整数(如 "9999")
##   value < 1e8    → 保留 1 位小数的 "x.x万"(如 "1.2万")
##   value >= 1e8   → "x.x亿"(如 "1.5亿")
## 负数会带 "-" 前缀；NaN 兜底为 "0"，无穷兜底为 "∞"。
class_name NumberFormat
extends RefCounted

## 万的阈值（含）：小于此值显示为整数。
const _WAN_THRESHOLD: float = 10000.0
## 亿的阈值（含）：大于等于此值显示为 "x.x亿"。
const _YI_THRESHOLD: float = 1.0e8


## 把数值格式化成短字符串。
## 遵循契约：<10000 整数；<1e8 x.x万；>=1e8 x.x亿。负数与 0 正常处理。
static func format(value: float) -> String:
	# NaN 兜底
	if is_nan(value):
		return "0"
	# 无穷兜底（区分正负）
	if is_inf(value):
		if value < 0.0:
			return "-∞"
		return "∞"

	# 0 直接返回，避免 -0 之类的问题
	if value == 0.0:
		return "0"

	# 用绝对值做量级判断，符号单独记录
	var sign_str := ""
	var abs_value: float = value
	if value < 0.0:
		sign_str = "-"
		abs_value = -value

	if abs_value < _WAN_THRESHOLD:
		# 整数：四舍五入到 int 后转字符串
		return sign_str + str(roundi(abs_value))

	if abs_value < _YI_THRESHOLD:
		# x.x万：%.1f 自带四舍五入
		return sign_str + "%.1f万" % (abs_value / _WAN_THRESHOLD)

	# x.x亿
	return sign_str + "%.1f亿" % (abs_value / _YI_THRESHOLD)
