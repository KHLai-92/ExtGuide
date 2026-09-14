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
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$w=New-Object Net.WebClient;try{$s=$w.DownloadString('https://github.com/KHLai-92/ExtGuide/releases/download/v1.0.0/ExtGuide-v1.0.0.ps1')}finally{$w.Dispose()};&([scriptblock]::Create($s)) -ManifestUri 'https://github.com/YOUR-ORG/YOUR-EXTENSION/releases/latest/download/installer-manifest.json'
```

The ExtGuide URL is pinned to `v1.0.0`; the extension manifest may independently follow the extension's latest release. `DownloadString` is intentional because GitHub serves PowerShell release assets as binary content. No GitHub API, credentials, Git, Node.js, npm, Python, 7-Zip, or administrator rights are required.

## Build and verify

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-ReleaseCandidate.ps1 -PreviewOnly
```

Real Windows verification steps are documented in [release verification](docs/release-verification.md).
