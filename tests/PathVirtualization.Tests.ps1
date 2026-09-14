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
}
