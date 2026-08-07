class_name AutomationSystem
extends RefCounted

## 灵脉与离线结算自动化模块。
## 金丹突破后由 GameState 调用 activate_spirit_vein() 激活灵脉；
## 每帧由 GameState.update_world() 调用 tick() 结算本帧被动产出；
## 加载存档时由 GameState 调用 compute_offline() 结算离线期间灵脉产出。
## 本模块不读写任何全局单例，所有外部数据通过参数传入、结果以 Dictionary 返回，
## 由 GameState 协调应用到自身货币字段。

# 灵脉基础产出速率（每秒）
const BASE_CULTIVATION_PER_SEC := 20.0
const BASE_QI_PER_SEC := 5.0

# 离线收益结算封顶：8 小时 = 28800 秒
const OFFLINE_CAP_SECONDS := 28800.0

# 灵脉是否已激活（金丹突破后由 GameState 置 true）
var spirit_vein_active := false


func is_spirit_vein_active() -> bool:
    return spirit_vein_active


func activate_spirit_vein() -> void:
    spirit_vein_active = true


## 每帧结算灵脉被动产出。
## delta: 本帧时长（秒）；reincarnation_mult: 转世全局产出倍率。
## 基础 20 修为/秒 + 5 灵气/秒，结果乘以 reincarnation_mult。
## 灵脉未激活时返回 {"cultivation": 0.0, "qi": 0.0}。
func tick(delta: float, reincarnation_mult: float) -> Dictionary:
    if not spirit_vein_active:
        return {"cultivation": 0.0, "qi": 0.0}
    var seconds := maxf(0.0, delta)
    var mult := maxf(0.0, reincarnation_mult)
    return {
        "cultivation": BASE_CULTIVATION_PER_SEC * seconds * mult,
        "qi": BASE_QI_PER_SEC * seconds * mult,
    }


## 结算离线期间的灵脉产出。
## elapsed_seconds: 离线时长（现在 - saved_at，秒）；reincarnation_mult: 转世全局产出倍率。
## 按 tick 速率结算，时长封顶 OFFLINE_CAP_SECONDS（8 小时）。
## 灵脉未激活时产出为 0，但仍如实返回 capped / credited_seconds 以便 UI 展示。
## 返回 {"cultivation": float, "qi": float, "capped": bool, "credited_seconds": float}。
func compute_offline(elapsed_seconds: float, reincarnation_mult: float) -> Dictionary:
    var elapsed := maxf(0.0, elapsed_seconds)
    var capped := elapsed > OFFLINE_CAP_SECONDS
    var credited_seconds := minf(elapsed, OFFLINE_CAP_SECONDS)
    var mult := maxf(0.0, reincarnation_mult)
    var cultivation := 0.0
    var qi := 0.0
    if spirit_vein_active:
        cultivation = BASE_CULTIVATION_PER_SEC * credited_seconds * mult
        qi = BASE_QI_PER_SEC * credited_seconds * mult
    return {
        "cultivation": cultivation,
        "qi": qi,
        "capped": capped,
        "credited_seconds": credited_seconds,
    }
