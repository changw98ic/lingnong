#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUEUE="$ROOT/.art-pipeline/queues/static.json"
TASK_SPACE="lingnong-art-generation"
DELAY_SECONDS=60
READY_TIMEOUT_SECONDS=45
GENERATION_TIMEOUT_SECONDS=720
MAX_ITEMS=0
MAX_ATTEMPTS=2
DRY_RUN=0
RETRY_FAILED=0
KEEP_BROWSER=0
ORIGINAL_ARGS=("$@")

usage() {
  cat <<'USAGE'
Usage: ego_batch_generate.sh [options]

Sequentially generates static mother images in ChatGPT through ego-browser.
The runner uses one browser worker and never overwrites a completed output.

Options:
  --queue PATH                 Queue JSON (default: .art-pipeline/queues/static.json)
  --task-space NAME            ego-browser task space name
  --delay SECONDS              Delay after each job (default: 60)
  --ready-timeout SECONDS      Prompt-box timeout (default: 45)
  --generation-timeout SECONDS Image completion timeout (default: 720)
  --max-items N                Stop after N jobs; 0 means all pending jobs
  --max-attempts N             Maximum attempts per job (default: 2)
  --retry-failed               Include failed jobs below max-attempts
  --keep-browser               Keep the task space after the run
  --dry-run                    Validate and print the bounded run without opening a browser
  -h, --help                   Show this help
USAGE
}

while (($#)); do
  case "$1" in
    --queue) QUEUE="$2"; shift 2 ;;
    --task-space) TASK_SPACE="$2"; shift 2 ;;
    --delay) DELAY_SECONDS="$2"; shift 2 ;;
    --ready-timeout) READY_TIMEOUT_SECONDS="$2"; shift 2 ;;
    --generation-timeout) GENERATION_TIMEOUT_SECONDS="$2"; shift 2 ;;
    --max-items) MAX_ITEMS="$2"; shift 2 ;;
    --max-attempts) MAX_ATTEMPTS="$2"; shift 2 ;;
    --retry-failed) RETRY_FAILED=1; shift ;;
    --keep-browser) KEEP_BROWSER=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for number in "$DELAY_SECONDS" "$READY_TIMEOUT_SECONDS" "$GENERATION_TIMEOUT_SECONDS" "$MAX_ITEMS" "$MAX_ATTEMPTS"; do
  [[ "$number" =~ ^[0-9]+$ ]] || { echo "Numeric options must be non-negative integers" >&2; exit 2; }
done
(( MAX_ATTEMPTS > 0 )) || { echo "--max-attempts must be greater than zero" >&2; exit 2; }

LOCK_FILE="$HOME/.cache/lingnong-art-pipeline/pipeline.lock"
if [[ "${LINGNONG_PARALLEL_WORKER:-0}" != "1" ]]; then
  if [[ -z "${LINGNONG_PIPELINE_LOCK_FD:-}" ]]; then
    exec python3 "$ROOT/tools/art_pipeline/run_with_lock.py" \
      "$LOCK_FILE" "$0" "${ORIGINAL_ARGS[@]}"
  fi
  python3 - "$LOCK_FILE" "$LINGNONG_PIPELINE_LOCK_FD" <<'PY'
import fcntl
import os
import sys
from pathlib import Path

lock_path = Path(sys.argv[1]).expanduser().resolve()
try:
    fd = int(sys.argv[2])
    descriptor = os.fstat(fd)
    expected = lock_path.stat()
    if (descriptor.st_dev, descriptor.st_ino) != (expected.st_dev, expected.st_ino):
        raise OSError("descriptor points to a different file")
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
except (ValueError, OSError, BlockingIOError) as exc:
    print(f"Invalid inherited art-pipeline lock: {exc}", file=sys.stderr)
    raise SystemExit(3)
PY
fi

python3 "$ROOT/tools/art_pipeline/art_pipeline.py" validate >/dev/null
[[ -f "$QUEUE" ]] || python3 "$ROOT/tools/art_pipeline/art_pipeline.py" queue --kind static --output "$QUEUE" >/dev/null
QUEUE="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "$QUEUE")"
FFMPEG_BIN="$(command -v ffmpeg || true)"
FFPROBE_BIN="$(command -v ffprobe || true)"
[[ -n "$FFMPEG_BIN" && -n "$FFPROBE_BIN" ]] || {
  echo "ffmpeg and ffprobe are required" >&2
  exit 2
}

python3 - "$QUEUE" <<'PY'
import json
import sys
from pathlib import Path

queue = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if queue.get("kind") != "static":
    print(f"Expected a static queue, got {queue.get('kind')}", file=sys.stderr)
    raise SystemExit(2)
PY
SUMMARY="$(python3 "$ROOT/tools/art_pipeline/art_pipeline.py" report --queue "$QUEUE")"
if (( DRY_RUN )); then
  printf '%s\n' "$SUMMARY"
  printf 'task_space=%s concurrency=1 delay_seconds=%s max_items=%s retry_failed=%s\n' \
    "$TASK_SPACE" "$DELAY_SECONDS" "$MAX_ITEMS" "$RETRY_FAILED"
  exit 0
fi

CONFIG_PATH="$HOME/.cache/lingnong-art-pipeline/ego-runtime.json"
mkdir -p "$(dirname "$CONFIG_PATH")"
CONFIG_PATH="$(mktemp "$HOME/.cache/lingnong-art-pipeline/ego-runtime.XXXXXX")"
REPORT_KEY="$(python3 -c 'import re,sys; print(re.sub(r"[^A-Za-z0-9_.-]+", "-", sys.argv[1]).strip("-") or "static")' "$TASK_SPACE")"
RUNTIME_POINTER="$HOME/.cache/lingnong-art-pipeline/ego-runtime-$REPORT_KEY.path"
RUNTIME_CONFIG_LINK="/tmp/lingnong-ego-runtime-$REPORT_KEY.json"
RUNTIME_CONFIG_JS="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$RUNTIME_CONFIG_LINK")"
python3 - "$CONFIG_PATH" "$QUEUE" "$TASK_SPACE" "$DELAY_SECONDS" \
  "$READY_TIMEOUT_SECONDS" "$GENERATION_TIMEOUT_SECONDS" "$MAX_ITEMS" \
  "$MAX_ATTEMPTS" "$RETRY_FAILED" "$KEEP_BROWSER" "$ROOT/.art-pipeline/reports" \
  "$FFMPEG_BIN" "$FFPROBE_BIN" "$REPORT_KEY" <<'PY'
import json
import sys
from pathlib import Path

(
    config_path,
    queue,
    task_space,
    delay,
    ready_timeout,
    generation_timeout,
    max_items,
    max_attempts,
    retry_failed,
    keep_browser,
    report_dir,
    ffmpeg_bin,
    ffprobe_bin,
    report_key,
) = sys.argv[1:]
value = {
    "queue": str(Path(queue).resolve()),
    "task_space": task_space,
    "delay_seconds": int(delay),
    "ready_timeout_seconds": int(ready_timeout),
    "generation_timeout_seconds": int(generation_timeout),
    "max_items": int(max_items),
    "max_attempts": int(max_attempts),
    "retry_failed": retry_failed == "1",
    "keep_browser": keep_browser == "1",
    "report_dir": str(Path(report_dir).resolve()),
    "ffmpeg_bin": str(Path(ffmpeg_bin).resolve()),
    "ffprobe_bin": str(Path(ffprobe_bin).resolve()),
    "report_key": report_key,
}
Path(config_path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
PY
printf '%s\n' "$CONFIG_PATH" > "$RUNTIME_POINTER"
rm -f "$RUNTIME_CONFIG_LINK"
ln -s "$CONFIG_PATH" "$RUNTIME_CONFIG_LINK"
EGO_SOURCE="$(mktemp "$HOME/.cache/lingnong-art-pipeline/ego-source.XXXXXX")"
python3 - "$0" "$EGO_SOURCE" "$RUNTIME_CONFIG_LINK" <<'PY'
import json
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_text(encoding="utf-8")
marker = ": <<'EGO_JS'\n"
start = source.index(marker) + len(marker)
end = source.index("\nEGO_JS", start)
script = source[start:end].replace(
    "'__LINGNONG_RUNTIME_CONFIG__'", json.dumps(sys.argv[3])
)
Path(sys.argv[2]).write_text(script + "\n", encoding="utf-8")
PY

set +e
ego-browser nodejs < "$EGO_SOURCE"
RUN_STATUS=$?
set -e
if false; then
: <<'EGO_JS'
import fs from 'node:fs'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'

const runtimeConfigPath = '__LINGNONG_RUNTIME_CONFIG__'
const config = JSON.parse(fs.readFileSync(runtimeConfigPath, 'utf8'))
const queuePath = path.resolve(config.queue)
const taskSpaceName = config.task_space
const delaySeconds = Number(config.delay_seconds)
const readyTimeoutSeconds = Number(config.ready_timeout_seconds)
const generationTimeoutSeconds = Number(config.generation_timeout_seconds)
const maxItems = Number(config.max_items)
const maxAttempts = Number(config.max_attempts)
const retryFailed = Boolean(config.retry_failed)
const ffmpegBin = path.resolve(config.ffmpeg_bin)
const ffprobeBin = path.resolve(config.ffprobe_bin)

const queue = JSON.parse(fs.readFileSync(queuePath, 'utf8'))
if (queue.schema_version !== 2) throw new Error(`Expected queue schema 2, got ${queue.schema_version}`)
if (queue.kind !== 'static') throw new Error(`Expected a static queue, got ${queue.kind}`)
if (queue.concurrency !== 1) throw new Error('Browser queue concurrency must remain 1')

const reportDir = path.resolve(config.report_dir)
fs.mkdirSync(reportDir, { recursive: true })
const reportPath = path.join(reportDir, `static-${config.report_key || 'latest'}.json`)

function now() { return new Date().toISOString() }
function persist() {
  const temp = `${queuePath}.${process.pid}.tmp`
  fs.writeFileSync(temp, JSON.stringify(queue, null, 2) + '\n')
  fs.renameSync(temp, queuePath)
}

function sha256File(file) {
  const hash = createHash('sha256')
  hash.update(fs.readFileSync(file))
  return hash.digest('hex')
}

function computeInputDigest(item) {
  const files = [item.prompt_file, ...(item.reference_files || [])]
  const hash = createHash('sha256')
  hash.update(Buffer.from('lingnong-input-v1\0'))
  for (const file of files) {
    if (!fs.existsSync(file)) throw new Error(`Input file is missing: ${file}`)
    const content = fs.readFileSync(file)
    hash.update(Buffer.from(`bytes:${content.length}\n`))
    hash.update(content)
  }
  return hash.digest('hex')
}

function refreshResolvableInputDigests() {
  for (const item of queue.items) {
    if (item.status === 'done') continue
    try {
      const currentPromptDigest = sha256File(item.prompt_file)
      if (item.prompt_digest !== currentPromptDigest) {
        item.status = 'failed'
        item.last_error = 'Canonical prompt changed after queue creation; rebuild the queue.'
        item.updated_at = now()
        continue
      }
      const current = computeInputDigest(item)
      if (!item.input_digest) {
        item.input_digest = current
        item.attempts = 0
        if (!fs.existsSync(item.output_file)) item.status = 'pending'
        item.last_error = 'Generated dependencies became available; attempts were reset.'
        item.updated_at = now()
      } else if (item.input_digest !== current) {
        item.status = 'failed'
        item.last_error = 'Prompt or reference inputs changed after queue creation; rebuild the queue.'
        item.updated_at = now()
      }
    } catch (_) {
      // A generated dependency may not exist yet; dependency scheduling handles it.
    }
  }
}

function validateProvenance(item, inputDigest) {
  if (!inputDigest) throw new Error('Current input digest is unresolved')
  if (!fs.existsSync(item.output_meta_file)) {
    throw new Error(`Provenance metadata is missing: ${item.output_meta_file}`)
  }
  const metadata = JSON.parse(fs.readFileSync(item.output_meta_file, 'utf8'))
  if (metadata.id !== item.id) throw new Error('Provenance asset id does not match')
  if (metadata.input_digest !== inputDigest) {
    throw new Error('Prompt or reference inputs changed after this image was generated')
  }
  if (metadata.output_digest !== sha256File(item.output_file)) {
    throw new Error('Output content changed after completion')
  }
  return metadata
}

function writeProvenance(item, inputDigest) {
  const metadata = {
    schema_version: 1,
    id: item.id,
    input_digest: inputDigest,
    output_digest: sha256File(item.output_file),
    completed_at: now(),
  }
  const temporary = `${item.output_meta_file}.${process.pid}.tmp`
  fs.mkdirSync(path.dirname(item.output_meta_file), { recursive: true })
  fs.writeFileSync(temporary, JSON.stringify(metadata, null, 2) + '\n')
  fs.renameSync(temporary, item.output_meta_file)
}

function promptFromMarkdown(file) {
  const markdown = fs.readFileSync(file, 'utf8')
  const match = markdown.match(/```text\n([\s\S]*?)\n```/)
  if (!match) throw new Error(`No copyable text prompt in ${file}`)
  return match[1].trim()
}

function probeImage(file) {
  const result = spawnSync(ffprobeBin, [
    '-v', 'error', '-count_frames', '-select_streams', 'v:0',
    '-show_entries', 'stream=width,height,codec_name,pix_fmt,nb_read_frames',
    '-of', 'json', file,
  ], { encoding: 'utf8', timeout: 30000, maxBuffer: 16 * 1024 * 1024 })
  if (result.status !== 0) {
    const detail = result.error?.message || String(result.stderr || '').trim() || `exit ${result.status}`
    throw new Error(`ffprobe rejected ${file}: ${detail}`)
  }
  const stream = JSON.parse(result.stdout).streams?.[0]
  if (!stream?.width || !stream?.height) throw new Error(`No image dimensions in ${file}`)
  if (String(stream.nb_read_frames || '') !== '1') {
    throw new Error(`Animated or multi-frame images are not accepted: ${file}`)
  }
  return stream
}

function alphaCoverage(file, width, height) {
  const result = spawnSync(ffmpegBin, [
    '-hide_banner', '-loglevel', 'error', '-i', file,
    '-vf', 'alphaextract', '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'gray', '-',
  ], { encoding: null, timeout: 30000, maxBuffer: 256 * 1024 * 1024 })
  if (result.status !== 0 || !Buffer.isBuffer(result.stdout) || result.stdout.length === 0) {
    throw new Error('Image has no readable alpha channel')
  }
  if (result.stdout.length !== width * height) {
    throw new Error(`Image alpha channel has ${result.stdout.length} pixels; expected ${width * height}`)
  }
  let transparent = 0
  let visible = 0
  for (const value of result.stdout.values()) {
    if (value < 16) transparent += 1
    if (value > 32) visible += 1
  }
  const cornerIndices = [0, width - 1, (height - 1) * width, result.stdout.length - 1]
  return {
    transparentRatio: transparent / result.stdout.length,
    visibleRatio: visible / result.stdout.length,
    transparentCorners: cornerIndices.filter(index => result.stdout[index] < 16).length,
  }
}

function validateCanonicalImage(file, item) {
  const image = probeImage(file)
  if (image.width !== item.expected_width || image.height !== item.expected_height) {
    throw new Error(`Image is ${image.width}x${image.height}; expected ${item.expected_width}x${item.expected_height}`)
  }
  if (item.background === 'transparent') {
    const coverage = alphaCoverage(file, image.width, image.height)
    if (coverage.transparentRatio < 0.10 || coverage.visibleRatio < 0.005 || coverage.transparentCorners < 3) {
      throw new Error(
        `Transparent asset failed alpha coverage checks ` +
        `(transparent=${(coverage.transparentRatio * 100).toFixed(2)}%, ` +
        `visible=${(coverage.visibleRatio * 100).toFixed(2)}%, ` +
        `transparent_corners=${coverage.transparentCorners}/4)`
      )
    }
  }
  return image
}

function normalizeImage(source, destination, item) {
  const sourceImage = probeImage(source)
  if (item.background === 'transparent') {
    const coverage = alphaCoverage(source, sourceImage.width, sourceImage.height)
    if (coverage.transparentRatio < 0.10 || coverage.visibleRatio < 0.005 || coverage.transparentCorners < 3) {
      throw new Error(
        `Generated ${sourceImage.codec_name} image failed alpha coverage checks ` +
        `(transparent=${(coverage.transparentRatio * 100).toFixed(2)}%, ` +
        `visible=${(coverage.visibleRatio * 100).toFixed(2)}%, ` +
        `transparent_corners=${coverage.transparentCorners}/4)`
      )
    }
  }
  const width = Number(item.expected_width)
  const height = Number(item.expected_height)
  const filter = item.background === 'transparent'
    ? `format=rgba,scale=${width}:${height}:force_original_aspect_ratio=decrease:flags=lanczos,pad=${width}:${height}:(ow-iw)/2:(oh-ih)/2:color=0x00000000,format=rgba`
    : `scale=${width}:${height}:force_original_aspect_ratio=increase:flags=lanczos,crop=${width}:${height},format=rgb24`
  const result = spawnSync(ffmpegBin, [
    '-hide_banner', '-loglevel', 'error', '-y', '-i', source,
    '-vf', filter, '-frames:v', '1', destination,
  ], { encoding: 'utf8', timeout: 120000 })
  if (result.status !== 0) throw new Error(`Image normalization failed: ${result.stderr.trim()}`)
  return validateCanonicalImage(destination, item)
}

function rejectReferenceClone(output, item) {
  for (const reference of item.reference_files || []) {
    if (!fs.existsSync(reference)) continue
    const result = spawnSync(ffmpegBin, [
      '-hide_banner', '-i', output, '-i', reference,
      '-lavfi', `[1:v]scale=${item.expected_width}:${item.expected_height}[ref];[0:v][ref]ssim`,
      '-f', 'null', '-',
    ], { encoding: 'utf8', timeout: 120000, maxBuffer: 16 * 1024 * 1024 })
    if (result.error) throw new Error(`Reference-clone check failed: ${result.error.message}`)
    if (result.status !== 0) throw new Error(`Reference-clone check failed: ${String(result.stderr || '').trim()}`)
    const matches = [...String(result.stderr || '').matchAll(/All:([0-9.]+)/g)]
    const score = matches.length ? Number(matches.at(-1)[1]) : Number.NaN
    if (!Number.isFinite(score)) throw new Error(`Reference-clone check returned no SSIM score for ${reference}`)
    if (score >= 0.90) {
      throw new Error(
        `Downloaded image is a near-copy of uploaded reference ${path.basename(reference)} ` +
        `(SSIM=${score.toFixed(4)}); it is not accepted as a generated asset`
      )
    }
  }
}

function writeDataUrl(dataUrl, outputFile) {
  const match = /^data:([^;]+);base64,(.+)$/s.exec(dataUrl)
  if (!match) throw new Error('Browser returned an invalid image data URL')
  const mime = match[1]
  const bytes = Buffer.from(match[2], 'base64')
  if (bytes.length < 64) throw new Error(`Generated image is unexpectedly small: ${bytes.length} bytes`)
  fs.mkdirSync(path.dirname(outputFile), { recursive: true })
  if (mime === 'image/png') {
    fs.writeFileSync(outputFile, bytes)
    return
  }
  const extension = mime.includes('webp') ? '.webp' : mime.includes('jpeg') ? '.jpg' : '.img'
  const source = `${outputFile}${extension}`
  fs.writeFileSync(source, bytes)
  const converted = spawnSync(ffmpegBin, ['-hide_banner', '-loglevel', 'error', '-y', '-i', source, '-frames:v', '1', outputFile], { encoding: 'utf8', timeout: 120000 })
  fs.rmSync(source, { force: true })
  if (converted.status !== 0) throw new Error(`ffmpeg conversion failed: ${converted.stderr.trim()}`)
}

async function waitForPromptBox() {
  const deadline = Date.now() + readyTimeoutSeconds * 1000
  while (Date.now() < deadline) {
    const state = await js(String.raw`(() => ({
      prompt: Boolean(document.querySelector('#prompt-textarea')),
      login: [...document.querySelectorAll('a,button')].some(el => /log in|登录/i.test(el.textContent || '')),
      blocked: /captcha|verify you are human|cloudflare|验证码|人机验证/i.test((document.body?.innerText || '').slice(0, 20000)),
      url: location.href
    }))()`)
    if (state.blocked) {
      throw new Error('ChatGPT page is blocked by a CAPTCHA or Cloudflare verification')
    }
    if (state.login || /auth|login/.test(state.url)) {
      throw new Error('ChatGPT login is required in the ego-browser profile')
    }
    if (state.prompt) return
    await wait(2)
  }
  throw new Error(`ChatGPT prompt box was not ready after ${readyTimeoutSeconds}s`)
}

async function uploadReferences(files) {
  for (let index = 0; index < files.length; index += 1) {
    const file = files[index]
    if (!fs.existsSync(file)) throw new Error(`Missing reference image: ${file}`)
    const baseline = await js(String.raw`(() => ({
      attachments: document.querySelectorAll('form[data-type="unified-composer"] img').length,
      removeButtons: document.querySelectorAll('form[data-type="unified-composer"] button[aria-label*="移除文件"], form[data-type="unified-composer"] button[aria-label*="Remove file"]').length
    }))()`)
    await uploadFile('#upload-files', file)
    const deadline = Date.now() + 120000
    let attached = false
    while (Date.now() < deadline) {
      const state = await js(String.raw`(() => ({
        attachments: document.querySelectorAll('form[data-type="unified-composer"] img').length,
        removeButtons: document.querySelectorAll('form[data-type="unified-composer"] button[aria-label*="移除文件"], form[data-type="unified-composer"] button[aria-label*="Remove file"]').length,
        uploadBusy: Boolean(document.querySelector('form[data-type="unified-composer"] [data-state="loading"], form[data-type="unified-composer"] [aria-busy="true"]'))
      }))()`)
      if (
        !state.uploadBusy &&
        (state.attachments > baseline.attachments || state.removeButtons > baseline.removeButtons)
      ) {
        attached = true
        break
      }
      await wait(2)
    }
    if (!attached) throw new Error(`Reference upload did not finish: ${file}`)
  }
}

async function submitPrompt(prompt) {
  try {
    await fillInput('#prompt-textarea', prompt)
  } catch (_) {
    await click('#prompt-textarea')
    await typeText(prompt)
  }
  await wait(1)
  const enabled = await js(String.raw`Boolean(document.querySelector('button[data-testid="send-button"]:not([disabled])'))`)
  if (enabled) {
    await click('button[data-testid="send-button"]', { label: 'submit image prompt' })
  } else {
    await pressKey('ENTER')
  }
}

async function conversationBaseline() {
  return await js(String.raw`(() => {
    return {
      imageSources: [...document.images].map(img => img.currentSrc || img.src).filter(Boolean),
    }
  })()`)
}

async function waitForGeneratedImage(baseline) {
  const previous = new Set(baseline.imageSources || [])
  const deadline = Date.now() + generationTimeoutSeconds * 1000
  let stableSource = ''
  let stableChecks = 0
  while (Date.now() < deadline) {
    const state = await js(String.raw`(() => {
      const busy = Boolean(document.querySelector('button[data-testid="stop-button"], button[aria-label*="Stop"], button[aria-label*="停止"]'))
      return {
        busy,
        mainImages: [...document.querySelectorAll('main img')].map(img => ({
          src: img.currentSrc || img.src,
          width: img.naturalWidth || img.width || 0,
          height: img.naturalHeight || img.height || 0,
          alt: img.getAttribute('alt') || '',
          messageRole: img.closest('[data-message-author-role]')?.getAttribute('data-message-author-role') || '',
        })).filter(item => item.src),
      }
    })()`)
    // Uploaded references can receive a new estuary URL after submission. They
    // must never be accepted merely because their URL was absent from baseline.
    // Current ChatGPT generated-image canvases have no data-message-author-role
    // wrapper, so the explicit generated-image alt text is the stable signal.
    // Reject user-role images as an additional guard against uploaded files.
    const candidates = state.mainImages.filter(item =>
      !previous.has(item.src) && item.width >= 256 && item.height >= 256 &&
      item.messageRole !== 'user' &&
      /generated|已生成/i.test(item.alt || '')
    )
    const candidate = candidates.sort((a, b) => (b.width * b.height) - (a.width * a.height))[0]
    if (!state.busy && candidate) {
      if (candidate.src === stableSource) stableChecks += 1
      else { stableSource = candidate.src; stableChecks = 1 }
      if (stableChecks >= 3) return candidate.src
    } else {
      stableChecks = 0
    }
    await wait(5)
  }
  throw new Error(`Image generation did not complete after ${generationTimeoutSeconds}s`)
}

async function imageAsDataUrl(src) {
  const encoded = JSON.stringify(src)
  return await js(String.raw`(async () => {
    const response = await fetch(${encoded})
    if (!response.ok) throw new Error('image fetch failed: ' + response.status)
    const blob = await response.blob()
    return await new Promise((resolve, reject) => {
      const reader = new FileReader()
      reader.onerror = () => reject(reader.error)
      reader.onload = () => resolve(reader.result)
      reader.readAsDataURL(blob)
    })
  })()`)
}

async function runItem(item) {
  if (fs.existsSync(item.output_file) && item.status === 'done') return
  const currentPromptDigest = sha256File(item.prompt_file)
  if (item.prompt_digest !== currentPromptDigest) {
    throw new Error('Canonical prompt changed after queue creation; rebuild the queue')
  }
  const inputDigest = computeInputDigest(item)
  if (item.input_digest !== inputDigest) {
    throw new Error('Prompt or reference inputs changed after queue creation; rebuild the queue')
  }
  const tempRaw = `${item.output_file}.${process.pid}.raw.png`
  const tempOutput = `${item.output_file}.${process.pid}.part.png`
  item.status = 'running'
  item.attempts = Number(item.attempts || 0) + 1
  item.last_error = ''
  item.updated_at = now()
  persist()

  await gotoAndWait('https://chatgpt.com/', { timeout: 60, settle: 3 })
  await waitForPromptBox()
  await uploadReferences(item.reference_files || [])
  const before = await conversationBaseline()
  await submitPrompt(promptFromMarkdown(item.prompt_file))
  const src = await waitForGeneratedImage(before)
  const dataUrl = await imageAsDataUrl(src)
  fs.rmSync(tempRaw, { force: true })
  fs.rmSync(tempOutput, { force: true })
  writeDataUrl(dataUrl, tempRaw)
  let image = normalizeImage(tempRaw, tempOutput, item)
  rejectReferenceClone(tempOutput, item)
  fs.mkdirSync(path.dirname(item.output_file), { recursive: true })
  if (fs.existsSync(item.output_file)) {
    image = validateCanonicalImage(item.output_file, item)
    validateProvenance(item, inputDigest)
    fs.rmSync(tempOutput, { force: true })
  } else {
    try {
      // A hard-link publish is atomic and refuses to replace a file that appeared
      // while the browser was generating this item.
      fs.linkSync(tempOutput, item.output_file)
      fs.rmSync(tempOutput, { force: true })
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error
      image = validateCanonicalImage(item.output_file, item)
      validateProvenance(item, inputDigest)
      fs.rmSync(tempOutput, { force: true })
    }
  }
  fs.rmSync(tempRaw, { force: true })
  writeProvenance(item, inputDigest)
  item.actual_width = image.width
  item.actual_height = image.height
  item.codec = image.codec_name
  item.pix_fmt = image.pix_fmt
  item.dimension_warning = false
  item.status = 'done'
  item.updated_at = now()
  refreshResolvableInputDigests()
  persist()
}

const queueById = new Map(queue.items.map(item => [item.id, item]))

function dependencyBlockReason(item) {
  for (const dependencyId of item.dependencies || []) {
    const dependency = queueById.get(dependencyId)
    if (!dependency) return `dependency ${dependencyId} is not present in this queue`
    if (dependency.status !== 'done') {
      return `dependency ${dependencyId} is ${dependency.status}, not done`
    }
    if (!fs.existsSync(dependency.output_file)) {
      return `dependency ${dependencyId} output is missing`
    }
    try {
      validateCanonicalImage(dependency.output_file, dependency)
      if (dependency.prompt_digest !== sha256File(dependency.prompt_file)) {
        throw new Error('canonical prompt changed after queue creation')
      }
      const dependencyDigest = computeInputDigest(dependency)
      if (dependency.input_digest !== dependencyDigest) {
        throw new Error('prompt or reference inputs changed after queue creation')
      }
      validateProvenance(dependency, dependencyDigest)
    } catch (error) {
      return `dependency ${dependencyId} output is invalid: ${String(error?.message || error)}`
    }
  }
  return ''
}

for (const item of queue.items) {
  if (item.status === 'running') {
    item.status = 'pending'
    item.attempts = Math.max(0, Number(item.attempts || 0) - 1)
    item.last_error = 'Recovered an interrupted running item; it will resume from the queue.'
    item.updated_at = now()
  }
  if (!fs.existsSync(item.output_file)) continue
  const dependencyError = dependencyBlockReason(item)
  if (dependencyError) {
    item.status = 'pending'
    item.last_error = `Waiting for provenance-verified dependency: ${dependencyError}`
    item.updated_at = now()
    continue
  }
  try {
    const image = validateCanonicalImage(item.output_file, item)
    const currentPromptDigest = sha256File(item.prompt_file)
    if (item.prompt_digest !== currentPromptDigest) {
      throw new Error('Canonical prompt changed after queue creation; rebuild the queue')
    }
    const inputDigest = computeInputDigest(item)
    if (item.input_digest !== inputDigest) {
      throw new Error('Prompt or reference inputs changed after queue creation; rebuild the queue')
    }
    validateProvenance(item, inputDigest)
    item.actual_width = image.width
    item.actual_height = image.height
    item.codec = image.codec_name
    item.pix_fmt = image.pix_fmt
    item.dimension_warning = false
    item.status = 'done'
    item.last_error = ''
    item.updated_at = now()
  } catch (error) {
    item.status = 'failed'
    item.last_error = `Existing output is invalid and was preserved: ${String(error?.message || error)}`
    item.updated_at = now()
  }
}
refreshResolvableInputDigests()
persist()

const eligible = queue.items.filter(item => {
  if (item.status === 'pending') return Number(item.attempts || 0) < maxAttempts
  if (retryFailed && item.status === 'failed') return Number(item.attempts || 0) < maxAttempts
  return false
})
const selected = maxItems > 0 ? eligible.slice(0, maxItems) : eligible
const report = {
  started_at: now(), queue: queuePath, task_space: taskSpaceName,
  concurrency: 1, selected: selected.length, done: [], failed: [], skipped: [],
}

function isGlobalBrowserError(message) {
  return /login is required|captcha|cloudflare|user is controlling|not assigned|task space.*inactive|browser control/i.test(message)
}

let activeTask = null
try {
  activeTask = await useOrCreateTaskSpace(taskSpaceName)
  report.task_space_id = activeTask.id
  await openOrReuseTab('https://chatgpt.com/', { wait: true, timeout: 60 })
  await waitForPromptBox()
  for (let index = 0; index < selected.length; index += 1) {
    const item = selected[index]
    const dependencyError = dependencyBlockReason(item)
    if (dependencyError) {
      item.status = 'pending'
      item.last_error = `Waiting without consuming an attempt: ${dependencyError}`
      item.updated_at = now()
      persist()
      report.skipped.push({ id: item.id, reason: dependencyError })
      cliLog(`SKIP ${item.id}: ${dependencyError}`)
      continue
    }
    try {
      cliLog(`START ${index + 1}/${selected.length} ${item.id}`)
      await runItem(item)
      report.done.push(item.id)
      cliLog(`DONE ${item.id} ${item.actual_width}x${item.actual_height}`)
    } catch (error) {
      fs.rmSync(`${item.output_file}.${process.pid}.raw.png`, { force: true })
      fs.rmSync(`${item.output_file}.${process.pid}.part.png`, { force: true })
      fs.rmSync(`${item.output_meta_file}.${process.pid}.tmp`, { force: true })
      const message = String(error?.message || error)
      if (isGlobalBrowserError(message)) {
        item.status = 'pending'
        item.attempts = Math.max(0, Number(item.attempts || 0) - 1)
        item.last_error = `Batch paused without consuming an attempt: ${message}`
        item.updated_at = now()
        persist()
        report.global_error = item.last_error
        cliLog(`PAUSED ${item.id}: ${message}`)
        throw error
      }
      item.status = 'failed'
      item.last_error = message
      item.updated_at = now()
      persist()
      report.failed.push({ id: item.id, error: item.last_error })
      cliLog(`FAILED ${item.id}: ${item.last_error}`)
    }
    if (index + 1 < selected.length && delaySeconds > 0) await wait(delaySeconds)
  }
} catch (error) {
  const message = String(error?.message || error)
  if (isGlobalBrowserError(message)) {
    report.global_error = report.global_error || `Batch paused: ${message}`
    report.preserve_task_space = true
    if (activeTask && /login is required|captcha|cloudflare/i.test(message)) {
      try {
        report.handoff = await handOffTaskSpace(activeTask.id)
      } catch (handoffError) {
        report.handoff_error = String(handoffError?.message || handoffError)
      }
    }
  } else {
    report.run_error = message
  }
  throw error
} finally {
  report.finished_at = now()
  report.queue_counts = queue.items.reduce((acc, item) => {
    acc[item.status] = (acc[item.status] || 0) + 1
    return acc
  }, { pending: 0, running: 0, done: 0, failed: 0 })
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2) + '\n')
  cliLog(JSON.stringify({ report: reportPath, ...report.queue_counts }))
}
if (report.queue_counts.failed > 0) process.exitCode = 4
else if (report.skipped.length > 0) process.exitCode = 5
EGO_JS
fi
rm -f "$CONFIG_PATH"
rm -f "$RUNTIME_POINTER"
rm -f "$RUNTIME_CONFIG_LINK"
rm -f "$EGO_SOURCE"

# Task-space cleanup is deliberately isolated in its own final ego-browser run.
REPORT_PATH="$ROOT/.art-pipeline/reports/static-$REPORT_KEY.json"
PRESERVE_TASK_SPACE="$(python3 - "$REPORT_PATH" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
try:
    value = json.loads(path.read_text())
except (OSError, json.JSONDecodeError):
    value = {}
print("1" if value.get("preserve_task_space") else "0")
PY
)"
if [[ "$PRESERVE_TASK_SPACE" == "1" ]]; then
  printf '{"task_space":"%s","cleanup":"preserved-for-user"}\n' "$TASK_SPACE"
  CLEANUP_STATUS=0
else
  set +e
  EGO_CLEANUP_SOURCE="$(mktemp "$HOME/.cache/lingnong-art-pipeline/ego-cleanup.XXXXXX")"
  cat > "$EGO_CLEANUP_SOURCE" <<EGO_CLEANUP
import fs from 'node:fs'
import path from 'node:path'
const name = $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$TASK_SPACE")
const keep = $([[ "$KEEP_BROWSER" == "1" ]] && echo true || echo false)
const reportPath = $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$REPORT_PATH")
let report = {}
try { report = JSON.parse(fs.readFileSync(reportPath, 'utf8')) } catch (_) {}
const target = report.task_space_id ?? name
const spaces = await listTaskSpaces()
const task = spaces.find(item => String(item.id) === String(target) || item.name === target)
if (task) {
  const result = await completeTaskSpace(task.id, { keep })
  cliLog(JSON.stringify({ task_space: task.id, keep, cleanup: result }))
} else {
  cliLog(JSON.stringify({ task_space: target, cleanup: 'not-found' }))
}
EGO_CLEANUP
  ego-browser nodejs < "$EGO_CLEANUP_SOURCE"
  CLEANUP_STATUS=$?
  rm -f "$EGO_CLEANUP_SOURCE"
  set -e
fi

if (( RUN_STATUS != 0 )); then
  exit "$RUN_STATUS"
fi
exit "$CLEANUP_STATUS"
