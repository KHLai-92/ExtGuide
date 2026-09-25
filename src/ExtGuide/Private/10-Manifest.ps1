function Test-ExtGuideSafeName {
    param([string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Length -gt 64) { return $false }
    if ($Value -in @('.', '..') -or $Value -ne $Value.Trim()) { return $false }
    if ($Value.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) { return $false }
    return $Value -match '^[\p{L}\p{N}][\p{L}\p{N} ._-]*$'
}

function Test-ExtGuideRelativePath {
    param([string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or [System.IO.Path]::IsPathRooted($Value)) { return $false }
    if ($Value -match ':' -or $Value -match '(^|[\\/])\.\.([\\/]|$)') { return $false }
    return $true
}

function ConvertFrom-ExtGuideManifest {
    param([Parameter(Mandatory = $true)][string] $Json)

    try { $manifest = $Json | ConvertFrom-Json -ErrorAction Stop }
    catch {
        Throw-ExtGuideError -Category 'Configuration' -Message 'The installer manifest is not valid JSON.' -Recovery 'Ask the extension publisher to publish a valid versioned installer manifest.' -InnerException $_.Exception
    }

    foreach ($propertyName in @('schemaVersion', 'displayName', 'publisher', 'installFolderName', 'archiveUrl', 'extensionRoot')) {
        if ($null -eq $manifest.PSObject.Properties[$propertyName] -or [string]::IsNullOrWhiteSpace([string] $manifest.$propertyName)) {
            Throw-ExtGuideError -Category 'Configuration' -Message "The installer manifest is missing '$propertyName'." -Recovery 'Ask the extension publisher to correct the installer manifest.'
        }
    }
    if ([int] $manifest.schemaVersion -ne 1) {
        Throw-ExtGuideError -Category 'Configuration' -Message "Installer manifest schema version '$($manifest.schemaVersion)' is not supported." -Recovery 'Use an ExtGuide release that supports this schema, or ask the publisher to use schema version 1.'
    }
    foreach ($propertyName in @('publisher', 'installFolderName')) {
        if (-not (Test-ExtGuideSafeName -Value ([string] $manifest.$propertyName))) {
            Throw-ExtGuideError -Category 'Configuration' -Message "The manifest value '$propertyName' is not a safe folder name." -Recovery 'Ask the extension publisher to use a short name without path separators or reserved characters.'
        }
    }
    if ($null -ne $manifest.PSObject.Properties['integrationId'] -and
        -not [string]::IsNullOrWhiteSpace([string] $manifest.integrationId) -and
        [string] $manifest.integrationId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$') {
        Throw-ExtGuideError -Category 'Configuration' -Message "The manifest value 'integrationId' is not a safe identifier." -Recovery 'Ask the publisher to use 3-128 letters, numbers, dots, underscores, or hyphens.'
    }
    if ($null -ne $manifest.PSObject.Properties['extensionVersion'] -and
        -not [string]::IsNullOrWhiteSpace([string] $manifest.extensionVersion) -and
        [string] $manifest.extensionVersion -notmatch '^\d+(\.\d+){0,3}$') {
        Throw-ExtGuideError -Category 'Configuration' -Message "The manifest value 'extensionVersion' is not a valid Chrome extension version." -Recovery 'Ask the publisher to use one to four dot-separated numeric components.'
    }
    if (-not (Test-ExtGuideRelativePath -Value ([string] $manifest.extensionRoot))) {
        Throw-ExtGuideError -Category 'Configuration' -Message 'The extension root must be a relative path inside the release archive.' -Recovery 'Ask the extension publisher to correct extensionRoot.'
    }
    foreach ($urlProperty in @('archiveUrl', 'sha256Url')) {
        if ($null -eq $manifest.PSObject.Properties[$urlProperty] -or [string]::IsNullOrWhiteSpace([string] $manifest.$urlProperty)) { continue }
        $uri = $null
        if (-not [uri]::TryCreate([string] $manifest.$urlProperty, [System.UriKind]::Absolute, [ref] $uri) -or $uri.Scheme -ne 'https') {
            Throw-ExtGuideError -Category 'Configuration' -Message "The manifest value '$urlProperty' must be an absolute HTTPS URL." -Recovery 'Ask the extension publisher to use a direct HTTPS release asset URL.'
        }
    }

    $inlineDigest = if ($null -ne $manifest.PSObject.Properties['sha256']) { [string] $manifest.sha256 } else { '' }
    $digestUrl = if ($null -ne $manifest.PSObject.Properties['sha256Url']) { [string] $manifest.sha256Url } else { '' }
    if ([string]::IsNullOrWhiteSpace($inlineDigest) -eq [string]::IsNullOrWhiteSpace($digestUrl)) {
        Throw-ExtGuideError -Category 'Configuration' -Message 'The manifest must declare exactly one SHA-256 digest or SHA-256 URL.' -Recovery 'Ask the extension publisher to provide either sha256 or sha256Url.'
    }
    if (-not [string]::IsNullOrWhiteSpace($inlineDigest) -and $inlineDigest -notmatch '^[a-fA-F0-9]{64}$') {
        Throw-ExtGuideError -Category 'Configuration' -Message 'The manifest SHA-256 digest is malformed.' -Recovery 'Ask the extension publisher to publish a 64-character hexadecimal SHA-256 digest.'
    }
    return $manifest
}

function Get-ExtGuideIntegrationId {
    param([Parameter(Mandatory = $true)] $Manifest)

    if ($null -ne $Manifest.PSObject.Properties['integrationId'] -and -not [string]::IsNullOrWhiteSpace([string] $Manifest.integrationId)) {
        return [string] $Manifest.integrationId
    }
    return ([string] $Manifest.publisher + '|' + [string] $Manifest.installFolderName)
}

function ConvertFrom-ExtGuideDigestText {
    param([string] $Text)

    $match = [regex]::Match($Text, '(?i)(?<![a-f0-9])[a-f0-9]{64}(?![a-f0-9])')
    if (-not $match.Success) {
        Throw-ExtGuideError -Category 'Integrity' -Message 'The downloaded SHA-256 file does not contain a valid digest.' -Recovery 'Ask the extension publisher to repair the digest asset before retrying.'
    }
    return $match.Value.ToLowerInvariant()
}
