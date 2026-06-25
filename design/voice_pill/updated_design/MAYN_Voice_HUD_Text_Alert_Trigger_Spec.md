---
title: "MAYN Voice HUD 文案 / Helper / Alert 触发规则"
subtitle: "Final centered native direction - UI copy, timing, hierarchy, and edge cases"
author: "MAYN Voice Design"
date: "2026-06-16"
---

# MAYN Voice HUD 文案 / Helper / Alert 触发规则

**版本:** Final centered native direction  
**基准原型:** `mayn_voice_pill_centered_final.html`  
**设计方向:** one primary pill surface, text-free recording, centered motion, caption-style helper, graphite HUD across light/dark.  
**范围:** 只定义功能/UI 设计、文案、触发条件、显示时机、优先级、edge cases。不讨论开发 scope。

---

## 0. 一句话结论

MAYN Voice HUD 应该像一个很小、很稳、很 native 的 macOS system overlay。它不是网页组件，也不是玻璃装饰件。它的语言应该是：**直接、安静、居中、必要时才说话**。

最终设计原则：

1. **只有一个真正的 surface。** 主 voice pill 是唯一的圆角 pill。上方信息只能是 caption/helper，不应该有背景、圆角、border、blur、shadow。
2. **Recording 默认不显示文字。** waveform 已经在表达 mic active；不要再显示 `Listening`。
3. **Processing 才需要文字。** 用户松开后，waveform 不再表达状态，此时显示 `Transcribing` + wipe。
4. **所有 pill 内元素都必须绝对居中。** waveform、label、wipe、terminal text 都在同一条视觉中轴线上。
5. **不要默认使用 check icon。** Hold 模式 release 就是 finish；Toggle 模式再次按 hotkey 就是 finish。checkmark 会制造不必要的按钮心智。
6. **alert 只解释异常，不抢主状态。** mic、慢速、clipboard、permission、education 都不应该把主 pill 变复杂。
7. **light/dark 都要支持，但 HUD 颜色不需要两套。** 背景环境跟随系统，HUD 本体保持同一个 graphite overlay。

最终层级应该是：

```text
caption helper, only when useful
[ centered main voice pill ]
```

而不是：

```text
[ helper pill ]
[ main pill ]
```

---

## 1. Surface 与视觉层级

### 1.1 UI surface 分类

| Layer | 视觉形式 | 作用 | 是否应该像 pill | 默认出现时机 |
|---|---|---|---|---|
| Main voice pill | graphite rounded capsule | 当前 voice session 的核心状态 | 是 | 只有 voice session 期间 |
| Caption/helper | pill 上方一行轻文字 | 临时解释、提示、轻提醒 | 否 | 仅在有必要时 |
| Blocking alert | 小型 native popover/card | 权限、错误、需要用户选择的情况 | 否 | 少数阻塞场景 |
| Cursor anchor | 光标附近极小 mic/anchor | 可选的目标位置提示 | 否 | 首次使用或 paste target 不确定时 |

### 1.2 为什么上方 indicator 不应该和 pill 同色同形

如果 top indicator 使用和主 pill 一样的颜色、圆角、border、shadow，用户会看到两个独立组件：

```text
[ top pill ]
[ main pill ]
```

这会削弱主 pill 的中心地位，也会让 HUD 显得更重。更好的方案是：

```text
caption text
[ main pill ]
```

caption/helper 的视觉规则：

| 属性 | 建议 |
|---|---|
| Background | none |
| Border | none |
| Shadow | none |
| Blur | none |
| Radius | none |
| Font size | 10.5-11px |
| Weight | 500-560 |
| Opacity | 45-60% |
| Gap from pill | 4-6px |
| Max lines | 1 line |
| Alignment | 与 pill 完全同一中轴线 |

如果一句话长到需要两行，它就不再是 caption，而应该升级为 blocking alert/popover。

---

## 2. 核心文案原则

### 2.1 Recording 阶段

Recording 阶段的默认语言是 **motion first**：

- 主 pill 只显示居中 waveform。
- 不显示 `Listening`。
- 不显示 live partial 默认文本。
- 不显示 sparkle。
- 不显示 check icon。
- 短录音不显示 timer。
- 只有异常、教育、设备变化时，才在 pill 上方显示一行 caption。

原因：用户看到 waveform 就知道系统正在听。`Listening` 是重复信息，并且会破坏 simple / native 的气质。

### 2.2 Processing 阶段

Processing 阶段的默认语言是 **text + wipe**：

- release/finish 后立即显示 `Transcribing`。
- wipe 从 release 的同一帧或下一帧开始。
- 正常状态不要暴露 `ASR`、`cleanup`、`finalizing` 等内部阶段。
- 如果慢，pill 文字改为 `Still working...`。
- 如果 auto-paste 失败但文字已复制，pill 显示 `⌘V to paste`。
- 成功不显示 `Applied`，100% hold 后直接消失。

### 2.3 不推荐使用的文案/元素

| 不建议 | 建议 | 原因 |
|---|---|---|
| `Listening` | recording 期间无文字 | waveform 已经说明状态 |
| `Applied` | 成功后直接 dismiss | 目标文本出现就是成功反馈 |
| checkmark icon | 默认不显示 | release/second hotkey 已经是 finish |
| `Stop` | hold 下不需要；processing 用 cancel 语义 | stop 容易和 finish/cancel 混淆 |
| `Failed` | 具体错误，如 `Mic unavailable` | generic failure 没有恢复路径 |
| `Better mic detected` | `Clearer mic available` | 更温和，不显得系统过度自信 |
| `Thinking` | `Transcribing` | dictation 不是 generic AI thinking |
| 默认 `Pasting...` | 继续显示 `Transcribing` | paste 通常太快，单独状态容易闪 |

### 2.4 Ellipsis 规则

`...` 只用于正在等待的过程：

- `Still working...`
- `Taking longer than usual...`
- `Starting microphone...`

不要用于 terminal state：

- `Cancelled`
- `No speech detected`
- `⌘V to paste`

---

## 3. Geometry 与居中规范

### 3.1 Pill 内部必须居中

| 元素 | 水平居中 | 垂直居中 | 说明 |
|---|---|---|---|
| waveform canvas | 以整个 pill 宽度为基准居中 | 以 32px 高度居中 | 不使用左槽/右槽布局 |
| text label | 以整个 pill 宽度为基准居中 | 以 32px 高度居中 | 不被隐藏按钮或右侧 action 推偏 |
| wipe | 从左向右铺满背景 | 全高覆盖 | wipe 是方向性的，但 label 不偏移 |
| terminal text | 以整个 pill 宽度为基准居中 | 以 32px 高度居中 | `⌘V to paste` / `Cancelled` 等 |
| optional warning icon | 默认不用 | 如果用，不能推偏文字 | 文字优先，图标只用于 scanability |

### 3.2 避免 slot-based layout

旧方案里的三槽布局：

```text
[left icon] [center label] [right action]
```

会让中心 label 产生视觉偏移。最终 HUD 应该使用单一 centered layer：

```text
[        centered content        ]
```

如果未来必须有 action，action 应该 overlay 在右侧，但 label 仍然按整个 pill 居中计算。不要把 label 放在剩余空间中居中。

### 3.3 Pill 尺寸规则

| 状态 | 建议宽度 | 高度 | 内容 |
|---|---:|---:|---|
| Recording waveform | 144px | 32px | 居中 waveform |
| Transcribing | 164px | 32px | 居中 `Transcribing` + wipe |
| Slow processing | 172px | 32px | 居中 `Still working...` + wipe |
| Clipboard fallback | 144px | 32px | 居中 `⌘V to paste` |
| Short terminal error | 160-180px | 32px | 具体短错误 |
| Longer actionable error | 不塞进 pill | alert/popover | pill 只显示短 headline |

### 3.4 Light / dark 策略

| 元素 | Light mode | Dark mode | 规则 |
|---|---|---|---|
| 背景环境 | light system material | dark system material | 跟随系统 |
| 主 pill | graphite / near black | 同一个 graphite / near black | 不换成白色 pill |
| caption/helper | 深色低透明文字 | 浅色低透明文字 | 跟背景对比变化 |
| wipe | 白色低透明 overlay | 同样白色低透明 overlay | 语义一致 |
| main text | 白色 | 白色 | 保持 HUD 身份 |

---

## 4. Surface taxonomy 与优先级

### 4.1 Main pill text 字典

| Pill text | 类型 | 什么时候用 | 自动消失 |
|---|---|---|---|
| empty / waveform only | Recording | mic active 或 mic starting | 否，直到 release/cancel/error |
| `Transcribing` | Processing | release/finish 后 pipeline 正在处理 | success/fallback/error/cancel |
| `Still working...` | Soft slow processing | processing 超过阈值且无明显进展 | progress 恢复或 terminal |
| `⌘V to paste` | Clipboard fallback | 已生成文本，但 auto-paste 失败 | 3-5s 或用户 dismiss |
| `Cancelled` | Cancel terminal | 用户取消，且还没 paste | 1.5-3s；如果可 restore 可更久 |
| `No speech detected` | Terminal | 没有有效语音/有效 transcript | 2-3s |
| `Mic permission needed` | Blocking headline | mic 权限缺失 | 直到 action/dismiss |
| `Mic unavailable` | Blocking headline | mic 无法启动、被占用、断开 | 直到 action/dismiss |
| `Couldn't transcribe` | Error | ASR/refine 失败且没有可用 fallback | retry/dismiss 或 3-5s |
| `Couldn't paste` | Error | paste 和 clipboard 都失败 | 直到解释/操作 |
| `Voice unavailable` | Error | account/model/system voice 不可用 | 直到解释/操作 |

### 4.2 Caption/helper 字典

| Caption text | 触发 | 显示时长 | 优先级 | 重复规则 |
|---|---|---:|---:|---|
| `Using {mic}` | mic start 成功，设备变化，或第一次成功录音 | 1.6-2.2s | Low | 同一设备不重复 |
| `To {app}` | paste target 明确且值得提示 | 1.4-2.0s | Low | 首次、target 变化、不确定时显示 |
| `Release to finish` | hold 模式新用户教育 | 1.5-2.5s | Low | 最多 2-3 次 |
| `Press Fn again to finish` | toggle 模式新用户教育 | 1.5-2.5s | Low | 最多 2-3 次 |
| `Press Esc to cancel` | 取消教育或长录音提示 | 1.5-2.5s | Low | 低频，不要每次出现 |
| `Starting microphone...` | mic warmup 超过 600-800ms | 直到 mic ready/error | Medium | 快速启动不显示 |
| `Input seems quiet` | recording 中持续低音量 | 2-4s | Medium | 每 session 最多 1 次，或 30s cooldown |
| `No input detected` | mic ready 后持续近乎无输入 | 2-4s | Medium | 每 session 最多 1 次 |
| `Taking longer than usual...` | processing 慢 | 3-6s | Medium | 每 session 1 次为主 |
| `Text copied to clipboard` | auto-paste 失败但 clipboard 成功 | 2-4s | High | 和 `⌘V to paste` 同时出现 |
| `Check microphone access` | mic 权限/访问错误 | 直到 action/dismiss | High | blocking 类 |
| `Still transcribing your last recording` | transcribing 中再次按 hotkey | 3-5s | High | throttle，每 2s 最多一次 |
| `Long recordings can take a little longer` | 长录音 processing 慢 | 3-6s | Medium | 每 session 1 次 |

### 4.3 Blocking alert 字典

Blocking alert 只有在用户必须采取动作时才出现。它不能长得像第二个 pill。可以是更像 macOS popover 的小卡片，与主 pill 保持明确层级差异。

| Alert title | Body | Actions | 触发 |
|---|---|---|---|
| `Microphone permission required` | `Allow microphone access to use dictation.` | `Open Settings`, `Dismiss` | macOS TCC mic 权限缺失 |
| `Accessibility permission required` | `Allow MAYN to paste into other apps.` | `Open Settings`, `Dismiss` | auto-paste 需要 Accessibility 权限 |
| `Couldn't access your microphone` | `Another app may be using it, or the device was disconnected.` | `Choose Microphone`, `Retry`, `Dismiss` | mic start 失败 |
| `Clearer mic available` | `Audio from {device} may improve accuracy.` | `Choose Microphone`, `Not Now` | 高置信度检测到更清晰输入 |
| `Still transcribing your last recording` | `Wait for it to finish before starting another.` | `Keep Waiting`, `Cancel Previous` | previous pending |
| `Couldn't paste automatically` | `Text was copied to clipboard. Click where you want it, then press ⌘V.` | `Dismiss` | auto-paste 失败但 clipboard 成功 |
| `Couldn't transcribe` | `Something went wrong while transcribing.` | `Retry`, `Use Raw Transcript`, `Dismiss` | ASR/refine 失败，可能有 raw transcript |
| `Voice model unavailable` | `The selected transcription model is not ready.` | `Retry`, `Change Model`, `Dismiss` | 本地/云端模型不可用 |
| `Secure input is active` | `This app may block automatic paste.` | `Copy Text`, `Dismiss` | secure input 或目标 app 限制 |

### 4.4 优先级

| Priority | 类型 | 例子 | Surface |
|---:|---|---|---|
| P0 | Blocking permission/system | mic permission, accessibility, secure input | Blocking alert + short pill headline |
| P1 | Terminal result | clipboard fallback, no speech, cancelled, couldn't transcribe | Main pill + optional caption |
| P2 | Active processing risk | slow processing, timeout approaching, previous pending | Pill label/caption |
| P3 | Session info | using mic, target app, duration | Caption/helper |
| P4 | Education | release to finish, press Esc to cancel | Caption/helper |

### 4.5 冲突规则

| 当前显示 | 新事件 | 结果 |
|---|---|---|
| education | 任意 P0-P3 | 立即替换 education |
| `Using {mic}` | slow processing | 立即替换 |
| `To {app}` | clipboard fallback | 立即替换 |
| slow processing | permission/system error | 立即替换 |
| blocking alert | temporary helper | suppress helper |
| terminal pill | education | suppress education |
| clipboard fallback | success dismiss | 保留 fallback，不要快速隐藏 |
| previous pending | mic info | 保留 previous pending，suppress mic info |

队列规则：

- 同时只显示一个 caption。
- caption 不堆叠。
- 过期的 temporary helper 可以直接丢弃。
- blocking alert 可以替换 caption，但 caption 不能替换 blocking alert。
- `Using {mic}` 和 `To {app}` 同时触发时：第一次录音或 mic 变化优先 `Using {mic}`；目标不确定时优先 `To {app}`。

---

## 5. 完整状态触发矩阵

### 5.1 Hidden / Activation

| State | 进入条件 | Main pill | Caption/helper | 动画 | 退出 |
|---|---|---|---|---|---|
| Hidden | 无 voice session | 不显示 | 无 | 无 | hotkey/click activation |
| Activation accepted | hotkey down / toggle start | pill 出现，waveform 容器准备 | 无 | 180-280ms entrance | mic starting |
| Duplicate activation ignored | 同一 session starting 时重复 key event | 保持当前 | 无；如果 warmup 慢可显示 `Starting microphone...` | 不重新入场 | mic ready/error/cancel |
| Start blocked: logged out/account | voice 功能不可用 | `Voice unavailable` 或不显示 | blocking alert | 无 recording 动画 | 用户处理/dismiss |
| Start blocked: secure/system | 系统状态禁止开始 | `Voice unavailable` 或 `Mic unavailable` | blocking alert | 无 waveform | dismiss/action |

### 5.2 Mic starting

| State | 进入条件 | Main pill | Caption/helper | 动画 | Timing / exit |
|---|---|---|---|---|---|
| Fast mic warmup | mic start <600ms | 居中 dim waveform，无文字 | 无 | low amplitude waveform 或 subtle pulse | mic ready -> recording |
| Slow mic warmup | mic start >600-800ms | 居中 dim waveform，无文字 | `Starting microphone...` | dim waveform | mic ready/error/cancel |
| Permission prompt | macOS permission prompt / TCC check | dim waveform 或 `Mic permission needed` | `Check microphone access` | 无 stream 时停止 waveform | granted/denied |
| Release before mic ready | hold 模式用户过早松开 | <300ms 可 silent cancel；否则 `Cancelled` | 无 | dismiss or cancelled | 必须防止 mic ready 后迟到开始 |
| Esc before mic ready | warmup 中取消 | `Cancelled` 或 silent dismiss | 无 | quick dismiss | Hidden |
| Device changes during warmup | 系统切换 input | 保持 dim waveform | stream 成功后才显示 `Using {mic}` | 无额外 transition | recording/error |

设计判断：不要把 `Starting...` 放进 pill。快速 mic start 时不需要任何文案；慢的时候用 caption 解释。

### 5.3 Recording - hold 模式

| State | 进入条件 | Main pill | Caption/helper | 动画 | 退出 |
|---|---|---|---|---|---|
| Recording active | mic stream ready，hold key 仍按住 | 居中 waveform only | 通常无 | audio-reactive waveform | release -> processing; Esc -> cancel |
| First hold education | 前 1-3 次成功 ready 后 | waveform only | `Release to finish` | caption fade | 学会后 suppress |
| Cancel education | 第一次长按或第一次暴露 cancel | waveform only | `Press Esc to cancel` | caption fade | suppress if other caption active |
| Input quiet | RMS 低但非零，持续 1.5-2.5s | waveform only | `Input seems quiet` | waveform 保持低幅度 | continue recording |
| No input | mic ready 后 2-3s 近乎无输入 | waveform only | `No input detected` | minimal waveform | release 后可能 no speech |
| Clipping | 连续 1-2s peak clipping | waveform only | optional `Input is too loud` | waveform capped | continue recording |
| Device removed | 录音中 input device 消失 | `Mic unavailable` | blocking/caption explanation | waveform 停止 | error terminal |
| User releases | hold key up | 立即 `Transcribing` | 清除 recording captions | wipe 立刻开始 | processing |

### 5.4 Recording - toggle / hands-free 模式

| State | 进入条件 | Main pill | Caption/helper | 动画 | 退出 |
|---|---|---|---|---|---|
| Toggle recording | 用户开始 toggle mode | 居中 waveform only | 通常无 | audio-reactive waveform | second hotkey -> processing |
| Toggle education | 前几次 toggle mode | waveform only | `Press Fn again to finish` | caption fade | 成功使用后 suppress |
| Idle hands-free wait | toggle 已开始但未说话 | low waveform | optional first-time `Start speaking` | low idle motion | speech -> active recording; timeout -> no speech |
| Toggle cancel | Esc during toggle | `Cancelled` | 无 | terminal hold | hidden/restore window |
| Toggle max silence | 一段时间没有任何 speech | `No speech detected` | 无 | terminal | hidden |

不要在主 HUD 放 checkmark。finish 的交互是第二次 hotkey。如果未来必须支持鼠标 finish，也不要默认显示 check icon；可以让 pill click 作为 secondary 行为，但视觉上不打扰中心内容。

### 5.5 Processing - normal path

| State | 进入条件 | Main pill | Caption/helper | 动画 | 退出 |
|---|---|---|---|---|---|
| Finalizing audio | release/finish received | `Transcribing` | 无 | wipe 从 0 立即开始 | ASR/cleanup/error/cancel |
| ASR | audio submitted | `Transcribing` | 无 | boot wipe：约 1s 50%，10s 约 63% | cleanup/raw/error/cancel |
| Cleanup/refine | ASR result available | `Transcribing` | 无 | wipe = max(boot, real progress)，单调不回退 | paste/success/fallback/error |
| Paste attempt <500ms | final text ready, paste underway | 继续 `Transcribing` | 无 | wipe 接近 95-100% | success/fallback |
| Slow paste >500ms | paste latency 可见 | optional `Pasting...` 或继续 `Transcribing` | 无 | wipe near 95% | success/fallback/error |
| Success | paste succeeded | 不显示 success text | 无 | wipe snap 100%，hold 250-350ms | dismiss |

建议默认不显示 `Pasting...`，除非 paste latency 经常可见。否则会产生不必要的闪烁。

### 5.6 Processing - slow path

| State | 触发 | Main pill | Caption/helper | 动画 | 退出 |
|---|---|---|---|---|---|
| Slightly slow | processing >3-4s 且无真实进展 | `Still working...` | 暂时无 | wipe 继续缓慢推进 | progress/success/error |
| Noticeably slow | processing >6-8s | `Still working...` | `Taking longer than usual...` | wipe 保持 alive | progress/success/error/cancel |
| Very slow | processing >20-30s | `Still working...` | blocking/soft alert: `Keep Waiting` / `Cancel` | wipe 不能冻结 | action/success/error |
| Long recording processing | recording >60s，预计处理更久 | `Still working...` | `Long recordings can take a little longer` | wipe 继续 | success/error |
| Weak network but alive | cloud ASR/refine retrying | `Still working...` | `Taking longer than usual...` or `Connection is slow` | wipe alive | success/error/cancel |
| Progress resumes | slow state 后 stream 有进展 | 可回 `Transcribing` 或维持 `Still working...` 到结束 | caption 1-2s 后清除 | wipe smooth jump | success/error |

避免在 `Transcribing` 和 `Still working...` 之间来回跳。慢速文案出现后，通常保持到完成更稳。

### 5.7 Terminal / recovery states

| State | 触发 | Main pill | Caption/helper | Duration | Recovery |
|---|---|---|---|---:|---|
| Success | paste complete | 无文字，dismiss | 无 | 100% 后 250-350ms | 无 |
| Clipboard fallback | auto-paste 失败但 clipboard 成功 | `⌘V to paste` | `Text copied to clipboard` | 3-5s | 用户按 ⌘V |
| Clipboard write failed | paste 和 clipboard 都失败 | `Couldn't paste` | blocking alert | until action | `Copy Text`, `Retry` |
| Cancel recording | Esc/cancel during recording | `Cancelled` | 无 | 1.5-3s | 可选 restore |
| Cancel processing | Esc/cancel before paste | `Cancelled` | 无 | 2-5s | 如果有缓存可 `Restore` |
| No speech | release 后 transcript 为空 | `No speech detected` | 无，或之前已有 quiet helper | 2-3s | 新录音 |
| ASR failed | 没有可用 transcript | `Couldn't transcribe` | optional alert | until retry/dismiss | audio cached 时可 retry |
| Cleanup failed with raw | raw ASR 有，cleanup failed | `Couldn't transcribe` 或 `Couldn't clean up` | `Raw transcript available` | until action | `Use Raw Transcript`, `Retry` |
| Paste target lost | 文本 ready 但目标丢失 | `⌘V to paste` | `Text copied to clipboard` | 3-5s | manual paste |
| Permission error | mic/accessibility permission missing | specific headline | blocking alert | until action | Open Settings |

---

## 6. 各类 text / alert 详细触发条件

### 6.1 Recording text policy

默认：**recording 期间主 pill 不显示文字。**

| 场景 | Pill 内是否显示文字 | 是否显示 caption | 原因 |
|---|---|---|---|
| 正常 recording | 否 | 否 | waveform 足够 |
| 第一次 hold | 否 | `Release to finish` | 教育信息放外面 |
| 第一次 toggle | 否 | `Press Fn again to finish` | 教育信息放外面 |
| mic warmup <600ms | 否 | 否 | 避免闪烁 |
| mic warmup >600-800ms | 否 | `Starting microphone...` | 只解释延迟 |
| input quiet | 否 | `Input seems quiet` | 轻提醒，不切状态 |
| no input | 否 | `No input detected` | release 前不判失败 |
| device changed | 否 | `Using {mic}` | 临时信息 |
| target known | 否 | optional `To {app}` | 仅增强粘贴目标信心 |
| screen sharing/privacy | 否 | 尽量 suppress non-critical captions | 减少敏感暴露 |

### 6.2 Processing text policy

| 场景 | Pill label | Caption/helper | 说明 |
|---|---|---|---|
| release 第一帧 | `Transcribing` | 清除 recording helper | wipe must start immediately |
| 正常 ASR/cleanup | `Transcribing` | 无 | 不暴露内部阶段 |
| 无进展 >3-4s | `Still working...` | 初始可无 | pill 可以改变 |
| 无进展 >6-8s | `Still working...` | `Taking longer than usual...` | helper 解释慢 |
| paste <500ms | `Transcribing` | 无 | 不需要 `Pasting...` |
| paste >500ms | optional `Pasting...` | 无 | 只有明显慢才显示 |
| success | dismiss | 无 | 不显示 `Applied` |
| clipboard fallback | `⌘V to paste` | `Text copied to clipboard` | 这是 fallback，不是失败 |
| failure | 具体错误 | 如果需要，alert | 避免 `Failed` |

### 6.3 Education hints

| Hint | 触发 | Surface | 频率限制 | Suppression |
|---|---|---|---|---|
| `Release to finish` | 前几次 hold recording，mic ready 后 | caption | 最多 2-3 次 | 成功使用后 suppress |
| `Press Fn again to finish` | 前几次 toggle recording | caption | 最多 2-3 次 | 成功 toggle finish 后 suppress |
| `Press Esc to cancel` | 第一次长录音或第一次需要 cancel 教育 | caption | 最多 1-2 次 | 有 slow/error/helper 时 suppress |
| `Click where you want the text, then press ⌘V` | 第一次 clipboard fallback | blocking/caption | 最多 2 次 | 用户学会 fallback 后 suppress |
| `Hold Fn to dictate` | 可选 cursor anchor onboarding | cursor anchor/caption | 最多 2-3 次 | 用户成功使用 voice 后 suppress |

### 6.4 Mic / audio helpers

| 触发 | 条件 | Main pill | Caption/alert | Duration | Edge handling |
|---|---|---|---|---:|---|
| Mic ready, same device | 和上次 successful session 同 device | waveform | 无 | N/A | 避免重复噪音 |
| Mic ready, changed device | device ID 变化 | waveform | `Using {mic}` | 1.6-2.2s | 长设备名中间截断 |
| First ever mic session | 没有 last used device | waveform | optional `Using {mic}` | 1.6-2.2s | 建立信任 |
| Device label unavailable | label 为空 | waveform | `Using selected microphone` | 1.6-2.2s | 不显示空变量 |
| Better mic candidate | 高置信度输入质量更好 | waveform or processing | blocking `Clearer mic available` | 8-10s 或 action | 不要频繁打断 |
| Input quiet | RMS 低但非零 | waveform | `Input seems quiet` | 2-4s | cooldown |
| No input | RMS 近零 | waveform | `No input detected` | 2-4s | release 后才 terminal no speech |
| Clipping | sustained clipping | waveform | optional `Input is too loud` | 2-4s | sparingly |
| Mic muted | 高置信度静音 | `Mic unavailable` or waveform | `Microphone may be muted` | until resolved | 置信度不高不显示 |
| Device removed | active input disappears | `Mic unavailable` | blocking alert | until action | 安全停止 |
| Permission denied | TCC denied | `Mic permission needed` | blocking alert | until action | Open Settings |
| Another app using mic | start fails | `Mic unavailable` | `Another app may be using your microphone` | until action | Choose/Retry |

### 6.5 Paste target helpers

| 触发 | 条件 | Main pill | Caption/alert | Timing |
|---|---|---|---|---|
| Target known at start | active app/text field reliable | waveform | optional `To {app}` | 首次/target 变化/不确定时 |
| Target changed during recording | active app changed before release | waveform or `Transcribing` | `To {new app}` only if paste safe | 如果不确定，clipboard fallback |
| Target lost before paste | no focused text field | `⌘V to paste` | `Text copied to clipboard` | terminal fallback |
| Target app blocks paste | paste rejected/timed out | `⌘V to paste` | `Text copied to clipboard` | terminal fallback |
| Secure field | password/secure input | `⌘V to paste` or `Couldn't paste` | blocking if clipboard also blocked | 不 silent paste |
| Clipboard overwritten | user changed clipboard after fallback | 保持 fallback only if valid | optional no message | 不重复覆盖 |
| Accessibility missing | paste automation blocked | `Accessibility permission required` | blocking alert | before/after fallback |

### 6.6 Previous pending / concurrency

| 用户动作 | 当前状态 | 推荐行为 | Main pill | Caption/alert |
|---|---|---|---|---|
| hotkey pressed | previous transcript processing | 默认不开始新录音 | 保持 `Transcribing`/`Still working...` | `Still transcribing your last recording` |
| hotkey repeatedly pressed | previous transcript processing | throttle helper，不 restart | 保持当前 | 每 2s 最多一次 |
| Esc pressed | previous transcript processing | 如果安全，cancel previous | `Cancelled` | optional restore |
| `Cancel Previous` | blocking alert visible | cancel pipeline，保证不会 paste | `Cancelled` | 无 |
| `Keep Waiting` | blocking alert visible | 继续 previous pipeline | previous state | clear alert |
| queue mode | 产品明确支持时 | 显示明确 queue count | 避免默认支持 | `1 recording queued` if supported |

默认建议：**不要 silent queue dictation**。语音插入顺序和目标 app 太敏感。上一段处理完成前，默认 block 新录音。

### 6.7 Long recording

| 条件 | Main pill | Caption/helper | 规则 |
|---|---|---|---|
| recording <60s | waveform only | 无 | 不显示 timer |
| recording >60s | waveform only | optional `Recording {m:ss}` | 仅当有产品价值 |
| max duration 最后 60s | waveform only | `Recording will stop in {time}` | helper，不放 pill center |
| max duration reached | `Transcribing` | `Limit reached. Transcribing captured audio` | graceful finish，不当作 error |
| long recording processing | `Still working...` | `Long recordings can take a little longer` | 每 session 1 次 |
| cancel long recording | `Cancelled` | 无 | 不 process/paste |

### 6.8 Privacy contexts

| Context | Main pill | Caption/helper | 规则 |
|---|---|---|---|
| screen sharing detected | waveform only | suppress partial/non-critical captions | 不显示敏感内容 |
| privacy mode enabled | waveform only | 只显示 critical alerts | suppress mic label if configured |
| device label includes personal/company info | waveform | 可显示 `Using {mic}`，但 analytics 不存 raw label | UI 可以，日志要处理 |
| secure field | 避免 auto-paste | fallback or block | 不 silent insert |
| presentation/meeting mode | waveform only | suppress education | 减少干扰 |

### 6.9 Accessibility / Reduced Motion

| Requirement | 行为 |
|---|---|
| VoiceOver recording start | 只播报一次 `Recording started`；视觉上仍然不显示 `Listening` |
| VoiceOver processing | 只播报一次 `Transcribing`；不要播报每个 progress update |
| VoiceOver slow state | 播报一次 `Taking longer than usual` |
| VoiceOver fallback | 播报 `Text copied to clipboard. Press Command V to paste.` |
| Reduce Motion | 降低 waveform amplitude，关闭夸张 transition，保留简单 wipe |
| High Contrast | helper opacity 需要提高，warning/error 仍可读 |
| Keyboard | Esc cancel；hold release finish；toggle hotkey finish |
| Click target | 如果 pill 可点击，实际 hit target 应比 32px 视觉高度更大 |

---

## 7. Edge case catalog

### 7.1 Activation / hotkey edge cases

| Edge case | 期望行为 | User-facing copy |
|---|---|---|
| 用户极短 tap hold key | 如果 <阈值，silent dismiss；如果 session 成立但无语音，`No speech detected` | 尽量避免误触也弹文字 |
| key repeat 触发多个 start | 忽略重复 start | 无 |
| release before mic ready | 取消 pending start，不能 mic ready 后迟到开始 | `Cancelled` only if visible enough |
| Esc during warmup | cancel pending session | `Cancelled` or silent dismiss |
| hotkey while processing | block new start | `Still transcribing your last recording` |
| toggle start 后马上再次 press | 如果有有效音频则 finish，否则 no speech | `No speech detected` if meaningful |
| app loses focus during recording | 继续 recording，但 lock original target | optional `To {app}` if target changes |
| computer sleeps mid-recording | cancel safely 或仅在 stream 仍有效时 resume | `Cancelled` or `Couldn't transcribe` |
| screen locks | stop/cancel；unlock 后不自动 paste stale transcript | `Cancelled` or recovery |
| MAYN quits/restarts mid-session | 不自动 paste stale transcript | restore only if explicit |

### 7.2 Audio capture edge cases

| Edge case | 期望行为 | Copy |
|---|---|---|
| permission not determined | 触发 macOS permission flow | `Mic permission needed` + alert |
| permission denied | 不显示 active recording waveform | `Microphone permission required` |
| permission granted after prompt | 进入 waveform recording | optional `Using {mic}` |
| selected mic unavailable | 可安全 fallback 就 fallback，否则 block | `Mic unavailable` |
| Bluetooth mic wakes slowly | dim waveform，超过阈值 caption | `Starting microphone...` |
| device disconnects mid-recording | stop capture，安全 fail | `Mic unavailable` |
| device switches automatically | stream valid 就继续 | `Using {mic}` only if useful |
| input silent | release 前继续 recording；release 后 no speech | `No input detected`, then `No speech detected` |
| input too quiet | 继续 recording | `Input seems quiet` |
| input clips | 继续 recording，optional helper | `Input is too loud` |
| unsupported sample rate | 尝试转换；不行则 error | `Mic unavailable` or `Couldn't transcribe` |
| audio file write fails | ASR 前 fail | `Couldn't transcribe` |

### 7.3 Transcription / cleanup edge cases

| Edge case | 期望行为 | Copy |
|---|---|---|
| ASR returns empty | terminal no speech | `No speech detected` |
| ASR low confidence/gibberish | no speech 或 raw fallback | `Couldn't transcribe` or `No speech detected` |
| ASR slow but alive | wipe alive | `Still working...`, `Taking longer than usual...` |
| ASR timeout | 有 audio cache 则 retry | `Couldn't transcribe` |
| cleanup/refine slow | wipe alive，slow state | `Still working...` |
| cleanup fails but raw transcript exists | offer raw transcript | `Raw transcript available`, action `Use Raw Transcript` |
| cleanup returns empty but raw exists | offer raw transcript | `Use Raw Transcript` |
| cleanup stream stalls | UI 不冻结 | `Still working...` |
| network offline | local fallback 或 retry window 后 fail | `Connection is slow` / `Couldn't transcribe` |
| model loading | >1s 才解释 | helper `Loading voice model...` if necessary |
| language unsupported | try default 或 error | `Couldn't transcribe` + alert if specific |
| transcript too long | chunk/process，慢时解释 | `Still working...` + long helper |

### 7.4 Paste / clipboard edge cases

| Edge case | 期望行为 | Copy |
|---|---|---|
| auto-paste succeeds | dismiss | 无 |
| auto-paste timeout | copy to clipboard | `⌘V to paste` + `Text copied to clipboard` |
| clipboard success but paste fails | fallback，不是 error | `⌘V to paste` |
| clipboard write fails | blocking error | `Couldn't paste` |
| target app changed | 安全才 paste；不确定则 fallback | `Text copied to clipboard` |
| target app closed | clipboard fallback | `⌘V to paste` |
| no focused text field | clipboard fallback | `⌘V to paste` |
| secure input blocks paste | fallback or blocking | `Couldn't paste automatically` |
| selection changed | target valid 时 paste 当前 selection | 无额外文案 |
| user clipboard valuable data | 尽量 preserve/restore clipboard | fallback 时解释 |
| wrong app risk | target validation；不确定就 fallback | 不 silent paste |

### 7.5 Error / recovery edge cases

| Edge case | 期望行为 | Copy |
|---|---|---|
| cancel before paste | guarantee pipeline cannot paste later | `Cancelled` |
| cancel after paste fired | 只有真的能撤销时才 offer undo | `Undo paste` only if guaranteed |
| restore after cancel | 只在缓存安全窗口内提供 | `Restore` action，不 clutter main pill |
| retry ASR | audio cached 且没过期才可 retry | `Retry` |
| retry paste | target still valid 才 retry paste | `Retry Paste` or fallback |
| permission changes mid-session | paste 前 re-check | permission-specific alert |
| user dismisses blocking alert | 不无限自动 retry | hidden or terminal |
| multiple errors | 显示最可操作的具体错误 | 避免 `Failed` |

---

## 8. Copy dictionary

### 8.1 Main pill copy

| Key | Text | 用途 |
|---|---|---|
| `recording.empty` | empty | recording waveform-only |
| `processing.transcribing` | `Transcribing` | 默认 processing |
| `processing.slow` | `Still working...` | slow processing |
| `fallback.clipboard` | `⌘V to paste` | clipboard fallback |
| `terminal.cancelled` | `Cancelled` | user cancelled before paste |
| `terminal.noSpeech` | `No speech detected` | no usable speech/transcript |
| `error.micPermission` | `Mic permission needed` | short pill headline |
| `error.micUnavailable` | `Mic unavailable` | short pill headline |
| `error.transcribe` | `Couldn't transcribe` | ASR/refine failure |
| `error.paste` | `Couldn't paste` | paste + clipboard failure |
| `error.voiceUnavailable` | `Voice unavailable` | account/model/system unavailable |
| `error.accessibility` | `Accessibility needed` | auto-paste permission missing |

### 8.2 Caption/helper copy

| Key | Text | Notes |
|---|---|---|
| `helper.usingMic` | `Using {mic}` | device name 过长中间截断 |
| `helper.targetApp` | `To {app}` | optional，只在有用时 |
| `helper.startingMic` | `Starting microphone...` | slow warmup threshold 后 |
| `helper.releaseToFinish` | `Release to finish` | hold education |
| `helper.pressAgain` | `Press Fn again to finish` | toggle education |
| `helper.escCancel` | `Press Esc to cancel` | cancel education |
| `helper.quiet` | `Input seems quiet` | soft warning |
| `helper.noInput` | `No input detected` | recording 中 soft warning |
| `helper.slow` | `Taking longer than usual...` | slow processing caption |
| `helper.longRecording` | `Long recordings can take a little longer` | 长录音慢速解释 |
| `helper.copied` | `Text copied to clipboard` | clipboard fallback |
| `helper.previousPending` | `Still transcribing your last recording` | duplicate activation |
| `helper.limitSoon` | `Recording will stop in {time}` | max duration countdown |
| `helper.limitReached` | `Limit reached. Transcribing captured audio` | graceful duration finish |
| `helper.checkMic` | `Check microphone access` | mic blocking support |
| `helper.modelLoading` | `Loading voice model...` | 只有明显加载时 |
| `helper.connectionSlow` | `Connection is slow` | cloud path only |

### 8.3 Blocking alert copy

| Key | Title | Body | Actions |
|---|---|---|---|
| `alert.micPermission` | `Microphone permission required` | `Allow microphone access to use dictation.` | `Open Settings`, `Dismiss` |
| `alert.accessibility` | `Accessibility permission required` | `Allow MAYN to paste into other apps.` | `Open Settings`, `Dismiss` |
| `alert.micUnavailable` | `Couldn't access your microphone` | `Another app may be using it, or the device was disconnected.` | `Choose Microphone`, `Retry`, `Dismiss` |
| `alert.clearerMic` | `Clearer mic available` | `Audio from {device} may improve accuracy.` | `Choose Microphone`, `Not Now` |
| `alert.previousPending` | `Still transcribing your last recording` | `Wait for it to finish before starting another.` | `Keep Waiting`, `Cancel Previous` |
| `alert.pasteFallback` | `Couldn't paste automatically` | `Text was copied to clipboard. Click where you want it, then press ⌘V.` | `Dismiss` |
| `alert.transcribeFailed` | `Couldn't transcribe` | `Something went wrong while transcribing.` | `Retry`, `Use Raw Transcript`, `Dismiss` |
| `alert.voiceModel` | `Voice model unavailable` | `The selected transcription model is not ready.` | `Retry`, `Change Model`, `Dismiss` |
| `alert.secureInput` | `Secure input is active` | `This app may block automatic paste.` | `Copy Text`, `Dismiss` |

### 8.4 Action copy

| Action | 用途 | Notes |
|---|---|---|
| `Open Settings` | 权限 | 尽量打开具体 macOS pane |
| `Choose Microphone` | mic unavailable / clearer mic | 打开 MAYN mic picker |
| `Retry` | ASR/model/transient errors | 只有 audio cache 可用时 |
| `Use Raw Transcript` | cleanup failed but ASR succeeded | 避免整段失败 |
| `Copy Text` | paste impossible | copy transcript |
| `Keep Waiting` | very slow / previous pending | 继续当前 session |
| `Cancel Previous` | previous pending | 必须保证不会 later paste |
| `Dismiss` | non-recoverable/info alert | clear alert |
| `Restore` | cancel recovery | 只有真实可恢复才显示 |
| `Undo paste` | already pasted and undo guaranteed | 不用于 pre-paste cancel |

---

## 9. Timing values

| Item | 建议值 |
|---|---:|
| Pill entrance | 180-280ms |
| Pill width change | 200-260ms |
| Caption fade in/out | 160-220ms |
| Mic warmup caption threshold | 600-800ms |
| `Using {mic}` duration | 1.6-2.2s |
| Education caption duration | 1.5-2.5s |
| Input quiet threshold | 1.5-2.5s sustained low RMS |
| No input caption threshold | 2-3s near-zero RMS |
| Slow processing label threshold | 3-4s with no real progress |
| Slow processing caption threshold | 6-8s total processing or 3-4s after stall |
| Very slow alert threshold | 20-30s |
| Success wipe hold | 250-350ms |
| Clipboard fallback pill | 3-5s |
| Terminal no speech | 2-3s |
| Cancelled terminal | 1.5-3s；有 restore 时可 5s |
| Previous pending helper throttle | 至少 2s |
| Better mic alert cooldown | ignored device recommendation 至少 24h |

---

## 10. Animation behavior

### 10.1 Waveform

| Rule | Behavior |
|---|---|
| Centering | waveform canvas 精确在 pill 中央 |
| Idle | mic active 但无 speech 时保持低幅度 motion |
| Speech | attack 快、release 慢，不 jitter |
| Quiet input | waveform 保持低幅度，caption 解释 |
| No input | minimal waveform，不硬停 |
| Reduce Motion | 降低 amplitude 和 transition，但保持状态可读 |

### 10.2 Wipe

| Rule | Behavior |
|---|---|
| Start | release/finish 后立即开始 |
| Meaning | 表示 active processing，不表示精确百分比 |
| Boot curve | 早期给反馈，后期渐近；约 1s 50%，10s 约 63% |
| Real progress | displayed progress = max(boot progress, stream progress)，永不回退 |
| Completion | snap 100%，hold 250-350ms，成功后 dismiss |
| Slow state | wipe 继续 alive，避免 frozen pill |

### 10.3 Caption motion

| Rule | Behavior |
|---|---|
| Entry | fade + 1-2px upward settle |
| Exit | fade only |
| No pill-like animation | 不 scale，不像第二个 capsule |
| Replacement | quick crossfade，不 stack |
| Reduce Motion | fade only |

---

## 11. QA / Acceptance checklist

### 11.1 Visual acceptance

- recording pill 只有居中 waveform。
- recording 阶段不出现 `Listening`。
- 默认 HUD 不出现 check icon。
- processing label 水平和垂直居中。
- caption/helper 与 pill 同一中轴线。
- caption/helper 无背景、无 border、无 blur、无 shadow。
- caption/helper 和 main pill 不像两个 pills。
- light/dark 下 HUD 本体保持同一个 graphite identity。
- wipe 不会推动或偏移 text。
- text truncation 不影响核心可读性。
- `⌘V to paste` 在 144px 宽度内清楚可读。

### 11.2 Behavior acceptance

- release/finish 后立即切到 `Transcribing`。
- wipe 在 release 同一帧或下一 render tick 启动。
- success 不显示 `Applied`。
- paste failure 显示 `⌘V to paste`，不是 generic failure。
- mic device change 只有在有用时显示 `Using {mic}`。
- slow processing 切到 `Still working...`，必要时 caption 显示 `Taking longer than usual...`。
- previous pending 不会 silent start 第二段。
- cancel before paste 必须保证后续不会 paste。
- cleanup failed 但 raw transcript 存在时，可以提供 `Use Raw Transcript`。
- VoiceOver 每个 major state 只播报一次，不播报每个 progress update。

### 11.3 Copy acceptance

- 除非真的没有具体原因，否则不使用 generic `Failed`。
- 不向用户暴露 `ASR`、`cleanup`、`finalizing` 等内部阶段。
- helper 不超过一行短文案。
- blocking alert 有可执行 action。
- error copy 告诉用户发生了什么，以及能做什么。
- education copy 有频率限制，不会无限重复。

---

## 12. 推荐默认体验

Happy path 应该是：

1. 用户按下 hotkey。
2. pill 立刻出现，只有居中 waveform。
3. 如果 mic 变化，上方 caption 短暂显示 `Using {mic}`。
4. 用户说话。没有 `Listening`，没有 check icon。
5. 用户 release/finish。
6. pill 立即变为 `Transcribing`，wipe 立刻开始。
7. 正常处理完成后，wipe 到 100%，hold 250-350ms，dismiss。
8. 如果慢，pill 变为 `Still working...`，caption 可显示 `Taking longer than usual...`。
9. 如果 auto-paste 失败但文本可用，pill 显示 `⌘V to paste`，caption 显示 `Text copied to clipboard`。
10. 如果出错，pill 显示最具体的短错误；只有用户需要行动时才显示 blocking alert。

最终效果：**MAYN Voice HUD 像 macOS 原生小工具一样存在：不解释显而易见的状态，只解释用户可能不确定的状态。**

---

## Appendix A - Condensed master matrix

| Moment | Main pill | Caption/helper | Surface count | Notes |
|---|---|---|---:|---|
| Hidden | none | none | 0 | 默认无 idle hover |
| Hotkey accepted | waveform | none | 1 | 即时反馈 |
| Mic warmup slow | waveform | `Starting microphone...` | 1 + caption | caption 不是第二个 pill |
| Recording | waveform | none | 1 | 无 `Listening` |
| First hold | waveform | `Release to finish` | 1 + caption | education capped |
| First toggle | waveform | `Press Fn again to finish` | 1 + caption | 无 check icon |
| Device changed | waveform | `Using {mic}` | 1 + caption | low priority |
| Input quiet | waveform | `Input seems quiet` | 1 + caption | soft warning |
| Release/finish | `Transcribing` | none | 1 | wipe immediately |
| Normal processing | `Transcribing` | none | 1 | no internal phase names |
| Slow processing | `Still working...` | optional `Taking longer than usual...` | 1 + caption | no frozen UI |
| Success | dismiss | none | 0 | no `Applied` |
| Paste fallback | `⌘V to paste` | `Text copied to clipboard` | 1 + caption | not an error |
| No speech | `No speech detected` | none | 1 | terminal |
| Cancel | `Cancelled` | none | 1 | restore only if real |
| Permission missing | `Mic permission needed` | blocking alert | 1 + alert | action required |
| Mic unavailable | `Mic unavailable` | blocking alert | 1 + alert | choose/retry |
| ASR failure | `Couldn't transcribe` | optional alert | 1 + alert | retry/raw if possible |
| Paste impossible | `Couldn't paste` | blocking alert | 1 + alert | copy/retry if possible |
| Previous pending | keep current processing | `Still transcribing your last recording` | 1 + caption | do not queue silently |

