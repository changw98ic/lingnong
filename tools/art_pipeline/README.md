# 《灵农修仙》美术生产脚本

这套脚本把三种内容分开保存：

- `tools/art_pipeline/catalog/`：唯一资产清单，人工维护。
- `docs/art-prompts/`：从清单生成的独立 Markdown 提示词。
- `.art-pipeline/`：运行队列、下载图片、视频、拆帧和报告，不提交到 Git。

## 1. 构建和检查提示词

```bash
python3 tools/art_pipeline/art_pipeline.py build
python3 tools/art_pipeline/art_pipeline.py validate
```

每次构建都会删除旧的生成文件，再按照当前清单完整重建，避免旧提示词继续混用。检查命令会逐字比对清单和生成结果，提示词被手工改旧、漏生成或多出旧文件时都会报错。

提示词或参考图更新后，需要重新运行对应的 `queue` 命令。队列同时记录规范提示词路径、提示词摘要和完整输入摘要；替换队列里的提示词路径、尺寸、背景、动画参数或依赖关系都会被拒绝。旧图片、旧视频或被手工改过的产物即使尺寸正确，也不会继续被标记为完成。

## 2. 建立单张母图队列

```bash
python3 tools/art_pipeline/art_pipeline.py queue --kind static
./tools/art_pipeline/ego_batch_generate.sh --dry-run
```

先做一个真实的低速冒烟任务：

```bash
./tools/art_pipeline/ego_batch_generate.sh --max-items 1 --delay 90
```

确认图片内容和下载都正确后，再继续未完成项：

```bash
./tools/art_pipeline/ego_batch_generate.sh --delay 90
```

需要三个低速浏览器工作者持续处理完整队列时：

```bash
./tools/art_pipeline/ego_parallel_daemon.sh start
./tools/art_pipeline/ego_parallel_daemon.sh status
```

后台服务每轮最多同时生成三张，单轮结束后统一冷却 300 秒再发起下一批。即使启动它的终端关闭，macOS 仍会继续运行；父进程意外退出后，下一次启动会先核对并合并已经生成完成的工作者结果，不会重复覆盖图片。停止命令是：

```bash
./tools/art_pipeline/ego_parallel_daemon.sh stop
```

脚本始终只有一个浏览器工作者。默认每项结束后等待 60 秒；完成图片不会被覆盖。每张完成图旁边会写入提示词、参考图和输出文件摘要，内容变化后旧完成状态自动失效。所有浏览器运行、队列重建和提示词重建共用一把真实继承的系统文件锁，单纯设置环境变量不能跳过它。依赖统一弟子设定图的动作资产只会在设定图已完成且图片有效后开始，等待依赖不会消耗尝试次数。登录失效或出现验证码时会暂停整批、保留任务空间并交给用户处理；脚本不会尝试绕过网站限制。失败项修复后使用：

```bash
./tools/art_pipeline/ego_batch_generate.sh --retry-failed --max-items 1
```

如果失败原因写明“已有图片校验不通过”，先把那张文件移到人工复查目录；脚本会保留它，不会直接覆盖。

静态母图必须是真正的单帧图片。脚本会拒绝 APNG 等多帧文件，并给图片探测和转码设置超时，避免动画图片让队列长时间卡住。

## 3. 建立图生视频队列

```bash
python3 tools/art_pipeline/art_pipeline.py queue --kind animation
```

动画队列保存母图路径、独立视频提示词、时长、循环方式、遮罩背景和 Godot 播放速度。Image 2.0 只生成静态母图。动画有两条明确边界：Media Plan 必须通过 MiniMax Design 桌面端生成；Open Platform API 只能走账户余额按量付费。两条路径最后都会汇入同一个本地标准化、校验和拆帧流程。

先检查一个任务，不发起付费请求：

```bash
python3 tools/art_pipeline/minimax_video_generate.py \
  --animation-id animation.waterwheel_turn \
  --billing-source media-plan \
  --dry-run
```

### Media Plan：MiniMax Design 路径

Media Plan 不使用 `sk-api` 或 `sk-cp` 调用 H3 API。把准备好的首帧作为附件上传到 MiniMax Design，在 Design 中选择 `MiniMax H3`、`4 秒`、`768P`、`1:1`，生成一次后，将 Design 项目里的原始 MP4 导入队列：

```bash
python3 tools/art_pipeline/minimax_video_generate.py \
  --animation-id animation.gathering_grass_sway \
  --billing-source media-plan \
  --resolution 768P \
  --import-design-video "/absolute/path/to/MiniMax Design Project/result.mp4" \
  --provider-task-id PROVIDER_TASK_ID \
  --design-task-id DESIGN_TASK_ID \
  --actual-media-plan-credits ACTUAL_CREDITS \
  --free-generations-before FREE_COUNT_BEFORE \
  --free-generations-after FREE_COUNT_AFTER
```

导入动作不再次调用远程接口，也不会重复扣费；它会把 Design 的原始视频完整变速到清单时长，统一画布和帧率，写入 Media Plan 来源、任务号、输入摘要和输出摘要，然后把队列标记为完成。Design 使用免费次数时，把 `ACTUAL_CREDITS` 写成 `0`，并把提交前后的免费次数一并记录。Design 没显示实际扣点时省略这三个参数，只保留估算值。已有输出会被保留，脚本不会覆盖。

所有首帧已经准备好后，可以让 MiniMax Design 的本地项目网关顺序处理整条动画队列：

```bash
./tools/art_pipeline/minimax_design_batch_daemon.sh start
./tools/art_pipeline/minimax_design_batch_daemon.sh status
```

运行时必须保持 MiniMax Design 的 `H3 PlayGround` 项目打开。后台服务只使用 Design 的 Media Plan，不读取 Open Platform API key；每次只提交一个 H3 任务，任务号会先保存再轮询，意外重启时继续已有任务而不重复计费。每个结果会自动导入标准 MP4，再拆成 PNG 帧与图集。

服务在每个任务前、每个任务完成后以及活动任务最长每 600 秒检查一次 Media Plan 余额和 H3 免费次数。免费次数为零且剩余积分不足下一条任务的保守估算时，不再提交新任务并正常退出；MiniMax 明确返回余额不足时也会立即停止。状态和停止原因保存在 `.art-pipeline/reports/minimax-design-batch-latest.json`，手动停止命令是：

```bash
./tools/art_pipeline/minimax_design_batch_daemon.sh stop
```

`--dry-run` 会显示 Design 端预计消耗：H3 768P 按 70 积分/秒估算，2K 按 120 积分/秒估算，最终以 MiniMax Design 实际显示为准。例如本项目的 2 秒动作需要先生成 H3 最短的 4 秒视频，所以 768P 预计为 280 积分。

### Open Platform：API 余额路径

确实需要从 API 账户余额按量付费时，必须显式选择 API 边界：

```bash
read -s "MINIMAX_API_KEY?MiniMax pay-as-you-go API key: "
export MINIMAX_API_KEY
echo

python3 tools/art_pipeline/minimax_video_generate.py \
  --animation-id animation.waterwheel_turn \
  --billing-source paygo \
  --resolution 768P
```

API 模式默认每次最多处理一个动画。单个任务验证通过后，使用 `--max-items 0` 继续所有已具备母图的任务。失败项修复后增加 `--retry-failed`；已经拿到任务编号但尚未完成的异步任务会从 `.art-pipeline/minimax-tasks/` 恢复，不会重新提交一份。网络在提交瞬间中断且没有返回任务编号时，脚本会停止自动重试，先到 MiniMax 任务列表核对，避免重复计费。

API 调用链是：准备固定画布首帧 → 以 Base64 Data URL 和 `role=first_frame` 调用 `POST /v2/video_generation` → 轮询 `GET /v2/query/video_generation/{task_id}` → 下载 MP4。Design 调用链是：准备固定画布首帧 → 上传为 Design 对话附件 → 由 Design 提交 H3 → 把生成 MP4 导入本地。两条链路最终都会统一到清单规定的画布、时长和源帧率。MiniMax H3 的最短输出是 4 秒；清单中的 2 秒或 3 秒动作会先要求模型把完整动作铺满 4 秒，再在本地完整变速到目标时长，不会只截掉尾部动作。

所有图片与视频工作者共用同一把锁。后台图片生成仍在运行时，视频脚本会停止并保留队列；等待本轮图片任务结束，或先停止图片后台服务，再运行视频任务。完成视频不会被覆盖。

把透明母图放到动画规定的固定画布和纯色背景：

```bash
python3 tools/art_pipeline/prepare_video_source.py \
  --animation-id animation.waterwheel_turn \
  --input /absolute/path/to/waterwheel.png
```

洋红底用于普通对象，青色底用于纯紫对象，红色底用于蓝紫或青玉对象，黑底只用于 Godot 加法混合特效。准备脚本会拒绝多帧、不透明、全透明或几乎没有主体的母图，并检查纯色背景与主体都占有有效面积。每个动画分别声明底部中心、右下根部、几何中心、身体中心或整画布定位；整画布母图按 5% 透明面积和至少一个透明角检查，独立对象按 10% 和至少三个透明角检查，与拆帧规则一致。整画布环境特效只固定画布，脚本不会把“画布尺寸没变”误报成“内部内容没有漂移”。输出已存在时脚本会停止；确认需要替换时显式增加 `--overwrite`。同一输出路径带独占锁，两个准备进程不会同时通过“禁止覆盖”检查。

## 4. 视频拆帧和图集

图生视频模型输出 MP4 后：

```bash
python3 tools/art_pipeline/extract_video.py \
  --animation-id animation.waterwheel_turn \
  --input /absolute/path/to/waterwheel.mp4
```

默认会核对 `.art-pipeline/video-sources/` 中对应的准备母图；使用别处的母图时显式增加 `--source-image /absolute/path/to/source.png`。输入视频必须严格使用清单画布，帧率不得低于清单源帧率。脚本把容许范围内的多余时长裁到精确预算，短片、低帧率、低尺寸和超出时长容差的文件都会停止处理。

脚本会：

1. 按资产清单指定帧率抽取 PNG。
2. 按目录配置对洋红、青色或红色背景进行色键抠图。
3. 对 `ping_pong` 动画只保存正向图片，并记录 Godot 正放后倒放，避免复制纹理。
4. 对 `seam_blend` 动画以预乘透明度方式融合首尾重叠段，避免色键底色污染半透明边缘。
5. 生成最多八列且不超过 8192 像素的 PNG 图集。
6. 检查输入时长、比例、帧率，并在每个对象声明的稳定根部或中心区域检查锚点漂移，避免把翅膀、箱盖、水流或法术的正常运动误判为漂移。
7. 检查抠图后每张图片的透明面积和边角；黑底加法特效则检查黑底与可见特效都真实存在。
8. 写出 Godot 所需帧数、尺寸、速度和锚点检查结果，并在视频旁保存母图、提示词和视频内容摘要。

黑底灵气与雷劫特效保留黑底，在 Godot 中使用加法混合。

拆帧输出已存在时默认保留；确认新视频已经验收后使用 `--overwrite`。同一动画输出带独占锁。脚本用随机版本目录先生成一套完整版本，再原子切换稳定输出路径；旧实体目录迁移也使用系统原子交换。处理中断或旧版本清理失败时，新旧稳定版本都不会因此断链。

如果 H3 保留了平坦背景但在视频中把洋红、青色或红色逐渐变成其他颜色，固定色键会留下不透明背景。此时可增加 `--adaptive-reference-matte`：脚本会逐帧估算边缘背景色，并用已经准备好的首帧限制主体范围，避免在背景变白或变绿时把浅色主体一并删除。输出元数据会记录 `adaptive_reference`，仍需通过透明面积、透明边角和锚点检查。

## 5. 发布到 Godot

静态图和动画拆帧全部验证完成后，运行：

```bash
python3 tools/art_pipeline/publish_godot_assets.py
```

脚本会核对 86 张静态图的尺寸与内容摘要，核对 26 组动画的帧数和图集尺寸，然后重建 `assets/art/`。每组动画会生成 Godot 可直接加载的 `sprite_frames.tres`；往返动画会在资源里按“正向后反向且不重复端点”排列。`assets/art/manifest.json` 是运行时唯一资产清单，不包含本机路径或凭据。

## 6. 查看状态

```bash
python3 tools/art_pipeline/art_pipeline.py report \
  --queue .art-pipeline/queues/static.json
```
