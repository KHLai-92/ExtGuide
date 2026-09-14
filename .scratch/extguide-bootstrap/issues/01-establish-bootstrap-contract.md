# 01 — Establish the executable bootstrap contract

**What to build:** A manifest-URL invocation that exercises a complete sample installation through a replaceable Windows-host adapter. The workflow must expose installed content, selected destination, clipboard, Chrome-launch, and guide-window outcomes so complete behavior can be tested without changing the developer machine.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [x] One high-level bootstrap invocation accepts an installer-manifest URL as its only required consumer input.
- [x] A supported sample manifest drives a complete deterministic workflow through a fake Windows host.
- [x] Tests assert externally observable workflow results rather than internal helper calls.
- [x] Network, filesystem, registry, process, signature, clipboard, launch, and window effects are replaceable behind an internal test seam.
- [x] The public bootstrap interface does not expose the internal host adapter or module structure.
