# ExtGuide

ExtGuide is a reusable Windows bootstrap that installs a trusted, prebuilt unpacked Chrome extension and guides the user through Chrome's required **Developer mode** and **Load unpacked** clicks. It does not inject into Chrome internal pages or automate consent-bearing controls.

## Preview without an extension

Open the real guidance UI without downloading, installing, or launching anything:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Show-ExtGuidePreview.ps1
```

Generate a PNG instead:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Show-ExtGuidePreview.ps1 -ScreenshotPath .\artifacts\guidance-preview.png
```

ExtGuide automatically follows the Windows UI culture. Traditional Chinese and English are supported, bundled, and work offline. Traditional Chinese cultures (`zh-TW`, `zh-HK`, `zh-MO`, `zh-Hant`) use Traditional Chinese. Simplified Chinese is no longer supported: its existing resource file remains bundled only as an inactive archive, while Simplified Chinese cultures (`zh-CN`, `zh-SG`, `zh-Hans`) receive the complete Traditional Chinese UI and visual guide. All non-Chinese cultures use English. To force a Traditional Chinese preview, add `-Culture zh-TW`. See [localization](docs/localization.md) for the selection and fallback policy.

The final Chrome setup window also includes an offline, privacy-neutral visual reference for Developer mode and Load unpacked. Its labels match the maintained UI language; image source and fallback details are documented in the localization guide.

## Extension author integration

Publish a prebuilt Manifest V3 ZIP and a schema-v1 installer manifest. See [the schema](docs/manifest-schema.md) and the sample extension. Build the sample assets with `tools\New-SampleRelease.ps1`.

Give users one version-pinned command. Replace only the manifest URL with your published extension release asset:

```powershell
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$w=New-Object Net.WebClient;try{$s=$w.DownloadString('https://github.com/KHLai-92/ExtGuide/releases/download/v1.3.0/ExtGuide-v1.3.0.ps1')}finally{$w.Dispose()};&([scriptblock]::Create($s)) -ManifestUri 'https://github.com/YOUR-ORG/YOUR-EXTENSION/releases/latest/download/installer-manifest.json'
```

The ExtGuide URL is pinned to `v1.3.0`. A GitHub `releases/latest/download/installer-manifest.json` URL now opens a release dropdown before folder selection. Choose a stable release, an older version, or a labeled pre-release/beta. A tag-specific `-ManifestUri` or a non-GitHub manifest continues to install that manifest directly. `DownloadString` is intentional because GitHub serves PowerShell release assets as binary content. Public downloads require no credentials or GitHub CLI. Git, Node.js, npm, Python, and 7-Zip are not required. The recommended per-user destination needs no administrator rights; Windows may show a UAC prompt only when the user explicitly chooses a protected location.

To run from a source checkout, use `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1` with the same `-ManifestUri` or `-GitHubRepository` arguments.

## Private GitHub releases

On each Windows computer, install the official [GitHub CLI](https://cli.github.com/) once if it is not installed:

```powershell
winget install --id GitHub.cli --source winget
```

Reopen PowerShell, then use the same command for installation and future updates:

```powershell
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$w=New-Object Net.WebClient;try{$s=$w.DownloadString('https://github.com/KHLai-92/ExtGuide/releases/download/v1.3.0/ExtGuide-v1.3.0.ps1')}finally{$w.Dispose()};&([scriptblock]::Create($s)) -GitHubRepository 'YOUR-ORG/YOUR-PRIVATE-EXTENSION'
```

ExtGuide checks the active GitHub CLI account. If this computer is not authenticated, it starts `gh auth login --hostname github.com --git-protocol https --web`; complete the browser sign-in with your own account. Browser sign-in alone does not authenticate PowerShell. The account must have permission to read the private repository. If necessary, run `gh auth switch --hostname github.com` to select the correct account.

The command contains a repository name and a public ExtGuide release URL, with no access token, password, or signed private download URL. GitHub CLI manages its own authentication; ExtGuide never requests or exports a token and does not put credentials in logs. Downloads use the authenticated GitHub release asset API and are restricted to the selected repository. After sign-in, ExtGuide lists installable published releases in a dropdown, including labeled pre-releases and betas. The first stable release in GitHub's returned order is selected by default. The chosen manifest, ZIP, and optional checksum are pinned to that release throughout the installation.

An unauthenticated or unauthorized account cannot download the private manifest or ZIP. Authentication, download, and SHA-256 verification finish before the existing installation is replaced. Existing ExtGuide installations update at their original location, including remembered custom folders; Chrome then needs its normal **Reload** action. Run the same command on another computer after authenticating that computer's own account. Use `-NoGitHubLogin` to fail without opening a login flow when authentication is missing.

To skip the dropdown and choose an exact version, append `-ReleaseTag 'v1.0.0'` (or a beta tag). An unavailable tag fails explicitly. Choosing an older release replaces the files at the existing installation location; reload the extension in Chrome afterward.

## Making releases selectable

Every selectable release, including a beta, must be published and have an uploaded asset named **`installer-manifest.json`**. Its schema-v1 manifest must reference that release's uploaded extension ZIP and include either its SHA-256 or the URL of an uploaded checksum. Draft releases and releases missing that manifest are excluded. Release discovery follows every page, so it is not limited to the first 30 or 100 releases. The selected manifest's ZIP and checksum must belong to the same repository and release; same-repository `latest` asset aliases are resolved against the selected tag, and explicit references to another tag are rejected.

No beta-specific ExtGuide flag or schema change is required. Include manifests when publishing stable and beta releases, and attach manifests to any older published releases you want listed. Git tags without GitHub releases do not appear.

When upgrading an existing integration, update its pinned ExtGuide command to `v1.3.0` and describe release selection. See [the schema](docs/manifest-schema.md) for a beta manifest example.

## Build and verify

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-ReleaseCandidate.ps1 -PreviewOnly
```

Real Windows verification steps are documented in [release verification](docs/release-verification.md).
