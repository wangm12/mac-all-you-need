# Spec 2 — Voice Pipeline Latency + ASR Model Strategy (TODO)

Status: **Deferred. Frame after Spec 1 (Personalization) lands.**
Owner: mingjie-father
Created: 2026-05-14 | Updated: 2026-05-15

---

## Goal
两个并行目标：
1. **降低延迟**：post-release 等待从 ~2.5s 降到 ≤500ms，感觉像 Typeless。
2. **解决中英混合 code-switching 问题**：Qwen3-ASR-0.6B auto 模式遇到英文主导内容会把中文翻译成英文，需要更好的模型或策略。

---

## 竞品调研结论（2026-05-15）

### Typeless 用的什么
- **云端 ASR**，音频发到 AWS us-east-2（独立测试证实）
- 大概率是 **Groq Whisper Large V3 / Turbo** — 唯一能做到近实时 + 100+ 语言 + 自然 code-switching 的方案
- Post-processing 是自己的 LLM（做 cleanup、格式化、个性化）
- 他们的 code-switching 好 = 云端大模型，不是什么黑魔法

### FluidVoice（https://github.com/altic-dev/FluidVoice）
- 和我们一样基于 FluidAudio
- 额外支持：Parakeet TDT v3、**Cohere Transcribe**（Apple Silicon 优化，含 Mandarin）、Whisper（本地）
- Cohere Transcribe：14 语言，含 Mandarin + English，专为 Apple Silicon 优化，但无显式 code-switching 文档

### OpenWhispr（https://github.com/OpenWhispr/openwhispr）
- Electron 跨平台，whisper.cpp 本地 + sherpa-onnx ONNX 推理
- 支持 OpenAI Whisper（本地/云端）+ Parakeet
- 无中文 code-switching 专项优化

---

## 当前状态（2026-05-15 verified）

- ASR：**Qwen3-ASR 0.6B**（f32 ~1.75GB / int8 ~900MB），FluidAudio + CoreML，macOS 15+
- `maxNewTokens` 已从 512 → **8192**（commit bf9e995，覆盖 ~30 分钟录音）
- ASR batch-only，无原生 streaming
- Cleanup：用户自带 LLM provider（云端）
- Pipeline：`record → batch ASR → LLM cleanup → paste`，两次串行等待

### 已知问题
- **Code-switching**：Qwen3-0.6B auto 模式遇英文主导内容（大量技术词汇）会把中文部分翻译成英文。
  - 临时缓解：Language hint 设为 Chinese（保中文输出，英文词保留）
  - 根本解决：升 ASR 模型

---

## ASR 模型选项对比（2026-05-15 新增）

| 模型 | 大小 | Code-switching | On-device | 备注 |
|---|---|---|---|---|
| **Qwen3-ASR-0.6B**（当前） | ~1.75GB | ⚠️ auto 模式有问题 | ✅ | FluidAudio 支持 |
| **Qwen3-ASR-1.7B** | ~3.5GB | ✅ 明显改善 | ✅ | FluidAudio **暂未支持**；同家族，最容易切换；1.7B 语言识别准确率 97.9% |
| **Groq Whisper Large V3** | 云端 | ✅✅ 最好 | ❌ 需联网 | $0.00185/min，164x 实时速度 |
| **Groq Whisper Large V3 Turbo** | 云端 | ✅✅ | ❌ 需联网 | **$0.0006/min**，228x 实时速度，业界最便宜 |
| **Cohere Transcribe**（FluidVoice 用） | 未知 | ⚠️ 未测试 | ✅ Apple Silicon 优化 | 需等 FluidAudio 集成 |
| **Parakeet TDT v3**（已在 FluidAudio） | ~500MB | ⚠️ 有中文但无专项 | ✅ | 25 语言，无 code-switching 优化 |
| **MiMo-V2.5 8B**（小米，MIT） | ~16GB | ✅✅✅ 最强 | ❌ 太大 | 目前最好的 code-switching |

### Groq Whisper 价格详情
- **Whisper Large V3**：$0.111/hr ≈ $0.00185/min
- **Whisper Large V3 Turbo**：$0.04/hr ≈ $0.0006/min（约 $3.6/100 小时语音，极便宜）
- Free tier 存在（每天有限额）
- 典型 5 分钟 dictation：~$0.003，可忽略不计
- 速度：228x 实时，5 分钟音频 < 1.3 秒处理完

---

## 延迟优化方案

### A. VAD 分段转写（推荐）
- 录音时 VAD 检测停顿边界，每段独立转写（后台）
- 释放时只转最后一段
- 优点：极少额外计算，无重叠 re-encoding
- 待确认：FluidAudio 是否内置 VAD

### B. Chunked-prefix 转写（备选）
- 每 N 秒转写当前缓冲区
- 优点：无 VAD 依赖
- 缺点：Qwen3 每次重 encode 重叠音频，GPU 浪费

### C. ASR Provider 选择（新增，参考 cleanup provider 设计）
- 默认：Qwen3 本地（隐私优先）
- 可选：Groq Whisper（更好 code-switching + 近实时速度，需 Groq key）
- UX：与现有 cleanup provider 选择完全一致，用户已经熟悉这个模式
- 好处：解决 code-switching 问题，同时给有需要的用户提供云端大模型

---

## 验收标准
- **ASR 准确率**：vs 当前 batch baseline，WER 回归 ≤5%（20 样本测试）
- **Cleanup 质量**：≥90% 的 dictation 无需手动再编辑
- **延迟**：post-release ≤500ms p50（5-15 秒录音，M 系列 Mac）
- **Code-switching**：中英混合的中文部分保留中文字符，不被翻译成英文

---

## 待确认问题
1. FluidAudio 是否已内置 VAD？（看 FluidVoice 源码有 VAD 选项）
2. FluidAudio 何时支持 Qwen3-ASR-1.7B？（关注官方 changelog）
3. Groq Whisper 有没有 free tier 足够日常 dogfood 用？
4. Cohere Transcribe 的 code-switching 实测效果如何？（可从 FluidVoice 二进制测试）
5. 离线 fallback：Groq 不可用时，自动回退到本地 Qwen3，还是显示 error？
6. ~~maxNewTokens 512 限制~~：已解决，已改为 8192（commit bf9e995）

---

## 推荐路线（优先级排序）

### 短期（直接上）
- [x] `maxNewTokens` 512 → 8192（已 done，bf9e995）
- [ ] 在 Voice Settings 里加 **ASR Language** 选项（Auto / Chinese / English），让用户自己选

### 中期（Spec 2 正式开始时）
- [ ] 加 **Groq Whisper** 作为可选 ASR provider（像 cleanup 那样 BYOK）
- [ ] 实验 VAD 分段转写（Option A）
- [ ] 20 样本 WER 基准测试

### 长期（等 FluidAudio 更新）
- [ ] 升到 Qwen3-ASR-1.7B（同家族，最小改动，最好的 on-device code-switching 提升）
- [ ] 评估 Cohere Transcribe（如果 FluidAudio 集成进来）

---

## 参考
- [Groq Whisper 定价](https://groq.com/pricing)
- [Groq Whisper 164x 实时速度](https://groq.com/blog/groq-runs-whisper-large-v3-at-a-164x-speed-factor-according-to-new-artificial-analysis-benchmark)
- [Qwen3-ASR-1.7B HuggingFace](https://huggingface.co/Qwen/Qwen3-ASR-1.7B)
- [MiMo-V2.5-ASR](https://huggingface.co/XiaomiMiMo/MiMo-V2.5-ASR)
- [FluidVoice](https://github.com/altic-dev/FluidVoice)
- [OpenWhispr](https://github.com/OpenWhispr/openwhispr)
