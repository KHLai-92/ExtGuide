[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $GitHubRepository,
    [Parameter(Mandatory = $true)][uri] $PreviousManifestUri,
    [string] $ReleaseScript,
    [string] $EvidenceDirectory
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $ReleaseScript) { $ReleaseScript = Join-Path $root 'artifacts\extguide-release\ExtGuide-v1.2.0.ps1' }
if (-not $EvidenceDirectory) { $EvidenceDirectory = Join-Path $root ('artifacts\private-github-update-' + [guid]::NewGuid().ToString('N')) }
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
if (Test-Path -LiteralPath $EvidenceDirectory) { throw 'Use a new, empty evidence directory.' }
$null = New-Item -ItemType Directory -Path $EvidenceDirectory

# Load the exact standalone release, replacing only its final automatic entry
# with a test call below. Download, validation, receipt, and update code remain
# unchanged; native UI and the settings-file location have isolated boundaries.
$source = [IO.File]::ReadAllText([IO.Path]::GetFullPath($ReleaseScript))
$footer = 'Invoke-ExtGuideBootstrap @PSBoundParameters'
$index = $source.LastIndexOf($footer, [StringComparison]::Ordinal)
if ($index -lt 0 -or $source.Substring($index + $footer.Length).Trim()) { throw 'Unexpected standalone release entry point.' }
$definitions = $source.Substring(0, $index)
$candidate = New-Module -Name ExtGuidePrivateUpdateValidation -ScriptBlock {
    param($Definitions, $Repository)
    . ([scriptblock]::Create($Definitions)) -GitHubRepository $Repository -NoGitHubLogin
} -ArgumentList @($definitions, $GitHubRepository)

$evidence = & $candidate {
    param($Repository, $PreviousUri, $EvidenceRoot)
    $script:ValidationSettingsPath = Join-Path $EvidenceRoot 'settings.json'
    $script:ValidationDestination = Join-Path $EvidenceRoot 'UserChosenFolder\Playmium'
    $script:ValidationAppData = Join-Path $EvidenceRoot 'FreshLocalAppData'
    function script:Get-ExtGuideSettingsPath { return $script:ValidationSettingsPath }
    $adapter = New-ExtGuideWindowsHostAdapter
    $adapter.GetLocalApplicationDataPath = { $script:ValidationAppData }
    $adapter.ChooseDestination = {
        param($Manifest, $Recommended, $Remembered)
        $destination = if ($Remembered) { $Remembered } else { $script:ValidationDestination }
        [pscustomobject]@{ Cancelled = $false; Destination = $destination; IsCustom = $true; UseElevation = $false }
    }
    $adapter.GetRunningChromeCandidates = { @((Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe')) }
    $adapter.GetRegisteredChromeCandidates = { @() }
    $adapter.SetClipboard = { param($Text) }
    $adapter.LaunchChrome = { param($Executable, $Uri) }
    $adapter.ShowGuide = { param($DisplayName, $InstalledRoot, $ChromeExecutable, $WasUpdate)
        [pscustomobject]@{ State = 'GuidanceReady'; WasUpdate = $WasUpdate }
    }
    $adapter.ShowError = { param($Failure) }
    $adapter.LogFailure = { param($Failure) }

    $previousJson = Invoke-ExtGuideDownload -Uri $PreviousUri
    $previous = ConvertFrom-ExtGuideManifest -Json $previousJson
    [byte[]] $previousBytes = Invoke-ExtGuideDownload -Uri ([uri]$previous.archiveUrl) -AsBytes
    if ((Get-ExtGuideSha256 -Bytes $previousBytes) -ne $previous.sha256) { throw 'Previous archive digest mismatch.' }
    $adapter.FetchText = { param($Uri) $previousJson }.GetNewClosure()
    $adapter.FetchBytes = { param($Uri) ,$previousBytes }.GetNewClosure()
    Set-ExtGuideHostAdapter -Adapter $adapter
    $first = Invoke-ExtGuideBootstrap -ManifestUri $PreviousUri
    if ($first.Status -ne 'GuidanceReady' -or $first.WasUpdate) { throw ('Old-version installation failed: ' + $first.Category) }
    $beforeHash = (Get-FileHash -LiteralPath (Join-Path $first.InstalledRoot 'manifest.json')).Hash
    $beforeReceipt = [IO.File]::ReadAllText((Join-Path $first.Destination '.extguide-install.json'))

    # A fresh gh configuration and no environment token must fail closed. The
    # real account/configuration is restored without copying or printing it.
    $names = @('GH_CONFIG_DIR', 'GH_TOKEN', 'GITHUB_TOKEN')
    $saved = @{}
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    try {
        [Environment]::SetEnvironmentVariable('GH_CONFIG_DIR', (Join-Path $EvidenceRoot 'UnauthenticatedGitHub'), 'Process')
        [Environment]::SetEnvironmentVariable('GH_TOKEN', $null, 'Process')
        [Environment]::SetEnvironmentVariable('GITHUB_TOKEN', $null, 'Process')
        $denied = Invoke-ExtGuideBootstrap -GitHubRepository $Repository -NoGitHubLogin
    }
    finally {
        foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
        $saved.Clear()
    }
    if ($denied.Status -ne 'Failed' -or $denied.Category -ne 'Authentication') { throw 'Unauthenticated access was not rejected.' }
    if ((Get-FileHash -LiteralPath (Join-Path $first.InstalledRoot 'manifest.json')).Hash -ne $beforeHash -or
        [IO.File]::ReadAllText((Join-Path $first.Destination '.extguide-install.json')) -cne $beforeReceipt) {
        throw 'The failed authentication changed the existing installation.'
    }

    $updated = Invoke-ExtGuideBootstrap -GitHubRepository $Repository -NoGitHubLogin
    if ($updated.Status -ne 'GuidanceReady') { throw ('Authenticated update failed: ' + $updated.Category + ': ' + $updated.Message) }
    if (-not $updated.WasUpdate -or $updated.PreviousVersion -ne $first.InstalledVersion -or
        $updated.InstalledRoot -ne $first.InstalledRoot -or -not $updated.Guide.WasUpdate) { throw 'The stable-root update contract failed.' }
    $receipt = Get-Content -LiteralPath (Join-Path $updated.Destination '.extguide-install.json') -Raw | ConvertFrom-Json
    $installed = Get-Content -LiteralPath (Join-Path $updated.InstalledRoot 'manifest.json') -Raw | ConvertFrom-Json
    if ($installed.version -ne $updated.InstalledVersion -or $receipt.extensionVersion -ne $updated.InstalledVersion) { throw 'Installed version/receipt mismatch.' }

    [pscustomobject]@{
        PreviousVersion = $first.InstalledVersion
        InstalledVersion = $updated.InstalledVersion
        WasUpdate = $updated.WasUpdate
        StableRootPreserved = $updated.InstalledRoot -eq $first.InstalledRoot
        RememberedCustomFolderPreserved = $updated.Destination -eq $script:ValidationDestination
        UnauthenticatedResult = $denied.Category
        FailedAuthenticationPreservedPreviousFiles = $true
        ArchiveSha256 = $receipt.archiveSha256
        ReloadGuidance = $updated.Guide.WasUpdate
        UiBoundary = 'Native folder choice, clipboard, Chrome launch, and guidance are isolated; production downloads, authentication, checksum, settings, receipt, and archive replacement are real.'
    }
} $GitHubRepository $PreviousManifestUri $EvidenceDirectory
$evidence | Add-Member -NotePropertyName ReleaseScriptSha256 -NotePropertyValue (Get-FileHash -LiteralPath $ReleaseScript).Hash.ToLowerInvariant()
$evidence | Add-Member -NotePropertyName PowerShellVersion -NotePropertyValue $PSVersionTable.PSVersion.ToString()
$evidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'result.json') -Encoding UTF8
$evidence
