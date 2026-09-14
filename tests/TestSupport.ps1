function Get-TestSha256 {
    param([byte[]] $Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return -join ($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}

function New-TestZipBytes {
    param([Parameter(Mandatory = $true)][object[]] $Entries)

    Add-Type -AssemblyName System.IO.Compression
    $memory = New-Object System.IO.MemoryStream
    $archive = New-Object System.IO.Compression.ZipArchive($memory, [System.IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        foreach ($item in $Entries) {
            $entry = $archive.CreateEntry([string] $item.Name)
            $stream = $entry.Open()
            $writer = New-Object System.IO.StreamWriter($stream, (New-Object System.Text.UTF8Encoding($false)))
            try { $writer.Write([string] $item.Content) }
            finally { $writer.Dispose(); $stream.Dispose() }
        }
    }
    finally { $archive.Dispose() }
    $bytes = $memory.ToArray()
    $memory.Dispose()
    return $bytes
}

function New-TestExtensionArchive {
    param([string] $Version = '1.0.0', [string] $Background = 'version-one')
    return New-TestZipBytes -Entries @(
        [pscustomobject]@{ Name = 'extension/manifest.json'; Content = "{ `"manifest_version`": 3, `"name`": `"Sample`", `"version`": `"$Version`" }" },
        [pscustomobject]@{ Name = 'extension/background.js'; Content = $Background }
    )
}

function New-TestInstallerManifest {
    param([byte[]] $ArchiveBytes, [string] $ExtensionRoot = 'extension', [string] $Publisher = 'ExtGuide', [string] $Folder = 'SampleExtension')
    return (@{
        schemaVersion = 1
        displayName = 'ExtGuide Sample'
        publisher = $Publisher
        installFolderName = $Folder
        archiveUrl = 'https://example.test/extension.zip'
        sha256 = Get-TestSha256 -Bytes $ArchiveBytes
        extensionRoot = $ExtensionRoot
    } | ConvertTo-Json)
}

function New-WorkflowTestAdapter {
    param(
        [Parameter(Mandatory = $true)][string] $ManifestJson,
        [Parameter(Mandatory = $true)][byte[]] $ArchiveBytes,
        [Parameter(Mandatory = $true)][string] $LocalApplicationData,
        [string] $Destination,
        [switch] $UseRealInstaller,
        [string[]] $RunningCandidates = @('C:\Chrome\chrome.exe'),
        [string[]] $RegisteredCandidates = @(),
        [string[]] $ValidChromeCandidates = @('C:\Chrome\chrome.exe'),
        [string] $ChromeChoice
    )

    $module = Get-Module -Name ExtGuide
    $state = @{
        DestinationRemembered = $null
        ChromeRemembered = $null
        Clipboard = $null
        Launch = $null
        Guide = $null
        Failure = $null
        LogCategory = $null
    }
    $resolvedDestination = if ($Destination) { $Destination } else { Join-Path (Join-Path $LocalApplicationData 'ExtGuide') 'SampleExtension' }
    $adapter = @{
        State = $state
        FetchText = { param($Uri) $ManifestJson }.GetNewClosure()
        FetchBytes = { param($Uri) $ArchiveBytes }.GetNewClosure()
        GetLocalApplicationDataPath = { $LocalApplicationData }.GetNewClosure()
        ChooseDestination = { param($Manifest, $Recommended, $Remembered) [pscustomobject]@{ Cancelled = $false; Destination = $resolvedDestination; IsCustom = [bool] $Destination } }.GetNewClosure()
        TestDestinationWritable = { param($Path) $true }
        GetRememberedDestination = { param($Manifest) $null }
        RememberDestination = { param($Manifest, $Path) $state.DestinationRemembered = $Path }.GetNewClosure()
        GetRunningChromeCandidates = { $RunningCandidates }.GetNewClosure()
        GetRegisteredChromeCandidates = { $RegisteredCandidates }.GetNewClosure()
        GetRememberedChrome = { $null }
        TestChromeSignature = { param($Path) @($ValidChromeCandidates) -contains $Path }.GetNewClosure()
        ChooseChrome = { param($Candidates) $ChromeChoice }.GetNewClosure()
        RememberChrome = { param($Path) $state.ChromeRemembered = $Path }.GetNewClosure()
        SetClipboard = { param($Text) $state.Clipboard = $Text }.GetNewClosure()
        LaunchChrome = { param($Executable, $Uri) $state.Launch = [pscustomobject]@{ Executable = $Executable; Uri = $Uri } }.GetNewClosure()
        ShowGuide = { param($DisplayName, $InstalledRoot, $ChromeExecutable) $state.Guide = [pscustomobject]@{ State = 'GuidanceReady'; DisplayName = $DisplayName; InstalledRoot = $InstalledRoot }; $state.Guide }.GetNewClosure()
        ShowError = { param($Failure) $state.Failure = $Failure }.GetNewClosure()
        LogFailure = { param($Failure) $state.LogCategory = $Failure.Category }.GetNewClosure()
    }
    if ($UseRealInstaller) {
        $adapter.WriteExtension = {
            param($Bytes, $Target, $Root)
            & $module { param($Archive, $DestinationPath, $ExtensionRootPath) Install-ExtGuideArchive -ArchiveBytes $Archive -Destination $DestinationPath -ExtensionRoot $ExtensionRootPath } $Bytes $Target $Root
        }.GetNewClosure()
    }
    else {
        $adapter.WriteExtension = {
            param($Bytes, $Target, $Root)
            [pscustomobject]@{ ExtensionRoot = Join-Path $Target $Root; Content = @{ 'manifest.json' = 1 }; WasUpdate = $false }
        }
    }
    return $adapter
}

function Set-WorkflowTestAdapter {
    param([hashtable] $Adapter)
    $module = Get-Module -Name ExtGuide
    & $module { param($Value) Set-ExtGuideHostAdapter -Adapter $Value } $Adapter
}
