function Get-ExtGuideSha256 {
    param([Parameter(Mandatory = $true)][byte[]] $Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try { return -join ($sha256.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha256.Dispose() }
}

function Test-ExtGuideDestinationWritable {
    param([Parameter(Mandatory = $true)][string] $Destination)

    $probeDirectory = if (Test-Path -LiteralPath $Destination -PathType Container) { $Destination } else { Split-Path -Parent $Destination }
    try {
        $null = New-Item -ItemType Directory -Path $probeDirectory -Force -ErrorAction Stop
        $probe = Join-Path $probeDirectory ('.extguide-write-' + [guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($probe, 'ExtGuide write probe')
        Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
        return $true
    }
    catch { return $false }
}

function Expand-ExtGuideArchiveSafely {
    param(
        [Parameter(Mandatory = $true)][byte[]] $ArchiveBytes,
        [Parameter(Mandatory = $true)][string] $StagingDirectory
    )

    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    $memory = New-Object System.IO.MemoryStream(, $ArchiveBytes)
    $archive = $null
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $stagingRoot = [System.IO.Path]::GetFullPath($StagingDirectory).TrimEnd('\') + '\'
    try {
        $archive = New-Object System.IO.Compression.ZipArchive($memory, [System.IO.Compression.ZipArchiveMode]::Read)
        foreach ($entry in $archive.Entries) {
            $entryPath = $entry.FullName.Replace('/', '\')
            $unixMode = (($entry.ExternalAttributes -shr 16) -band 0xF000)
            if ($unixMode -eq 0xA000) {
                Throw-ExtGuideError -Category 'Extraction' -Message 'The extension archive contains a symbolic link, which is not supported.' -Recovery 'Ask the publisher to provide a regular-file-only archive.'
            }
            if ([string]::IsNullOrWhiteSpace($entryPath)) { continue }
            if ([System.IO.Path]::IsPathRooted($entryPath) -or $entryPath -match ':' -or $entryPath -match '(^|\\)\.\.(\\|$)') {
                Throw-ExtGuideError -Category 'Extraction' -Message 'The extension archive contains an entry outside the selected installation directory.' -Recovery 'Do not install this archive; ask the publisher to remove unsafe paths.'
            }
            $targetPath = [System.IO.Path]::GetFullPath((Join-Path $StagingDirectory $entryPath))
            if (-not $targetPath.StartsWith($stagingRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                Throw-ExtGuideError -Category 'Extraction' -Message 'The extension archive contains an escaping path.' -Recovery 'Do not install this archive; ask the publisher to rebuild it safely.'
            }
            if (-not $seen.Add($targetPath)) {
                Throw-ExtGuideError -Category 'Extraction' -Message 'The extension archive contains duplicate or conflicting entries.' -Recovery 'Ask the publisher to remove duplicate archive entries.'
            }
            if ($entry.FullName.EndsWith('/')) {
                $null = New-Item -ItemType Directory -Path $targetPath -Force
                continue
            }
            $parent = Split-Path -Parent $targetPath
            $null = New-Item -ItemType Directory -Path $parent -Force
            $source = $entry.Open()
            $destinationStream = $null
            try {
                $destinationStream = New-Object System.IO.FileStream($targetPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                $source.CopyTo($destinationStream)
            }
            finally {
                if ($null -ne $destinationStream) { $destinationStream.Dispose() }
                $source.Dispose()
            }
        }
    }
    catch {
        if ($null -ne $_.Exception.Data['ExtGuideCategory']) { throw }
        Throw-ExtGuideError -Category 'Extraction' -Message 'The downloaded extension archive is corrupt or unsupported.' -Recovery 'Retry the download; if it fails again, ask the publisher to replace the archive.' -InnerException $_.Exception
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
        $memory.Dispose()
    }
}

function Get-ExtGuideExtensionManifest {
    param(
        [Parameter(Mandatory = $true)][string] $ExtensionDirectory,
        [string] $Category = 'Extraction'
    )

    $manifestPath = Join-Path $ExtensionDirectory 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Throw-ExtGuideError -Category $Category -Message 'The extension root does not contain manifest.json.' -Recovery 'Choose the correct existing installation or ask the publisher to rebuild the release archive.'
    }
    try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch {
        Throw-ExtGuideError -Category $Category -Message 'The Chrome extension manifest is not valid JSON.' -Recovery 'Choose the correct existing installation or ask the publisher to ship a valid prebuilt extension.' -InnerException $_.Exception
    }
    if ([int] $manifest.manifest_version -ne 3 -or [string]::IsNullOrWhiteSpace([string] $manifest.name) -or [string]::IsNullOrWhiteSpace([string] $manifest.version)) {
        Throw-ExtGuideError -Category $Category -Message 'The files are not a valid prebuilt Manifest V3 extension.' -Recovery 'Choose the correct existing installation or ask the publisher to include a complete built extension.'
    }
    return $manifest
}

function Get-ExtGuideUpdateJournalPath {
    param([Parameter(Mandatory = $true)][string] $Destination)
    $fullDestination = [System.IO.Path]::GetFullPath($Destination)
    return Join-Path (Split-Path -Parent $fullDestination) ('.' + (Split-Path -Leaf $fullDestination) + '.extguide-update.json')
}

function Write-ExtGuideUpdateJournal {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)] $Journal)

    $temporary = $Path + '.tmp-' + [guid]::NewGuid().ToString('N')
    try {
        [System.IO.File]::WriteAllText($temporary, ($Journal | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($true)))
        Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Test-ExtGuideTransactionPath {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Parent, [Parameter(Mandatory = $true)][string] $Leaf, [Parameter(Mandatory = $true)][string] $Kind)

    try { $fullPath = [System.IO.Path]::GetFullPath($Path) } catch { return $false }
    $expectedParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\')
    if (-not (Split-Path -Parent $fullPath).Equals($expectedParent, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    return (Split-Path -Leaf $fullPath) -match ('^\.' + [regex]::Escape($Leaf) + '\.extguide-' + $Kind + '-[0-9a-f]{32}$')
}

function Repair-ExtGuideInterruptedUpdate {
    param([Parameter(Mandatory = $true)][string] $Destination)

    $fullDestination = [System.IO.Path]::GetFullPath($Destination)
    $journalPath = Get-ExtGuideUpdateJournalPath -Destination $fullDestination
    if (-not (Test-Path -LiteralPath $journalPath -PathType Leaf)) { return $false }
    try { $journal = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch {
        Throw-ExtGuideError -Category 'Destination' -Message 'ExtGuide found a damaged update recovery record.' -Recovery 'Do not delete extension files. Ask the publisher or administrator to inspect the ExtGuide update files beside the installation.' -InnerException $_.Exception
    }

    $recordedDestination = [System.IO.Path]::GetFullPath([string] $journal.Destination)
    $parent = Split-Path -Parent $fullDestination
    $leaf = Split-Path -Leaf $fullDestination
    if (-not $recordedDestination.Equals($fullDestination, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-ExtGuideTransactionPath -Path ([string] $journal.Staging) -Parent $parent -Leaf $leaf -Kind 'stage') -or
        -not (Test-ExtGuideTransactionPath -Path ([string] $journal.Backup) -Parent $parent -Leaf $leaf -Kind 'backup')) {
        Throw-ExtGuideError -Category 'Destination' -Message 'ExtGuide rejected an unsafe update recovery record.' -Recovery 'Ask the publisher or administrator to inspect the installation directory.'
    }

    $staging = [string] $journal.Staging
    $backup = [string] $journal.Backup
    $destinationExists = Test-Path -LiteralPath $fullDestination -PathType Container
    $backupExists = Test-Path -LiteralPath $backup -PathType Container
    $stagingExists = Test-Path -LiteralPath $staging -PathType Container

    if (-not $destinationExists -and $backupExists) {
        Move-Item -LiteralPath $backup -Destination $fullDestination -ErrorAction Stop
        $destinationExists = $true
        $backupExists = $false
    }
    elseif (-not $destinationExists -and -not $backupExists -and $stagingExists) {
        Move-Item -LiteralPath $staging -Destination $fullDestination -ErrorAction Stop
        $destinationExists = $true
        $stagingExists = $false
    }

    if ($destinationExists -and $backupExists) { Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction Stop }
    if ($destinationExists -and $stagingExists) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction Stop }
    Remove-Item -LiteralPath $journalPath -Force -ErrorAction Stop
    return $true
}

function Read-ExtGuideInstallationReceipt {
    param([Parameter(Mandatory = $true)][string] $Destination)

    $path = Join-Path $Destination '.extguide-install.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch {
        Throw-ExtGuideError -Category 'Destination' -Message 'The existing ExtGuide installation receipt is damaged.' -Recovery 'Choose another folder or ask the publisher to inspect the existing installation.' -InnerException $_.Exception
    }
}

function Install-ExtGuideArchive {
    param(
        [Parameter(Mandatory = $true)][byte[]] $ArchiveBytes,
        [Parameter(Mandatory = $true)][string] $Destination,
        [Parameter(Mandatory = $true)][string] $ExtensionRoot,
        [string] $IntegrationId,
        [string] $Publisher,
        [string] $InstallFolderName,
        [string] $ArchiveSha256,
        [string] $ExpectedVersion
    )

    $Destination = [System.IO.Path]::GetFullPath($Destination)
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force -ErrorAction Stop
    $null = Repair-ExtGuideInterruptedUpdate -Destination $Destination
    $parent = Split-Path -Parent $Destination
    $leaf = Split-Path -Leaf $Destination
    $staging = Join-Path $parent ('.' + $leaf + '.extguide-stage-' + [guid]::NewGuid().ToString('N'))
    $backup = Join-Path $parent ('.' + $leaf + '.extguide-backup-' + [guid]::NewGuid().ToString('N'))
    $journalPath = Get-ExtGuideUpdateJournalPath -Destination $Destination
    $movedCurrent = $false
    $installed = $false
    $wasUpdate = Test-Path -LiteralPath $Destination
    $previousVersion = $null
    try {
        $null = New-Item -ItemType Directory -Path $staging -Force -ErrorAction Stop
        Expand-ExtGuideArchiveSafely -ArchiveBytes $ArchiveBytes -StagingDirectory $staging
        $stagedExtensionRoot = [System.IO.Path]::GetFullPath((Join-Path $staging $ExtensionRoot))
        $extensionManifest = Get-ExtGuideExtensionManifest -ExtensionDirectory $stagedExtensionRoot
        if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion) -and [string] $extensionManifest.version -ne $ExpectedVersion) {
            Throw-ExtGuideError -Category 'Integrity' -Message 'The extension version inside the archive does not match the installer manifest.' -Recovery 'Do not install this archive; ask the publisher to correct the release metadata.'
        }
        if ($wasUpdate) {
            $existingRoot = [System.IO.Path]::GetFullPath((Join-Path $Destination $ExtensionRoot))
            $existingManifest = Get-ExtGuideExtensionManifest -ExtensionDirectory $existingRoot -Category 'Destination'
            $previousVersion = [string] $existingManifest.version
            $receipt = Read-ExtGuideInstallationReceipt -Destination $Destination
            if ($null -ne $receipt) {
                if ([int] $receipt.receiptVersion -ne 1 -or
                    [string] $receipt.integrationId -ne $IntegrationId -or
                    [string] $receipt.extensionRoot -ne $ExtensionRoot) {
                    Throw-ExtGuideError -Category 'Destination' -Message 'The selected folder belongs to a different ExtGuide installation.' -Recovery 'Choose the folder previously used for this extension, or choose a new location.'
                }
            }
            elseif (-not ([string] $existingManifest.name).Equals([string] $extensionManifest.name, [System.StringComparison]::Ordinal)) {
                Throw-ExtGuideError -Category 'Destination' -Message 'The selected folder contains a different unpacked extension.' -Recovery 'Choose the folder previously used for this extension, or choose a new location.'
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($IntegrationId)) {
            $receiptPayload = [ordered]@{
                receiptVersion = 1
                integrationId = $IntegrationId
                publisher = $Publisher
                installFolderName = $InstallFolderName
                extensionRoot = $ExtensionRoot
                extensionVersion = [string] $extensionManifest.version
                archiveSha256 = $ArchiveSha256
            }
            [System.IO.File]::WriteAllText((Join-Path $staging '.extguide-install.json'), ($receiptPayload | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($true)))
        }

        $journal = [ordered]@{ journalVersion = 1; Destination = $Destination; Staging = $staging; Backup = $backup; Phase = 'Prepared' }
        Write-ExtGuideUpdateJournal -Path $journalPath -Journal $journal
        if ($wasUpdate) {
            Move-Item -LiteralPath $Destination -Destination $backup -ErrorAction Stop
            $movedCurrent = $true
            $journal.Phase = 'OldBackedUp'
            Write-ExtGuideUpdateJournal -Path $journalPath -Journal $journal
        }
        Move-Item -LiteralPath $staging -Destination $Destination -ErrorAction Stop
        $installed = $true
        $journal.Phase = 'NewActivated'
        Write-ExtGuideUpdateJournal -Path $journalPath -Journal $journal
        if ($movedCurrent -and (Test-Path -LiteralPath $backup)) {
            Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
            $movedCurrent = $false
        }
        Remove-Item -LiteralPath $journalPath -Force -ErrorAction SilentlyContinue
        $installedRoot = [System.IO.Path]::GetFullPath((Join-Path $Destination $ExtensionRoot))
        $content = @{}
        Get-ChildItem -LiteralPath $installedRoot -File -Recurse | ForEach-Object {
            $relative = $_.FullName.Substring($installedRoot.Length).TrimStart('\')
            $content[$relative] = $_.Length
        }
        return [pscustomobject]@{ ExtensionRoot = $installedRoot; Content = $content; WasUpdate = $wasUpdate; PreviousVersion = $previousVersion; InstalledVersion = [string] $extensionManifest.version }
    }
    catch {
        if ($movedCurrent -and -not (Test-Path -LiteralPath $Destination) -and (Test-Path -LiteralPath $backup)) {
            try { Move-Item -LiteralPath $backup -Destination $Destination -ErrorAction Stop } catch { }
            $movedCurrent = $false
        }
        if (-not $movedCurrent -and (Test-Path -LiteralPath $Destination) -and (Test-Path -LiteralPath $journalPath)) {
            Remove-Item -LiteralPath $journalPath -Force -ErrorAction SilentlyContinue
        }
        if ($null -ne $_.Exception.Data['ExtGuideCategory']) { throw }
        Throw-ExtGuideError -Category 'Destination' -Message 'ExtGuide could not replace the current installation safely.' -Recovery 'Close Chrome and any program using the extension files, then retry. The previous installation was preserved.' -InnerException $_.Exception
    }
    finally {
        if (-not $installed -and (Test-Path -LiteralPath $staging)) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
        if ($movedCurrent -and (Test-Path -LiteralPath $backup) -and (Test-Path -LiteralPath $Destination)) { Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
