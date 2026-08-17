# 《灵农修仙》美术生产提示词

本目录由 `tools/art_pipeline/art_pipeline.py` 从唯一资产目录生成。

- 单张母图提示词：86 份
- 图生视频提示词：26 份
- Image 2.0 只生产单张母图；所有动画由图生视频模型生成视频后拆分。
- 彩色参考锁定画风；线稿参考只锁定构图、透视和比例。
- 所有界面文字、数字和进度值由 Godot 实时绘制，不烘焙进图片。

## 使用命令

```bash
python3 tools/art_pipeline/art_pipeline.py build
python3 tools/art_pipeline/art_pipeline.py validate
python3 tools/art_pipeline/art_pipeline.py queue --kind static
./tools/art_pipeline/ego_batch_generate.sh --dry-run
```

## 单张母图

| ID | 名称 | 分类 | 提示词 |
|---|---|---|---|
| `action_icon.auto` | 自动运行图标 | `action_icon` | [action-icon-auto.md](static/action_icon/action-icon-auto.md) |
| `action_icon.available` | 可执行状态图标 | `action_icon` | [action-icon-available.md](static/action_icon/action-icon-available.md) |
| `action_icon.breakthrough` | 突破图标 | `action_icon` | [action-icon-breakthrough.md](static/action_icon/action-icon-breakthrough.md) |
| `action_icon.completed` | 已完成状态图标 | `action_icon` | [action-icon-completed.md](static/action_icon/action-icon-completed.md) |
| `action_icon.info` | 信息图标 | `action_icon` | [action-icon-info.md](static/action_icon/action-icon-info.md) |
| `action_icon.locked` | 未解锁状态图标 | `action_icon` | [action-icon-locked.md](static/action_icon/action-icon-locked.md) |
| `action_icon.receipt` | 批次收据图标 | `action_icon` | [action-icon-receipt.md](static/action_icon/action-icon-receipt.md) |
| `action_icon.save` | 保存图标 | `action_icon` | [action-icon-save.md](static/action_icon/action-icon-save.md) |
| `action_icon.unread_receipt` | 未读收据图标 | `action_icon` | [action-icon-unread-receipt.md](static/action_icon/action-icon-unread-receipt.md) |
| `action_icon.warning` | 警告状态图标 | `action_icon` | [action-icon-warning.md](static/action_icon/action-icon-warning.md) |
| `brand.lingnong_emblem` | 灵农修仙品牌徽记 | `brand` | [brand-lingnong-emblem.md](static/brand/brand-lingnong-emblem.md) |
| `character.butterfly` | 灵蝶母图 | `character` | [character-butterfly.md](static/character/character-butterfly.md) |
| `character.disciple_meditating` | 弟子打坐动作母图 | `character` | [character-disciple-meditating.md](static/character/character-disciple-meditating.md) |
| `character.disciple_model` | 弟子统一角色母设定 | `character` | [character-disciple-model.md](static/character/character-disciple-model.md) |
| `character.disciple_observing` | 弟子观察灵植动作母图 | `character` | [character-disciple-observing.md](static/character/character-disciple-observing.md) |
| `character.disciple_spellcasting` | 弟子施展灵术动作母图 | `character` | [character-disciple-spellcasting.md](static/character/character-disciple-spellcasting.md) |
| `character.disciple_watering` | 弟子浇水动作母图 | `character` | [character-disciple-watering.md](static/character/character-disciple-watering.md) |
| `character.spirit_beast` | 灵兽待机母图 | `character` | [character-spirit-beast.md](static/character/character-spirit-beast.md) |
| `chest.common` | 普通宝箱 | `chest` | [chest-common.md](static/chest/chest-common.md) |
| `chest.elite` | 精良宝箱 | `chest` | [chest-elite.md](static/chest/chest-elite.md) |
| `chest.rare` | 稀有宝箱 | `chest` | [chest-rare.md](static/chest/chest-rare.md) |
| `crop.five_element_ear` | 五行穗 | `crop` | [crop-five-element-ear.md](static/crop/crop-five-element-ear.md) |
| `crop.gathering_grass` | 聚灵草 | `crop` | [crop-gathering-grass.md](static/crop/crop-gathering-grass.md) |
| `crop.heaven_lotus` | 天道莲 | `crop` | [crop-heaven-lotus.md](static/crop/crop-heaven-lotus.md) |
| `crop.mind_flower` | 凝神花 | `crop` | [crop-mind-flower.md](static/crop/crop-mind-flower.md) |
| `crop.nourishing_ginseng` | 养元参 | `crop` | [crop-nourishing-ginseng.md](static/crop/crop-nourishing-ginseng.md) |
| `crop.purple_mushroom` | 紫芝 | `crop` | [crop-purple-mushroom.md](static/crop/crop-purple-mushroom.md) |
| `crop.sun_fruit` | 赤阳果 | `crop` | [crop-sun-fruit.md](static/crop/crop-sun-fruit.md) |
| `effect_source.bamboo_leaves` | 前景竹叶动态母图 | `effect_source` | [effect-source-bamboo-leaves.md](static/effect_source/effect-source-bamboo-leaves.md) |
| `effect_source.breakthrough` | 突破特效母图 | `effect_source` | [effect-source-breakthrough.md](static/effect_source/effect-source-breakthrough.md) |
| `effect_source.cloud_mist` | 山间云雾动态母图 | `effect_source` | [effect-source-cloud-mist.md](static/effect_source/effect-source-cloud-mist.md) |
| `effect_source.reincarnation` | 轮回特效母图 | `effect_source` | [effect-source-reincarnation.md](static/effect_source/effect-source-reincarnation.md) |
| `effect_source.stream` | 溪流动态母图 | `effect_source` | [effect-source-stream.md](static/effect_source/effect-source-stream.md) |
| `effect_source.tribulation` | 雷劫特效母图 | `effect_source` | [effect-source-tribulation.md](static/effect_source/effect-source-tribulation.md) |
| `effect_source.waterfall` | 瀑布动态母图 | `effect_source` | [effect-source-waterfall.md](static/effect_source/effect-source-waterfall.md) |
| `environment.cultivation_valley_base` | 灵田洞府静态底图 | `environment` | [environment-cultivation-valley-base.md](static/environment/environment-cultivation-valley-base.md) |
| `environment.foreground_foliage_occluder` | 前景竹叶遮挡层 | `environment` | [environment-foreground-foliage-occluder.md](static/environment/environment-foreground-foliage-occluder.md) |
| `farm_icon.field` | 灵田等级图标 | `farm_icon` | [farm-icon-field.md](static/farm_icon/farm-icon-field.md) |
| `farm_icon.gathering_array` | 聚灵阵等级图标 | `farm_icon` | [farm-icon-gathering-array.md](static/farm_icon/farm-icon-gathering-array.md) |
| `farm_icon.soil` | 灵土阶数图标 | `farm_icon` | [farm-icon-soil.md](static/farm_icon/farm-icon-soil.md) |
| `material.bi_shui_lian` | 碧水莲精粹 | `material` | [material-bi-shui-lian.md](static/material/material-bi-shui-lian.md) |
| `material.body_pill` | 锻体丹药力 | `material` | [material-body-pill.md](static/material/material-body-pill.md) |
| `material.cang_tian_zi_qi` | 苍天紫气精粹 | `material` | [material-cang-tian-zi-qi.md](static/material/material-cang-tian-zi-qi.md) |
| `material.da_di_ku_cao` | 大地苦草精粹 | `material` | [material-da-di-ku-cao.md](static/material/material-da-di-ku-cao.md) |
| `material.dao_mark` | 天道印记 | `material` | [material-dao-mark.md](static/material/material-dao-mark.md) |
| `material.dragon_tiger_pill` | 龙虎丹药力 | `material` | [material-dragon-tiger-pill.md](static/material/material-dragon-tiger-pill.md) |
| `material.fu_lu_zhou` | 福禄咒精粹 | `material` | [material-fu-lu-zhou.md](static/material/material-fu-lu-zhou.md) |
| `material.fu_qi_dan` | 服气丹精粹 | `material` | [material-fu-qi-dan.md](static/material/material-fu-qi-dan.md) |
| `material.jin_yang_hua` | 金阳花精粹 | `material` | [material-jin-yang-hua.md](static/material/material-jin-yang-hua.md) |
| `material.lei_ji_tao_mu` | 雷击桃木精粹 | `material` | [material-lei-ji-tao-mu.md](static/material/material-lei-ji-tao-mu.md) |
| `material.nourishing_spirit_pill` | 养神丹药力 | `material` | [material-nourishing-spirit-pill.md](static/material/material-nourishing-spirit-pill.md) |
| `material.san_qing_chi_ling` | 三清敕令精粹 | `material` | [material-san-qing-chi-ling.md](static/material/material-san-qing-chi-ling.md) |
| `material.spirit_pill` | 凝神丸药力 | `material` | [material-spirit-pill.md](static/material/material-spirit-pill.md) |
| `material.yan_ling_shu_xin` | 炎灵树心精粹 | `material` | [material-yan-ling-shu-xin.md](static/material/material-yan-ling-shu-xin.md) |
| `material.yang_ji_di_xin` | 阳极地心精粹 | `material` | [material-yang-ji-di-xin.md](static/material/material-yang-ji-di-xin.md) |
| `material.yin_ji_yue_hua` | 阴极月华精粹 | `material` | [material-yin-ji-yue-hua.md](static/material/material-yin-ji-yue-hua.md) |
| `material.zi_mu_gen` | 紫木根精粹 | `material` | [material-zi-mu-gen.md](static/material/material-zi-mu-gen.md) |
| `navigation_icon.automation` | 阵法导航图标 | `navigation_icon` | [navigation-icon-automation.md](static/navigation_icon/navigation-icon-automation.md) |
| `navigation_icon.materials` | 宝物导航图标 | `navigation_icon` | [navigation-icon-materials.md](static/navigation_icon/navigation-icon-materials.md) |
| `navigation_icon.overview` | 洞府导航图标 | `navigation_icon` | [navigation-icon-overview.md](static/navigation_icon/navigation-icon-overview.md) |
| `navigation_icon.paths` | 境界导航图标 | `navigation_icon` | [navigation-icon-paths.md](static/navigation_icon/navigation-icon-paths.md) |
| `navigation_icon.production` | 灵田导航图标 | `navigation_icon` | [navigation-icon-production.md](static/navigation_icon/navigation-icon-production.md) |
| `navigation_icon.receipts` | 日志导航图标 | `navigation_icon` | [navigation-icon-receipts.md](static/navigation_icon/navigation-icon-receipts.md) |
| `navigation_icon.reincarnation` | 轮回导航图标 | `navigation_icon` | [navigation-icon-reincarnation.md](static/navigation_icon/navigation-icon-reincarnation.md) |
| `navigation_icon.tribulation` | 雷劫导航图标 | `navigation_icon` | [navigation-icon-tribulation.md](static/navigation_icon/navigation-icon-tribulation.md) |
| `portrait.main_cultivator` | 主角修士头像 | `portrait` | [portrait-main-cultivator.md](static/portrait/portrait-main-cultivator.md) |
| `prop.gathering_array` | 中央聚灵阵 | `prop` | [prop-gathering-array.md](static/prop/prop-gathering-array.md) |
| `prop.spirit_crystal` | 聚灵灵晶 | `prop` | [prop-spirit-crystal.md](static/prop/prop-spirit-crystal.md) |
| `prop.waterwheel` | 木制水车 | `prop` | [prop-waterwheel.md](static/prop/prop-waterwheel.md) |
| `realm.foundation` | 筑基境徽记 | `realm` | [realm-foundation.md](static/realm/realm-foundation.md) |
| `realm.golden_core` | 金丹境徽记 | `realm` | [realm-golden-core.md](static/realm/realm-golden-core.md) |
| `realm.qi_refining` | 练气境徽记 | `realm` | [realm-qi-refining.md](static/realm/realm-qi-refining.md) |
| `resource_icon.consciousness` | 神识图标 | `resource_icon` | [resource-icon-consciousness.md](static/resource_icon/resource-icon-consciousness.md) |
| `resource_icon.cultivation` | 修为图标 | `resource_icon` | [resource-icon-cultivation.md](static/resource_icon/resource-icon-cultivation.md) |
| `resource_icon.dao_essence` | 道蕴图标 | `resource_icon` | [resource-icon-dao-essence.md](static/resource_icon/resource-icon-dao-essence.md) |
| `resource_icon.law` | 飞升法则图标 | `resource_icon` | [resource-icon-law.md](static/resource_icon/resource-icon-law.md) |
| `resource_icon.physique` | 体魄图标 | `resource_icon` | [resource-icon-physique.md](static/resource_icon/resource-icon-physique.md) |
| `resource_icon.spirit_stone` | 灵石图标 | `resource_icon` | [resource-icon-spirit-stone.md](static/resource_icon/resource-icon-spirit-stone.md) |
| `ui.bottom_navigation_dock` | 底部导航托盘 | `ui` | [ui-bottom-navigation-dock.md](static/ui/ui-bottom-navigation-dock.md) |
| `ui.context_panel` | 轻量上下文面板 | `ui` | [ui-context-panel.md](static/ui/ui-context-panel.md) |
| `ui.primary_action_button` | 主操作按钮底框 | `ui` | [ui-primary-action-button.md](static/ui/ui-primary-action-button.md) |
| `ui.progress_bar_frame` | 成长进度条底框 | `ui` | [ui-progress-bar-frame.md](static/ui/ui-progress-bar-frame.md) |
| `ui.resource_chip` | 资源胶囊底框 | `ui` | [ui-resource-chip.md](static/ui/ui-resource-chip.md) |
| `ui.round_icon_button_frame` | 圆形图标按钮底框 | `ui` | [ui-round-icon-button-frame.md](static/ui/ui-round-icon-button-frame.md) |
| `ui.status_pill` | 运行状态胶囊底框 | `ui` | [ui-status-pill.md](static/ui/ui-status-pill.md) |
| `ui.top_hud_frame` | 顶部低密度 HUD 框 | `ui` | [ui-top-hud-frame.md](static/ui/ui-top-hud-frame.md) |

## 图生视频

| ID | 名称 | 母图 | 提示词 |
|---|---|---|---|
| `animation.bamboo_leaves_sway` | 竹叶轻摆 | `effect_source.bamboo_leaves` | [animation-bamboo-leaves-sway.md](animation/animation-bamboo-leaves-sway.md) |
| `animation.breakthrough` | 突破演出 | `effect_source.breakthrough` | [animation-breakthrough.md](animation/animation-breakthrough.md) |
| `animation.butterfly_flight` | 蝴蝶振翅 | `character.butterfly` | [animation-butterfly-flight.md](animation/animation-butterfly-flight.md) |
| `animation.chest_common_open` | 普通宝箱开启 | `chest.common` | [animation-chest-common-open.md](animation/animation-chest-common-open.md) |
| `animation.chest_elite_open` | 精良宝箱开启 | `chest.elite` | [animation-chest-elite-open.md](animation/animation-chest-elite-open.md) |
| `animation.chest_rare_open` | 稀有宝箱开启 | `chest.rare` | [animation-chest-rare-open.md](animation/animation-chest-rare-open.md) |
| `animation.clouds_drift` | 云雾缓行 | `effect_source.cloud_mist` | [animation-clouds-drift.md](animation/animation-clouds-drift.md) |
| `animation.disciple_casting` | 弟子施展养护法术 | `character.disciple_spellcasting` | [animation-disciple-casting.md](animation/animation-disciple-casting.md) |
| `animation.disciple_inspecting` | 弟子观察灵植 | `character.disciple_observing` | [animation-disciple-inspecting.md](animation/animation-disciple-inspecting.md) |
| `animation.disciple_meditating` | 弟子打坐 | `character.disciple_meditating` | [animation-disciple-meditating.md](animation/animation-disciple-meditating.md) |
| `animation.disciple_watering` | 弟子浇水 | `character.disciple_watering` | [animation-disciple-watering.md](animation/animation-disciple-watering.md) |
| `animation.five_element_ear_sway` | 五行穗成熟循环 | `crop.five_element_ear` | [animation-five-element-ear-sway.md](animation/animation-five-element-ear-sway.md) |
| `animation.gathering_array_cycle` | 聚灵阵循环 | `prop.gathering_array` | [animation-gathering-array-cycle.md](animation/animation-gathering-array-cycle.md) |
| `animation.gathering_grass_sway` | 聚灵草成熟待机 | `crop.gathering_grass` | [animation-gathering-grass-sway.md](animation/animation-gathering-grass-sway.md) |
| `animation.heaven_lotus_breathe` | 天道莲成熟循环 | `crop.heaven_lotus` | [animation-heaven-lotus-breathe.md](animation/animation-heaven-lotus-breathe.md) |
| `animation.mind_flower_breathe` | 凝神花成熟待机 | `crop.mind_flower` | [animation-mind-flower-breathe.md](animation/animation-mind-flower-breathe.md) |
| `animation.nourishing_ginseng_breathe` | 养元参成熟待机 | `crop.nourishing_ginseng` | [animation-nourishing-ginseng-breathe.md](animation/animation-nourishing-ginseng-breathe.md) |
| `animation.purple_mushroom_breathe` | 紫芝成熟待机 | `crop.purple_mushroom` | [animation-purple-mushroom-breathe.md](animation/animation-purple-mushroom-breathe.md) |
| `animation.reincarnation` | 轮回演出 | `effect_source.reincarnation` | [animation-reincarnation.md](animation/animation-reincarnation.md) |
| `animation.spirit_beast_idle` | 灵兽待机 | `character.spirit_beast` | [animation-spirit-beast-idle.md](animation/animation-spirit-beast-idle.md) |
| `animation.spirit_crystal_breathe` | 灵晶核心呼吸 | `prop.spirit_crystal` | [animation-spirit-crystal-breathe.md](animation/animation-spirit-crystal-breathe.md) |
| `animation.stream_flow` | 溪流循环 | `effect_source.stream` | [animation-stream-flow.md](animation/animation-stream-flow.md) |
| `animation.sun_fruit_breathe` | 赤阳果成熟待机 | `crop.sun_fruit` | [animation-sun-fruit-breathe.md](animation/animation-sun-fruit-breathe.md) |
| `animation.tribulation` | 雷劫单雷反馈 | `effect_source.tribulation` | [animation-tribulation.md](animation/animation-tribulation.md) |
| `animation.waterfall_flow` | 瀑布流水 | `effect_source.waterfall` | [animation-waterfall-flow.md](animation/animation-waterfall-flow.md) |
| `animation.waterwheel_turn` | 水车缓转 | `prop.waterwheel` | [animation-waterwheel-turn.md](animation/animation-waterwheel-turn.md) |
