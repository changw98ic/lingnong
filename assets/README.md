# 《灵农修仙》运行时资源

正式美术资产统一放在 `assets/art/`：

- `static/`：86 张经过尺寸和内容摘要校验的静态 PNG。
- `animations/`：26 组动画图集、便携元数据和 Godot `SpriteFrames` 资源。
- `manifest.json`：资产 ID 到 `res://` 路径的唯一运行时清单。

主界面只引用这套路径。旧的总览图拆分资源已经移除，避免新旧图同时被 Godot 加载。

重新发布资产：

```bash
python3 tools/art_pipeline/publish_godot_assets.py
```

发布脚本只接受完整且校验通过的 `.art-pipeline` 产物，并会完整重建 `assets/art/`。动画默认使用 `sprite_frames.tres`；黑底法术特效通过 `scripts/art/art_catalog.gd` 创建时会自动使用加法混合。
