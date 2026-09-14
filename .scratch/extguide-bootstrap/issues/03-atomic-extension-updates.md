# 03 — Update an installed extension atomically

**What to build:** A later invocation can update an installed extension while preserving the Chrome-facing root. New content is staged and validated before replacement so a verification failure or interrupted update leaves either the complete old version or the complete new version available.

**Blocked by:** 02 — Securely install to the recommended destination.

**Status:** ready-for-agent

- [x] Successful updates preserve the exact extension-root identity already loaded into Chrome.
- [x] New content is fully downloaded, verified, extracted, and validated before it becomes current.
- [x] Integrity, extraction, and extension-validation failures preserve the previous working installation.
- [x] An interrupted replacement never leaves a mixed or partially extracted current version.
- [x] Unsafe replacement while Chrome is actively using files produces a recoverable user-facing outcome instead of forcing the update.
