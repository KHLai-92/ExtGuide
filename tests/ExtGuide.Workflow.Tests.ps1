$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'src\ExtGuide\ExtGuide.psd1') -Force
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$manifestUri = 'https://example.test/installer-manifest.json'

Describe 'ExtGuide secure workflow' {
    It 'installs and atomically updates a valid Manifest V3 extension at a stable root' {
        $archiveV1 = New-TestExtensionArchive -Version '1.0.0' -Background 'old-content'
        $destination = Join-Path $TestDrive 'LocalAppData\ExtGuide\SampleExtension'
        $adapterV1 = New-WorkflowTestAdapter -ManifestJson (New-TestInstallerManifest -ArchiveBytes $archiveV1) -ArchiveBytes $archiveV1 -LocalApplicationData (Join-Path $TestDrive 'LocalAppData') -Destination $destination -UseRealInstaller
        Set-WorkflowTestAdapter -Adapter $adapterV1

        $first = Invoke-ExtGuideBootstrap -ManifestUri $manifestUri

        $first.Status | Should Be 'GuidanceReady'
        $first.WasUpdate | Should Be $false
        $first.InstalledVersion | Should Be '1.0.0'
        $receipt = Get-Content -LiteralPath (Join-Path $destination '.extguide-install.json') -Raw | ConvertFrom-Json
        $receipt.integrationId | Should Be 'ExtGuide|SampleExtension'
        $receipt.extensionVersion | Should Be '1.0.0'
        (Get-Content -LiteralPath (Join-Path $first.InstalledRoot 'background.js') -Raw) | Should Be 'old-content'

        $archiveV2 = New-TestExtensionArchive -Version '2.0.0' -Background 'new-content'
        $adapterV2 = New-WorkflowTestAdapter -ManifestJson (New-TestInstallerManifest -ArchiveBytes $archiveV2) -ArchiveBytes $archiveV2 -LocalApplicationData (Join-Path $TestDrive 'LocalAppData') -Destination $destination -UseRealInstaller
        Set-WorkflowTestAdapter -Adapter $adapterV2
        $second = Invoke-ExtGuideBootstrap -ManifestUri $manifestUri

        $second.Status | Should Be 'GuidanceReady'
        $second.WasUpdate | Should Be $true
        $second.PreviousVersion | Should Be '1.0.0'
        $second.InstalledVersion | Should Be '2.0.0'
        $second.Guide.WasUpdate | Should Be $true
        $second.InstalledRoot | Should Be $first.InstalledRoot
        (Get-Content -LiteralPath (Join-Path $second.InstalledRoot 'background.js') -Raw) | Should Be 'new-content'
    }

    It 'refuses to replace a destination whose receipt belongs to another integration' {
        $archive = New-TestExtensionArchive -Version '1.0.0'
        $destination = Join-Path $TestDrive 'IdentityCase\SampleExtension'
        $firstAdapter = New-WorkflowTestAdapter -ManifestJson (New-TestInstallerManifest -ArchiveBytes $archive -IntegrationId 'example.first') -ArchiveBytes $archive -LocalApplicationData $TestDrive -Destination $destination -UseRealInstaller
        Set-WorkflowTestAdapter -Adapter $firstAdapter
        $null = Invoke-ExtGuideBootstrap -ManifestUri $manifestUri

        $secondAdapter = New-WorkflowTestAdapter -ManifestJson (New-TestInstallerManifest -ArchiveBytes $archive -IntegrationId 'example.second') -ArchiveBytes $archive -LocalApplicationData $TestDrive -Destination $destination -UseRealInstaller
        Set-WorkflowTestAdapter -Adapter $secondAdapter
        $result = Invoke-ExtGuideBootstrap -ManifestUri $manifestUri

        $result.Status | Should Be 'Failed'
        $result.Category | Should Be 'Destination'
        (Get-Content -LiteralPath (Join-Path $destination '.extguide-install.json') -Raw | ConvertFrom-Json).integrationId | Should Be 'example.first'
    }

    It 'keeps a remembered protected destination and requests scoped elevation' {
        $archive = New-TestExtensionArchive
        $destination = Join-Path $TestDrive 'Protected\SampleExtension'
        $adapter = New-WorkflowTestAdapter -ManifestJson (New-TestInstallerManifest -ArchiveBytes $archive) -ArchiveBytes $archive -LocalApplicationData $TestDrive
        $adapter.State.RememberedSeen = $null
        $adapter.State.InstallContext = $null
        $adapter.GetRememberedDestination = { param($Manifest) $destination }.GetNewClosure()
        $adapter.DestinationExists = { param($Path) $true }
        $adapter.TestDestinationWritable = { param($Path) $false }
        $adapter.ChooseDestination = {
            param($Manifest, $Recommended, $Remembered)
            $adapter.State.RememberedSeen = $Remembered
            [pscustomobject]@{ Cancelled = $false; Destination = $Remembered; IsCustom = $true; UseElevation = $true }
        }.GetNewClosure()
        $adapter.WriteExtension = {
            param($Bytes, $Target, $Root, $Context)
            $adapter.State.InstallContext = $Context
            [pscustomobject]@{ ExtensionRoot = Join-Path $Target $Root; Content = @{}; WasUpdate = $true; PreviousVersion = '1.0.0'; InstalledVersion = '2.0.0' }
        }.GetNewClosure()
        Set-WorkflowTestAdapter -Adapter $adapter

        $result = Invoke-ExtGuideBootstrap -ManifestUri $manifestUri

        $result.Status | Should Be 'GuidanceReady'
        $adapter.State.RememberedSeen | Should Be $destination
        $adapter.State.InstallContext.UseElevation | Should Be $true
        $adapter.State.InstallContext.ArchiveSha256 | Should Be (Get-TestSha256 -Bytes $archive)
    }

    It 'offers another folder when the Windows elevation prompt is declined' {
        $archive = New-TestExtensionArchive
        $protected = Join-Path $TestDrive 'ProtectedDeclined\SampleExtension'
        $fallback = Join-Path $TestDrive 'WritableFallback\SampleExtension'
        $adapter = New-WorkflowTestAdapter -ManifestJson (New-TestInstallerManifest -ArchiveBytes $archive) -ArchiveBytes $archive -LocalApplicationData $TestDrive
        $adapter.State.WriteAttempts = 0
        $adapter.ChooseDestination = { param($Manifest, $Recommended, $Remembered) [pscustomobject]@{ Cancelled = $false; Destination = $protected; IsCustom = $true; UseElevation = $true } }.GetNewClosure()
        $adapter.TestDestinationWritable = { param($Path) $Path -eq $fallback }.GetNewClosure()
        $adapter.ChooseFallbackDestination = { param($Manifest) $fallback }.GetNewClosure()
        $adapter.WriteExtension = {
            param($Bytes, $Target, $Root, $Context)
            $adapter.State.WriteAttempts++
            if ($adapter.State.WriteAttempts -eq 1) {
                $exception = New-Object System.Exception('UAC cancelled')
                $exception.Data['ExtGuideElevationDeclined'] = $true
                throw $exception
            }
            [pscustomobject]@{ ExtensionRoot = Join-Path $Target $Root; Content = @{}; WasUpdate = $false; PreviousVersion = ''; InstalledVersion = '1.0.0' }
        }.GetNewClosure()
        Set-WorkflowTestAdapter -Adapter $adapter

        $result = Invoke-ExtGuideBootstrap -ManifestUri $manifestUri

        $result.Status | Should Be 'GuidanceReady'
        $result.Destination | Should Be $fallback
        $adapter.State.WriteAttempts | Should Be 2
        $adapter.State.DestinationRemembered | Should Be $fallback
    }

    It 'offers administrator permission again when the same protected location is reselected' {
        $archive = New-TestExtensionArchive
        $protected = Join-Path $TestDrive 'ProtectedRetried\SampleExtension'
        $adapter = New-WorkflowTestAdapter -ManifestJson (New-TestInstallerManifest -ArchiveBytes $archive) -ArchiveBytes $archive -LocalApplicationData $TestDrive
        $adapter.State.WriteAttempts = 0
        $adapter.State.ElevationChoices = @()
        $adapter.ChooseDestination = { param($Manifest, $Recommended, $Remembered) [pscustomobject]@{ Cancelled = $false; Destination = $protected; IsCustom = $true; UseElevation = $true } }.GetNewClosure()
        $adapter.TestDestinationWritable = { param($Path) $false }
        $adapter.ChooseFallbackDestination = { param($Manifest) [pscustomobject]@{ Destination = $protected; UseElevation = $true } }.GetNewClosure()
        $adapter.WriteExtension = {
            param($Bytes, $Target, $Root, $Context)
            $adapter.State.WriteAttempts++
            $adapter.State.ElevationChoices = @($adapter.State.ElevationChoices) + [bool] $Context.UseElevation
            if ($adapter.State.WriteAttempts -eq 1) {
                $exception = New-Object System.Exception('UAC cancelled')
                $exception.Data['ExtGuideElevationDeclined'] = $true
                throw $exception
            }
            [pscustomobject]@{ ExtensionRoot = Join-Path $Target $Root; Content = @{}; WasUpdate = $true; PreviousVersion = '1.0.0'; InstalledVersion = '1.0.0' }
        }.GetNewClosure()
        Set-WorkflowTestAdapter -Adapter $adapter

        $result = Invoke-ExtGuideBootstrap -ManifestUri $manifestUri

        $result.Status | Should Be 'GuidanceReady'
        $result.Destination | Should Be $protected
        $adapter.State.WriteAttempts | Should Be 2
        $adapter.State.ElevationChoices | Should Be @($true, $true)
    }

    It 'repairs an interrupted swap by restoring the preserved installation' {
        $parent = Join-Path $TestDrive 'RecoveryCase'
        $destination = Join-Path $parent 'SampleExtension'
        $backup = Join-Path $parent '.SampleExtension.extguide-backup-11111111111111111111111111111111'
        $staging = Join-Path $parent '.SampleExtension.extguide-stage-22222222222222222222222222222222'
        $null = New-Item -ItemType Directory -Path (Join-Path $backup 'extension') -Force
        Set-Content -LiteralPath (Join-Path $backup 'extension\manifest.json') -Value '{ "manifest_version": 3, "name": "Sample", "version": "1.0.0" }'
        $null = New-Item -ItemType Directory -Path $staging -Force
        $journalPath = Join-Path $parent '.SampleExtension.extguide-update.json'
        [pscustomobject]@{ journalVersion = 1; Destination = $destination; Staging = $staging; Backup = $backup; Phase = 'OldBackedUp' } | ConvertTo-Json | Set-Content -LiteralPath $journalPath

        $module = Get-Module -Name ExtGuide
        $repaired = & $module { param($Path) Repair-ExtGuideInterruptedUpdate -Destination $Path } $destination

        $repaired | Should Be $true
        Test-Path -LiteralPath (Join-Path $destination 'extension\manifest.json') | Should Be $true
        Test-Path -LiteralPath $backup | Should Be $false
        Test-Path -LiteralPath $staging | Should Be $false
        Test-Path -LiteralPath $journalPath | Should Be $false
    }

    It 'preserves the current installation when archive integrity fails' {
        $archive = New-TestExtensionArchive -Background 'working-content'
        $destination = Join-Path $TestDrive 'IntegrityCase\SampleExtension'
        $adapter = New-WorkflowTestAdapter -ManifestJson (New-TestInstallerManifest -ArchiveBytes $archive) -ArchiveBytes $archive -LocalApplicationData (Join-Path $TestDrive 'IntegrityCase') -Destination $destination -UseRealInstaller
        Set-WorkflowTestAdapter -Adapter $adapter
        $installed = Invoke-ExtGuideBootstrap -ManifestUri $manifestUri

        $badManifest = New-TestInstallerManifest -ArchiveBytes ([byte[]](9, 9, 9))
        $badAdapter = New-WorkflowTestAdapter -ManifestJson $badManifest -ArchiveBytes $archive -LocalApplicationData (Join-Path $TestDrive 'LocalAppData') -Destination $destination -UseRealInstaller
        Set-WorkflowTestAdapter -Adapter $badAdapter
        $failed = Invoke-ExtGuideBootstrap -ManifestUri $manifestUri

        $failed.Status | Should Be 'Failed'
        $failed.Category | Should Be 'Integrity'
        (Get-Content -LiteralPath (Join-Path $installed.InstalledRoot 'background.js') -Raw) | Should Be 'working-content'
    }

    It 'preserves the current installation when release metadata names the wrong extension version' {
        $archiveV1 = New-TestExtensionArchive -Version '1.0.0' -Background 'working-content'
        $destination = Join-Path $TestDrive 'VersionMismatch\SampleExtension'
        $firstAdapter = New-WorkflowTestAdapter -ManifestJson (New-TestInstallerManifest -ArchiveBytes $archiveV1 -ExtensionVersion '1.0.0') -ArchiveBytes $archiveV1 -LocalApplicationData $TestDrive -Destination $destination -UseRealInstaller
        Set-WorkflowTestAdapter -Adapter $firstAdapter
        $installed = Invoke-ExtGuideBootstrap -ManifestUri $manifestUri

        $archiveV2 = New-TestExtensionArchive -Version '2.0.0' -Background 'untrusted-content'
        $badAdapter = New-WorkflowTestAdapter -ManifestJson (New-TestInstallerManifest -ArchiveBytes $archiveV2 -ExtensionVersion '3.0.0') -ArchiveBytes $archiveV2 -LocalApplicationData $TestDrive -Destination $destination -UseRealInstaller
        Set-WorkflowTestAdapter -Adapter $badAdapter
        $failed = Invoke-ExtGuideBootstrap -ManifestUri $manifestUri

        $failed.Status | Should Be 'Failed'
        $failed.Category | Should Be 'Integrity'
        (Get-Content -LiteralPath (Join-Path $installed.InstalledRoot 'background.js') -Raw) | Should Be 'working-content'
    }

    It 'rejects archive path traversal without writing outside the destination' {
        $archive = New-TestZipBytes -Entries @(
            [pscustomobject]@{ Name = '../escape.txt'; Content = 'unsafe' },
            [pscustomobject]@{ Name = 'extension/manifest.json'; Content = '{ "manifest_version": 3, "name": "Sample", "version": "1.0" }' }
        )
        $destination = Join-Path $TestDrive 'TraversalCase\SampleExtension'
        $adapter = New-WorkflowTestAdapter -ManifestJson (New-TestInstallerManifest -ArchiveBytes $archive) -ArchiveBytes $archive -LocalApplicationData (Join-Path $TestDrive 'TraversalCase') -Destination $destination -UseRealInstaller
        Set-WorkflowTestAdapter -Adapter $adapter

        $result = Invoke-ExtGuideBootstrap -ManifestUri $manifestUri

        $result.Category | Should Be 'Extraction'
        (Test-Path -LiteralPath (Join-Path $TestDrive 'TraversalCase\escape.txt')) | Should Be $false
        (Test-Path -LiteralPath $destination) | Should Be $false
    }

    It 'rejects unsafe manifest-controlled folder names before installation' {
        $archive = New-TestExtensionArchive
        $manifest = New-TestInstallerManifest -ArchiveBytes $archive -Folder '..\escape'
        $adapter = New-WorkflowTestAdapter -ManifestJson $manifest -ArchiveBytes $archive -LocalApplicationData (Join-Path $TestDrive 'LocalAppData')
        Set-WorkflowTestAdapter -Adapter $adapter

        $result = Invoke-ExtGuideBootstrap -ManifestUri $manifestUri

        $result.Status | Should Be 'Failed'
        $result.Category | Should Be 'Configuration'
    }

    It 'uses and remembers the resolved custom destination' {
        $archive = New-TestExtensionArchive
        $customDestination = Join-Path $TestDrive 'ChosenBase\SampleExtension'
        $null = New-Item -ItemType Directory -Path $customDestination -Force
        $adapter = New-WorkflowTestAdapter -ManifestJson (New-TestInstallerManifest -ArchiveBytes $archive) -ArchiveBytes $archive -LocalApplicationData (Join-Path $TestDrive 'LocalAppData') -Destination $customDestination
        Set-WorkflowTestAdapter -Adapter $adapter

        $result = Invoke-ExtGuideBootstrap -ManifestUri $manifestUri

        [System.IO.Path]::IsPathRooted($result.Destination) | Should Be $true
        $result.Destination | Should Match ([regex]::Escape('ChosenBase\SampleExtension') + '$')
        $adapter.State.DestinationRemembered | Should Be $result.Destination
    }

    It 'lets the user choose among multiple authentic Chrome candidates and remembers the choice' {
        $archive = New-TestExtensionArchive
        $firstChrome = 'C:\ChromeOne\chrome.exe'
        $secondChrome = 'C:\ChromeTwo\chrome.exe'
        $adapter = New-WorkflowTestAdapter -ManifestJson (New-TestInstallerManifest -ArchiveBytes $archive) -ArchiveBytes $archive -LocalApplicationData (Join-Path $TestDrive 'LocalAppData') -RunningCandidates @($firstChrome) -RegisteredCandidates @($secondChrome) -ValidChromeCandidates @($firstChrome, $secondChrome) -ChromeChoice $secondChrome
        Set-WorkflowTestAdapter -Adapter $adapter

        $result = Invoke-ExtGuideBootstrap -ManifestUri $manifestUri

        $result.ChromeExecutable | Should Be $secondChrome
        $adapter.State.ChromeRemembered | Should Be $secondChrome
    }
}

Describe 'ExtGuide actionable failures' {
    It 'categorizes configuration, network, integrity, destination, extraction, discovery, validation, launch, and policy failures' {
        $archive = New-TestExtensionArchive
        $validManifest = New-TestInstallerManifest -ArchiveBytes $archive
        $categories = @()

        $configuration = New-WorkflowTestAdapter -ManifestJson '{"schemaVersion":99}' -ArchiveBytes $archive -LocalApplicationData $TestDrive
        Set-WorkflowTestAdapter $configuration
        $categories += (Invoke-ExtGuideBootstrap $manifestUri).Category

        $network = New-WorkflowTestAdapter -ManifestJson $validManifest -ArchiveBytes $archive -LocalApplicationData $TestDrive
        $network.FetchText = { throw 'offline' }
        Set-WorkflowTestAdapter $network
        $categories += (Invoke-ExtGuideBootstrap $manifestUri).Category

        $integrity = New-WorkflowTestAdapter -ManifestJson (New-TestInstallerManifest -ArchiveBytes ([byte[]](0))) -ArchiveBytes $archive -LocalApplicationData $TestDrive
        Set-WorkflowTestAdapter $integrity
        $categories += (Invoke-ExtGuideBootstrap $manifestUri).Category

        $destination = New-WorkflowTestAdapter -ManifestJson $validManifest -ArchiveBytes $archive -LocalApplicationData $TestDrive
        $destination.TestDestinationWritable = { param($Path) $false }
        Set-WorkflowTestAdapter $destination
        $categories += (Invoke-ExtGuideBootstrap $manifestUri).Category

        $corrupt = [byte[]](1, 2, 3)
        $extraction = New-WorkflowTestAdapter -ManifestJson (New-TestInstallerManifest -ArchiveBytes $corrupt) -ArchiveBytes $corrupt -LocalApplicationData $TestDrive -UseRealInstaller
        Set-WorkflowTestAdapter $extraction
        $categories += (Invoke-ExtGuideBootstrap $manifestUri).Category

        $discovery = New-WorkflowTestAdapter -ManifestJson $validManifest -ArchiveBytes $archive -LocalApplicationData $TestDrive -RunningCandidates @() -RegisteredCandidates @() -ValidChromeCandidates @()
        Set-WorkflowTestAdapter $discovery
        $categories += (Invoke-ExtGuideBootstrap $manifestUri).Category

        $validation = New-WorkflowTestAdapter -ManifestJson $validManifest -ArchiveBytes $archive -LocalApplicationData $TestDrive -RunningCandidates @() -RegisteredCandidates @() -ValidChromeCandidates @() -ChromeChoice 'C:\Fake\chrome.exe'
        Set-WorkflowTestAdapter $validation
        $categories += (Invoke-ExtGuideBootstrap $manifestUri).Category

        $launch = New-WorkflowTestAdapter -ManifestJson $validManifest -ArchiveBytes $archive -LocalApplicationData $TestDrive
        $launch.LaunchChrome = { param($Executable, $Uri) throw 'launch blocked' }
        Set-WorkflowTestAdapter $launch
        $categories += (Invoke-ExtGuideBootstrap $manifestUri).Category

        $policy = New-WorkflowTestAdapter -ManifestJson $validManifest -ArchiveBytes $archive -LocalApplicationData $TestDrive
        $policy.FetchText = {
            $exception = New-Object System.Exception('Script execution is blocked by organizational policy.')
            $exception.Data['ExtGuideCategory'] = 'Policy'
            $exception.Data['ExtGuideRecovery'] = 'Contact your administrator; ExtGuide will not bypass policy.'
            throw $exception
        }
        Set-WorkflowTestAdapter $policy
        $categories += (Invoke-ExtGuideBootstrap $manifestUri).Category

        $categories | Should Be @('Configuration', 'Network', 'Integrity', 'Destination', 'Extraction', 'ChromeDiscovery', 'ExecutableValidation', 'Launch', 'Policy')
    }
}
