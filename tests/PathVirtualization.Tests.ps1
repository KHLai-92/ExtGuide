$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'src\ExtGuide\ExtGuide.psd1') -Force

Describe 'ExtGuide Windows path virtualization handling' {
    It 'delegates archive installation when Windows redirects the requested destination' {
        $module = Get-Module -Name ExtGuide
        $calls = New-Object System.Collections.ArrayList
        $detector = { param($Path) $null = $calls.Add("detect:$Path"); $true }.GetNewClosure()
        $delegated = {
            param($Bytes, $Destination, $Root)
            $null = $calls.Add("delegate:$Destination")
            [pscustomobject]@{ ExtensionRoot = Join-Path $Destination $Root; Content = @{}; WasUpdate = $false }
        }.GetNewClosure()
        $direct = { param($Bytes, $Destination, $Root) throw 'The virtualized process must not write the extension directly.' }

        $result = & $module {
            param($Bytes, $Destination, $Root, $Detector, $Delegated, $Direct)
            Install-ExtGuideArchiveForWindows -ArchiveBytes $Bytes -Destination $Destination -ExtensionRoot $Root -VirtualizationDetector $Detector -OutOfProcessInstaller $Delegated -InProcessInstaller $Direct
        } ([byte[]](1, 2, 3)) 'C:\Users\Example\AppData\Local\Publisher\Extension' 'extension' $detector $delegated $direct

        $calls | Should Be @(
            'detect:C:\Users\Example\AppData\Local\Publisher\Extension',
            'delegate:C:\Users\Example\AppData\Local\Publisher\Extension'
        )
        $result.ExtensionRoot | Should Be 'C:\Users\Example\AppData\Local\Publisher\Extension\extension'
    }

    It 'keeps ordinary filesystem writes in the current process' {
        $module = Get-Module -Name ExtGuide
        $calls = New-Object System.Collections.ArrayList
        $detector = { param($Path) $false }
        $delegated = { param($Bytes, $Destination, $Root) throw 'An ordinary process must not use WMI.' }
        $direct = {
            param($Bytes, $Destination, $Root)
            $null = $calls.Add("direct:$Destination")
            [pscustomobject]@{ ExtensionRoot = Join-Path $Destination $Root; Content = @{}; WasUpdate = $false }
        }.GetNewClosure()

        $null = & $module {
            param($Bytes, $Destination, $Root, $Detector, $Delegated, $Direct)
            Install-ExtGuideArchiveForWindows -ArchiveBytes $Bytes -Destination $Destination -ExtensionRoot $Root -VirtualizationDetector $Detector -OutOfProcessInstaller $Delegated -InProcessInstaller $Direct
        } ([byte[]](1, 2, 3)) 'C:\Extensions\Sample' 'extension' $detector $delegated $direct

        $calls | Should Be @('direct:C:\Extensions\Sample')
    }

    It 'routes only the archive writer through the elevated installer when requested' {
        $module = Get-Module -Name ExtGuide
        $calls = New-Object System.Collections.ArrayList
        $context = [pscustomobject]@{ UseElevation = $true; IntegrationId = 'example.sample'; Publisher = 'Example'; InstallFolderName = 'Sample'; ArchiveSha256 = 'abc'; ExpectedVersion = '1.0.0' }
        $detector = { param($Path) throw 'Elevation routing must happen before virtualization probing.' }
        $elevated = {
            param($Bytes, $Destination, $Root, $InstallContext)
            $null = $calls.Add("elevated:${Destination}:$($InstallContext.IntegrationId)")
            [pscustomobject]@{ ExtensionRoot = Join-Path $Destination $Root; Content = @{}; WasUpdate = $true }
        }.GetNewClosure()

        $result = & $module {
            param($Bytes, $Destination, $Root, $Context, $Detector, $Elevated)
            Install-ExtGuideArchiveForWindows -ArchiveBytes $Bytes -Destination $Destination -ExtensionRoot $Root -InstallContext $Context -VirtualizationDetector $Detector -ElevatedInstaller $Elevated
        } ([byte[]](1, 2, 3)) 'C:\Protected\Sample' 'extension' $context $detector $elevated

        $calls | Should Be @('elevated:C:\Protected\Sample:example.sample')
        $result.WasUpdate | Should Be $true
    }

    It 'builds a parseable standalone worker from the validated archive installer' {
        $module = Get-Module -Name ExtGuide
        $source = & $module { Get-ExtGuideInstallWorkerSource }
        $tokens = $null
        $errors = $null

        $null = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref] $tokens, [ref] $errors)

        $errors.Count | Should Be 0
        $source | Should Match 'Install-ExtGuideArchive'
        $source | Should Match 'ConvertTo-Json'
    }

    It 'builds a parseable unvirtualized settings worker' {
        $module = Get-Module -Name ExtGuide
        $source = & $module { Get-ExtGuideSettingsWorkerSource }
        $tokens = $null
        $errors = $null

        $null = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref] $tokens, [ref] $errors)

        $errors.Count | Should Be 0
        $source | Should Match "Operation -eq 'Read'"
        $source | Should Match "Operation -eq 'Write'"
    }
}
