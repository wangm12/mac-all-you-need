# Mayn Voice HUD — Liquid Glass V3 Production Spec

## Product decision

Use one fixed-size, centered Voice HUD pill for all runtime states.

- No stacked caption + hub by default.
- No text buttons such as `Stop` or `Undo 5s`.
- No nested glass, no ghost ring, no semantic colors.
- Liquid Glass is the default visual style; Graphite is only a fallback setting.

## Fixed geometry

| Token | Value |
|---|---:|
| HUD width | 392 px |
| HUD height | 58 px |
| Radius | capsule / 999 px |
| Left slot | 64 px |
| Center label | flexible, centered |
| Right slot | 64 px |
| Action icon button | 40 x 40 px |
| Waveform box | 44 x 28 px |

The label must remain optically centered regardless of whether the right action is present. Reserve both left and right slots in every state.

## State layout

| State | Left slot | Center label | Right slot |
|---|---|---|---|
| Starting | pulsing dot | Starting | empty |
| Listening | waveform | Listening | stop square icon button |
| Transcribing | dim waveform | Transcribing | empty |
| Inserted | check | Inserted | empty |
| Cancelled | x mark | Cancelled | undo icon button + countdown ring |
| Failed | warning mark | Couldn't transcribe | retry icon button |

## Progress

Transcribing progress is a full-bleed background wipe clipped by the capsule.

Do not use an inner loading line.
Do not place the progress layer inside content padding.
Do not add a second panel behind the pill.

## Liquid Glass surface

Implement the Voice HUD as a single shaped glass surface.

SwiftUI macOS 26+ direction:

```swift
VoiceHUDContent()
    .frame(width: 392, height: 58)
    .glassEffect(.regular, in: .capsule)
```

For the background progress, draw a clipped layer inside the same capsule behind the content:

```swift
Capsule()
    .fill(progressFill)
    .frame(width: 392 * progress)
    .frame(maxWidth: .infinity, alignment: .leading)
    .clipShape(Capsule())
```

For macOS 14–25 fallback, use an `NSVisualEffectView` or SwiftUI material inside the same capsule shape. Do not simulate glass with stacked custom blurs.

## Icon rules

- Use SF Symbols in the actual app.
- All icons render monochrome.
- Action icons live inside 40 x 40 circular glass buttons.
- Icons are centered with `frame(width: 40, height: 40)` and no optical offset hacks.
- Use icon-only controls:
  - Stop: `stop.fill` or a centered rounded square.
  - Undo: `arrow.uturn.backward` or `arrow.counterclockwise` with countdown ring.
  - Retry: `arrow.clockwise`.

## Motion

| Interaction | Motion |
|---|---|
| HUD enter | opacity 0→1, scale 0.94→1, y 8→0, 150 ms |
| HUD exit | opacity 1→0, scale 1→0.985, 120 ms |
| Listening waveform | 700–900 ms bar cycle |
| Transcribing progress | background wipe, content stays fixed |
| Cancelled countdown | subtle circular ring, 5s |
| Reduce Motion | no scale/y, opacity only, static waveform |

## QA checklist

- [ ] Every state has identical width and height.
- [ ] Label center does not move between states.
- [ ] Progress fill touches the pill edge and covers the full pill height.
- [ ] Stop / Undo / Retry are icon-only.
- [ ] Icons in circular controls are visually centered.
- [ ] No duplicate rim, ghost ring, or stacked glass.
- [ ] Works in light and dark mode.
- [ ] Reduce Transparency has an opaque elevated fallback.
- [ ] Reduce Motion removes waveform/progress animation.
