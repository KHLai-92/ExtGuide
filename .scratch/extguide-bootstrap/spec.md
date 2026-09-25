# ExtGuide: Reusable Guided Installer for Unpacked Chrome Extensions

Status: ready-for-agent

## Problem Statement

Developers who distribute open-source Chrome extensions directly from GitHub cannot give ordinary users a supported, zero-interaction installation command for official Google Chrome. Chrome requires the user to enable Developer mode and explicitly choose an unpacked extension directory, while recent official Chrome builds no longer accept command-line loading of unpacked extensions. The standard manual flow also asks non-technical users to understand GitHub Releases, choose the correct archive, extract it to a durable location, find Chrome's extension-management page, and select the correct nested directory. These steps are easy to misunderstand and produce fragile installations.

Each extension author could write a bespoke installer, but that would duplicate download, verification, path selection, Chrome discovery, and onboarding logic across repositories. It would also lead to inconsistent security and user experience. Extension authors need a reusable Windows bootstrap that hides this complexity behind a small integration interface, while preserving the user actions Chrome intentionally requires.

## Solution

Build ExtGuide as an independent, reusable Windows bootstrap for trusted, unpacked Chrome extensions published through GitHub Releases. An extension repository integrates with ExtGuide by publishing a small, versioned installer manifest and a prebuilt extension archive. Its README presents one PowerShell command. The user does not need to locate or understand GitHub's download interface.

When invoked, ExtGuide downloads and validates the installer manifest, presents a compact installer window with a safe per-user default destination and an optional native folder chooser, downloads and verifies the extension archive, extracts it to a stable extension root, finds the user's actual Chrome installation through Windows registration data and layered fallbacks, copies the extension root to the clipboard, opens Chrome's extension-management page, and converts the same window into a topmost step-by-step guide.

The guide tells the user to enable Developer mode, select Load unpacked, focus the folder dialog's location field, paste the prepared path, and confirm. It also provides buttons to copy the path again, reopen the extension-management page, and open the installed directory. ExtGuide does not inject content into Chrome's protected internal pages and does not automate the consent-bearing Chrome clicks.

## User Stories

1. As a non-technical Windows user, I want one command that starts installation, so that I do not have to understand GitHub Releases.
2. As a non-technical Windows user, I want the command to download the correct release asset automatically, so that I do not accidentally choose source code or the wrong archive.
3. As a non-technical Windows user, I want a graphical window to appear after running the command, so that I am not required to continue working in the terminal.
4. As a non-technical Windows user, I want a safe installation directory to be selected by default, so that I can proceed without understanding Windows filesystem conventions.
5. As a user who organizes software manually, I want to change the installation location through a native folder chooser, so that I can keep the extension where I prefer.
6. As a user choosing a custom location, I want ExtGuide to create an extension-specific child directory automatically, so that extracted files do not pollute the directory I selected.
7. As a user choosing a custom location, I want to see the final resolved destination before installation, so that I know exactly where the extension will live.
8. As a user, I want the installer to detect whether the selected destination is writable, so that permission problems are explained before a download or extraction fails.
9. As a user, I want the recommended installation to work without administrator privileges, while retaining the option to approve a scoped UAC prompt when I explicitly choose a protected location.
10. As a user, I want ExtGuide to remember my chosen destination, so that later installs or updates continue using the same location.
11. As a user, I want the extension root to remain stable across versions, so that Chrome does not lose the unpacked extension when it is updated.
12. As a security-conscious user, I want the downloaded archive verified against its declared SHA-256 digest, so that corrupted or substituted content is rejected.
13. As a security-conscious user, I want ExtGuide to reject malformed or unsupported installer manifests, so that remote configuration cannot cause unexpected behavior.
14. As a security-conscious user, I want ExtGuide to prevent archive entries from escaping the selected installation directory, so that extraction cannot overwrite unrelated files.
15. As a user, I want failed verification to stop before installed files are replaced, so that an existing working extension is preserved.
16. As a user, I want an interrupted update to leave either the old version or the complete new version available, so that partial extraction does not break the installation.
17. As a user with Chrome already running, I want ExtGuide to prefer the Chrome instance I am actually using, so that the extension-management page opens in the expected browser.
18. As a user who installed Chrome in a custom location, I want ExtGuide to use Windows application registration rather than assuming a fixed directory, so that custom installs are discovered reliably.
19. As a user with a per-user Chrome installation, I want that installation detected, so that a machine-wide installation is not incorrectly preferred.
20. As a user with a machine-wide Chrome installation, I want that installation detected without elevated privileges, so that setup remains per-user.
21. As a user on a 64-bit Windows machine, I want both 32-bit and 64-bit registry views considered, so that Chrome is found regardless of installer architecture.
22. As a user whose Chrome registration is incomplete, I want ExtGuide to try additional registered-browser, updater, uninstall, and conventional-location signals, so that recovery is automatic where possible.
23. As a user whose portable or unusual Chrome installation is not registered, I want to select the Chrome executable once through a native file chooser, so that setup can still continue.
24. As a user who manually selects Chrome, I want ExtGuide to remember and revalidate that choice later, so that I do not have to select it repeatedly.
25. As a security-conscious user, I want detected Chrome candidates validated as authentic Google Chrome executables, so that a misleading registry value or unrelated executable is not launched.
26. As a user with multiple detected Chrome candidates, I want a clear choice rather than an arbitrary launch, so that I remain in control of the target browser.
27. As a user, I want Chrome's extension-management page opened automatically after extraction, so that I do not need to type an internal URL.
28. As a user, I want the exact unpacked extension directory copied to the clipboard, so that I do not need to browse through nested folders.
29. As a user, I want the installer window to remain visible above Chrome, so that I can follow the instructions while interacting with Chrome.
30. As a user, I want the guide to present one short step at a time, so that the unfamiliar Developer mode process is approachable.
31. As a user, I want the guide to explain how to focus the folder dialog and paste the prepared path, so that selecting the unpacked directory is quick and reliable.
32. As a user, I want a button that copies the extension path again, so that overwriting my clipboard does not force me to restart.
33. As a user, I want a button that reopens the extension-management page, so that accidentally closing the tab is recoverable.
34. As a user, I want a button that opens the installed directory, so that I can inspect the files or select the folder manually if necessary.
35. As a user, I want actionable error messages for download, validation, extraction, Chrome discovery, and launch failures, so that I know how to recover.
36. As a user on a managed corporate device, I want ExtGuide to explain when policy blocks script execution or Developer mode, so that policy restrictions are not mistaken for an installer defect.
37. As an extension author, I want to integrate by publishing configuration rather than copying installer code, so that fixes to installation behavior remain centralized in ExtGuide.
38. As an extension author, I want a versioned installer-manifest schema, so that integrations can be validated and evolved compatibly.
39. As an extension author, I want the manifest to describe display metadata, the release artifact, its digest, the install-directory name, and the archive's extension root, so that ExtGuide has everything it needs without repository-specific logic.
40. As an extension author, I want the release artifact to contain a prebuilt extension, so that users do not need Git, Node.js, npm, or a build toolchain.
41. As an extension author, I want stable direct asset URLs to work without the GitHub API, so that installation avoids API credentials and rate-limit dependencies.
42. As an extension author, I want the README command to pin an ExtGuide release, so that future ExtGuide changes do not silently alter an existing installation flow.
43. As an extension author, I want to point the pinned bootstrap at my latest versioned installer manifest, so that extension releases can update independently of ExtGuide.
44. As an extension author, I want manifest-controlled names sanitized and confined beneath user-approved locations, so that configuration cannot select arbitrary default filesystem targets.
45. As an extension author, I want an optional post-install onboarding convention, so that my extension can open its own welcome page once Chrome has loaded it.
46. As an ExtGuide maintainer, I want one high-level bootstrap interface, so that consumers do not need to learn the internal download, Windows, Chrome, or UI modules.
47. As an ExtGuide maintainer, I want environmental operations replaceable inside tests, so that complete workflows can be exercised deterministically without opening real Chrome or changing the developer machine.
48. As an ExtGuide maintainer, I want the public bootstrap source to remain inspectable and versioned, so that extension authors and users can audit what the copied command executes.

## Implementation Decisions

- ExtGuide is an independent project shared by multiple extension repositories. Extension repositories reference a released ExtGuide bootstrap and do not copy its implementation.
- The consumer-facing interface consists of one bootstrap invocation with one required installer-manifest URL. Downloading, verification, destination management, Chrome discovery, launching, and guidance remain behind that interface.
- The initial supported platform is desktop Windows 10 and Windows 11 with Google Chrome installed.
- The bootstrap targets built-in Windows PowerShell 5.1 and desktop .NET capabilities. It must not require PowerShell 7, Git, curl, tar, Node.js, npm, Python, 7-Zip, or another separately installed runtime.
- The bootstrap runs per user and does not require administrator privileges at the recommended destination or modify Chrome enterprise policies. If the user explicitly selects a protected destination, only the validated archive writer may request UAC elevation; declining returns the user to location selection.
- Each extension integration publishes a versioned installer manifest. The schema includes a schema version, display name, publisher, safe install-folder name, direct archive URL, direct SHA-256 URL or digest, and the relative extension root inside the archive.
- Remote configuration may select names beneath the bootstrap-managed per-user root but may not declare an arbitrary absolute default destination. Arbitrary locations are accepted only after explicit selection in the native folder chooser.
- The default destination is a durable per-user Local Application Data location organized by publisher and extension. Downloads, desktop folders, temporary folders, and version-numbered Chrome roots are not defaults.
- When a user chooses a custom base directory, ExtGuide creates an extension-specific child directory and displays the resulting path before continuing.
- The actual directory loaded into Chrome has a stable identity across releases. Updates stage and validate new content before replacing the stable installation, and do not expose partially extracted content as the current installation.
- Release archives contain the already-built Manifest V3 extension. ExtGuide does not build source code on the user's machine.
- Downloads use HTTPS. The archive must pass SHA-256 verification before installation, and extraction must reject path traversal and content outside the selected root.
- The configured relative extension root must resolve to a directory containing a valid extension manifest before ExtGuide treats installation as successful.
- The graphical experience uses a compact WPF or Windows Forms window that begins as an installation-location and progress view, then transitions into the topmost Chrome guidance view. It is not a browser content script.
- The location view provides the recommended destination, a Change location action, the final resolved path, and a primary installation action. Cancelling a custom folder chooser returns to the prior selection without losing state.
- The guidance view provides numbered instructions, the resolved extension-root path, Copy path, Reopen extensions page, and Open folder actions.
- The documented manual sequence is to enable Developer mode, select Load unpacked, focus the native folder dialog's location field, paste the path already placed on the clipboard, and confirm.
- ExtGuide does not inject, overlay, or modify Chrome internal pages. A pixel-positioned full-screen overlay is rejected because it is fragile across Chrome versions, languages, window sizes, display scaling, and multi-monitor layouts.
- ExtGuide does not click Developer mode, Load unpacked, or confirm the folder on the user's behalf. These remain explicit consent-bearing user actions.
- Chrome discovery uses a layered resolver rather than three hard-coded paths. The resolver considers a currently running Chrome process, per-user and machine App Paths in both registry views, Chrome updater state, Windows browser and application registrations, uninstall metadata, and conventional locations.
- Every discovered candidate is normalized, checked for existence, and validated using executable metadata and Authenticode identity. Invalid candidates are ignored and reported diagnostically.
- A running, validated stable Chrome is preferred when it gives the best match to the browser the user is actively using. If multiple credible candidates remain and selection affects behavior, the user is shown a concise chooser.
- If automatic discovery fails, ExtGuide opens a native executable chooser, validates the selection, and remembers it for later runs. A remembered selection is always revalidated before use.
- The bootstrap opens the protected Chrome extension-management URL by launching the resolved Chrome executable. It does not rely on Chrome being present in the process PATH or on Chrome being the Windows default browser.
- The bootstrap places the resolved extension root on the clipboard before displaying the load instructions and allows the user to copy it again.
- Extension projects may implement their own first-install welcome page using Chrome's installation event. This onboarding is optional and outside ExtGuide's protected-page guidance.
- README commands use a version-pinned ExtGuide release. An extension may separately use a latest-release direct URL for its own manifest and archive when that matches the author's release policy.
- Bootstrap failures are categorized at the user level: configuration, network, integrity, destination, extraction, Chrome discovery, executable validation, launch, or managed-device policy. Error messages include a recovery action without exposing sensitive environment data.
- Configuration and remembered selections are per-user. Logs must avoid tokens, private URLs, clipboard contents unrelated to ExtGuide, and unnecessary personal path disclosure.

## Testing Decisions

- The primary automated test seam is the highest-level bootstrap invocation with an installer-manifest URL. Tests assert externally observable results through this seam rather than testing helper functions or internal module structure.
- The bootstrap orchestration accepts an internal Windows-host adapter for network, filesystem, registry, process, signature, clipboard, browser-launch, and guide-window effects. Production uses the real Windows adapter; tests use an in-memory or temporary-directory fake. This is an internal seam and is not added to the consumer-facing interface.
- A good automated test describes user-visible behavior: final installed content, preserved prior content, selected destination, presented state, copied path, chosen Chrome candidate, attempted launch, or actionable failure. It must survive refactoring of the internal modules.
- End-to-end workflow tests cover the recommended destination and a user-selected custom destination through the same bootstrap seam.
- Manifest contract tests cover supported schema versions, missing required values, unsafe names, invalid relative roots, unsupported URLs, and forward-incompatible manifests.
- Download tests cover successful retrieval, redirect handling for direct release assets, network interruption, unavailable assets, and retry-safe behavior.
- Integrity tests cover valid SHA-256 values, mismatches, malformed digest data, and the rule that failed verification cannot replace an existing installation.
- Extraction tests cover valid archives, corrupt archives, nested extension roots, missing extension manifests, path traversal entries, duplicate/conflicting entries, and interrupted extraction.
- Update tests verify that the Chrome-facing extension root remains stable, old content remains available until validation succeeds, and failed updates do not leave a mixed version.
- Destination tests cover the per-user default, custom base selection, unwritable directories, cancelled selection, invalid remembered paths, and automatic creation of the extension-specific child directory.
- Chrome resolver tests cover each discovery source independently and in precedence combinations: running process, per-user App Paths, machine App Paths, 32-bit and 64-bit views, updater state, browser registration, uninstall registration, conventional fallback, remembered path, and manual selection.
- Chrome validation tests reject nonexistent paths, unrelated executables named like Chrome, mismatched product metadata, and invalid or unexpected signatures.
- Multi-candidate tests verify deterministic preference where safe and user choice where ambiguity remains.
- Launch tests assert that the resolved executable receives the extension-management URL without depending on PATH or the default browser.
- Guide-state tests cover transition from destination selection through progress to manual Chrome guidance, including Copy path, Reopen extensions page, Open folder, cancellation, and retry actions.
- Accessibility tests verify keyboard navigation, focus order, readable labels, usable scaling, and screen-reader names for the installer and guide window.
- One manual Windows smoke test exercises a packaged bootstrap against a sample extension in a clean user profile and verifies the real folder chooser, clipboard, topmost window, Chrome discovery, and final Load unpacked experience.
- Managed-device smoke coverage records the expected failure experience when PowerShell execution or Chrome Developer mode is blocked, without attempting to bypass policy.
- The repository is currently empty and has no prior test conventions. The first implementation should establish tests at the bootstrap seam rather than introducing tests around every internal helper.

## Out of Scope

- Publishing extensions to the Chrome Web Store or automating Chrome Web Store review.
- Silent installation into ordinary consumer Chrome without user confirmation.
- Enterprise policy, registry force-installation, or any mechanism that prevents users from removing the extension.
- Programmatically enabling Developer mode, clicking Load unpacked, controlling the folder chooser, or otherwise bypassing Chrome's user-consent flow.
- Injecting scripts, CSS, tours, or overlays into protected Chrome internal pages.
- A coordinate-based overlay that attempts to spotlight live Chrome controls.
- Installing Google Chrome when it is absent.
- Building an extension from source or installing extension-specific build dependencies on the user's machine.
- Supporting macOS, Linux, ChromeOS, Microsoft Edge, Brave, Chromium, or Chrome for Testing in the initial release.
- Supporting private GitHub repositories that require user credentials or personal access tokens.
- Acting as a general-purpose software installer for non-extension applications.
- Automatically selecting a Chrome profile or synchronizing an unpacked extension between profiles.
- Automatically updating an extension while Chrome is actively using files when a safe replacement cannot be guaranteed; such cases must be surfaced for user recovery rather than forced.

## Further Notes

- The project name is ExtGuide. Its positioning should emphasize guided setup rather than claim a silent or fully automatic Chrome installation.
- The intended user experience is one copied command followed by a small number of clearly guided Chrome clicks.
- The bootstrap source should be easy to inspect in its own repository. Release signing with an Authenticode certificate would improve trust and reduce warnings, but certificate procurement and reputation management can be treated as a separate release-engineering decision.
- A simple integration example and sample extension release should accompany the first implementation so extension authors can validate their manifest without studying ExtGuide internals.
- The local issue tracker marks this spec `ready-for-agent`; implementation tickets can be derived beneath the same feature directory when work begins.
