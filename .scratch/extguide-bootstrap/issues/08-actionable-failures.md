# 08 — Make failures actionable and policy-aware

**What to build:** Failures throughout the guided installation stop at a safe boundary and tell the user what happened and what to do next. Managed-device restrictions are distinguished from installer defects without attempting to bypass organizational policy or exposing sensitive environment data.

**Blocked by:** 03 — Update an installed extension atomically; 04 — Choose and remember a custom destination; 07 — Guide the consent-bearing Chrome setup.

**Status:** ready-for-agent

- [x] Configuration, network, integrity, destination, extraction, Chrome discovery, executable validation, launch, and policy failures have distinct user-level categories.
- [x] Every displayed failure includes an actionable retry, correction, selection, or administrator-contact recovery step.
- [x] Retrying cannot bypass validation or corrupt an existing working installation.
- [x] PowerShell execution restrictions and Chrome Developer mode policy are explained without offering a policy bypass.
- [x] Logs avoid tokens, private URLs, unrelated clipboard contents, and unnecessary disclosure of personal paths.
- [x] Complete workflow tests verify the visible failure state and preservation guarantees for each category.
