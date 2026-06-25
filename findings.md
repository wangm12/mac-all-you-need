# Findings

## Live surface captures already completed
- Dashboard
- Clipboard
- Voice
- Downloads
- Enhanced Finder
- Window Layouts
- Window Grab
- Windows
- System -> Permissions
- System -> Advanced
- Voice Setup onboarding
- Clipboard -> History
- Clipboard -> Snippets
- Clipboard -> Settings
- Window Layouts -> Shortcuts

## Real app capture notes
- Real app navigation was verified on the live window through AppleScript/Accessibility presses.
- Captured real-page states include Dashboard, Clipboard History, Clipboard Snippets, Voice, Downloads, AI File Organizer, Window Grab, Windows, and Voice Setup.
- System subpages General, Permissions, and Advanced are reachable in the live app.
- Live capture now includes System -> General, Permissions, and Advanced as verified screenshots.
- Live capture now includes Voice -> History, Recognition, Dictionary, Personalization, and Settings as verified screenshots.
- Voice onboarding wizard now shows the reusable step header and progress bar at the top of every step.
- Voice onboarding Try It step now exposes the current readiness state as a visible pill, not just plain text.
- Reminders popover now uses the same pill language for empty and permission states as the rest of the app.
- Dashboard navigation is now working in the live app after re-checking the selection path.

## Initial UI observations
- The dashboard quick-start strip was too passive for first-run guidance, so it was upgraded to be clickable and route users into key entry points.
- The app still needs a pass over transient surfaces and setup/onboarding flows to make the product feel complete and foolproof.
- The dashboard still needed a stronger "what should I do next" affordance for partially configured installs, so a setup prompt was added above the quick-start strip.
- The dashboard now also has a top summary rail to make setup state, feature count, and downloads queue visible at a glance.
- Disabled dashboard tiles now route into onboarding or permissions instead of stopping cold.
- AI File Organizer now has a clear overview block, a no-proposal empty state, and a direct route to Voice setup when the LLM is missing.
- The Voice Command Center popover now explains its role and offers a direct path to the full Voice page.
- The Downloads Command Center popover now explains queue behavior and offers a direct path to the full Downloads page.
- The Clipboard and Window Layouts popovers now explain their purpose and offer direct paths to the full pages.
- The Reminders Command Center popover now explains its role and offers a direct path to the full Voice page.
- The "Grant permissions" quick-start now routes directly to the Settings > Permissions page instead of stopping at the Settings root.
- The Dashboard quick-start copy was still naming Window Hub in a way that didn't match the most obvious first-run path, so it was narrowed to Clipboard/Voice/Downloads language.
- The Dashboard downloads card needed clearer retry feedback, so the failed state now exposes an explicit "Retrying" pill while the retry task is in flight.
- The Dashboard failed-download card now explains that Retry fetches the feature pack again, which should make the state easier to understand at a glance.
- UI audit startup was not leaving usable artifact evidence, so the audit controller was adjusted to write an initial manifest before screenshot rendering begins.
- Even after lowering screenshot-render peak memory, the audit binary still exits with `137`, so capture evidence remains incomplete and needs a different launch/debug path.
- Voice Try It was still too open-ended for first-time users, so the step was rewritten as a concrete 3-step task flow with clearer readiness feedback and less duplicated status text.
- Live indicator capture: copying a downloadable YouTube URL into the clipboard immediately created a new top history item and showed the auto-download prompt indicator on the right edge of that row.
- Clipboard history source-app / fallback icons now have explicit accessibility labels so the indicator state is readable to assistive technologies.
- AutoDownloadHUD buttons now expose explicit accessibility labels and hints so the transient download prompt is self-describing.
- AutoDownloadHUD now uses "Ready to download" and a single chip-level accessibility announcement so the prompt reads like a clear next action.
- Live indicator capture updated: repeated copies of the same downloadable URL continue to create new top history entries, confirming the auto-download recognition path stays active.
- AutoDownloadHUD now separates its accessibility label and value so the status reads cleanly and the host domain is spoken as the value.

## Code references already inspected
- `MacAllYouNeed/App/MainWindow/Destinations/DashboardDestinationView.swift`
- `MacAllYouNeed/Onboarding/OnboardingWizardView.swift`
- `MacAllYouNeed/Onboarding/FeatureOnboardingFlowView.swift`
- `MacAllYouNeed/Onboarding/OnboardingWindowController.swift`
- `MacAllYouNeed/App/CopyHUD.swift`
- `MacAllYouNeed/App/AutoDownloadHUD.swift`
- `MacAllYouNeed/ClipboardDock/Views/Cheatsheet/CheatsheetOverlay.swift`
- `MacAllYouNeed/WindowControl/Radial/RadialPuckHUDView.swift`
- `MacAllYouNeed/Voice/UI/MiniVoiceHUD.swift`
- `MacAllYouNeed/App/AppControllerOnboarding.swift`
- `MacAllYouNeed/App/AppController.swift`
- `MacAllYouNeed/App/MainAppDestination.swift`
- `MacAllYouNeed/App/FunctionDestinationRegistry.swift`
- `MacAllYouNeed/Settings/SettingsDestination.swift`
- `MacAllYouNeed/Settings/SettingsRoot.swift`
- `MacAllYouNeed/App/Audit/UIAuditAppController.swift`
- `MacAllYouNeed/App/Audit/UIAuditGalleryView.swift`
- `MacAllYouNeed/App/MainWindowRoot.swift`
