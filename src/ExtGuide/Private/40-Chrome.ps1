function ConvertFrom-ExtGuideCommandPath {
    param([string] $Command)

    if ([string]::IsNullOrWhiteSpace($Command)) { return $null }
    $quoted = [regex]::Match($Command, '^\s*"([^"]+\.exe)"')
    if ($quoted.Success) { return $quoted.Groups[1].Value }
    $plain = [regex]::Match($Command, '^\s*([^\s]+\.exe)')
    if ($plain.Success) { return $plain.Groups[1].Value }
    return $null
}

function Get-ExtGuideRunningChromeCandidates {
    $paths = @()
    Get-Process -Name chrome -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $path = $_.Path
            if ([string]::IsNullOrWhiteSpace($path)) { $path = $_.MainModule.FileName }
            if (-not [string]::IsNullOrWhiteSpace($path)) { $paths += $path }
        }
        catch { }
    }
    return $paths
}

function Get-ExtGuideRegistryValue {
    param(
        [Microsoft.Win32.RegistryHive] $Hive,
        [Microsoft.Win32.RegistryView] $View,
        [string] $SubKey,
        [string] $ValueName
    )

    $baseKey = $null
    $key = $null
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $View)
        $key = $baseKey.OpenSubKey($SubKey)
        if ($null -eq $key) { return $null }
        return $key.GetValue($ValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    }
    catch { return $null }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        if ($null -ne $baseKey) { $baseKey.Dispose() }
    }
}

function Get-ExtGuideRegisteredChromeCandidates {
    $candidates = @()
    $hives = @([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryHive]::LocalMachine)
    $views = @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)

    foreach ($hive in $hives) {
        foreach ($view in $views) {
            $appPath = Get-ExtGuideRegistryValue -Hive $hive -View $view -SubKey 'Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe' -ValueName ''
            if ($appPath) { $candidates += [Environment]::ExpandEnvironmentVariables([string] $appPath) }

            $clientRoot = 'Software\Clients\StartMenuInternet'
            $baseKey = $null
            $root = $null
            try {
                $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
                $root = $baseKey.OpenSubKey($clientRoot)
                if ($null -ne $root) {
                    foreach ($clientName in $root.GetSubKeyNames()) {
                        if ($clientName -notmatch 'Chrome') { continue }
                        $command = Get-ExtGuideRegistryValue -Hive $hive -View $view -SubKey "$clientRoot\$clientName\shell\open\command" -ValueName ''
                        $path = ConvertFrom-ExtGuideCommandPath -Command ([string] $command)
                        if ($path) { $candidates += [Environment]::ExpandEnvironmentVariables($path) }
                    }
                }
            }
            catch { }
            finally {
                if ($null -ne $root) { $root.Dispose() }
                if ($null -ne $baseKey) { $baseKey.Dispose() }
            }

            $updateLocation = Get-ExtGuideRegistryValue -Hive $hive -View $view -SubKey 'Software\Google\Update\Clients\{8A69D345-D564-463c-AFF1-A69D9E530F96}' -ValueName 'location'
            if ($updateLocation) { $candidates += (Join-Path ([Environment]::ExpandEnvironmentVariables([string] $updateLocation)) 'chrome.exe') }

            $uninstallRoot = 'Software\Microsoft\Windows\CurrentVersion\Uninstall'
            $baseKey = $null
            $root = $null
            try {
                $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
                $root = $baseKey.OpenSubKey($uninstallRoot)
                if ($null -ne $root) {
                    foreach ($name in $root.GetSubKeyNames()) {
                        $subKey = $root.OpenSubKey($name)
                        try {
                            if ([string] $subKey.GetValue('DisplayName') -notmatch '^Google Chrome') { continue }
                            $location = [string] $subKey.GetValue('InstallLocation')
                            if ($location) { $candidates += (Join-Path ([Environment]::ExpandEnvironmentVariables($location)) 'chrome.exe') }
                            $iconPath = ConvertFrom-ExtGuideCommandPath -Command ([string] $subKey.GetValue('DisplayIcon'))
                            if ($iconPath) { $candidates += [Environment]::ExpandEnvironmentVariables($iconPath) }
                        }
                        finally { if ($null -ne $subKey) { $subKey.Dispose() } }
                    }
                }
            }
            catch { }
            finally {
                if ($null -ne $root) { $root.Dispose() }
                if ($null -ne $baseKey) { $baseKey.Dispose() }
            }
        }
    }

    foreach ($base in @($env:LOCALAPPDATA, $env:PROGRAMFILES, ${env:PROGRAMFILES(X86)})) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        $candidates += (Join-Path $base 'Google\Chrome\Application\chrome.exe')
    }
    return $candidates
}

function Test-ExtGuideChromeExecutable {
    param([Parameter(Mandatory = $true)][string] $Path)

    try {
        $normalized = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path.Trim('"')))
        if (-not (Test-Path -LiteralPath $normalized -PathType Leaf)) { return $false }
        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($normalized)
        if ($versionInfo.ProductName -notmatch '^Google Chrome') { return $false }
        $signature = Get-AuthenticodeSignature -LiteralPath $normalized -ErrorAction Stop
        if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or $null -eq $signature.SignerCertificate) { return $false }
        return $signature.SignerCertificate.Subject -match 'O=Google (LLC|Inc)'
    }
    catch { return $false }
}

function Initialize-ExtGuideForegroundInterop {
    if ('ExtGuide.Native.ForegroundWindow' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace ExtGuide.Native {
    public static class ForegroundWindow {
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    }
}
'@ -ErrorAction Stop
}

function Get-ExtGuideWindowExecutable {
    param([Parameter(Mandatory = $true)][IntPtr] $Handle)

    Initialize-ExtGuideForegroundInterop
    [uint32] $processId = 0
    $null = [ExtGuide.Native.ForegroundWindow]::GetWindowThreadProcessId($Handle, [ref] $processId)
    if ($processId -eq 0) { return $null }
    try { return (Get-Process -Id $processId -ErrorAction Stop).Path }
    catch { return $null }
}

function Find-ExtGuideChromeWindow {
    param(
        [Parameter(Mandatory = $true)][string] $Executable,
        [int] $TimeoutMilliseconds = 3000
    )

    Initialize-ExtGuideForegroundInterop
    $expected = [System.IO.Path]::GetFullPath($Executable)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    do {
        $foreground = [ExtGuide.Native.ForegroundWindow]::GetForegroundWindow()
        if ($foreground -ne [IntPtr]::Zero) {
            $foregroundExecutable = Get-ExtGuideWindowExecutable -Handle $foreground
            if (-not [string]::IsNullOrWhiteSpace($foregroundExecutable) -and
                [string]::Equals([System.IO.Path]::GetFullPath($foregroundExecutable), $expected, [System.StringComparison]::OrdinalIgnoreCase)) {
                return [pscustomobject]@{ Handle = $foreground; Executable = $foregroundExecutable }
            }
        }

        $candidates = @(Get-Process -Name chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Sort-Object StartTime -Descending)
        foreach ($candidate in $candidates) {
            try { $candidateExecutable = $candidate.Path }
            catch { continue }
            if (-not [string]::IsNullOrWhiteSpace($candidateExecutable) -and
                [string]::Equals([System.IO.Path]::GetFullPath($candidateExecutable), $expected, [System.StringComparison]::OrdinalIgnoreCase)) {
                return [pscustomobject]@{ Handle = [IntPtr] $candidate.MainWindowHandle; Executable = $candidateExecutable }
            }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    return $null
}

function Initialize-ExtGuideUiAutomation {
    if ('System.Windows.Automation.AutomationElement' -as [type]) { return }
    Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
    Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
}

function Get-ExtGuideChromeAutomationRoot {
    param([Parameter(Mandatory = $true)][IntPtr] $Handle)

    Initialize-ExtGuideUiAutomation
    return [System.Windows.Automation.AutomationElement]::FromHandle($Handle)
}

function Find-ExtGuideChromeAddressBar {
    param([Parameter(Mandatory = $true)][IntPtr] $Handle)

    $root = Get-ExtGuideChromeAutomationRoot -Handle $Handle
    if ($null -eq $root) { return $null }
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ClassNameProperty,
        'OmniboxViewViews'
    )
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
}

function Set-ExtGuideChromeAddressBarValue {
    param(
        [Parameter(Mandatory = $true)] $AddressBar,
        [Parameter(Mandatory = $true)][string] $Value
    )

    Initialize-ExtGuideUiAutomation
    $pattern = $null
    if (-not $AddressBar.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref] $pattern)) {
        throw 'The verified Chrome address bar does not support direct value injection.'
    }
    if ($pattern.Current.IsReadOnly) { throw 'The verified Chrome address bar is read-only.' }
    $AddressBar.SetFocus()
    $pattern.SetValue($Value)
    $actual = [string] $pattern.Current.Value
    if (-not [string]::Equals($actual.TrimEnd('/'), $Value.TrimEnd('/'), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Chrome did not retain the injected extensions page address.'
    }
}

function Find-ExtGuideChromeAddressSuggestion {
    param(
        [Parameter(Mandatory = $true)][IntPtr] $Handle,
        [Parameter(Mandatory = $true)][string] $Uri,
        [int] $TimeoutMilliseconds = 2000
    )

    Initialize-ExtGuideUiAutomation
    $target = $Uri.TrimEnd('/')
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    do {
        $root = Get-ExtGuideChromeAutomationRoot -Handle $Handle
        $condition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::ListItem
        )
        $items = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
        for ($index = 0; $index -lt $items.Count; $index++) {
            $candidate = $items.Item($index)
            $name = [string] $candidate.Current.Name
            if (-not $name.StartsWith($target, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $remainder = $name.Substring($target.Length)
            if ($remainder.Length -gt 0 -and $remainder[0] -match '[A-Za-z0-9_-]') { continue }
            $pattern = $null
            if ($candidate.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref] $pattern)) { return $candidate }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    return $null
}

function Get-ExtGuideChromeSelectedTab {
    param([Parameter(Mandatory = $true)][IntPtr] $Handle)

    Initialize-ExtGuideUiAutomation
    $root = Get-ExtGuideChromeAutomationRoot -Handle $Handle
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::TabItem
    )
    $tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
    for ($index = 0; $index -lt $tabs.Count; $index++) {
        $tab = $tabs.Item($index)
        $pattern = $null
        if ($tab.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref] $pattern) -and $pattern.Current.IsSelected) {
            return $tab
        }
    }
    return $null
}

function Test-ExtGuideAutomationElementSelected {
    param([Parameter(Mandatory = $true)] $Element)

    try {
        $pattern = $null
        return $Element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref] $pattern) -and $pattern.Current.IsSelected
    }
    catch { return $false }
}

function Invoke-ExtGuideAutomationElement {
    param([Parameter(Mandatory = $true)] $Element)

    Initialize-ExtGuideUiAutomation
    $pattern = $null
    if (-not $Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref] $pattern)) {
        throw 'The Chrome automation element does not support its native invoke action.'
    }
    $pattern.Invoke()
}

function Close-ExtGuideChromeTab {
    param([Parameter(Mandatory = $true)] $Tab)

    Initialize-ExtGuideUiAutomation
    try {
        $condition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ClassNameProperty,
            'TabCloseButton'
        )
        $closeButton = $Tab.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
        if ($null -ne $closeButton) { Invoke-ExtGuideAutomationElement -Element $closeButton }
    }
    catch { }
}

function New-ExtGuideChromeNavigationOperations {
    return @{
        StartChrome = { param($Executable, $Uri) Start-Process -FilePath $Executable -ArgumentList $Uri -PassThru }
        FindChromeWindow = { param($Executable) Find-ExtGuideChromeWindow -Executable $Executable }
        RestoreWindow = { param($Handle) Initialize-ExtGuideForegroundInterop; [ExtGuide.Native.ForegroundWindow]::ShowWindow($Handle, 9) }
        ActivateWindow = { param($Handle) Initialize-ExtGuideForegroundInterop; [ExtGuide.Native.ForegroundWindow]::SetForegroundWindow($Handle) }
        GetForegroundWindow = { Initialize-ExtGuideForegroundInterop; [ExtGuide.Native.ForegroundWindow]::GetForegroundWindow() }
        GetWindowExecutable = { param($Handle) Get-ExtGuideWindowExecutable -Handle $Handle }
        GetSelectedTab = { param($Handle) Get-ExtGuideChromeSelectedTab -Handle $Handle }
        FindAddressBar = { param($Handle) Find-ExtGuideChromeAddressBar -Handle $Handle }
        SetAddressBarValue = { param($AddressBar, $Value) Set-ExtGuideChromeAddressBarValue -AddressBar $AddressBar -Value $Value }
        FindAddressSuggestion = { param($Handle, $Uri) Find-ExtGuideChromeAddressSuggestion -Handle $Handle -Uri $Uri }
        InvokeElement = { param($Element) Invoke-ExtGuideAutomationElement -Element $Element }
        IsElementSelected = { param($Element) Test-ExtGuideAutomationElementSelected -Element $Element }
        CloseElement = { param($Element) Close-ExtGuideChromeTab -Tab $Element }
        Delay = { param($Milliseconds) Start-Sleep -Milliseconds $Milliseconds }
    }
}

function Open-ExtGuideChromeExtensionsPage {
    param(
        [Parameter(Mandatory = $true)][string] $Executable,
        [string] $Uri = 'chrome://extensions/',
        [hashtable] $Operations = (New-ExtGuideChromeNavigationOperations)
    )

    $requiredOperations = @('StartChrome', 'FindChromeWindow', 'RestoreWindow', 'ActivateWindow', 'GetForegroundWindow', 'GetWindowExecutable', 'GetSelectedTab', 'FindAddressBar', 'SetAddressBarValue', 'FindAddressSuggestion', 'InvokeElement', 'IsElementSelected', 'CloseElement', 'Delay')
    foreach ($name in $requiredOperations) {
        if (-not $Operations.ContainsKey($name) -or $Operations[$name] -isnot [scriptblock]) {
            throw "Chrome navigation operation '$name' is unavailable."
        }
    }

    $null = & $Operations.StartChrome $Executable 'about:blank'
    $null = & $Operations.Delay 900
    $window = & $Operations.FindChromeWindow $Executable
    if ($null -eq $window -or [IntPtr] $window.Handle -eq [IntPtr]::Zero) {
        throw 'ExtGuide could not find a Chrome window after starting Chrome.'
    }

    $handle = [IntPtr] $window.Handle
    $null = & $Operations.RestoreWindow $handle
    if (-not (& $Operations.ActivateWindow $handle)) {
        throw 'ExtGuide could not activate the verified Chrome window.'
    }
    $null = & $Operations.Delay 200

    $foreground = [IntPtr] (& $Operations.GetForegroundWindow)
    $foregroundExecutable = & $Operations.GetWindowExecutable $foreground
    if ($foreground -ne $handle -or [string]::IsNullOrWhiteSpace([string] $foregroundExecutable) -or
        -not [string]::Equals([System.IO.Path]::GetFullPath([string] $foregroundExecutable), [System.IO.Path]::GetFullPath($Executable), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'ExtGuide did not inject the address because the foreground window was not the verified Chrome executable.'
    }

    $createdTab = & $Operations.GetSelectedTab $handle
    $addressBar = & $Operations.FindAddressBar $handle
    if ($null -eq $addressBar) { throw 'ExtGuide could not locate the verified Chrome address bar.' }
    $null = & $Operations.SetAddressBarValue $addressBar $Uri
    $null = & $Operations.Delay 300
    $suggestion = & $Operations.FindAddressSuggestion $handle $Uri
    if ($null -eq $suggestion) { throw 'ExtGuide could not locate Chrome navigation for the injected extensions page address.' }
    $null = & $Operations.InvokeElement $suggestion
    $null = & $Operations.Delay 300
    if ($null -ne $createdTab -and -not (& $Operations.IsElementSelected $createdTab)) {
        $null = & $Operations.CloseElement $createdTab
    }
    return [pscustomobject]@{
        Executable = $Executable
        Uri = $Uri
        NavigationMethod = 'UiAutomationValueAndInvoke'
        KeyboardSimulation = $false
    }
}

function Get-ExtGuideManagedPolicyNotice {
    $messages = @()
    foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryHive]::LocalMachine)) {
        $developerTools = Get-ExtGuideRegistryValue -Hive $hive -View ([Microsoft.Win32.RegistryView]::Default) -SubKey 'Software\Policies\Google\Chrome' -ValueName 'DeveloperToolsAvailability'
        if ($null -ne $developerTools -and [int] $developerTools -eq 2) { $messages += Get-ExtGuideText -Key 'ManagedDeveloperTools' }
        $blockList = Get-ExtGuideRegistryValue -Hive $hive -View ([Microsoft.Win32.RegistryView]::Default) -SubKey 'Software\Policies\Google\Chrome\ExtensionInstallBlocklist' -ValueName '1'
        if ([string] $blockList -eq '*') { $messages += Get-ExtGuideText -Key 'ManagedExtensions' }
    }
    return ($messages | Select-Object -Unique) -join ' '
}
