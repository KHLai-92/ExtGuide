# 02 — Securely install to the recommended destination

**What to build:** A user can launch ExtGuide without administrator privileges, review the recommended per-user destination, and install a prebuilt extension from a supported manifest. ExtGuide validates configuration, verifies the archive digest, rejects unsafe archive content, and exposes only a complete extension at the stable destination.

**Blocked by:** 01 — Establish the executable bootstrap contract.

**Status:** ready-for-agent

- [x] Supported manifest versions and required display, publisher, folder, archive, digest, and extension-root values are validated before installation.
- [x] Unsafe names, absolute or escaping roots, unsupported URLs, and forward-incompatible manifests are rejected with no installed-content change.
- [x] HTTPS release downloads support redirects, network interruption, unavailable assets, and retry-safe behavior.
- [x] SHA-256 mismatches or malformed digest data stop before any existing installed content is replaced.
- [x] Extraction rejects traversal, corrupt archives, duplicate or conflicting entries, and content outside the selected root.
- [x] The configured extension root must contain a valid extension manifest before ExtGuide treats installation as successful.
- [x] The default destination is a durable publisher-and-extension location under per-user Local Application Data.
