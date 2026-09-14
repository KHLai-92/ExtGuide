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

function Install-ExtGuideArchive {
    param(
        [Parameter(Mandatory = $true)][byte[]] $ArchiveBytes,
        [Parameter(Mandatory = $true)][string] $Destination,
        [Parameter(Mandatory = $true)][string] $ExtensionRoot
    )

    $parent = Split-Path -Parent $Destination
    $leaf = Split-Path -Leaf $Destination
    $staging = Join-Path $parent ('.' + $leaf + '.extguide-stage-' + [guid]::NewGuid().ToString('N'))
    $backup = Join-Path $parent ('.' + $leaf + '.extguide-backup-' + [guid]::NewGuid().ToString('N'))
    $movedCurrent = $false
    $installed = $false
    $wasUpdate = Test-Path -LiteralPath $Destination
    try {
        $null = New-Item -ItemType Directory -Path $staging -Force -ErrorAction Stop
        Expand-ExtGuideArchiveSafely -ArchiveBytes $ArchiveBytes -StagingDirectory $staging
        $stagedExtensionRoot = [System.IO.Path]::GetFullPath((Join-Path $staging $ExtensionRoot))
        $manifestPath = Join-Path $stagedExtensionRoot 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Throw-ExtGuideError -Category 'Extraction' -Message 'The configured extension root does not contain manifest.json.' -Recovery 'Ask the publisher to correct extensionRoot or rebuild the release archive.'
        }
        try { $extensionManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop }
        catch {
            Throw-ExtGuideError -Category 'Extraction' -Message 'The extracted Chrome extension manifest is not valid JSON.' -Recovery 'Ask the publisher to ship a valid prebuilt extension.' -InnerException $_.Exception
        }
        if ([int] $extensionManifest.manifest_version -ne 3 -or [string]::IsNullOrWhiteSpace([string] $extensionManifest.name) -or [string]::IsNullOrWhiteSpace([string] $extensionManifest.version)) {
            Throw-ExtGuideError -Category 'Extraction' -Message 'The extracted files are not a valid prebuilt Manifest V3 extension.' -Recovery 'Ask the publisher to include a complete built extension in the release archive.'
        }
        if ($wasUpdate) {
            Move-Item -LiteralPath $Destination -Destination $backup -ErrorAction Stop
            $movedCurrent = $true
        }
        Move-Item -LiteralPath $staging -Destination $Destination -ErrorAction Stop
        $installed = $true
        if ($movedCurrent -and (Test-Path -LiteralPath $backup)) {
            Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
            $movedCurrent = $false
        }
        $installedRoot = [System.IO.Path]::GetFullPath((Join-Path $Destination $ExtensionRoot))
        $content = @{}
        Get-ChildItem -LiteralPath $installedRoot -File -Recurse | ForEach-Object {
            $relative = $_.FullName.Substring($installedRoot.Length).TrimStart('\')
            $content[$relative] = $_.Length
        }
        return [pscustomobject]@{ ExtensionRoot = $installedRoot; Content = $content; WasUpdate = $wasUpdate }
    }
    catch {
        if ($movedCurrent -and -not (Test-Path -LiteralPath $Destination) -and (Test-Path -LiteralPath $backup)) {
            try { Move-Item -LiteralPath $backup -Destination $Destination -ErrorAction Stop } catch { }
            $movedCurrent = $false
        }
        if ($null -ne $_.Exception.Data['ExtGuideCategory']) { throw }
        Throw-ExtGuideError -Category 'Destination' -Message 'ExtGuide could not replace the current installation safely.' -Recovery 'Close Chrome and any program using the extension files, then retry. The previous installation was preserved.' -InnerException $_.Exception
    }
    finally {
        if (-not $installed -and (Test-Path -LiteralPath $staging)) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
        if ($movedCurrent -and (Test-Path -LiteralPath $backup) -and (Test-Path -LiteralPath $Destination)) { Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
