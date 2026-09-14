# 06 — Recover from unusual or ambiguous Chrome installations

**What to build:** Users with incomplete registration, custom installation locations, or multiple credible Chrome installations can still continue. ExtGuide searches secondary Windows registration signals, presents meaningful ambiguity for user choice, and supports a validated manual executable selection that is remembered and revalidated.

**Blocked by:** 05 — Resolve and authenticate common Chrome installations.

**Status:** ready-for-agent

- [x] Chrome updater state, browser and application registrations, uninstall metadata, and conventional locations participate as layered fallbacks.
- [x] Deterministic preference is applied where one candidate is clearly safest and most relevant.
- [x] When credible candidates remain meaningfully ambiguous, the user receives a concise chooser instead of an arbitrary launch.
- [x] Automatic-discovery failure opens a native executable chooser and validates the selected file before continuing.
- [x] A valid manual choice is remembered per user and revalidated on every later use.
- [x] Invalid remembered or manually chosen executables are rejected with diagnostics and a recovery action.
