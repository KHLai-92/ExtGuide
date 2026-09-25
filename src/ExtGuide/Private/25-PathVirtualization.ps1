function Initialize-ExtGuideNativePathMethods {
    if ('ExtGuide.NativePathMethods' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace ExtGuide {
    public static class NativePathMethods {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern SafeFileHandle CreateFile(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern uint GetFinalPathNameByHandle(
            SafeFileHandle file,
            System.Text.StringBuilder path,
            uint pathLength,
            uint flags);
    }
}
'@
}

function ConvertFrom-ExtGuideDevicePath {
    param([Parameter(Mandatory = $true)][string] $Path)

    if ($Path.StartsWith('\\?\UNC\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return '\\' + $Path.Substring(8)
    }
    if ($Path.StartsWith('\\?\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring(4)
    }
    return $Path
}

function Get-ExtGuideFinalPath {
    param([Parameter(Mandatory = $true)][string] $Path)

    Initialize-ExtGuideNativePathMethods
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $flags = if (Test-Path -LiteralPath $fullPath -PathType Container) { [uint32] 0x02000000 } else { [uint32] 0x00000080 }
    $handle = [ExtGuide.NativePathMethods]::CreateFile($fullPath, 0, 7, [IntPtr]::Zero, 3, $flags, [IntPtr]::Zero)
    try {
        if ($handle.IsInvalid) {
            throw "CreateFile failed for '$fullPath': $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        }
        $buffer = New-Object System.Text.StringBuilder 32768
        $length = [ExtGuide.NativePathMethods]::GetFinalPathNameByHandle($handle, $buffer, $buffer.Capacity, 0)
        if ($length -eq 0) {
            throw "GetFinalPathNameByHandle failed for '$fullPath': $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        }
        return ConvertFrom-ExtGuideDevicePath -Path $buffer.ToString()
    }
    finally {
        $handle.Dispose()
    }
}

function Test-ExtGuidePathVirtualized {
    param([Parameter(Mandatory = $true)][string] $Destination)

    $parent = Split-Path -Parent ([System.IO.Path]::GetFullPath($Destination))
    $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop
    $probePath = Join-Path $parent ('.extguide-path-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($probePath, 'ExtGuide path probe')
        $requestedPath = [System.IO.Path]::GetFullPath($probePath)
        $finalPath = Get-ExtGuideFinalPath -Path $probePath
        return -not $requestedPath.Equals($finalPath, [System.StringComparison]::OrdinalIgnoreCase)
    }
    finally {
        if (Test-Path -LiteralPath $probePath -PathType Leaf) {
            Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-ExtGuideInstallWorkerSource {
    $parts = @(
        @'
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string] $JobPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
'@
    )
    foreach ($functionName in @(
        'New-ExtGuideException',
        'Throw-ExtGuideError',
        'Get-ExtGuideSha256',
        'Expand-ExtGuideArchiveSafely',
        'Get-ExtGuideExtensionManifest',
        'Get-ExtGuideUpdateJournalPath',
        'Write-ExtGuideUpdateJournal',
        'Test-ExtGuideTransactionPath',
        'Repair-ExtGuideInterruptedUpdate',
        'Read-ExtGuideInstallationReceipt',
        'Install-ExtGuideArchive'
    )) {
        $definition = (Get-Command -Name $functionName -CommandType Function -ErrorAction Stop).Definition
        $parts += "function $functionName {`r`n$definition`r`n}"
    }
    $parts += @'
$job = Get-Content -LiteralPath $JobPath -Raw | ConvertFrom-Json -ErrorAction Stop
try {
    [byte[]] $archiveBytes = [System.IO.File]::ReadAllBytes([string] $job.ArchivePath)
    if ((Get-ExtGuideSha256 -Bytes $archiveBytes) -ne [string] $job.ArchiveSha256) {
        Throw-ExtGuideError -Category 'Integrity' -Message 'The elevated installer received archive bytes that do not match the verified digest.' -Recovery 'Cancel the installation and run ExtGuide again.'
    }
    $installation = Install-ExtGuideArchive `
        -ArchiveBytes $archiveBytes `
        -Destination ([string] $job.Destination) `
        -ExtensionRoot ([string] $job.ExtensionRoot) `
        -IntegrationId ([string] $job.IntegrationId) `
        -Publisher ([string] $job.Publisher) `
        -InstallFolderName ([string] $job.InstallFolderName) `
        -ArchiveSha256 ([string] $job.ArchiveSha256) `
        -ExpectedVersion ([string] $job.ExpectedVersion)
    $payload = [ordered]@{
        Succeeded = $true
        ExtensionRoot = [string] $installation.ExtensionRoot
        Content = $installation.Content
        WasUpdate = [bool] $installation.WasUpdate
        PreviousVersion = [string] $installation.PreviousVersion
        InstalledVersion = [string] $installation.InstalledVersion
    }
}
catch {
    $category = [string] $_.Exception.Data['ExtGuideCategory']
    $recovery = [string] $_.Exception.Data['ExtGuideRecovery']
    if ([string]::IsNullOrWhiteSpace($category)) { $category = 'Destination' }
    if ([string]::IsNullOrWhiteSpace($recovery)) { $recovery = 'Run ExtGuide again from a regular Windows PowerShell window.' }
    $payload = [ordered]@{
        Succeeded = $false
        Category = $category
        Message = $_.Exception.Message
        Recovery = $recovery
    }
}

$json = $payload | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText([string] $job.ResultPath, $json, (New-Object System.Text.UTF8Encoding($true)))
'@
    return $parts -join "`r`n`r`n"
}

function Start-ExtGuideUnvirtualizedProcess {
    param([Parameter(Mandatory = $true)][string] $CommandLine)

    try {
        $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $CommandLine } -ErrorAction Stop
    }
    catch {
        Throw-ExtGuideError -Category 'Destination' -Message 'Windows could not start an unvirtualized extension installer.' -Recovery 'Run ExtGuide again from a regular Windows PowerShell window outside the packaged application.' -InnerException $_.Exception
    }
    if ([int] $result.ReturnValue -ne 0) {
        Throw-ExtGuideError -Category 'Destination' -Message "Windows could not start the extension installer (WMI return code $($result.ReturnValue))." -Recovery 'Run ExtGuide again from a regular Windows PowerShell window outside the packaged application.'
    }
    return [int] $result.ProcessId
}

function Start-ExtGuideElevatedProcess {
    param(
        [Parameter(Mandatory = $true)][string] $PowerShellPath,
        [Parameter(Mandatory = $true)][string] $EncodedCommand
    )

    try {
        $process = Start-Process -FilePath $PowerShellPath -ArgumentList @('-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $EncodedCommand) -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop
        return [int] $process.Id
    }
    catch {
        $exception = New-ExtGuideException -Category 'Destination' -Message 'Windows did not grant administrator permission for the selected installation location.' -Recovery 'Choose another folder, or try again and approve the Windows permission prompt.' -InnerException $_.Exception
        $exception.Data['ExtGuideElevationDeclined'] = $true
        throw $exception
    }
}

function Remove-ExtGuideInstallJobDirectory {
    param([Parameter(Mandatory = $true)][string] $JobDirectory)

    $fullJobDirectory = [System.IO.Path]::GetFullPath($JobDirectory)
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $leaf = Split-Path -Leaf $fullJobDirectory
    if ($fullJobDirectory.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and $leaf -match '^ExtGuide-(install|settings)-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $fullJobDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-ExtGuideArchiveOutOfProcess {
    param(
        [Parameter(Mandatory = $true)][byte[]] $ArchiveBytes,
        [Parameter(Mandatory = $true)][string] $Destination,
        [Parameter(Mandatory = $true)][string] $ExtensionRoot,
        [Parameter(Mandatory = $true)] $InstallContext,
        [switch] $Elevated
    )

    $jobDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('ExtGuide-install-' + [guid]::NewGuid().ToString('N'))
    try {
        $null = New-Item -ItemType Directory -Path $jobDirectory -Force -ErrorAction Stop
        $workerPath = Join-Path $jobDirectory 'worker.ps1'
        $archivePath = Join-Path $jobDirectory 'extension.zip'
        $jobPath = Join-Path $jobDirectory 'job.json'
        $resultPath = Join-Path $jobDirectory 'result.json'

        [System.IO.File]::WriteAllText($workerPath, (Get-ExtGuideInstallWorkerSource), (New-Object System.Text.UTF8Encoding($true)))
        [System.IO.File]::WriteAllBytes($archivePath, $ArchiveBytes)
        [System.IO.File]::WriteAllText($resultPath, '')

        $physicalWorkerPath = Get-ExtGuideFinalPath -Path $workerPath
        $physicalArchivePath = Get-ExtGuideFinalPath -Path $archivePath
        $physicalResultPath = Get-ExtGuideFinalPath -Path $resultPath
        $job = [ordered]@{
            ArchivePath = $physicalArchivePath
            Destination = [System.IO.Path]::GetFullPath($Destination)
            ExtensionRoot = $ExtensionRoot
            ResultPath = $physicalResultPath
            IntegrationId = [string] $InstallContext.IntegrationId
            Publisher = [string] $InstallContext.Publisher
            InstallFolderName = [string] $InstallContext.InstallFolderName
            ArchiveSha256 = [string] $InstallContext.ArchiveSha256
            ExpectedVersion = [string] $InstallContext.ExpectedVersion
        }
        [System.IO.File]::WriteAllText($jobPath, ($job | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($true)))
        $physicalJobPath = Get-ExtGuideFinalPath -Path $jobPath

        $workerCommand = "& '$($physicalWorkerPath.Replace("'", "''"))' -JobPath '$($physicalJobPath.Replace("'", "''"))'"
        $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($workerCommand))
        $powerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if ($Elevated) {
            $null = Start-ExtGuideElevatedProcess -PowerShellPath $powerShell -EncodedCommand $encodedCommand
        }
        else {
            $commandLine = '"{0}" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand {1}' -f $powerShell, $encodedCommand
            $null = Start-ExtGuideUnvirtualizedProcess -CommandLine $commandLine
        }

        $deadline = [DateTime]::UtcNow.AddMinutes(5)
        while ([DateTime]::UtcNow -lt $deadline) {
            if ((Get-Item -LiteralPath $resultPath -ErrorAction SilentlyContinue).Length -gt 0) { break }
            Start-Sleep -Milliseconds 100
        }
        if ((Get-Item -LiteralPath $resultPath -ErrorAction SilentlyContinue).Length -le 0) {
            Throw-ExtGuideError -Category 'Destination' -Message 'The unvirtualized extension installer did not finish in time.' -Recovery 'Run ExtGuide again from a regular Windows PowerShell window outside the packaged application.'
        }

        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if (-not [bool] $result.Succeeded) {
            Throw-ExtGuideError -Category ([string] $result.Category) -Message ([string] $result.Message) -Recovery ([string] $result.Recovery)
        }
        $content = @{}
        if ($null -ne $result.Content) {
            foreach ($property in $result.Content.PSObject.Properties) { $content[$property.Name] = $property.Value }
        }
        return [pscustomobject]@{
            ExtensionRoot = [string] $result.ExtensionRoot
            Content = $content
            WasUpdate = [bool] $result.WasUpdate
            PreviousVersion = [string] $result.PreviousVersion
            InstalledVersion = [string] $result.InstalledVersion
        }
    }
    finally {
        Remove-ExtGuideInstallJobDirectory -JobDirectory $jobDirectory
    }
}

function Install-ExtGuideArchiveForWindows {
    param(
        [Parameter(Mandatory = $true)][byte[]] $ArchiveBytes,
        [Parameter(Mandatory = $true)][string] $Destination,
        [Parameter(Mandatory = $true)][string] $ExtensionRoot,
        $InstallContext,
        [scriptblock] $VirtualizationDetector,
        [scriptblock] $OutOfProcessInstaller,
        [scriptblock] $InProcessInstaller,
        [scriptblock] $ElevatedInstaller
    )

    if ($null -eq $InstallContext) {
        $InstallContext = [pscustomobject]@{ UseElevation = $false; IntegrationId = ''; Publisher = ''; InstallFolderName = ''; ArchiveSha256 = (Get-ExtGuideSha256 -Bytes $ArchiveBytes); ExpectedVersion = '' }
    }
    if ($null -eq $VirtualizationDetector) { $VirtualizationDetector = { param($Path) Test-ExtGuidePathVirtualized -Destination $Path } }
    if ($null -eq $OutOfProcessInstaller) { $OutOfProcessInstaller = { param($Bytes, $Target, $Root, $Context) Install-ExtGuideArchiveOutOfProcess -ArchiveBytes $Bytes -Destination $Target -ExtensionRoot $Root -InstallContext $Context } }
    if ($null -eq $ElevatedInstaller) { $ElevatedInstaller = { param($Bytes, $Target, $Root, $Context) Install-ExtGuideArchiveOutOfProcess -ArchiveBytes $Bytes -Destination $Target -ExtensionRoot $Root -InstallContext $Context -Elevated } }
    if ($null -eq $InProcessInstaller) {
        $InProcessInstaller = {
            param($Bytes, $Target, $Root, $Context)
            Install-ExtGuideArchive -ArchiveBytes $Bytes -Destination $Target -ExtensionRoot $Root -IntegrationId ([string] $Context.IntegrationId) -Publisher ([string] $Context.Publisher) -InstallFolderName ([string] $Context.InstallFolderName) -ArchiveSha256 ([string] $Context.ArchiveSha256) -ExpectedVersion ([string] $Context.ExpectedVersion)
        }
    }

    if ([bool] $InstallContext.UseElevation) {
        return & $ElevatedInstaller $ArchiveBytes $Destination $ExtensionRoot $InstallContext
    }

    if (& $VirtualizationDetector $Destination) {
        return & $OutOfProcessInstaller $ArchiveBytes $Destination $ExtensionRoot $InstallContext
    }
    return & $InProcessInstaller $ArchiveBytes $Destination $ExtensionRoot $InstallContext
}
