[CmdletBinding()]
param(
    [uri] $ManifestUri,
    [string] $EvidencePath,
    [switch] $PreviewOnly
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($EvidencePath)) { $EvidencePath = Join-Path $repositoryRoot 'artifacts\release-evidence.json' }
Import-Module Pester -RequiredVersion 3.4.0 -Force
$null = & (Join-Path $PSScriptRoot 'Build-Release.ps1')
$null = & (Join-Path $PSScriptRoot 'New-SampleRelease.ps1')
$artifactCheck = & (Join-Path $PSScriptRoot 'Test-BuiltArtifacts.ps1')
$testResult = Invoke-Pester -Script (Join-Path $repositoryRoot 'tests') -PassThru
$windowsHostCheck = & (Join-Path $repositoryRoot 'tests\verify-windows-host.ps1')
$previewPath = Join-Path (Split-Path -Parent $EvidencePath) 'guidance-preview.png'
& (Join-Path $PSScriptRoot 'Show-ExtGuidePreview.ps1') -ScreenshotPath $previewPath | Out-Null

$workflowStatus = 'NotRun'
if (-not $PreviewOnly -and $ManifestUri) {
    Import-Module (Join-Path $repositoryRoot 'src\ExtGuide\ExtGuide.psd1') -Force
    $workflowStatus = (Invoke-ExtGuideBootstrap -ManifestUri $ManifestUri).Status
}

$osCaption = 'Windows'
try { $osCaption = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption }
catch {
    try { $osCaption = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).ProductName }
    catch { $osCaption = 'Windows ' + [Environment]::OSVersion.Version.ToString() }
}

$evidence = [ordered]@{
    recordedAtUtc = [DateTime]::UtcNow.ToString('o')
    osCaption = $osCaption
    osVersion = [Environment]::OSVersion.Version.ToString()
    powershell = $PSVersionTable.PSVersion.ToString()
    isAdministrator = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    automatedTestsPassed = $testResult.FailedCount -eq 0
    automatedTestCount = $testResult.TotalCount
    builtArtifactsVerified = [bool] ($artifactCheck.ReleaseScriptParses -and $artifactCheck.LocalizationsEmbedded -and $artifactCheck.VisualAssetsEmbedded -and $artifactCheck.DigestMatches)
    windowsHostCheck = $windowsHostCheck
    previewImage = $previewPath
    realWorkflowStatus = $workflowStatus
    manualChecks = [ordered]@{
        folderChooser = 'Record after observation'
        clipboard = 'Record after observation'
        guideForegroundAndNormalZOrder = 'Record after observation'
        chromeDiscovery = 'Record after observation'
        loadUnpacked = 'Record after observation'
        keyboardAndScaling = 'Record after observation'
        managedPolicy = 'Record on a managed test device'
    }
}
$parent = Split-Path -Parent $EvidencePath
$null = New-Item -ItemType Directory -Path $parent -Force
$evidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
$evidence
