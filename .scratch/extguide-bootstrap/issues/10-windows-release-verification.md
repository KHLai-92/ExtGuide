# 10 — Verify release readiness on real Windows

**What to build:** A release candidate is exercised on supported Windows versions with a clean user profile and a real sample extension. The verification demonstrates the complete guided experience and records expected behavior on managed devices so maintainers can release with evidence rather than relying only on fake-host tests.

**Blocked by:** 08 — Make failures actionable and policy-aware; 09 — Provide a pinned extension-author integration.

**Status:** ready-for-agent

Automated workflow, release-build, preview rendering, local Chrome discovery, Authenticode, accessibility, and non-elevated evidence capture are implemented. The remaining acceptance criteria require manual observations on clean Windows 10, Windows 11, and managed-device profiles; they cannot be truthfully completed on this single host.

- [ ] A clean-profile smoke test covers the pinned command, manifest and archive download, recommended destination, and successful initial install.
- [ ] The real folder and executable choosers, clipboard, initial guide foreground presentation followed by stable normal z-order, Chrome discovery, launch, and Load unpacked experience are verified.
- [ ] A subsequent release verifies stable-root update behavior and preservation after a deliberately failed update.
- [ ] Windows 10 and Windows 11 coverage records keyboard, scaling, and screen-reader observations for the installer and guide.
- [ ] Managed-device coverage records the expected response to blocked PowerShell execution or Chrome Developer mode without attempting a bypass.
- [ ] Release evidence identifies any manual prerequisites and confirms that no administrator privileges or separately installed runtime were required.

## Comments

- 2026-09-14 current-host verification used the public `KHLai-92/youtube-auto-skip` v1.0.0 release. Real download, SHA-256 validation, initial installation, stable-root update, and preservation after a deliberately bad digest passed without administrator privileges.
- The first interactive run exposed two release blockers: Chrome 150 discarded externally supplied `chrome://extensions` command-line URLs and the guide remained permanently topmost.
- The release candidate now injects `chrome://extensions/` directly into the verified Chrome omnibox through Windows UI Automation, invokes Chrome's native suggestion without keyboard simulation, and removes any superseded blank tab. The guide is surfaced once and then returns to normal z-order.
- The user confirmed real Chrome navigation, Load unpacked, stable foreground/background switching, and that **Done** closes the guide as intended. Evidence is recorded in `artifacts/release-evidence.json`.
- A packaged Codex run exposed AppData write virtualization: the displayed logical destination was redirected into the Codex package `LocalCache`, so Explorer and Chrome could not use it. ExtGuide now detects the final Win32 path and delegates only redirected archive writes to a hidden, same-user WMI worker. The user confirmed that **Open folder** reaches the displayed logical `%LOCALAPPDATA%\<publisher>\<extension>` path; the prior redirected copy was preserved.
- The ticket remains open because clean-profile, full Windows 10/11 accessibility coverage, the real executable chooser, and managed-device behavior still require separate environments or observations.
