$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'src\ExtGuide\ExtGuide.psd1'
$sampleManifestPath = Join-Path $repositoryRoot 'examples\sample-installer-manifest.json'

Import-Module $modulePath -Force

function New-SampleHostAdapter {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ManifestPath
    )

    $manifestJson = Get-Content -LiteralPath $ManifestPath -Raw
    $localApplicationData = 'C:\Users\Example\AppData\Local'
    $destination = Join-Path (Join-Path $localApplicationData 'ExtGuide') 'SampleExtension'
    $extensionRoot = Join-Path $destination 'extension'
    $chromeExecutable = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
    $state = @{
        ManifestRequests = @()
        ArchiveRequests = @()
        Installation = $null
        ProcessCandidatesRead = $false
        RegistryCandidatesRead = $false
        SignatureChecks = @()
        Clipboard = $null
        Launch = $null
        Guide = $null
    }

    return @{
        State = $state
        FetchText = {
            param($Uri)
            $state.ManifestRequests = @($state.ManifestRequests) + $Uri.AbsoluteUri
            $manifestJson
        }.GetNewClosure()
        FetchBytes = {
            param($Uri)
            $state.ArchiveRequests = @($state.ArchiveRequests) + $Uri.AbsoluteUri
            [byte[]](1, 2, 3)
        }.GetNewClosure()
        GetLocalApplicationDataPath = { $localApplicationData }.GetNewClosure()
        WriteExtension = {
            param($ArchiveBytes, $Destination, $ConfiguredExtensionRoot)
            $state.Installation = [pscustomobject]@{
                ArchiveBytes = $ArchiveBytes
                Destination = $Destination
                ExtensionRoot = $extensionRoot
                Content = @{
                    'manifest.json' = '{ "manifest_version": 3, "name": "ExtGuide Sample", "version": "1.0.0" }'
                    'background.js' = 'chrome.runtime.onInstalled.addListener(() => {});'
                }
                WasUpdate = $false
            }
            $state.Installation
        }.GetNewClosure()
        GetRunningChromeCandidates = {
            $state.ProcessCandidatesRead = $true
            @('C:\Program Files\Google\Chrome Beta\Application\chrome.exe')
        }.GetNewClosure()
        GetRegisteredChromeCandidates = {
            $state.RegistryCandidatesRead = $true
            @($chromeExecutable)
        }.GetNewClosure()
        TestChromeSignature = {
            param($Path)
            $state.SignatureChecks = @($state.SignatureChecks) + $Path
            $Path -eq $chromeExecutable
        }.GetNewClosure()
        SetClipboard = {
            param($Text)
            $state.Clipboard = $Text
        }.GetNewClosure()
        LaunchChrome = {
            param($Executable, $Uri)
            $state.Launch = [pscustomobject]@{ Executable = $Executable; Uri = $Uri }
            $state.Launch
        }.GetNewClosure()
        ShowGuide = {
            param($DisplayName, $InstalledRoot)
            $state.Guide = [pscustomobject]@{ State = 'GuidanceReady'; DisplayName = $DisplayName; InstalledRoot = $InstalledRoot }
            $state.Guide
        }.GetNewClosure()
    }
}

Describe 'Invoke-ExtGuideBootstrap' {
    It 'installs a supported sample manifest and prepares guided Chrome setup' {
        $adapter = New-SampleHostAdapter -ManifestPath $sampleManifestPath
        $module = Get-Module -Name ExtGuide
        & $module { param($HostAdapter) Set-ExtGuideHostAdapter -Adapter $HostAdapter } $adapter

        $result = Invoke-ExtGuideBootstrap -ManifestUri 'https://github.com/example/extguide-sample/releases/latest/download/installer-manifest.json'

        $result.Status | Should Be 'GuidanceReady'
        $result.Destination | Should Be 'C:\Users\Example\AppData\Local\ExtGuide\SampleExtension'
        $result.InstalledRoot | Should Be 'C:\Users\Example\AppData\Local\ExtGuide\SampleExtension\extension'
        $result.InstalledContent['manifest.json'] | Should Match '"manifest_version": 3'
        $result.ClipboardPath | Should Be $result.InstalledRoot
        $result.ChromeExecutable | Should Be 'C:\Program Files\Google\Chrome\Application\chrome.exe'
        $result.LaunchUri | Should Be 'chrome://extensions/'
        $result.Guide.DisplayName | Should Be 'ExtGuide Sample'

        $adapter.State.ManifestRequests | Should Be @('https://github.com/example/extguide-sample/releases/latest/download/installer-manifest.json')
        $adapter.State.ArchiveRequests | Should Be @('https://github.com/example/extguide-sample/releases/download/v1.0.0/extension.zip')
        $adapter.State.Installation.Destination | Should Be $result.Destination
        $adapter.State.Installation.ExtensionRoot | Should Be $result.InstalledRoot
        $adapter.State.ProcessCandidatesRead | Should Be $true
        $adapter.State.RegistryCandidatesRead | Should Be $true
        $adapter.State.SignatureChecks | Should Be @(
            'C:\Program Files\Google\Chrome Beta\Application\chrome.exe',
            'C:\Program Files\Google\Chrome\Application\chrome.exe',
            'C:\Program Files\Google\Chrome\Application\chrome.exe'
        )
        $adapter.State.Clipboard | Should Be $result.InstalledRoot
        $adapter.State.Launch.Uri | Should Be 'chrome://extensions/'
        $adapter.State.Guide.State | Should Be 'GuidanceReady'
    }
}
