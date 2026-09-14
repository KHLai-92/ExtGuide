[CmdletBinding()]
param(
    [string] $ReleaseScript,
    [string] $SampleManifest
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ReleaseScript)) { $ReleaseScript = Join-Path $repositoryRoot 'artifacts\extguide-release\ExtGuide-v1.0.0.ps1' }
if ([string]::IsNullOrWhiteSpace($SampleManifest)) { $SampleManifest = Join-Path $repositoryRoot 'artifacts\sample-release\installer-manifest.json' }

$tokens = $null
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($ReleaseScript, [ref] $tokens, [ref] $parseErrors)
if ($parseErrors.Count -gt 0) { throw 'The self-contained release script does not parse in Windows PowerShell 5.1.' }
$releaseContent = [System.IO.File]::ReadAllText($ReleaseScript)
$resourceDirectory = Join-Path $repositoryRoot 'src\ExtGuide\Resources'
foreach ($resource in Get-ChildItem -LiteralPath $resourceDirectory -Filter 'strings.*.json') {
    $base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($resource.FullName))
    if (-not $releaseContent.Contains($base64)) { throw "The self-contained release is missing localized resource '$($resource.Name)'." }
}
$assetDirectory = Join-Path $repositoryRoot 'src\ExtGuide\Assets'
foreach ($asset in Get-ChildItem -LiteralPath $assetDirectory -Filter '*.png') {
    $base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($asset.FullName))
    if (-not $releaseContent.Contains($base64)) { throw "The self-contained release is missing visual asset '$($asset.Name)'." }
}

$manifest = Get-Content -LiteralPath $SampleManifest -Raw | ConvertFrom-Json
$archivePath = Join-Path (Split-Path -Parent $SampleManifest) (Split-Path -Leaf ([uri] $manifest.archiveUrl).AbsolutePath)
$archiveBytes = [System.IO.File]::ReadAllBytes($archivePath)
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $actualDigest = -join ($sha.ComputeHash($archiveBytes) | ForEach-Object { $_.ToString('x2') }) }
finally { $sha.Dispose() }
if ($actualDigest -ne [string] $manifest.sha256) { throw 'The sample manifest digest does not match the sample archive.' }

Import-Module (Join-Path $repositoryRoot 'src\ExtGuide\ExtGuide.psd1') -Force
$module = Get-Module -Name ExtGuide
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ExtGuide-artifact-' + [guid]::NewGuid().ToString('N'))
$destination = Join-Path $temporaryRoot 'SampleExtension'
try {
    $installation = & $module { param($Bytes, $Target, $Root) Install-ExtGuideArchive -ArchiveBytes $Bytes -Destination $Target -ExtensionRoot $Root } $archiveBytes $destination ([string] $manifest.extensionRoot)
    if (-not (Test-Path -LiteralPath (Join-Path $installation.ExtensionRoot 'manifest.json') -PathType Leaf)) { throw 'The sample artifact did not install a Chrome extension manifest.' }
    [pscustomobject]@{ ReleaseScriptParses = $true; LocalizationsEmbedded = $true; VisualAssetsEmbedded = $true; DigestMatches = $true; InstalledRoot = $installation.ExtensionRoot }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
