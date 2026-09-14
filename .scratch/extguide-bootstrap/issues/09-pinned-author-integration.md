# 09 — Provide a pinned extension-author integration

**What to build:** An extension author can publish configuration and a prebuilt Manifest V3 archive, then offer ordinary Windows users one inspectable PowerShell command. The command pins ExtGuide independently from the extension release and uses stable direct asset URLs without requiring GitHub API credentials or a local build toolchain.

**Blocked by:** 03 — Update an installed extension atomically; 07 — Guide the consent-bearing Chrome setup.

**Status:** ready-for-agent

- [x] A documented example manifest contains all required integration metadata and passes the same production validation as real integrations.
- [x] A sample prebuilt extension release demonstrates nested extension roots and optional first-install onboarding.
- [x] The README command pins a specific ExtGuide release and supplies one installer-manifest URL.
- [x] The extension manifest and archive may advance independently through direct release asset URLs without using the GitHub API.
- [x] The user needs only built-in Windows PowerShell 5.1 and desktop .NET capabilities—no Git, build tools, archive utilities, or separate runtime.
- [x] The fetched bootstrap source remains versioned and readily inspectable by extension authors and users.
