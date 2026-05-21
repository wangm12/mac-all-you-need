# Voice Models - Advanced Engine Picker Redesign

This pack replaces the jammed advanced model manager with a two-pane picker.

## Core fix

The old modal repeated the same state in two places: status pills on the left and actions/status on the right. The new layout removes per-row actions entirely.

- Left pane: engine names only, grouped by Local, Cloud, and Experimental.
- Right pane: the selected engine's state, details, and one primary action.
- Current engine: shown with one checkmark in the list and one read-only detail state.
- Not installed engine: action is `Download and use`.
- Cloud engine without a key: action is `Configure API key`.
- Unavailable engines: shown only in the advanced picker and disabled in the detail pane.

## Suggested product copy

Rename `Advanced model manager` to `Choose recognition engine`.
The word advanced can stay in the subtitle, not the title.

## Main page relationship

On the simplified Models page, keep only:

1. Recognition card with `Change...`.
2. LLM cleanup card.
3. Secondary link: `Choose exact engine...`.

`Choose exact engine...` opens this picker.
