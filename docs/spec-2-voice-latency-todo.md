# Spec 2 — Voice Quality + Latency

Status: **Track 1 done. Track 2 ready to plan.**
Owner: mingjie-father
Created: 2026-05-14 | Updated: 2026-05-15 (post-testing rewrite)

---

## 目标

1. **正确性（已部分解决）**：长录音不截断，code-switching 保留各自语言
2. **质量（Track 2）**：Groq Whisper 作为可选 ASR provider，解决 code-switching 质量上限
3. **延迟（Track 3）**：post-release 等待 ≤500ms（在质量解决后再做）

---

## 竞品调研（2026-05-15 已确认）

### Typeless 用的什么
- **云端 ASR**，音频发到 AWS us-east-2（独立测试证实）
- 大概率是 **Groq Whisper Large V3 / Turbo** — 唯一能做到近实时 + 100+ 语言 + 自然 code-switching 的方案
- 他们的 code-switching 好 = 云端大模型，不是什么黑魔法

### FluidVoice（https://github.com/altic-dev/FluidVoice）
- 和我们一样基于 FluidAudio，额外支持 Parakeet TDT v3、Cohere Transcribe、Whisper

### OpenWhispr（https://github.com/OpenWhispr/openwhispr）
- Electron 跨平台，whisper.cpp 本地 + ONNX

---

## 当前代码状态（2026-05-15 verified）

### 已解决
- ✅ **HUD UX**：去掉 "Ask anything"，waveform 顺滑（decay + 50ms poll + 动画），X 按钮第一次点即响应（commits 1a59253 + 9d7a59b）
- ✅ **长录音 30s 限制**：根本原因是 FluidAudio Qwen3-ASR 的 `maxCacheSeqLen = 512`（CoreML 硬限），`maxNewTokens` 参数对此无效。修法：25s 分段 chunking，每段 `maxNewTokens: 448`（= 512 - 64 template tokens），结果拼接（commit 18c8dca）
- ✅ **Chunking bug**：已修复（用户确认）

### 仍然存在
- ⚠️ **Code-switching 质量**：Qwen3-ASR 0.6B auto 模式对英文主导内容有中文→英文翻译偏置。临时缓解：Language hint 设为 Chinese。根本解决：Groq Whisper（Track 2）
- ⚠️ **延迟**：post-release ~2.5s（ASR + LLM cleanup）。在 Track 2 之后处理（Track 3）

---

## Qwen3-ASR 架构限制（从 FluidAudio 源码确认，无法通过参数绕过）

```swift
// FluidAudio/Sources/FluidAudio/ASR/Qwen3/Qwen3AsrConfig.swift
public static let maxCacheSeqLen = 512     // CoreML stateful decoder 硬限
public static let maxAudioSeconds: Double = 30.0
```

- 30s 音频 → prompt ~343 tokens → 剩余 169 tokens 给输出（约 80 汉字）
- 这是 CoreML 模型设计约束，不是 runtime 参数
- 分段 chunking 是唯一可行的本地长录音方案

---

## ASR 模型选项对比

| 模型 | 大小 | Code-switching | On-device | 长录音 | 备注 |
|---|---|---|---|---|---|
| **Qwen3-ASR-0.6B**（当前默认） | ~1.75GB | ⚠️ auto 模式偏英文 | ✅ | ✅ chunking | FluidAudio 支持 |
| **Qwen3-ASR-1.7B** | ~3.5GB | ✅ 改善 | ✅ | ✅ chunking | FluidAudio **暂未支持** |
| **Groq Whisper Large V3 Turbo** | 云端 | ✅✅ 天然 | ❌ 需联网 | ✅ 无限制 | **$0.0006/min，228x 实时** |
| **Groq Whisper Large V3** | 云端 | ✅✅ | ❌ | ✅ | $0.00185/min，更准确 |
| **Parakeet TDT v3** | ~500MB | ⚠️ 有中文 | ✅ | ⚠️ | 已在 FluidAudio，无 code-switching 优化 |
| **MiMo-V2.5 8B**（小米 MIT） | ~16GB | ✅✅✅ | ❌ 太大 | ✅ | 暂时不可行 |

---

## Groq Whisper 研究结论（2026-05-15）

### 价格
- **Turbo**：$0.04/hr ≈ $0.0006/min（业界最便宜）
- **Large V3**：$0.111/hr ≈ $0.00185/min（更高精度）
- 典型 1 分钟 dictation：**$0.0006**，可忽略不计

### Free tier 完全够个人使用
- 2,000 requests/day（每次 dictation 1 request）
- 7,200 audio seconds/hour = 每小时可转写 2 小时音频
- 28,800 audio seconds/day = **每天 8 小时音频**
- → 个人使用完全不会触碰上限，**无需付费即可 dogfood**
- 用户愿意付费 → 无限制，成本极低

### API 规格
- Endpoint：`https://api.groq.com/openai/v1/audio/transcriptions`
- OpenAI 兼容格式（multipart/form-data），WAV/MP3/FLAC 等
- Free tier 最大 25MB（= ~13 分钟 16kHz 16-bit WAV）
- 关键参数：`model`, `language`（ISO-639-1，可选，nil = auto）, `response_format=json`
- 速度：228x 实时 → 1 分钟录音 < 0.26 秒处理完

### 与现有 cleanup provider 的对比
- 用户已接受文字发到云端 cleanup provider（Anthropic/OpenAI/Groq）
- 音频数据同等隐私级别（BYOK，用户主动选择，明示告知）
- 实现模式完全一致（Keychain key，Settings，Factory，Test 按钮）

---

## Track 1：修复本地路径（✅ DONE）

- ✅ HUD UX 三项修复
- ✅ 长录音 chunking（25s 分段）
- ✅ Chunking bug 修复
- [ ] **ASR Language UI**：Voice Settings 加 Auto / Chinese / English 选项（小工作，可独立 commit）

---

## Track 2：Groq Whisper ASR Provider（READY TO PLAN）

### 架构：新增 GroqASREngine 实现现有协议

现有协议（无需修改）：
```swift
protocol VoiceTranscriptionEngine {
    var modelIdentifier: String { get }
    func transcribe(samples: [Float], sampleRate: Double, options: VoiceTranscriptionOptions) async throws -> VoiceTranscriptionResult
}
```

`GroqASREngine` 负责：
1. PCM Float32 samples → WAV bytes（in-memory，标准 RIFF）
2. multipart/form-data POST 到 Groq API
3. 解析 JSON response → `VoiceTranscriptionResult`
4. Groq 失败时 throw，让 coordinator 展示 error（不自动降级）

### 需要新增的组件

| 文件 | 职责 |
|---|---|
| `MacAllYouNeed/Voice/ASR/GroqASREngine.swift` | 实现 VoiceTranscriptionEngine，HTTP + WAV 编码 |
| `MacAllYouNeed/Voice/ASR/GroqASRSettings.swift` | provider kind、model 选择（Turbo/V3）、language |
| 扩展 `VoiceASRSettingsStore` | 保存 ASR provider 选择 |
| 新建 `VoiceASRKeyStore.swift` | Groq API key 存 Keychain（复用现有 keychain 模式） |
| `AppController.makeVoiceCoordinator()` | 根据设置选择 Qwen3Engine 或 GroqASREngine |
| `VoiceSettingsView` + 新 section | ASR provider 选择 UI（BYOK，Test 按钮） |

### WAV 编码（标准 RIFF）
```
Float32 PCM at 16kHz → scale to Int16 → RIFF header → Data
1 分钟音频 = 1,920,000 bytes ≈ 1.9 MB（< 25 MB free tier 限制）
```

### UX 设计（与 AI Cleanup 一致）
- Voice Settings → "Recognition" section
- Local (Qwen3 默认) / Groq Whisper 选择
- 选 Groq → 展开：API key 输入 + Model（Turbo/V3）+ Test 按钮
- 告知用户：音频发到 Groq，有隐私说明

---

## Track 3：延迟优化（Track 2 完成后再议）

Groq Whisper 228x 实时已基本解决延迟：
- 1 分钟录音 → < 0.26s ASR 处理
- 主要剩余延迟来自可选的 LLM cleanup

VAD 分段转写仍值得做（对本地 Qwen3 路径有益），但不再是 blocker。

---

## 验收标准

| 目标 | 标准 |
|---|---|
| 长录音（本地 Qwen3） | 1 分钟录音完整转写，chunking 正常工作 |
| Code-switching（Groq） | 英文说英文，中文说中文，字符正确，不翻译 |
| 长录音（Groq） | 任意长度（< 13 分钟/request） |
| 成本 | Free tier 够 dogfood；付费 < $0.001/次 |
| UX | Provider 选择 ≤2 步，与 cleanup 体验一致 |
| 延迟（Track 3） | post-release ≤500ms p50（5-15s 录音） |

---

## Open Questions

1. **Groq 不可用时 fallback**：自动降级 Qwen3 还是 show error？推荐：show error（降级会静默改变输出质量）
2. **Language 参数**：Groq Whisper auto 检测（language=nil）对英文主导中英混合效果如何？应在实测中验证
3. **WAV 格式**：16-bit PCM WAV 是否被 Groq 正确处理？（文档支持 WAV，但需实测）

---

## Live ASR Combination UAT（2026-06-08）

### 长录音（本地 Qwen3）

- [ ] 40s 中文连续口述：全文无丢头、25s 边界无明显重复
- [ ] 90s 中文连续口述：每 25s 读不同数字，检查接缝
- [ ] 3min 中文连续口述：Esc cancel + Undo 回放正常
- [ ] Reduce Motion 开启时 HUD 无异常

### Groq code-switching 手动实测

| 脚本 | Provider | Latency | 质量 | 误翻译 |
|------|----------|---------|------|--------|
| 纯中文 | Groq Turbo | | | |
| 纯英文 | Groq Turbo | | | |
| 句内 zh/en 切换 | Groq Turbo | | | |
| 技术术语混合 | Groq Turbo | | | |
| 数字 + 单位混合 | Groq Turbo | | | |

记录字段：`recordingMs`, `liveFinishMs`, `batchASRMs`, `cleanupMs`, `pasteMs`（见 `voice.pipeline metrics` OSLog）。

---

## 参考资料
- [Groq Whisper API 文档](https://console.groq.com/docs/speech-to-text)
- [Groq Rate Limits](https://console.groq.com/docs/rate-limits)
- [Groq 定价](https://groq.com/pricing)
- [Qwen3-ASR-1.7B HuggingFace](https://huggingface.co/Qwen/Qwen3-ASR-1.7B)
- [MiMo-V2.5-ASR](https://huggingface.co/XiaomiMiMo/MiMo-V2.5-ASR)
- [FluidVoice](https://github.com/altic-dev/FluidVoice)
- [OpenWhispr](https://github.com/OpenWhispr/openwhispr)
