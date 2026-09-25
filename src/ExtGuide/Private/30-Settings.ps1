function Get-ExtGuideSettingsPath {
    return Join-Path (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ExtGuide') 'settings.json'
}

function Get-ExtGuideSettingsWorkerSource {
    return @'
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string] $JobPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$job = Get-Content -LiteralPath $JobPath -Raw | ConvertFrom-Json -ErrorAction Stop
try {
    if ([string] $job.Operation -eq 'Read') {
        $exists = Test-Path -LiteralPath ([string] $job.SettingsPath) -PathType Leaf
        $settingsJson = if ($exists) { [System.IO.File]::ReadAllText([string] $job.SettingsPath) } else { '' }
        $payload = [ordered]@{ Succeeded = $true; Exists = $exists; SettingsJson = $settingsJson }
    }
    elseif ([string] $job.Operation -eq 'Write') {
        $settingsPath = [System.IO.Path]::GetFullPath([string] $job.SettingsPath)
        $directory = Split-Path -Parent $settingsPath
        $null = New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop
        $temporary = $settingsPath + '.tmp-' + [guid]::NewGuid().ToString('N')
        try {
            [System.IO.File]::WriteAllText($temporary, [string] $job.SettingsJson, (New-Object System.Text.UTF8Encoding($true)))
            Move-Item -LiteralPath $temporary -Destination $settingsPath -Force -ErrorAction Stop
        }
        finally {
            if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
        }
        $payload = [ordered]@{ Succeeded = $true; Exists = $true; SettingsJson = '' }
    }
    else {
        throw "Unsupported settings operation '$($job.Operation)'."
    }
}
catch {
    $payload = [ordered]@{ Succeeded = $false; Message = $_.Exception.Message }
}

[System.IO.File]::WriteAllText([string] $job.ResultPath, ($payload | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($true)))
'@
}

function Invoke-ExtGuideSettingsIoOutOfProcess {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Read', 'Write')][string] $Operation,
        [Parameter(Mandatory = $true)][string] $SettingsPath,
        [string] $SettingsJson = ''
    )

    $jobDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('ExtGuide-settings-' + [guid]::NewGuid().ToString('N'))
    try {
        $null = New-Item -ItemType Directory -Path $jobDirectory -Force -ErrorAction Stop
        $workerPath = Join-Path $jobDirectory 'worker.ps1'
        $jobPath = Join-Path $jobDirectory 'job.json'
        $resultPath = Join-Path $jobDirectory 'result.json'
        [System.IO.File]::WriteAllText($workerPath, (Get-ExtGuideSettingsWorkerSource), (New-Object System.Text.UTF8Encoding($true)))
        [System.IO.File]::WriteAllText($resultPath, '')

        $physicalWorkerPath = Get-ExtGuideFinalPath -Path $workerPath
        $physicalResultPath = Get-ExtGuideFinalPath -Path $resultPath
        $job = [ordered]@{
            Operation = $Operation
            SettingsPath = [System.IO.Path]::GetFullPath($SettingsPath)
            SettingsJson = $SettingsJson
            ResultPath = $physicalResultPath
        }
        [System.IO.File]::WriteAllText($jobPath, ($job | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($true)))
        $physicalJobPath = Get-ExtGuideFinalPath -Path $jobPath
        $workerCommand = "& '$($physicalWorkerPath.Replace("'", "''"))' -JobPath '$($physicalJobPath.Replace("'", "''"))'"
        $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($workerCommand))
        $powerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $commandLine = '"{0}" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand {1}' -f $powerShell, $encodedCommand
        $null = Start-ExtGuideUnvirtualizedProcess -CommandLine $commandLine

        $deadline = [DateTime]::UtcNow.AddMinutes(1)
        while ([DateTime]::UtcNow -lt $deadline) {
            if ((Get-Item -LiteralPath $resultPath -ErrorAction SilentlyContinue).Length -gt 0) { break }
            Start-Sleep -Milliseconds 100
        }
        if ((Get-Item -LiteralPath $resultPath -ErrorAction SilentlyContinue).Length -le 0) {
            Throw-ExtGuideError -Category 'Destination' -Message 'The unvirtualized settings operation did not finish in time.' -Recovery 'Run ExtGuide again from a regular Windows PowerShell window.'
        }
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if (-not [bool] $result.Succeeded) {
            Throw-ExtGuideError -Category 'Destination' -Message 'ExtGuide could not access its real per-user settings file.' -Recovery 'Run ExtGuide again from a regular Windows PowerShell window.'
        }
        return $result
    }
    finally {
        Remove-ExtGuideInstallJobDirectory -JobDirectory $jobDirectory
    }
}

function Test-ExtGuideSettingsPathVirtualized {
    param([Parameter(Mandatory = $true)][string] $Path)
    try { return Test-ExtGuidePathVirtualized -Destination $Path }
    catch { return $false }
}

function Read-ExtGuideSettings {
    $path = Get-ExtGuideSettingsPath
    try {
        $json = $null
        if (Test-ExtGuideSettingsPathVirtualized -Path $path) {
            $result = Invoke-ExtGuideSettingsIoOutOfProcess -Operation 'Read' -SettingsPath $path
            if ([bool] $result.Exists) {
                $json = [string] $result.SettingsJson
            }
            elseif (Test-Path -LiteralPath $path -PathType Leaf) {
                $json = Get-Content -LiteralPath $path -Raw
                $null = Invoke-ExtGuideSettingsIoOutOfProcess -Operation 'Write' -SettingsPath $path -SettingsJson $json
            }
        }
        elseif (Test-Path -LiteralPath $path -PathType Leaf) {
            $json = Get-Content -LiteralPath $path -Raw
        }
        if ([string]::IsNullOrWhiteSpace($json)) { return @{ destinations = @{}; chromePath = $null } }
        $raw = $json | ConvertFrom-Json -ErrorAction Stop
        $destinations = @{}
        if ($null -ne $raw.destinations) {
            foreach ($property in $raw.destinations.PSObject.Properties) { $destinations[$property.Name] = [string] $property.Value }
        }
        return @{ destinations = $destinations; chromePath = [string] $raw.chromePath }
    }
    catch { return @{ destinations = @{}; chromePath = $null } }
}

function Write-ExtGuideSettings {
    param([Parameter(Mandatory = $true)][hashtable] $Settings)

    $path = Get-ExtGuideSettingsPath
    $json = $Settings | ConvertTo-Json -Depth 5
    if (Test-ExtGuideSettingsPathVirtualized -Path $path) {
        $null = Invoke-ExtGuideSettingsIoOutOfProcess -Operation 'Write' -SettingsPath $path -SettingsJson $json
        return
    }
    $directory = Split-Path -Parent $path
    $null = New-Item -ItemType Directory -Path $directory -Force
    $temporary = $path + '.tmp-' + [guid]::NewGuid().ToString('N')
    try {
        $json | Set-Content -LiteralPath $temporary -Encoding UTF8
        Move-Item -LiteralPath $temporary -Destination $path -Force
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}

function Get-ExtGuideSettingsKey { param($Manifest) return ([string] $Manifest.publisher + '|' + [string] $Manifest.installFolderName) }
function Get-ExtGuideRememberedDestination { param($Manifest) $settings = Read-ExtGuideSettings; return [string] $settings.destinations[(Get-ExtGuideSettingsKey -Manifest $Manifest)] }
function Set-ExtGuideRememberedDestination { param($Manifest, [string] $Destination) $settings = Read-ExtGuideSettings; $settings.destinations[(Get-ExtGuideSettingsKey -Manifest $Manifest)] = $Destination; Write-ExtGuideSettings -Settings $settings }
function Get-ExtGuideRememberedChrome { return [string] (Read-ExtGuideSettings).chromePath }
function Set-ExtGuideRememberedChrome { param([string] $Path) $settings = Read-ExtGuideSettings; $settings.chromePath = $Path; Write-ExtGuideSettings -Settings $settings }
