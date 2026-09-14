# 07 — Guide the consent-bearing Chrome setup

**What to build:** After installation, ExtGuide opens Chrome's extension-management page, prepares the stable extension-root path, and turns the installer window into a topmost step-by-step guide. The user retains control of Developer mode, Load unpacked, and folder confirmation while receiving clear recovery actions.

**Blocked by:** 02 — Securely install to the recommended destination; 06 — Recover from unusual or ambiguous Chrome installations.

**Status:** ready-for-agent

- [x] The resolved Chrome executable is launched directly with the extension-management URL.
- [x] The exact stable extension root is copied to the clipboard before manual load instructions appear.
- [x] The same compact window transitions from location and progress state into a topmost numbered guidance state.
- [x] Instructions cover enabling Developer mode, selecting Load unpacked, focusing the folder location field, pasting the prepared path, and confirming.
- [x] Copy path, Reopen extensions page, and Open folder actions work after accidental clipboard or window changes.
- [x] Keyboard navigation, focus order, readable labels, scaling, and screen-reader names are usable throughout the workflow.
- [x] ExtGuide never injects into Chrome internal pages or automates consent-bearing Chrome controls.
