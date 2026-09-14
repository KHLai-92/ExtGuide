# 05 — Resolve and authenticate common Chrome installations

**What to build:** ExtGuide finds the stable Google Chrome instance the user is likely to be using without relying on PATH or the default browser. It considers a running instance and registered per-user or machine installations across Windows registry views, then launches only a normalized, existing, authentic Google Chrome executable.

**Blocked by:** 01 — Establish the executable bootstrap contract.

**Status:** ready-for-agent

- [x] A validated running stable Chrome is preferred when it best represents the browser the user is actively using.
- [x] Per-user and machine App Paths are considered in both 32-bit and 64-bit registry views.
- [x] Candidate paths are normalized, deduplicated, and checked for existence.
- [x] Product metadata and Authenticode identity checks reject unrelated, renamed, or unexpectedly signed executables.
- [x] Resolver tests cover every primary discovery source independently and in precedence combinations.
- [x] Resolution remains per-user and requires no elevation.
