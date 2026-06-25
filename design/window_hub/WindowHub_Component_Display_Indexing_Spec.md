# Window Hub — Component Display & Indexing Spec

Version: v0.4  
Status: Product / engineering draft  
UI direction: compact masonry dashboard, one-click final targets, macOS-native utility, minimal visual noise

---

## 0. Product decision summary

Window Hub should feel like a fast native Mac utility, not a browser tab manager and not a visual thumbnail switcher.

The default surface is a compact dashboard. It should show all active apps and windows immediately, then show the most useful tabs/files/targets inside each app section. Every visible row is a final destination: one click or Enter should switch directly to that window, tab, file, or workspace.

For browsers with many tabs, the dashboard must not render every tab by default. The rule is:

> All windows should be visible. All tabs should be searchable. Only the active, recent, and summarized tabs should be visible by default when a window is heavy.

This avoids the two bad extremes:

1. Showing only app filters, which forces the user to drill down.
2. Showing 200 browser tabs, which destroys scanability and performance.

The display should use open-time incremental indexing, not continuous real-time background indexing. When the panel is closed, Window Hub should not keep a live tab index, AX observers, polling loops, screenshots, thumbnail cache, or browser extension worker. When the panel opens, it builds a short-lived snapshot from running apps with strict time budgets and progressive UI updates.

---

## 1. Glossary

### 1.1 Target

A target is anything the user can activate directly from Window Hub.

Examples:

- App window
- Browser tab
- Finder window
- Cursor / VS Code window
- Terminal window / tab if available
- Figma document window
- Notes note window
- Mail message window

A visible target row must always be actionable. It should never be only a category label unless it is explicitly styled as a group row such as a domain group or a window group header.

### 1.2 Indexed target

An indexed target is known to Window Hub and can be searched or activated, but may not be visible in the default dashboard.

Example: Chrome has 200 tabs. Window Hub may visibly show 12 rows, but 200 tabs can still become searchable once the browser provider has finished indexing.

### 1.3 Displayed target

A displayed target is rendered as a visible row in the dashboard.

Displayed target count must be intentionally capped. Rendering every possible target is only allowed for small workspaces.

### 1.4 Window group

A window group is a section inside an app section representing one app window and its child targets.

For Chrome with two windows, Chrome has one app section and two window groups.

### 1.5 Heavy window

A heavy window is any window with too many child targets to display directly.

Default threshold:

- Browser window with more than 30 tabs: heavy
- App section with more than 36 total child rows: heavy
- Global workspace with more than 500 indexed targets: huge workspace mode

These thresholds are product defaults and can be tuned after profiling.

### 1.6 Current window

The current window is the frontmost active window at the moment Window Hub opens, or the most recent user-facing window if the frontmost element cannot be resolved through Accessibility.

The user must always be able to identify it visually.

---

## 2. Display lifecycle

### 2.1 Closed state

Window Hub is closed when the floating panel and the main Window Hub page are not visible.

Behavior:

- No live global window index.
- No browser tab polling.
- No AXObserver attached to arbitrary apps.
- No ScreenCaptureKit.
- No CG screenshot.
- No thumbnail cache.
- No background worker dedicated to Window Hub.
- No continuous browser extension dependency.
- Optional: keep a tiny recent target ring buffer in memory or UserDefaults, capped at 50 entries, containing only lightweight labels and activation hints. This is not a full tab index.

Allowed while closed:

- Global hotkey registration.
- Feature state registration.
- A tiny recent-target summary if needed for instant skeleton display.

Not allowed while closed:

- Enumerating all browser tabs repeatedly.
- Observing Dock hover.
- Observing every running app.
- Keeping AXUIElement references alive for all windows.
- Storing URLs or tab lists on disk.

### 2.2 Hotkey pressed / panel opening

Trigger:

- User presses the Window Hub shortcut.
- User clicks Window Hub entry in the main app.
- User invokes Window Hub through a command palette or menu item.

Immediate display within 0 to 80 ms:

- Panel shell.
- Titlebar / toolbar.
- Search field focused.
- Empty compact dashboard body with skeleton rows or recent target placeholders.
- Current context strip if current app/window can be resolved immediately.

The panel should not wait for full enumeration before appearing.

### 2.3 Snapshot building

After the panel shell is visible, Window Hub builds a snapshot in phases:

1. Resolve frontmost app and current window.
2. Enumerate regular running apps.
3. Enumerate visible windows for each app.
4. Build app sections and window groups.
5. Enumerate child tabs/files for selected high-priority apps.
6. Incrementally enrich rows with tab title, host/domain, active state, pinned/audible/private state if available.
7. Mark snapshot complete or partial after the hard deadline.

The UI should update progressively. App sections can appear before all tab details are available.

### 2.4 Panel open / soft live state

While the panel is open, Window Hub can behave as a soft real-time view.

Allowed:

- Temporary snapshot in memory.
- Temporary AX observers for frontmost app or currently expanded app only.
- Debounced refresh when the user searches, expands a window, or clicks Show all.
- Coalesced UI updates every 80 to 120 ms.
- Re-indexing a single app when that app section becomes visible or focused.

Not allowed:

- Polling all apps at high frequency.
- Keeping browser-wide observers after the panel closes.
- Re-enumerating all tabs on every keystroke.
- Blocking keyboard input while indexing.

### 2.5 Panel closing

Trigger:

- Esc.
- Click outside panel.
- User activates a target.
- User opens a modal flow that moves to main app.
- System cancels panel due to focus or secure input condition.

Behavior:

- Cancel in-flight enumeration tasks.
- Detach temporary AX observers.
- Release full snapshot and AX references.
- Keep only small recent target ring buffer if enabled.
- Restore previous foreground app unless user activated a target.

### 2.6 Main Window Hub page open

The main page can use the same snapshot system but with longer lifetime while the page is visible.

Rules:

- Main page and panel share a snapshot coordinator.
- If both are open, do not enumerate twice.
- Main page can show more rows because it has more space.
- Still no background indexing after main page is closed.

---

## 3. Indexing strategy: answer to realtime vs open-time reading

### 3.1 Decision

Use a hybrid strategy:

> No continuous realtime index while closed. Build an incremental live snapshot when the panel or main page opens. Keep it fresh only while the Window Hub surface is visible.

This gives the speed of a live panel without the resource cost of a background daemon.

### 3.2 Why not realtime background indexing

A continuous realtime index sounds fast, but it creates hidden cost:

- AX observers across many processes can be fragile and expensive.
- Browser tab state changes frequently.
- Polling browser UI trees can spike CPU.
- Holding large tab lists increases memory.
- Background URL/tab metadata collection creates privacy concerns.
- It conflicts with the product promise that Window Hub is lighter than Dock Previews.

### 3.3 Why not purely read everything only after open

Reading everything only after open is resource-light but can feel slow when users have many browser tabs.

So the panel should not wait for everything. It should show the shell and current app immediately, then progressively fill the rest.

### 3.4 Final indexing model

Use four layers.

#### Layer 0 — Closed-state minimal memory

When closed, keep only:

- Hotkey.
- Feature settings.
- Optional recent target ring buffer, max 50 entries.
- Optional app icon cache through system mechanisms.

Do not keep:

- Full list of windows.
- Full list of tabs.
- AX element references.
- URL list.
- Domain group list.
- AI-ready tab JSON.

#### Layer 1 — Opening shell snapshot

Time budget: 0 to 80 ms.

Data:

- Current time.
- Current frontmost app if available.
- Previous recent targets if available.
- Search field.
- Skeleton app sections.

Display:

- Panel opens instantly.
- Current context strip may show `Resolving current window…` if not ready.

#### Layer 2 — App/window index

Time budget: 80 to 250 ms target, 500 ms soft deadline.

Data:

- Running regular apps.
- App icons.
- Window titles.
- Window count.
- Minimized / hidden state if available.
- Current window marker.
- Basic activation target.

Display:

- All app sections with windows become visible.
- Browser windows show tab count only if cheap; otherwise show `tabs loading`.

#### Layer 3 — Priority child target index

Time budget: 250 to 800 ms target, 1.5 s soft deadline.

Priority order:

1. Current app.
2. Current window.
3. Recently active app/window if known.
4. Browser apps currently visible in masonry viewport.
5. Apps matching current search query.
6. Remaining regular apps.

Data:

- Active tab.
- Recent tabs if available.
- Top domain groups if host is available.
- Small window full tab list if tab count is below threshold.
- Capability flags.

Display:

- Current window becomes rich first.
- Other apps can remain window-only or summarized until loaded.

#### Layer 4 — Full child target index

Triggered only when useful:

- Search field is non-empty.
- User expands a heavy window.
- User clicks Show all tabs in this window.
- User opens Cleanup review.
- User opens Suggest groups.
- Main page Browse is visible and idle.

Data:

- Full tab list for the requested app/window if provider supports it.
- Normalized URL / host only if available and allowed.
- Duplicate candidates.
- AI-safe redacted input if AI flow is opened.

Display:

- Search results fill progressively.
- Heavy windows show indexing progress.
- Results remain actionable as they arrive.

### 3.5 Snapshot freshness

Snapshot fields:

- `createdAt`
- `updatedAt`
- `sourceGeneration`
- `isPartial`
- `partialFailures`
- `dataQuality`
- `providerCapabilities`

Freshness rules:

- Snapshot is fresh while panel is open and updates are still being coalesced.
- Snapshot becomes stale if an app quits, AX returns invalid element, or activation fails.
- If stale row is clicked, try to reacquire target by stable identity before failing.
- If reacquire fails, show toast: `This window or tab is no longer available` and refresh that app section.

### 3.6 Stable identity strategy

Do not rely on only row index because browser tabs move.

Preferred identity order:

1. App bundle ID + process ID + AX window reference + browser tab identifier if provider exposes it.
2. App bundle ID + window title + tab title + URL normalized hash.
3. App bundle ID + window title + tab title + position fallback.
4. App bundle ID + window title only for window-only apps.

For activation, always validate target before focusing.

---

## 4. Global layout rules

### 4.1 Overall structure

The panel has five regions:

1. Titlebar / traffic lights / title.
2. Search and action toolbar.
3. Current context strip.
4. Compact masonry content area.
5. Footer status bar.

The content area uses app sections in a masonry layout:

- Max two columns.
- One column on narrow panels.
- Each app section stays intact and is never split across columns.
- App sections are packed into the shorter column like a small masonry feed.
- App section gutter: 8 to 10 px.
- Content outer padding: minimal, 8 to 10 px.
- No grid row alignment, so there should be no large holes.

### 4.2 Density modes

Default density: Compact.

Compact row height:

- Target row: 28 to 30 px.
- Window header: 28 px.
- App header: 32 px.

Comfort row height:

- Target row: 34 to 36 px.
- Window header: 32 px.
- App header: 36 px.

Density toggle is optional in v1. If included, it should be subtle and not part of the main decision flow.

### 4.3 What should never be shown by default

Do not show:

- `Tab`, `Win`, `File` type tags on every row.
- Repetitive app labels on every row.
- Domains for non-web apps.
- Full URLs in the dashboard.
- Big cards for individual tabs.
- Screenshot thumbnails.
- Decorative gradients or AI-style glow.
- Three or more masonry columns.

### 4.4 What can be shown on the right side of a row

Right-side metadata is reserved for only useful context.

Show:

- Web host for web tabs, e.g. `github.com`, `notion.so`.
- `minimized`, `hidden`, `fullscreen`, or `private` only when needed.
- Count summary on group rows, e.g. `12 tabs`.
- Loading state, e.g. `indexing…`.

Do not show:

- `Tab` tag.
- `Win` tag.
- `File` tag.
- App name repeated inside the same app section.
- Finder domain or generic `Finder` label on every row.

---

## 5. Component display spec

## 5.1 WindowHubPanelController

### Trigger

Show when:

- User presses default shortcut, e.g. Option + Shift + W.
- User clicks Window Hub from menu or sidebar.
- User invokes Window Hub command from another MAYN entry point.

Do not show when:

- Accessibility permission is missing and the app is already showing a blocking permission setup window. In that case, focus the setup window or show a lightweight permission panel.
- Hotkey recording is active.
- The app is in a state where showing a nonactivating panel would break user input.

### Display

- Center on current screen or screen containing cursor.
- Width target: 760 to 840 px.
- Height target: 560 to 640 px.
- Use macOS material / subtle blur / thin border.
- No dramatic entrance. Use small opacity + scale transition only.

### Edge cases

- Multiple displays: open on cursor display; if no cursor info, open on active display.
- Full-screen Space: show in active Space if possible; otherwise show on main display and preserve activation behavior.
- Reduce Motion: disable scale animation.
- Secure Input: panel can show, but hotkey/search may be limited. Show small status if keyboard input is blocked.
- Panel opened while main page is open: reuse snapshot, do not duplicate enumeration.

---

## 5.2 Titlebar

### Trigger

Always shown in panel.

### Display

- macOS traffic lights on the left if panel style supports it.
- Title: `Window Hub` or no visible title if search field is dominant.
- Optional subtitle: `Windows and tabs` only in main window, not necessary in panel.

### Edge cases

- In compact panel, titlebar should not take too much height.
- If using nonactivating NSPanel and traffic lights are visually awkward, use a custom minimal top bar.

---

## 5.3 Search field

### Trigger

Always shown.

### Display

Placeholder:

- Default: `Search windows, tabs, apps…`
- During partial indexing: `Search windows, tabs, apps… indexing more tabs`
- No Accessibility permission: disabled placeholder `Accessibility permission required`

Behavior:

- Autofocus on open.
- Typing filters current snapshot immediately.
- If query is non-empty and full tab index is incomplete, schedule priority indexing for apps likely to match.
- Search results remain in the same dashboard surface; do not switch to a totally different full-page mode unless results need a temporary overlay.

### Search matching fields

Use available fields in this priority:

1. App name.
2. Window title.
3. Tab title.
4. Host/domain if available.
5. Normalized URL path if available and privacy setting allows.
6. File name / folder name for Finder.

### Edge cases

- Search typed before indexing completes: show existing matches immediately and an inline `Still indexing…` row.
- Search with no results but indexing incomplete: show `No matches yet — still indexing tabs`.
- Search with no results after complete: show `No match` and suggest app/window/title/domain.
- Search query is a URL: prioritize host/path matching for web tabs.
- Search query matches a collapsed heavy window: expand matched rows only, not the entire window.
- IME/composition input: do not trigger aggressive refresh on every composition event.
- Paste long query: debounce and cap fuzzy scoring cost.

---

## 5.4 Toolbar action: Review

### Trigger

Show when at least one cleanup-capable item exists or cleanup can run local analysis.

### Display

Button label: `Review`

Do not label as `Clean up` in the default toolbar because it sounds destructive.

On click:

- Opens Cleanup Review sheet.
- If full index is incomplete, start cleanup-specific indexing first.
- Sheet can show `Analyzing…` while duplicate/stale candidates are computed.

### Edge cases

- No cleanup candidates: show sheet with `Nothing obvious to review`.
- No full URL data: duplicate detection falls back to title/host and labels candidates as low confidence.
- Browser cannot close tabs: show suggestions as manual only.
- Private/incognito window: excluded by default.
- Active/pinned/audible tabs: never selected by default.

---

## 5.5 Toolbar action: Suggest

### Trigger

Show when AI provider is configured or can be configured.

### Display

Button label: `Suggest`

Do not label as `AI Organize` in the primary UI. The word AI can appear inside the sheet for transparency.

On click:

- Opens Suggest Groups sheet.
- If provider is missing, show setup state instead of failing silently.
- If full tab data is incomplete, index only the needed browser windows up to budget.

### Edge cases

- AI provider missing: disabled button with tooltip or enabled button that opens setup card.
- AI timeout: fallback to local duplicate review.
- Too many tabs: send top N redacted tabs and indicate truncation.
- Private tabs: excluded by default.
- Full URLs: excluded by default; host/title only unless user opts in.
- Unsupported browser move operation: suggestion is `Manual only`.

---

## 5.6 Current context strip

### Trigger

Show when:

- Current app/window can be resolved.
- There are multiple windows in the current app.
- A heavy browser app has multiple windows.
- User needs orientation.

Can be hidden when:

- Workspace is tiny and current context is obvious.
- Search query is active and top result is current target.

### Display

Format:

`Current: Chrome › MAYN / GitHub Work › PR #42 review`

If tab is unknown:

`Current: Chrome › MAYN / GitHub Work`

If only app is known:

`Current: Chrome`

Visual style:

- One-line compact strip.
- Small icon of app.
- Not a large banner.
- Current context is informational and not a separate navigation path.

### Edge cases

- Current tab title changes during indexing: update text softly without layout jump.
- Current window cannot be resolved: show `Current window unavailable` only if needed; otherwise omit strip.
- Multiple displays: optionally append `Display 2` only if there is ambiguity.
- Current Space only setting: if enabled, context strip can show `Current Space`.

---

## 5.7 Indexing status indicator

### Trigger

Show when snapshot is not complete or has partial failures.

### Display

Subtle status in toolbar or footer:

- `Indexing…`
- `Partial — 1 app timed out`
- `Ready`
- `No Accessibility permission`

Never use a large spinner in the middle unless the dashboard has no content at all.

### Edge cases

- One app times out: dashboard still usable.
- Browser tabs incomplete: show `tabs still indexing` only near affected app/window.
- Search in incomplete index: show `searching more tabs…` inline.
- User clicks target while indexing: activation should proceed; indexing is cancelled or continues in background only until panel closes.

---

## 5.8 MasonryContentView

### Trigger

Show when Accessibility permission exists and at least app/window skeleton is available.

### Display

- Up to two columns.
- App sections packed by shortest column.
- 8 to 10 px gutter between sections.
- 8 to 10 px outer padding.
- App section maintains internal window grouping.
- No big whitespace caused by CSS/grid row alignment.

### Packing rule

When app sections are loaded:

1. Current app section always appears first in the left column.
2. Recently active apps follow.
3. Remaining apps sorted by last activation or app name.
4. Each new section is placed into the currently shorter column.
5. If one app is extremely tall, cap its default visible rows and add `Show more` / `Show all` inside that app, rather than making the whole masonry unbalanced.

### Edge cases

- Panel width below threshold: one column.
- App section height exceeds viewport: internal virtualization or capped rows.
- Search hides many rows: re-pack visible app sections after debounce.
- App section has zero visible rows after search: hide that app section.
- App quits during display: fade out or mark stale, then remove on next coalesced update.

---

## 5.9 AppSection

### Trigger

Show when app has at least one user-facing window or setting `Show background apps` is enabled.

Default show:

- Apps with windows.
- Browser apps with tab/windows.
- Finder if it has windows.
- Terminal/iTerm if it has windows.
- Cursor/VS Code if it has windows.

Default hide:

- MAYN itself.
- Helper apps.
- Menu bar only apps.
- Background processes.
- Apps with `activationPolicy != regular`.
- Apps with no windows unless user enables background apps.

### Display

Header contains:

- App icon.
- App name.
- Summary count, e.g. `2 windows · 203 tabs`.

Header does not contain:

- Large action buttons.
- Repeated filters.
- Decorative badges.

Body contains:

- Window groups for multi-window apps.
- Direct target rows for single-window apps or simple apps.
- Loading rows if children are still indexing.
- Empty state only if user explicitly expanded an app that has no visible targets.

### Edge cases

- App has one window and few targets: flatten window group if this improves scanability.
- App has multiple windows: always show window group headers.
- App has more than 5 windows: show current/recent windows first, then collapsed `Show N more windows`.
- App section too tall: cap body height and show app-level `Show more`.
- App window titles duplicate: include secondary context in window header, e.g. Space/display or tab count.
- App icon unavailable: use default app glyph or first letter.

---

## 5.10 AppSection header

### Trigger

Always shown when AppSection is shown.

### Display

Examples:

- `Chrome` right side `2 windows · 203 tabs`
- `Safari` right side `1 window · 6 tabs`
- `Finder` right side `3 windows`
- `Cursor` right side `2 windows`

Use count text only in header, not repeated in every row.

### Current app indicator

If this app contains the current window:

- Add a subtle left accent to the whole app section or current window group.
- Do not make the whole card bright blue.

### Edge cases

- Counts are unknown while indexing: show `indexing…` or omit count until known.
- Count changes after indexing: update without layout jump.
- App has tabs but tab count unavailable: show `2 windows` instead of wrong tab count.

---

## 5.11 WindowGroup

### Trigger

Show inside an AppSection when:

- App has multiple windows.
- Browser window has many tabs.
- Window identity matters for orientation.
- Window title is meaningful.

Can be flattened when:

- App has one window.
- Window has fewer than 5 child targets.
- Window title duplicates app name and adds no value.

### Display

Window header contains:

- Window title.
- Tab/file count if available.
- `Current` pill if it is the current window.
- Optional status: `minimized`, `hidden`, `fullscreen`, `private`.

Window body contains:

- Active tab row.
- Recent tab rows.
- Domain group rows for web tabs.
- Show all row for heavy windows.
- Direct window row for window-only apps if needed.

### Current window indicator

A current browser window should be identifiable through at least three signals:

1. Current context strip at top.
2. Subtle vertical accent on the current window group.
3. `Current` pill in the window header.
4. Active tab row has a small dot.

Use at least two of these; use all four for heavy browser apps with multiple windows.

### Edge cases

- Two Chrome windows have same title: append count/context, e.g. `GitHub — PRs · 47 tabs` and `GitHub — PRs · 82 tabs`.
- Window title empty: use `Untitled window` or top active tab title.
- Window minimized: show but dim; activation should unminimize if possible.
- Window hidden: show status; activation should unhide app.
- Window on other Space: show if setting allows; activation will switch Space.
- Full-screen window: show `fullscreen` only if useful; activation switches Space.
- Window closes during index: remove group on refresh.

---

## 5.12 WindowGroup header

### Trigger

Always shown for multi-window app sections. Optional for single-window simple apps.

### Display

Example for Chrome:

`MAYN / GitHub Work` right side `100 tabs · Current`

Example for non-current Chrome window:

`Research / Product References` right side `103 tabs`

Example for Finder:

`Downloads` right side omitted or `window` only if needed. Usually omit repetitive right label.

### Interactions

- Click header activates the window itself, not necessarily a specific tab.
- Disclosure control can expand/collapse the window group if it is heavy.
- Keyboard focus on header + Enter activates window.

### Edge cases

- Header click on browser window with active tab known should focus active tab/window.
- Header click on stale window triggers reacquire.
- If window group is collapsed due to size, header remains visible.

---

## 5.13 TargetRow

### Trigger

Show for every displayed final target.

### Display

Left side:

- Small favicon/glyph/app-specific icon.
- Target title.
- Optional active dot, pinned glyph, audible glyph.

Right side:

- Web host only for web tabs.
- Status only when important.
- Nothing for Finder/Cursor/Terminal/Figma rows unless status is needed.

Do not show `Tab`, `Win`, `File` tags.

### Examples

Chrome web tab:

- Title: `PR #42 review`
- Right: `github.com`

Safari web tab:

- Title: `AXUIElement · Apple Developer`
- Right: `apple.com`

Finder:

- Title: `Downloads`
- Right: empty

Cursor:

- Title: `WindowHubProvider.swift`
- Right: empty

Terminal:

- Title: `zsh — mayn`
- Right: empty

### Interaction

- Single click activates target.
- Enter activates focused target.
- Cmd+Enter may reveal in app or open secondary action menu in v2.
- Right click opens contextual actions if supported.

### Edge cases

- Target title empty: show `(Untitled)`.
- Title changes while panel is open: update row text.
- Row target is stale: on click, attempt reacquire, then show toast if unavailable.
- Activation is slow: show subtle progress on row, not global blocking spinner.
- Target is private/incognito: show `private` only in window header or row if necessary.
- Target is active: show small active dot; do not show loud selected background unless keyboard-focused.

---

## 5.14 ActiveTabIndicator

### Trigger

Show when provider can identify active tab or active target.

### Display

- Small dot before title.
- Current active tab can also have slightly stronger text weight.
- Do not use large colored badges.

### Edge cases

- Active tab unknown: omit indicator.
- Multiple active tabs reported due to provider bug: pick the tab in current window; otherwise omit.
- Active tab in collapsed domain group: show active tab separately above domain groups.

---

## 5.15 DomainGroupRow

### Trigger

Show only for web browser windows when:

- Host/domain is available.
- Window has enough tabs to benefit from grouping.
- Domain count is greater than 1, or domain is one of the top repeated hosts.

Default thresholds:

- Show domain groups when browser window has more than 30 tabs.
- Show top 5 to 7 domains by count or recency.
- Do not show domain groups for non-web apps.

### Display

Example:

`github.com` right side `12`

No `Tab` tag.
No full URL.
No repeated `Chrome` label.

### Interaction

- Click row expands that domain group inside the same window group.
- Expanded group shows matching tabs as TargetRows.
- Option-click can expand all domains in that window in v2.

### Edge cases

- URL unavailable but title suggests domain: do not invent domain unless confidence is high.
- Multiple subdomains: normalize to registrable host when possible, e.g. `github.com`; preserve important hosts like `localhost:3000`.
- Localhost: show `localhost` or `localhost:3000` only for web/browser tabs.
- Private tabs: include in count only if listed in dashboard; exclude from AI/cleanup by default.
- Domain group contains active tab: active tab should be surfaced separately even if group is collapsed.

---

## 5.16 ShowAllRow

### Trigger

Show when a window/app has more child targets than default display threshold.

Examples:

- Browser window has more than 30 tabs.
- App has more than 5 windows.
- Search result set has more than 80 matches.

### Display

Examples:

- `Show all 100 tabs in this window`
- `Show 9 more windows`
- `Show 42 more matches`

### Behavior

- Expands only the relevant scope.
- For Chrome with two 100-tab windows, clicking Show all in Window A expands only Window A.
- Do not expand all Chrome tabs across both windows unless user explicitly chooses app-level Show all.

### Edge cases

- If full index is not ready: row becomes `Indexing all tabs…` and updates when done.
- If provider cannot enumerate all tabs: show `Full tab list unavailable`.
- If expansion would create more than 300 visible rows: use virtualized internal list and keep scroll position stable.

---

## 5.17 LoadingRow / SkeletonRow

### Trigger

Show when a section has started indexing but child targets are not yet available.

### Display

- Compact grey placeholder rows.
- Text such as `Loading tabs…` only where helpful.
- Avoid heavy shimmer animation; use static or very subtle opacity pulse.

### Edge cases

- Loading exceeds 500 ms for one app: convert to `Still indexing…`.
- Loading exceeds hard timeout: show partial failure row.
- User starts search while loading: keep search interactive; loading row should not steal focus.

---

## 5.18 PermissionCard

### Trigger

Show when Accessibility permission is missing, revoked, or denied.

### Display

Title:

`Accessibility permission required`

Body:

`Window Hub uses Accessibility to read window titles and switch windows. It does not capture screenshots.`

Action:

`Open System Settings`

Secondary:

`Retry`

### Edge cases

- Permission granted while panel is open: retry enumeration automatically.
- Permission revoked mid-session: stop indexing, show card, release snapshot.
- User denies permission: keep card, do not show broken empty dashboard.
- Do not request Screen Recording.

---

## 5.19 EmptyState

### Trigger

Show when there is no content for the current scope.

Variants:

1. No windows found.
2. Search no results.
3. Tabs unavailable for this app.
4. Indexing still in progress.

### Display

No windows:

`No windows to show`

Search no result after complete:

`No match`

Search no result while incomplete:

`No matches yet — still indexing tabs`

Tabs unavailable:

`Tabs are unavailable for this app`

### Edge cases

- Do not show `No match` while index is still partial without saying indexing is still happening.
- For window-only apps, show the window row instead of an empty tab state.

---

## 5.20 PartialFailureRow

### Trigger

Show inside an app section when that app times out or provider fails.

### Display

Examples:

- `Tabs unavailable`
- `App did not respond`
- `Partial results`

Use subtle warning icon only if necessary.

### Edge cases

- Do not block other apps.
- Allow retry from row context menu.
- If the app becomes responsive later, update section.

---

## 5.21 Footer status bar

### Trigger

Always shown if it fits without clutter. Can be hidden in ultra-compact mode.

### Display

Left:

- `8 apps · 12 windows · 147 tabs`
- During indexing: `8 apps · 12 windows · indexing tabs…`
- Partial: `Partial · 1 app timed out`

Right:

- Keyboard hint, e.g. `Enter to open · Esc to close`.
- Optional `Review` / `Suggest` actions if not in toolbar.

### Edge cases

- Tab count unknown: show known counts only.
- Count changes: update with no dramatic animation.
- Huge workspace: show `500+ tabs indexed` or exact count if cheap.

---

## 5.22 CleanupReviewSheet

### Trigger

Show when user clicks Review.

### Display

Sheet sections:

1. Duplicates.
2. Stale tabs.
3. Background apps.
4. Empty windows.
5. Manual-only suggestions.

Each candidate row shows:

- Proposed action.
- Target count.
- Protection reason if disabled.
- Checkbox default off unless extremely safe.

Default safety:

- Active tab not selected.
- Pinned tab not selected.
- Audible tab not selected.
- Private/incognito not selected.
- Unsaved document windows not selected.
- Browser unsupported close operation not selected.

### Edge cases

- Duplicate by exact URL: high confidence.
- Duplicate by normalized URL: medium confidence.
- Duplicate by title only: low confidence and not selected.
- Provider cannot close tabs: show manual-only.
- User selects many destructive actions: confirm before execution.
- Execution partially fails: show failure summary and keep failed items visible.

---

## 5.23 SuggestGroupsSheet

### Trigger

Show when user clicks Suggest.

### Display

Top privacy summary:

- `Using: Voice AI provider`
- `Sending: titles + hosts only`
- `Excluded: private windows, full URLs, active close actions`

Suggestion cards:

- Project grouping.
- Create new browser window.
- Duplicate cleanup.
- Manual-only group.

Each suggestion shows:

- Name.
- Count.
- Proposed action.
- Capability status.
- Checkbox default off.

### Edge cases

- AI provider missing: show setup card.
- AI returns invalid IDs: ignore invalid suggestions and show warning.
- AI suggests closing active/pinned/audible/private tabs: reject or mark protected.
- AI suggests moving tabs in unsupported browser: manual-only.
- Snapshot changed after AI generated suggestions: mark suggestions stale and require refresh.
- AI timeout: show local duplicate fallback.

---

## 5.24 Toast / transient error

### Trigger

Show for short-lived non-blocking results.

Examples:

- Activation failed.
- Target no longer exists.
- Partial indexing completed.
- Cleanup finished with failures.
- AI timed out.

### Display

- Bottom area or top-right inside panel.
- Short text.
- No modal unless destructive action needs confirmation.

### Edge cases

- Multiple toasts: queue or collapse.
- Panel closing: discard non-critical toast.
- Activation target stale: toast should not prevent refresh.

---

## 6. Browser with multiple windows and 100+ tabs

This is the most important dashboard stress case.

### 6.1 Example scenario

Chrome has two windows:

1. `MAYN / GitHub Work` with 100 tabs.
2. `Research / Product References` with 103 tabs.

The current active window is `MAYN / GitHub Work`, active tab `PR #42 review`.

### 6.2 Chrome app section display

App header:

`Chrome` right side `2 windows · 203 tabs`

Inside Chrome:

Window group 1:

`MAYN / GitHub Work` right side `100 tabs · Current`

Rows:

1. Active tab: `● PR #42 review` right `github.com`
2. Recent tab: `Actions CI failing` right `github.com`
3. Recent tab: `Window Hub implementation plan` right `docs`
4. Domain group: `github.com` right `42`
5. Domain group: `notion.so` right `12`
6. Domain group: `apple.com` right `8`
7. Domain group: `localhost` right `6`
8. `Show all 100 tabs in this window`

Window group 2:

`Research / Product References` right side `103 tabs`

Rows:

1. Active tab if provider can read it, otherwise top recent tab.
2. Recent 3 to 5 tabs.
3. Top domain groups.
4. `Show all 103 tabs in this window`

### 6.3 How the user knows which window they are looking at

Use a layered orientation system:

1. Top current context strip: `Current: Chrome › MAYN / GitHub Work › PR #42 review`.
2. Chrome app section appears first because it contains the current window.
3. Current window group has a subtle left accent.
4. Current window header has `Current` text.
5. Active tab row has a dot.
6. If two windows have similar titles, include tab count and maybe display/Space context.

The user should not need to infer the current window from ordering alone.

### 6.4 Why not display all 203 Chrome tabs by default

Default dashboard is for fast scan and switching. Showing 203 browser rows by default causes:

- Important apps below Chrome disappear.
- User cannot scan the dashboard.
- Layout becomes a long browser tab list.
- Rendering and fuzzy index cost increases.
- It visually punishes users with messy browsers.

So the product rule is:

- Show every Chrome window.
- Show the active/recent/domain summary for each heavy window.
- Make every tab searchable once indexed.
- Show all tabs only inside the window the user expands.

### 6.5 Search behavior in this scenario

If user searches `github`:

- Search results appear inside the Chrome window groups where they belong.
- Matching tabs from both Chrome windows can appear.
- The current window still carries `Current` indicator.
- If full tab index is incomplete, show `searching more Chrome tabs…`.
- Results are actionable as soon as they appear.

If user searches exact tab title:

- The matching tab should be top result.
- Breadcrumb/secondary context should show which window it belongs to.

Example row:

`PR #42 review` right `Chrome › MAYN / GitHub Work · github.com`

### 6.6 Show all behavior

Clicking `Show all 100 tabs in this window`:

- Expands only `MAYN / GitHub Work`.
- Does not expand `Research / Product References`.
- Uses virtualization if visible rows exceed 80.
- Keeps active tab pinned at top or scrolls to active tab if user chooses.
- Keeps domain grouping available as a secondary organizer.

### 6.7 Cleanup/Suggest behavior in this scenario

Cleanup:

- Full tab index may be required.
- User should see progress: `Analyzing Chrome tabs…`.
- Duplicates across both Chrome windows can be detected if URL data is available.
- Active/pinned/audible/private tabs are protected.

Suggest:

- AI receives redacted title + host, not full URL by default.
- AI can suggest project windows across both Chrome windows.
- Suggestions must show original window context before moving/closing anything.

---

## 7. Visibility thresholds

### 7.1 Small workspace

Condition:

- Total indexed targets <= 60.
- No browser window has more than 30 tabs.
- No app has more than 5 windows.

Display:

- Show all apps.
- Show all windows.
- Show all tabs/targets.
- No Show all rows needed.

### 7.2 Medium workspace

Condition:

- Total indexed targets <= 250.
- Some browser windows may have 31 to 100 tabs.

Display:

- Show all app sections.
- Heavy browser windows are summarized.
- Small windows show all rows.
- App section height is capped if it harms masonry balance.

### 7.3 Huge workspace

Condition:

- Total indexed targets > 500, or one app has >300 targets, or one browser window has >150 tabs.

Display:

- Current app first.
- Current window summary first.
- Recent apps next.
- Heavy sections summarized aggressively.
- Footer says `Large workspace — search to jump directly`.
- Full indexing only on search/expand/review/suggest.

### 7.4 Per-window tab display rule

For browser windows:

- 0 tabs known: show window row + `tabs loading` or `tabs unavailable`.
- 1 to 30 tabs: show all tabs.
- 31 to 100 tabs: show active tab + recent 8 + top domain groups 5 + Show all.
- More than 100 tabs: show active tab + recent 5 + top domain groups 5 + Show all + search hint.

### 7.5 Per-app window display rule

For apps:

- 1 window: flatten if the window title is not useful.
- 2 to 5 windows: show all window groups.
- More than 5 windows: show current/recent 5 windows + `Show N more windows`.
- More than 20 windows: lazy render window groups and show search hint.

---

## 8. Search result display rules

### 8.1 Default search result structure

Search should not make the user lose context.

Preferred:

- Keep app sections, but hide non-matching rows.
- Keep window headers if they contain matching rows.
- Show breadcrumbs on rows where context is otherwise unclear.

Alternative for very dense results:

- Temporarily show a flat result list with breadcrumb text.
- Still include app/window context in every row.

### 8.2 Ranking

Ranking priority:

1. Exact active/current target match.
2. Prefix match in title.
3. App name match.
4. Window title match.
5. Tab title match.
6. Host/domain match.
7. URL path match.
8. Fuzzy match.
9. Recent activation boost.
10. Current app/window boost.

### 8.3 Search result count cap

- Show first 80 results by default.
- If more results exist, show `Show more matches`.
- Do not render hundreds of rows at once unless virtualized.

### 8.4 Edge cases

- Query matches app name `chrome`: show Chrome app section with current/recent window groups, not every Chrome tab immediately.
- Query matches host `github.com`: show matching domain rows and top matching tabs.
- Query matches title duplicated across windows: show window context.
- Query typed while index incomplete: combine current results with `indexing more…`.
- Query empty after search: return to compact dashboard and restore expansion state where reasonable.

---

## 9. Data quality and capability rules

### 9.1 Metadata quality states

Each target should carry metadata quality:

- `windowOnly`
- `titleOnly`
- `titleAndHost`
- `titleAndURL`
- `unsupported`
- `failed`

### 9.2 Display by quality

`windowOnly`:

- Show window row.
- No domain.
- Activation: switch window.

`titleOnly`:

- Show title.
- No domain unless host is confidently extracted.
- Search matches title only.

`titleAndHost`:

- Show host for web tabs.
- Domain groups enabled.
- Cleanup duplicate by host only is not enough; URL missing means lower confidence.

`titleAndURL`:

- Show host only in dashboard.
- Use normalized URL internally for exact duplicate detection.
- Full URL shown only in detail/review if privacy allows.

`unsupported`:

- Show `Tabs unavailable` or window-only row.
- Do not pretend tab count is known.

`failed`:

- Show partial failure row.
- Retry available.

### 9.3 Provider capabilities

Capabilities should be explicit:

- Enumerate windows.
- Enumerate tabs.
- Read URL.
- Read active tab.
- Focus tab.
- Close tab.
- Move tab.
- Create window.
- Detect pinned.
- Detect audible.
- Detect private/incognito.

UI and AI actions must only offer operations supported by capability flags.

### 9.4 Edge cases

- Browser can list tabs but cannot focus a specific tab: row can activate window, then show manual instruction or fallback.
- Browser can focus but cannot close/move: Review/Suggest marks actions manual-only.
- URL available for Chrome but not Safari: UI should not show domain-based features for unsupported sources.
- Provider returns stale tab: activation validates before focus.

---

## 10. Activation behavior

### 10.1 Row click

Trigger:

- User clicks TargetRow.
- User presses Enter on focused row.

Behavior:

1. Freeze selected row visually.
2. Validate target still exists.
3. Activate app.
4. Raise window.
5. Focus tab if capability exists.
6. Close panel after success.
7. If failure, keep panel open and show toast.

### 10.2 Window header click

Behavior:

- Activate the window.
- If browser active tab is known, focus active tab.
- If active tab unknown, just raise the window.

### 10.3 Edge cases

- App quit after indexing: show stale toast and remove section.
- Window moved to another Space: activation may switch Space.
- Minimized window: unminimize if possible.
- Hidden app: unhide app.
- Fullscreen window: switch to fullscreen Space.
- Browser tab closed: reacquire by URL/title; if fail, show unavailable toast.
- Activation takes longer than 500 ms: show row progress.
- User double-clicks: debounce activation; ignore second click.

---

## 11. Resource and performance plan

### 11.1 Hard product constraints

Window Hub must remain lightweight:

- No screenshots.
- No thumbnails.
- No Screen Recording permission.
- No Dock hover observer.
- No background browser tab daemon.
- No continuous all-app polling.
- No disk cache for tab/window data.

### 11.2 Time budgets

Recommended targets:

- Hotkey to panel shell: under 80 ms.
- Shell to app/window skeleton: under 200 ms.
- Current app enriched: under 400 ms.
- Most visible apps enriched: under 800 ms.
- Full initial snapshot: best effort under 1.5 s.
- Hard partial deadline: 2.0 s.
- Search keystroke response: under 16 ms for already-indexed data.
- Search-triggered indexing: progressive, never block typing.

### 11.3 CPU budget

- Indexing should run on background tasks.
- UI updates coalesced every 80 to 120 ms.
- Concurrency cap: 3 to 4 app providers at once.
- Per-PID soft timeout: 300 to 500 ms.
- Per-heavy-window full tab timeout: 500 to 800 ms.
- Stop indexing immediately when panel closes unless main page still needs it.

### 11.4 Memory budget

- Snapshot should be text-only and compact.
- Avoid retaining large AX trees.
- Keep stable IDs and minimal metadata, not full UI object graphs.
- Release snapshot on close.
- Keep recent target ring buffer small.
- Do not store full URL list on disk.

Suggested memory goals:

- Panel closed Window Hub incremental memory: near zero, ideally under 2 MB above baseline.
- Panel open normal workspace: under 5 MB incremental.
- Huge workspace: cap indexed/rendered targets and keep under 10 MB incremental if possible.

### 11.5 Rendering budget

- Use lazy rows.
- Do not render hidden collapsed tabs.
- Do not render more than about 120 visible rows without virtualization.
- App sections can be virtualized if workspace is huge.
- Avoid expensive per-row shadows, blur, gradients, or image decoding.

### 11.6 App icon and favicon policy

App icons:

- Use system app icons.
- Cache only via normal system APIs or tiny in-memory cache.

Favicons:

- Do not fetch favicons from the internet.
- Use browser-provided icon only if cheap and local.
- Otherwise use host letter/glyph.

### 11.7 URL privacy and indexing

Default:

- Use host for display.
- Use normalized URL only for duplicate detection if provider returns it.
- Do not show full URL in compact dashboard.
- Do not send full URL to AI unless user opts in.
- Strip query and fragment by default for AI.

---

## 12. Edge case matrix

### 12.1 Permission and system access

| Case | Display | Behavior |
|---|---|---|
| Accessibility missing | PermissionCard | No enumeration. Open System Settings action. |
| Accessibility revoked mid-session | PermissionCard replaces dashboard | Cancel tasks and release snapshot. |
| Screen Recording missing | Nothing | Should not be required. Do not prompt. |
| Secure Input active | Small status | Panel still opens if possible; search may be limited. |
| Hotkey recording active | Panel suppressed | Resume after recording ends. |

### 12.2 App enumeration

| Case | Display | Behavior |
|---|---|---|
| Helper app | Hidden | Exclude by activation policy. |
| MAYN own window | Hidden | Avoid switching to self. |
| App has no windows | Hidden by default | Show only if setting enabled. |
| App unresponsive | PartialFailureRow | Timeout and continue. |
| App quits while indexing | Remove section | Coalesced update. |
| App launches while panel open | Optional new section | Add only if observer/refresh detects it. |

### 12.3 Window handling

| Case | Display | Behavior |
|---|---|---|
| One window app | Flatten or one group | Keep simple. |
| Multiple windows | WindowGroup headers | Current window clearly marked. |
| Duplicate window titles | Add count/context | Avoid ambiguity. |
| Minimized window | Dim + status if needed | Activation unminimizes. |
| Hidden app window | Dim + hidden status | Activation unhides app. |
| Other Space window | Show unless Current Space only | Activation switches Space. |
| Fullscreen window | Optional fullscreen status | Activation switches Space. |
| Window closes | Remove or stale toast | Refresh app section. |

### 12.4 Browser tabs

| Case | Display | Behavior |
|---|---|---|
| 1 to 30 tabs | Show all | Direct rows. |
| 31 to 100 tabs | Summary + Show all | Active/recent/domains. |
| 100+ tabs | Aggressive summary | Search and per-window expansion. |
| Two browser windows | Separate WindowGroups | Never mix tabs without context. |
| Active tab known | Dot row | Surface even when domain collapsed. |
| Active tab unknown | No dot | Window header still actionable. |
| Pinned tab | Small pin if known | Protected in cleanup. |
| Audible tab | Small sound glyph if known | Protected in cleanup. |
| Private/incognito | Private status if known | Excluded from AI/cleanup by default. |
| URL unavailable | No domain | Title-only search. |
| Title empty | `(Untitled)` | Use host if available. |
| about:blank | `(Untitled)` or `about:blank` | Low priority. |

### 12.5 Search

| Case | Display | Behavior |
|---|---|---|
| Query empty | Compact dashboard | Restore default sections. |
| Query while indexing | Matches + indexing row | Schedule relevant full indexing. |
| Query no result incomplete | `No matches yet` | Continue indexing. |
| Query no result complete | `No match` | No false loading state. |
| Query app name | App section / app result | Do not dump all tabs immediately. |
| Query domain | Matching web tabs/groups | Requires host data. |
| Query exact title | Target row top | Breadcrumb if ambiguous. |
| Very long query | Debounced | Cap fuzzy cost. |

### 12.6 Cleanup

| Case | Display | Behavior |
|---|---|---|
| Exact duplicate URL | High-confidence row | Default off or safe default depending policy. |
| Same title different URL | Low confidence | Not selected by default. |
| Active duplicate | Protected | Never selected by default. |
| Pinned duplicate | Protected | Never selected by default. |
| Audible duplicate | Protected | Never selected by default. |
| Private duplicate | Excluded | User opt-in required. |
| Unsupported close | Manual-only | No execute button. |
| Batch close failure | Failure summary | Keep failed rows visible. |

### 12.7 AI Suggest

| Case | Display | Behavior |
|---|---|---|
| Provider configured | Suggest sheet | Redacted input. |
| Provider missing | Setup card | Link to Voice settings. |
| AI timeout | Toast + fallback | Local duplicate review. |
| AI invalid IDs | Warning | Drop invalid items. |
| AI suggests risky close | Protected | Do not select. |
| AI suggests unsupported move | Manual-only | No automatic execution. |
| Snapshot stale | Stale banner | Require regenerate. |

### 12.8 Layout

| Case | Display | Behavior |
|---|---|---|
| Narrow width | One column | Keep compact rows. |
| Normal width | Two-column masonry | Max two columns. |
| App section too tall | Internal cap + Show more | Do not break masonry. |
| Search hides sections | Repack columns | No vertical holes. |
| Reduce Motion | No animations | Instant transitions. |
| Large text/accessibility | Taller rows | Preserve click targets. |

---

## 13. Implementation architecture notes

### 13.1 Coordinator

`WindowHubCoordinator` owns:

- Panel state.
- Snapshot lifecycle.
- Indexing tasks.
- Cancellation.
- Shared state between panel and main page.

It should expose:

- `openPanel()`
- `closePanel()`
- `startSnapshot(reason:)`
- `cancelSnapshot(reason:)`
- `refreshApp(bundleID:)`
- `expandWindow(windowID:)`
- `search(query:)`
- `activate(targetID:)`

### 13.2 Snapshot model

Suggested shape:

```swift
struct WindowHubSnapshot {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var apps: [WindowHubAppNode]
    var indexState: WindowHubIndexState
    var partialFailures: [WindowHubFailure]
}
```

Important:

- Snapshot should be immutable when passed to UI.
- Updates should create new snapshots or patch sections in a controlled way.
- AI suggestions must reference snapshot ID and target IDs.

### 13.3 App node

```swift
struct WindowHubAppNode {
    let id: AppID
    let bundleID: String
    let processID: pid_t
    let displayName: String
    let iconID: IconID
    let isCurrent: Bool
    let windows: [WindowHubWindowNode]
    let capabilities: WindowHubProviderCapabilities
    let indexState: NodeIndexState
}
```

### 13.4 Window node

```swift
struct WindowHubWindowNode {
    let id: WindowID
    let title: String
    let isCurrent: Bool
    let isMinimized: Bool
    let isHidden: Bool
    let isFullscreen: Bool?
    let spaceHint: String?
    let displayHint: String?
    let childSummary: ChildSummary
    let children: [WindowHubTargetNode]
    let groups: [WindowHubDomainGroup]
    let indexState: NodeIndexState
}
```

### 13.5 Target node

```swift
struct WindowHubTargetNode {
    let id: TargetID
    let kind: TargetKind
    let title: String
    let host: String?
    let normalizedURLHash: String?
    let isActive: Bool?
    let isPinned: Bool?
    let isAudible: Bool?
    let isPrivate: Bool?
    let metadataQuality: MetadataQuality
    let activation: ActivationDescriptor
}
```

### 13.6 Provider registry

Provider order:

1. Generic app/window provider.
2. Browser-specific tab providers where reliable.
3. Finder provider.
4. Terminal/iTerm provider if feasible.
5. Editor provider for Cursor/VS Code if feasible.
6. Window-only fallback.

Every provider must declare capabilities before UI offers actions.

---

## 14. Recommended implementation sequence

### Phase A — Dashboard foundation

- Panel shell.
- Search field.
- Masonry layout.
- AppSection / WindowGroup / TargetRow components.
- Static sample data including Chrome 2 windows x 100 tabs.

Acceptance:

- Structure matches compact dashboard.
- No app switching filters required.
- Every visible row is final target.

### Phase B — Open-time app/window indexing

- Running apps.
- Window titles.
- Current window detection.
- Window activation.
- Permission card.
- Partial failure row.

Acceptance:

- Hotkey opens under target budget.
- Current window is clear.
- No background indexing when closed.

### Phase C — Browser summary indexing

- Active tab.
- Recent tabs if possible.
- Domain groups if host available.
- Heavy window summary.
- Show all per window.

Acceptance:

- Chrome 2 windows x 100 tabs is readable.
- Search can progressively find tabs.
- Dashboard does not render 200 rows by default.

### Phase D — Search and activation hardening

- Fuzzy ranking.
- Search-triggered indexing.
- Stale target reacquire.
- Keyboard navigation.

Acceptance:

- Type to jump feels instant.
- Enter activates correct target.
- Stale rows fail gracefully.

### Phase E — Review cleanup

- Local duplicate detection.
- Review sheet.
- Protected states.
- Manual-only states.

Acceptance:

- No destructive action without review.
- Active/pinned/audible/private protections work.

### Phase F — Suggest groups

- AI redaction.
- AI suggestion parser.
- Snapshot stale handling.
- Capability-based executor.

Acceptance:

- AI never directly modifies tabs without user confirmation.
- Unsupported actions are manual-only.

---

## 15. Final behavioral rules

1. Default view is all-app dashboard, not app filter mode.
2. App sections are visual grouping, not required navigation.
3. Every target row is one-click activation.
4. Browser windows must be grouped by window identity.
5. Current window must be explicitly marked.
6. Heavy browser windows are summarized by active/recent/domain groups.
7. Full tab lists are loaded on demand or when search/review/suggest requires them.
8. Search is always available and should feel instant.
9. Domain appears only for web tabs.
10. Per-row `Tab`, `Win`, `File` tags are removed.
11. No screenshots or thumbnails.
12. No Screen Recording permission.
13. No continuous background tab index.
14. Snapshot exists only while Window Hub is visible, except tiny recent metadata.
15. AI and cleanup are review-first and capability-aware.

---

## 16. Open decisions

These need product/engineering confirmation before implementation:

1. Exact threshold for heavy browser windows: 30 tabs vs 50 tabs.
2. Whether app sections should cap at fixed pixel height or fixed row count.
3. Whether recent target ring buffer is allowed while panel is closed.
4. Whether search should preserve masonry grouping or switch to flat results for dense queries.
5. Whether non-current Spaces are shown by default.
6. Whether private/incognito windows are visible in dashboard by default.
7. Whether full URL display is ever available outside review/details.
8. Which browsers get browser-specific providers in v1.
9. Whether existing Downloader Chrome extension remains completely untouched in v1.
10. Whether main Window Hub page can keep a longer-lived snapshot while open.

