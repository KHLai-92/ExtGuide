# Release verification

Run the automated and visual preview checks in Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-ReleaseCandidate.ps1 -PreviewOnly
```

For a real clean-profile smoke test, publish the sample release assets, then pass its HTTPS manifest URL without `-PreviewOnly`. Record the native folder chooser, clipboard, initial guide foreground presentation followed by normal window z-order, Chrome discovery, and final **Load unpacked** result in the generated evidence JSON.

The release matrix requires separate observations on Windows 10 and Windows 11. On a managed test device, record the message shown when script execution or Chrome extension policy is blocked. Do not change or bypass policy for the test.

The smoke test must use a standard user account. The evidence records whether the process was elevated and lists any remaining manual observations instead of silently claiming them.

## Private GitHub update verification

Build the standalone release, authenticate GitHub CLI with an account that can read the test repository, and run:

```powershell
powershell.exe -NoProfile -File .\tools\Test-PrivateGitHubUpdate.ps1 -GitHubRepository 'YOUR-ORG/YOUR-PRIVATE-EXTENSION' -PreviousManifestUri 'https://github.com/YOUR-ORG/YOUR-PUBLIC-EXTENSION/releases/download/v1.0.0/installer-manifest.json'
```

The test loads the exact built standalone script. It installs the previous archive in an isolated custom folder, checks that a fresh unauthenticated GitHub configuration cannot update or change the old files, restores the current process's GitHub configuration, then downloads and installs the latest private release using the real authentication and archive writer. Settings, receipts, checksums, remembered custom location, and update-specific Reload guidance are verified. Folder selection, clipboard, Chrome launch, and UI presentation are isolated test boundaries, so this does not modify the user's existing extension or clipboard.

To verify the published artifact, download it and pass `-ReleaseScript` with that file's path. The evidence records the script SHA-256 and PowerShell version. A successful authorized-account test is not evidence for a different account; private access remains enforced by GitHub. Simulated permission-denied responses, cancelled login, absent credentials, and cross-host/cross-repository URLs are covered by `tests\GitHubDownloads.Tests.ps1`.
