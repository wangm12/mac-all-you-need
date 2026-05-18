# Voice History — Row Actions and Retention Design Spec

**Status:** Approved in chat on 2026-05-18
**Owner:** mingjie-father
**Project:** mac-all-you-need

---

## 1. Problem

The Voice tool page shows recent transcripts but offers no per-row actions and no retention bound. Transcripts grow forever, audio is only kept opportunistically when personalization consent (`saveTrainingExamplesEnabled`) happens to be on, and there is no way for a user to retry a misheard dictation, download the raw recording, or delete a single noisy transcript without going through a multi-select bulk path.

The Wispr-Flow-style history reference shared by mingjie-father suggests three concrete additions, scoped narrowly:

1. A per-row overflow menu offering **Retry**, **Download audio**, **Delete transcript**.
2. A **Keep history** retention dropdown that prunes both transcripts and their audio.
3. A **Save audio recordings** toggle that decouples audio retention from personalization, since Retry and Download audio both require audio to exist.

Out of scope for this spec: filter pills, a privacy reassurance card, date-grouped sections, a standalone History sidebar entry, copy/flag icons, or any app-wide style refresh. The reference is inspiration; the change is surgical.

## 2. Product Principle

Voice History stays a section on the Voice tool page. The new controls live at the top of that section so users can see retention and audio policy in the same place where they observe their transcripts. Audio retention is opt-in, never silently expanded. Retry is non-destructive — it produces a new transcript row, never overwrites the original. Delete is reversible for a short undo window so power users do not lose work to a misclick.

## 3. Information Architecture

```
Voice tool page (existing)
  ...other sections...
  Recent transcripts (existing section)
    [NEW] Storage header row
      - Keep history          [Dropdown: Forever / 90d / 30d / 7d / 1d]
      - Save audio recordings [Toggle]
    [EXISTING] List of VoiceTranscriptHistoryRow
      - Each row gains a hover-revealed ⋯ menu:
          Retry
          Download audio
          Delete transcript
      - Row metadata line: HH:MM AM/PM · lang · model · 1.2 s
      - The "1234 ms" StatusPill is removed; duration folds into metadata.
```

The Personalization page keeps `saveTrainingExamplesEnabled` exactly as is. A one-line helper text below that toggle clarifies that enabling personalization implicitly enables audio storage for those transcripts.

## 4. Settings and Persistence

Two new keys under the App Group `UserDefaults` (`AppGroupSettings.defaults`):

| Key | Type | Default | Meaning |
|---|---|---|---|
| `voice.history.retention` | `String` | `"forever"` | One of `"forever" | "90d" | "30d" | "7d" | "1d"`. Maps to a `VoiceHistoryRetention` enum. |
| `voice.history.saveAudio` | `Bool` | `false` | When true, every new transcript persists its encrypted WAV under the existing training-example store directory. |

Default of `"forever"` preserves today's behavior (no implicit deletion). Default of `false` for `saveAudio` keeps disk impact and privacy posture unchanged unless the user opts in.

Settings live in a small new `Shared/Sources/Core/Voice/VoiceHistorySettings.swift` value type with a `load(from:) / save(to:)` pair against `UserDefaults`, following the shape of existing `VoicePersonalizationSettings`.

## 5. Data Model and Storage

### 5.1 No new database tables

Transcripts and their audio paths already live in `voice_transcripts` (id, started_at, ended_at, duration_ms, raw_text, cleaned_text, app_bundle_id, language, model_identifier, audio_path). The `audio_path` column is already populated by `VoiceCoordinator.saveTrainingExample`. We extend the conditions under which it is populated; we do not add columns.

### 5.2 New repository method

`Shared/Sources/Core/Voice/VoiceTranscriptStore.swift` gains:

```swift
@discardableResult
public func expireByAge(maxAge: TimeInterval, now: Date = Date()) throws -> [VoiceTranscript]
```

Returns the transcripts that were deleted, so the retention runner can clean their `.aesgcm` audio files from disk. Implementation uses a single `DELETE ... RETURNING` SQL (GRDB supports this on SQLite ≥ 3.35) or falls back to a select-then-delete pair inside one write transaction.

### 5.3 Audio save guard

`VoiceCoordinator.saveTrainingExample` currently guards on `personalization.saveTrainingExamplesEnabled`. Change to:

```swift
guard personalization.saveTrainingExamplesEnabled || historySettings().saveAudio else { return }
```

When only `historySettings().saveAudio` is true (personalization off), we still write the encrypted audio file but **must not** call `trainingExampleStore.save(...)` for the training-example row — that table is personalization-owned. Refactor: lift the audio-encryption call out of `saveTrainingExample` into a dedicated helper `persistAudio(captured:transcriptID:) -> String?` that both paths can use, then have `VoiceCoordinator` set the resulting path on the `VoiceTranscriptDraft` before `voiceTranscriptStore.save(draft)`. Personalization continues to call `trainingExampleStore.save(...)` only when its own gate is on.

This reorders the recording pipeline: today, `voiceTranscriptStore.save(draft)` runs first (with `audioPath: nil`) and personalization optionally writes audio afterward. After the refactor, audio is persisted first when either gate is true, then the transcript draft is built with the resulting path, then both stores are written. The transcript ID used to name the audio file is generated up-front (UUID) and reused by `VoiceTranscriptStore.save` — extend `save` to accept an optional `existingID:` parameter, defaulting to a fresh UUID.

### 5.4 Audio file lifecycle

Audio files stay in the existing training-example store directory and keep their `.aesgcm` extension. The retention runner (§7) deletes a transcript's audio file by name when its row expires. Defense in depth: after each sweep, the runner lists the audio directory and deletes any `.aesgcm` file whose corresponding transcript ID is no longer in `voice_transcripts`.

## 6. UI

### 6.1 Storage header row

New private view `VoiceHistoryStorageHeader` rendered as the first child of `voiceHistorySection` (`MainWindowRoot.swift:1818`). Uses a single `MAYNSection(title: "Storage")` wrapping two `MAYNSettingsRow`s:

| Row | Subtitle | Trailing control |
|---|---|---|
| Keep history | "How long to keep voice transcripts on this device." | `MAYNDropdown<VoiceHistoryRetention>` (Forever / 90 days / 30 days / 7 days / 1 day) |
| Save audio recordings | "Required for Download audio and Retry. Recordings are encrypted locally." | `Toggle` |

No new design tokens. The dropdown reuses `MAYNDropdown` with a `title` formatter that returns "Forever" or "Last N days".

### 6.2 Row changes

`VoiceTranscriptHistoryRow` (`MainWindowRoot.swift:2459`) changes:

- The trailing `StatusPill(text: "\(durationMs) ms", kind: .neutral)` is removed.
- The metadata line becomes `HH:MM a · lang · model · 1.2 s`, where the duration formatter is `String(format: "%.1f s", Double(durationMs) / 1000.0)` for durations under 60 s, and `Xm Ys` above.
- A new trailing `VoiceTranscriptRowMenu` view is added inside the same `HStack`. It renders nothing when `!isHovering && !isFocused`. On hover/focus it fades in (via `MAYNMotion.normalAnimation`) a 22 pt `Image(systemName: "ellipsis")` button that opens a SwiftUI `Menu` with the three items below.

### 6.3 Menu items

| Label | SF symbol | Action | Disabled state |
|---|---|---|---|
| Retry | `arrow.clockwise` | Calls `retryTranscript(id:)` on `VoiceCoordinator` (§7.2). | `audioPath == nil` — disabled with help "Audio recording wasn't saved for this transcript." |
| Download audio | `arrow.down.circle` | Decrypts audio, runs `NSSavePanel` with default name `voice-yyyy-MM-dd-HHmm.wav`, writes plain WAV. | Same disabled state as Retry. |
| Delete transcript | `trash` (destructive role) | Immediate delete; surfaces a `MAYNToast` with an Undo button for 5 s. | Never disabled. |

The menu uses SwiftUI `Menu` content closures; we do not introduce a custom popover. The disabled-with-help pattern uses `.disabled(true).help("…")` because SwiftUI menu items do not accept tooltips on a `.disabled` Button; the help shows when the user hovers the menu row.

### 6.4 Undo toast

`MainWindowRoot` already exposes Voice errors through a transient `errorMessage` row in the Activation section. We do not reuse that slot. Instead we add a sibling `historyToast: VoiceHistoryToast?` state on the Voice view that renders a `MAYNToast` overlaid above the history section. `VoiceHistoryToast` is a value type carrying a message, a `restore` closure, and a deadline. A `Task` scheduled at delete time clears the toast after 5 s. If the user taps Undo before that deadline, the `restore` closure runs and the toast clears immediately.

Restore semantics: the deleted `VoiceTranscript` value is captured by the closure. On undo, the closure calls `voiceTranscriptStore.save(VoiceTranscriptDraft(...), existingID: transcript.id)` so the restored row keeps its original UUID. This matters because the audio file is named after the original ID and the §7.1 orphan sweep matches files to live transcript IDs — a new UUID on restore would cause the next sweep to delete the audio. The audio file is **not** deleted until the toast expires, so restore is safe.

## 7. Behavior

### 7.1 Retention sweep

A new actor `VoiceTranscriptRetentionRunner` in `MacAllYouNeed/Voice/VoiceTranscriptRetentionRunner.swift` owns the sweep:

- Triggered on `AppController.start`.
- Triggered every 1 hour by a `Timer` while the app is running.
- Triggered after every new transcript append (cheap: a single age check on the oldest row).

For a non-`forever` window, the runner:

1. Reads the current retention setting.
2. Calls `voiceTranscriptStore.expireByAge(maxAge: window.seconds)`.
3. For each returned `VoiceTranscript` with a non-nil `audioPath`, deletes that file (best-effort; log failures, do not throw).
4. Lists the audio directory and deletes any `<id>.wav.aesgcm` file whose `<id>` is not present in the live transcript IDs. (`VoiceTrainingExampleStore.saveEncryptedAudio` writes files as `<id>.wav.aesgcm`; the orphan sweep parses the stem by stripping both extensions.)

For `forever`, the runner does nothing — same shape as today's clipboard `RetentionPolicy` with `maxAgeSeconds = nil`.

Step 4 (orphan sweep) is the only piece that walks the directory and is therefore the only place we need to coordinate carefully with the personalization training-example store, which writes the same files. To avoid deleting audio that personalization still references, the orphan sweep keeps any `<id>` that appears in either `voice_transcripts.audio_path` or `training_examples.audio_path` (matched by substring on the file path or by re-deriving the ID from the stem). The runner takes both stores as dependencies.

### 7.2 Retry

`VoiceCoordinator.retryTranscript(id:)` async:

1. Load the transcript by ID.
2. If `audioPath == nil`, throw `VoiceRetryError.noAudio`.
3. Decrypt the file using the existing AES-GCM helper that produced it.
4. Decode WAV to `CapturedAudio` (sample rate from WAV header, samples to `[Float]`).
5. Run the configured ASR engine and cleanup pipeline as if this were a fresh recording, **without** invoking the paste injector and **without** invoking personalization-side updates.
6. Persist a new `VoiceTranscript` row with the new text, new `startedAt`/`endedAt`/`durationMs` reflecting the original recording, new `modelIdentifier`, and the **same** `audioPath` so the new row can also be retried/downloaded. The original row is untouched.
7. Return the new transcript.

Failures throw a typed `VoiceRetryError`. The UI surfaces them as a transient `MAYNToast`. The original row remains.

### 7.3 Download audio

In the main app (not the daemon, which lacks the keys):

1. If `audioPath == nil`, the menu item is disabled and the path is never reached.
2. Decrypt audio to a temporary `Data` blob.
3. Show `NSSavePanel` with default filename `voice-yyyy-MM-dd-HHmm.wav`, allowed content types `[.wav]`.
4. On accept, write the decrypted bytes to the chosen URL.
5. On cancel, do nothing. On error, present an `NSAlert`.

We deliberately decrypt to memory rather than writing to a temp file because the audio is short (a single dictation), and a temp file would have to be wiped after the save.

### 7.4 Delete transcript

1. Capture the `VoiceTranscript` value being deleted.
2. Call `voiceTranscriptStore.delete(ids: [id])`.
3. Schedule audio file deletion after 5 s (a `Task.detached`).
4. Surface the undo toast (§6.4).
5. If undo fires before the 5 s elapse, cancel the audio delete task and re-save the captured value as a fresh draft.

If the personalization training-example store also references the audio file (it does whenever `personalization.saveTrainingExamplesEnabled` was on at recording time), the delayed audio delete must skip the file. The Task closure checks for this via the training-example store before deleting.

## 8. Edge Cases

| Case | Behavior |
|---|---|
| User toggles `saveAudio` from on to off | New recordings stop saving audio. Existing audio files are kept; Retry/Download still work for old transcripts until retention prunes them. |
| User shortens retention from Forever to 7 days | Next sweep prunes everything older than 7 days, including audio files. No confirmation prompt; the dropdown change is the intent signal. We surface a small `MAYNToast` with the count of items pruned ("Removed 12 transcripts older than 7 days"). |
| Audio file is missing on disk but `audio_path` is non-nil | Retry and Download show a toast "Couldn't read recording" and offer to clear the stale path (one-shot `UPDATE voice_transcripts SET audio_path = NULL WHERE id = ?`). |
| AES decrypt fails (corrupt file) | Same as above. |
| Retry's ASR call fails | Toast with the underlying error; original row untouched; no new row inserted. |
| User mass-deletes via the existing multi-select shortcut while undo toast is showing for a single-row delete | The pending undo restores the single row; the multi-select delete still proceeds for its own IDs. The two operations are independent. |
| Retention runner runs while a recording is in progress | Active recording's transcript does not exist yet, so it is not affected. The runner only touches committed rows. |
| App is force-quit between row delete and the 5 s audio cleanup | Audio file remains. The orphan sweep on next launch removes it. |

## 9. Errors

All user-visible errors surface as `MAYNToast`s, not modal alerts (except the `NSSavePanel` write failure which uses `NSAlert` because the save panel itself is modal). Toasts use the existing error variant.

Logged-only failures: retention sweep errors, orphan audio cleanup errors, undo audio-cancel race.

## 10. Testing

### 10.1 Unit tests in `Shared/Tests/CoreTests/Voice/`

- `VoiceTranscriptRetentionTests`
  - Table: `(window, transcriptAgeDays, hasAudio) -> (rowDeleted, audioDeleted)`.
  - Cases include `forever` never deletes, exact-boundary age, multiple windows.
- `VoiceTranscriptStoreTests` (extend existing file)
  - `expireByAge` returns the expected deleted set, leaves newer rows intact, deletes nothing when nothing matches.
- `VoiceHistorySettingsTests`
  - Round-trip persistence through a stub `UserDefaults`; default values when keys absent.

### 10.2 Coordinator tests in `MacAllYouNeedTests/Voice/`

- `VoiceCoordinatorRetryTests`
  - Fake ASR + fake cleanup. Asserts: a new row is inserted, the original row is preserved, the paste injector is never called, the `audioPath` of the new row equals the original.
  - Error path: ASR throws → no new row, error returned.
  - Missing-audio path: `audioPath == nil` → `VoiceRetryError.noAudio`, no ASR call.
- `VoiceCoordinatorAudioPolicyTests`
  - When only `saveAudio` is true (personalization off): audio file is written, `voice_transcripts.audio_path` is set, no `training_examples` row is created.
  - When only personalization is on: existing behavior preserved.
  - When both are on: behavior identical to personalization-only (audio written once, training row created).
  - When both are off: no audio file written, `audio_path` is `nil`.

### 10.3 View-level tests in `MacAllYouNeedTests/`

- A small snapshot-style test of `VoiceTranscriptHistoryRow` that asserts the metadata format string ("HH:mm a · lang · model · 1.2 s") and that the row exposes the menu when hovered (we can drive hover state via a SwiftUI environment or `View` modifier path).
- Manual checklist appended to the spec: enable Save audio → record → Retry → Download → delete → Undo → confirm row returns → retention sweep manually (set to 1 day, set system clock forward) → confirm rows and files vanish.

## 11. Migration

No schema migration. Existing transcripts keep their `audio_path` values (most are `nil`). Existing personalization users immediately see Retry/Download available on transcripts captured while personalization was on. Existing non-personalization users see the toggles default off and the menu items disabled until they opt into `saveAudio`.

## 12. Out of Scope

- A standalone History sidebar entry.
- Filter pills (All / Dictations / Ask anything).
- Date-grouped section headers in the list.
- A privacy reassurance card.
- A copy or flag per-row icon.
- App-wide visual restyle.
- A streamed download UI for very long recordings (current scope assumes single-dictation lengths; `NSSavePanel` + `Data.write` is acceptable).
- Sync of transcripts between devices.

## 13. Review Checklist (pre-PR)

- `swiftlint --strict` passes.
- Reduce Motion: enable in System Settings → re-run hover-reveal and undo toast → confirm both honor the setting.
- Audio file count on disk matches the count of `voice_transcripts.audio_path IS NOT NULL` rows plus the count of `training_examples.audio_path IS NOT NULL` rows.
- Disable Save audio after recording with it on → confirm new recordings stop writing files but old files remain accessible.
- Shorten retention from Forever to 1 day → confirm sweep runs on next hour boundary or on next transcript append, whichever first.
- Manual Retry on a Chinese transcript still picks the right ASR language path.
- Manual Download produces a `.wav` that plays in QuickTime.
