# 04 — Choose and remember a custom destination

**What to build:** The installation window shows the recommended destination and lets the user choose another base directory with a native folder chooser. ExtGuide displays and validates the final extension-specific destination, remembers successful choices per user, and safely falls back when a remembered location is no longer valid.

**Blocked by:** 02 — Securely install to the recommended destination.

**Status:** ready-for-agent

- [x] The location view displays the exact resolved destination before installation begins.
- [x] Choosing a custom base always creates a sanitized extension-specific child directory beneath it.
- [x] Cancelling the folder chooser preserves the previously selected destination and window state.
- [x] Unwritable destinations are detected before download or extraction and include a recovery action.
- [x] A successful custom selection is remembered per user and reused on later installs or updates.
- [x] Invalid or unavailable remembered paths are not used without giving the user a safe alternative.
