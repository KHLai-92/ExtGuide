# Release verification

Run the automated and visual preview checks in Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-ReleaseCandidate.ps1 -PreviewOnly
```

For a real clean-profile smoke test, publish the sample release assets, then pass its HTTPS manifest URL without `-PreviewOnly`. Record the native folder chooser, clipboard, initial guide foreground presentation followed by normal window z-order, Chrome discovery, and final **Load unpacked** result in the generated evidence JSON.

The release matrix requires separate observations on Windows 10 and Windows 11. On a managed test device, record the message shown when script execution or Chrome extension policy is blocked. Do not change or bypass policy for the test.

The smoke test must use a standard user account. The evidence records whether the process was elevated and lists any remaining manual observations instead of silently claiming them.

## Private GitHub update verification

ExtGuide 1.3 release selection is covered by `tests/ReleaseSelection.Tests.ps1`, including authenticated downloads, older releases, selectable pre-releases, pagination beyond 100 releases, cancellation, explicit tags, release pinning, and localized accessible dropdowns. `ExtGuide.Workflow.Tests.ps1` also checks a real archive downgrade at the same root with an updated receipt and Reload guidance. The private update verifier selects the default stable tag at the UI boundary so it remains unattended.

For release selection QA, run `bootstrap.ps1 -GitHubRepository OWNER/REPOSITORY`, open the dropdown, select an older stable version and an eligible beta, and verify the resulting ZIP version and receipt at an isolated destination. A beta needs its own uploaded `installer-manifest.json`; see [the schema](manifest-schema.md) for an example. GitHub's [release API](https://docs.github.com/en/rest/releases/releases) supplies paginated published release metadata; ExtGuide applies its manifest eligibility rules and marks prereleases in the UI.

Build the standalone release, authenticate GitHub CLI with an account that can read the test repository, and run:

```powershell
powershell.exe -NoProfile -File .\tools\Test-PrivateGitHubUpdate.ps1 -GitHubRepository 'YOUR-ORG/YOUR-PRIVATE-EXTENSION' -PreviousManifestUri 'https://github.com/YOUR-ORG/YOUR-PUBLIC-EXTENSION/releases/download/v1.0.0/installer-manifest.json'
```

The test loads the exact built standalone script. It installs the previous archive in an isolated custom folder, checks that a fresh unauthenticated GitHub configuration cannot update or change the old files, restores the current process's GitHub configuration, then downloads and installs the latest private release using the real authentication and archive writer. Settings, receipts, checksums, remembered custom location, and update-specific Reload guidance are verified. Folder selection, clipboard, Chrome launch, and UI presentation are isolated test boundaries, so this does not modify the user's existing extension or clipboard.

To verify the published artifact, download it and pass `-ReleaseScript` with that file's path. The evidence records the script SHA-256 and PowerShell version. A successful authorized-account test is not evidence for a different account; private access remains enforced by GitHub. Simulated permission-denied responses, cancelled login, absent credentials, and cross-host/cross-repository URLs are covered by `tests\GitHubDownloads.Tests.ps1`.
