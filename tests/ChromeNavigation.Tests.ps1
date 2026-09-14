$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'src\ExtGuide\ExtGuide.psd1') -Force
$module = Get-Module -Name ExtGuide

Describe 'Chrome extensions navigation' {
    It 'opens a safe page before navigating the verified foreground Chrome window' {
        $state = @{
            Started = @()
            Restored = @()
            Activated = @()
            AddressValues = @()
            Invoked = @()
            Closed = @()
            Delays = @()
        }
        $chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
        $operations = @{
            StartChrome = { param($Executable, $Uri) $state.Started += [pscustomobject]@{ Executable = $Executable; Uri = $Uri } }.GetNewClosure()
            FindChromeWindow = { param($Executable) [pscustomobject]@{ Handle = [IntPtr]42; Executable = $Executable } }
            RestoreWindow = { param($Handle) $state.Restored += $Handle }.GetNewClosure()
            ActivateWindow = { param($Handle) $state.Activated += $Handle; $true }.GetNewClosure()
            GetForegroundWindow = { [IntPtr]42 }
            GetWindowExecutable = { param($Handle) $chrome }.GetNewClosure()
            GetSelectedTab = { param($Handle) 'new-tab' }
            FindAddressBar = { param($Handle) 'address-bar' }
            SetAddressBarValue = { param($AddressBar, $Value) $state.AddressValues += [pscustomobject]@{ Element = $AddressBar; Value = $Value } }.GetNewClosure()
            FindAddressSuggestion = { param($Handle, $Uri) 'extensions-suggestion' }
            InvokeElement = { param($Element) $state.Invoked += $Element }.GetNewClosure()
            IsElementSelected = { param($Element) $false }
            CloseElement = { param($Element) $state.Closed += $Element }.GetNewClosure()
            Delay = { param($Milliseconds) $state.Delays += $Milliseconds }.GetNewClosure()
        }

        $result = & $module {
            param($Executable, $HostOperations)
            Open-ExtGuideChromeExtensionsPage -Executable $Executable -Uri 'chrome://extensions/' -Operations $HostOperations
        } $chrome $operations

        $state.Started.Count | Should Be 1
        $state.Started[0].Executable | Should Be $chrome
        $state.Started[0].Uri | Should Be 'about:blank'
        $state.Restored | Should Be @([IntPtr]42)
        $state.Activated | Should Be @([IntPtr]42)
        $state.AddressValues.Count | Should Be 1
        $state.AddressValues[0].Element | Should Be 'address-bar'
        $state.AddressValues[0].Value | Should Be 'chrome://extensions/'
        $state.Invoked | Should Be @('extensions-suggestion')
        $state.Closed | Should Be @('new-tab')
        ($state.Delays -join ',') | Should Be '900,200,300,300'
        $result.NavigationMethod | Should Be 'UiAutomationValueAndInvoke'
        $result.KeyboardSimulation | Should Be $false
    }

    It 'does not inject an address when the foreground window is not the verified Chrome executable' {
        $state = @{ AddressValues = @() }
        $chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
        $operations = @{
            StartChrome = { param($Executable, $Uri) }
            FindChromeWindow = { param($Executable) [pscustomobject]@{ Handle = [IntPtr]42; Executable = $Executable } }
            RestoreWindow = { param($Handle) }
            ActivateWindow = { param($Handle) $true }
            GetForegroundWindow = { [IntPtr]99 }
            GetWindowExecutable = { param($Handle) 'C:\Windows\System32\notepad.exe' }
            GetSelectedTab = { param($Handle) 'new-tab' }
            FindAddressBar = { param($Handle) 'address-bar' }
            SetAddressBarValue = { param($AddressBar, $Value) $state.AddressValues += $Value }.GetNewClosure()
            FindAddressSuggestion = { param($Handle, $Uri) 'extensions-suggestion' }
            InvokeElement = { param($Element) }
            IsElementSelected = { param($Element) $false }
            CloseElement = { param($Element) }
            Delay = { param($Milliseconds) }
        }

        $caught = $null
        try {
            & $module {
                param($Executable, $HostOperations)
                Open-ExtGuideChromeExtensionsPage -Executable $Executable -Uri 'chrome://extensions/' -Operations $HostOperations
            } $chrome $operations
        }
        catch { $caught = $_ }
        $caught | Should Not BeNullOrEmpty
        $caught.Exception.Message | Should Match 'foreground window was not the verified Chrome executable'
        $state.AddressValues.Count | Should Be 0
    }
}
