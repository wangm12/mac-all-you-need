# Runtime Surfaces

Source:

- `MacAllYouNeed/App/CopyHUD.swift`
- `MacAllYouNeed/App/AutoDownloadHUD.swift`
- `MacAllYouNeed/Settings/Permissions/PermissionGrantPresenter.swift`
- `MacAllYouNeed/WindowHub/WindowHubPanelController.swift`
- `MacAllYouNeed/Voice/UI/MiniVoiceHUD.swift`

What it covers:

- Copy confirmation toast.
- Auto-download prompt toast.
- Floating permission instruction panel.
- Floating window hub panel.
- The voice mini-pill and its recording/transcribing/cancelled states.

Captured UI:

- `screenshots/copy_hud_attempt.png`
- `screenshots/open_panel_choose_apps.png`
- `screenshots/window_hub_panel.png`
- `screenshots/window_hub_ai_organize.png`

Notes:

- Some runtime surfaces are represented by a stable live screenshot from the
  current app state.
- The voice mini-pill is described from code because its active runtime state
  was not stable enough to keep on screen during this pass.
- The window hub floating panel was captured after enabling the Windows feature
  from Dashboard and opening the runtime panel.
