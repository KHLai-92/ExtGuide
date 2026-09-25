# 11 — Recover custom installations and request write elevation

**What to build:** ExtGuide continues to recognize remembered custom installations even when the current process cannot write them, records installation identity beside the extension, offers a scoped UAC-assisted write path, and recovers an interrupted staged replacement on the next run.

**Blocked by:** 03, 04

**Status:** ready-for-agent

- [x] Remembered custom destinations are not discarded merely because the current token cannot write them.
- [x] Each successful installation contains an ExtGuide receipt that prevents an unrelated destination from being overwritten.
- [x] A protected destination offers administrator-assisted installation before asking the user to choose another folder.
- [x] Only the archive writer is elevated; downloading, Chrome discovery, and guidance stay in the normal process.
- [x] The elevated worker revalidates the archive digest and extension before replacing files.
- [x] An update journal repairs or completes an interrupted directory swap on the next run.
- [x] Update guidance tells the user to reload the existing unpacked extension instead of loading a duplicate.

## Comments

- Automated coverage includes protected remembered destinations, elevated-writer routing, UAC-declined fallback, receipt identity conflicts, metadata/version mismatches, interrupted-swap recovery, and localized update guidance.
- The generated standalone release parses and its embedded resources and sample artifact pass verification. A real UAC approval/cancellation smoke test still requires an interactive protected destination and is intentionally not claimed by automation.
